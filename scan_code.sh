#!/bin/bash
set -eo pipefail

# --- Script & Directory Paths ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKER_COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yaml"
CLONE_DIR="$SCRIPT_DIR/java-workspace"
TOKEN_DIR="$SCRIPT_DIR/sonar_tokens"

# --- Configuration & Variables ---
GITLAB_URL="${GITLAB_URL:-https://gitlab.com/yourapp}"
REPOS=("service1" "service2" "service3" "service4")
SONARQUBE_URL="${SONARQUBE_URL:-http://localhost:9001}"
SONARQUBE_USERNAME="${SONARQUBE_USERNAME:-admin}"
SONARQUBE_PASSWORD="${SONARQUBE_PASSWORD:-admin1}"
PROJECT_PREFIX="${PROJECT_PREFIX:-}" # Optional prefix matching initial_setup.sh
SERVICE_NAME="sonarqube"

# Default fallback token if per-repo token file is not found
TOKEN="${TOKEN:-}"

# Optional command-line flags
DELETE_BEFORE_SCAN=false
CLEAN_WORKSPACE_AFTER_SCAN=false
GENERATE_CNES_REPORT=false

for arg in "$@"; do
  case $arg in
    --clean-projects)
      DELETE_BEFORE_SCAN=true
      ;;
    --clean-workspace)
      CLEAN_WORKSPACE_AFTER_SCAN=true
      ;;
    --report)
      GENERATE_CNES_REPORT=true
      ;;
    *)
      ;;
  esac
done

# --- Utility Functions ---

# Check if the SonarQube container is running in Docker
_is_sonarqube_running() {
  local running_id
  running_id=$(docker compose -f "$DOCKER_COMPOSE_FILE" ps -q "$SERVICE_NAME" 2>/dev/null || true)
  if [ -n "$running_id" ]; then
    return 0
  else
    return 1
  fi
}

# Wait for SonarQube HTTP API to be completely UP and operational
wait_for_sonarqube_ready() {
  local max_attempts=30
  local wait_seconds=5
  local attempt=1

  echo "Waiting for SonarQube web API to be ready at $SONARQUBE_URL..."
  while [ "$attempt" -le "$max_attempts" ]; do
    local status
    status=$(curl -s -f "$SONARQUBE_URL/api/system/status" 2>/dev/null | jq -r '.status // empty' 2>/dev/null || true)
    if [ "$status" == "UP" ]; then
      echo "SonarQube is UP and healthy!"
      return 0
    fi
    echo "SonarQube is starting (status: '${status:-STARTING}', attempt $attempt/$max_attempts)... waiting ${wait_seconds}s"
    sleep "$wait_seconds"
    attempt=$((attempt + 1))
  done

  echo "Error: Timed out waiting for SonarQube to become ready."
  return 1
}

# Start SonarQube via docker compose if not already running
start_sonarqube() {
  echo "Starting SonarQube Docker containers..."
  docker compose -f "$DOCKER_COMPOSE_FILE" up -d

  if ! wait_for_sonarqube_ready; then
    echo "Error: SonarQube containers failed to initialize. Check logs with 'docker compose logs sonarqube'."
    exit 1
  fi
}

# Create project in SonarQube if it doesn't already exist
create_project() {
  for REPO in "${REPOS[@]}"; do
    local project_key="$REPO"
    [ -n "$PROJECT_PREFIX" ] && project_key="${PROJECT_PREFIX}-${REPO}"

    local exists
    exists=$(curl -s -u "$SONARQUBE_USERNAME:$SONARQUBE_PASSWORD" "$SONARQUBE_URL/api/projects/search?projects=$project_key" 2>/dev/null | jq -r '.components | length' 2>/dev/null || echo 0)
    
    if [ "$exists" -eq 0 ]; then
      local response
      response=$(curl -s -X POST -u "$SONARQUBE_USERNAME:$SONARQUBE_PASSWORD" \
        -d "name=$project_key&project=$project_key" \
        "$SONARQUBE_URL/api/projects/create")
      if echo "$response" | jq -e '.project' > /dev/null 2>&1; then
        echo "Project '$project_key' created."
      else
        echo "Warning: Could not create project '$project_key': $response"
      fi
    else
      echo "Project '$project_key' already exists. Ready for scan."
    fi
  done
}

# Delete project (Only executed if explicitly requested via --clean-projects)
delete_project() {
  for REPO in "${REPOS[@]}"; do
    local project_key="$REPO"
    [ -n "$PROJECT_PREFIX" ] && project_key="${PROJECT_PREFIX}-${REPO}"

    echo "Deleting project '$project_key'..."
    curl -s -X POST -u "$SONARQUBE_USERNAME:$SONARQUBE_PASSWORD" \
      -d "project=$project_key" \
      "$SONARQUBE_URL/api/projects/delete" > /dev/null 2>&1 || true
    echo "Project '$project_key' deleted."
  done
}

# Clone or update repositories safely using subshells
clone_or_update_repo() {
  mkdir -p "$CLONE_DIR"
  for REPO in "${REPOS[@]}"; do
    local repo_dir="$CLONE_DIR/$REPO"
    if [ -d "$repo_dir/.git" ]; then
      echo "Pulling latest changes for $REPO..."
      (
        cd "$repo_dir"
        git pull --ff-only || git pull
      )
    else
      echo "Cloning $REPO from $GITLAB_URL/$REPO.git..."
      git clone "$GITLAB_URL/$REPO.git" "$repo_dir"
    fi
  done
}

# Run SonarScanner via Maven using the resolved token for each repo
run_sonar_scanner() {
  for REPO in "${REPOS[@]}"; do
    local repo_dir="$CLONE_DIR/$REPO"
    local project_key="$REPO"
    [ -n "$PROJECT_PREFIX" ] && project_key="${PROJECT_PREFIX}-${REPO}"

    # Resolve token: per-repo file first, then environment/variable fallback
    local repo_token=""
    local token_file="$TOKEN_DIR/${REPO}_token.txt"
    if [ -f "$token_file" ]; then
      repo_token="$(cat "$token_file" | tr -d '\r\n[:space:]')"
    elif [ -n "$TOKEN" ]; then
      repo_token="$TOKEN"
    fi

    if [ -z "$repo_token" ]; then
      echo "Warning: No token found for $REPO (checked $token_file and \$TOKEN). Skipping scan."
      continue
    fi

    if [ ! -d "$repo_dir" ]; then
      echo "Warning: Directory '$repo_dir' does not exist. Skipping."
      continue
    fi

    echo "=========================================================="
    echo "Running SonarQube analysis for: $REPO (Key: $project_key)"
    echo "=========================================================="

    (
      cd "$repo_dir"
      # Run Maven Sonar scan passing both modern -Dsonar.token and legacy -Dsonar.login
      mvn clean verify sonar:sonar \
        -Dsonar.projectKey="$project_key" \
        -Dsonar.projectName="$project_key" \
        -Dsonar.host.url="$SONARQUBE_URL" \
        -Dsonar.token="$repo_token" \
        -Dsonar.login="$repo_token"
    )

    if [ "$GENERATE_CNES_REPORT" = true ]; then
      take_report "$REPO" "$project_key" "$repo_token"
    fi
  done
}

# Optional CNES report generation
take_report() {
  local repo="$1"
  local project_key="$2"
  local token="$3"

  local cnes_jar
  cnes_jar=$(find "$SCRIPT_DIR/sonarqube_plugins" -name "sonar-cnes-report-*.jar" 2>/dev/null | head -n 1 || true)
  if [ -n "$cnes_jar" ] && [ -f "$cnes_jar" ]; then
    echo "Generating CNES report for $project_key..."
    java -jar "$cnes_jar" -t "$token" -s "$SONARQUBE_URL" -p "$project_key" -o "$SCRIPT_DIR/reports/$repo"
  else
    echo "CNES report jar not found in sonarqube_plugins/. Skipping report."
  fi
}

# --- Main Script Execution ---

echo "=== SonarQube Microservices Analysis Workflow ==="

# 1. Ensure SonarQube is running and ready
if _is_sonarqube_running; then
  echo "The '$SERVICE_NAME' container is already running."
  if ! wait_for_sonarqube_ready; then
    echo "SonarQube is starting up. Retrying..."
    start_sonarqube
  fi
else
  echo "The '$SERVICE_NAME' container is NOT running. Starting containers..."
  start_sonarqube
fi

# 2. Optional: Clean projects if explicitly requested via --clean-projects
if [ "$DELETE_BEFORE_SCAN" = true ]; then
  echo "Flag --clean-projects detected. Deleting existing SonarQube projects..."
  delete_project
fi

# 3. Create projects in SonarQube if they do not already exist
echo "Ensuring SonarQube projects exist..."
create_project

# 4. Clone or pull code from GitLab
echo "Preparing repositories..."
clone_or_update_repo

# 5. Run SonarScanner analysis
echo "Starting code analysis..."
run_sonar_scanner

# 6. Optional workspace cleanup
if [ "$CLEAN_WORKSPACE_AFTER_SCAN" = true ]; then
  echo "Cleaning up workspace directory ($CLONE_DIR)..."
  rm -rf "$CLONE_DIR"
fi

echo "=========================================================="
echo "SonarScanner analysis completed for all microservices."
echo "Dashboard: $SONARQUBE_URL"
