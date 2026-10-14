#!/bin/bash
set -eo pipefail

# --- Script & Directory Paths ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKER_COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yaml"
CLONE_DIR="$SCRIPT_DIR/java-workspace"
TOKEN_DIR="$SCRIPT_DIR/sonar_tokens"
REPORTS_DIR="$SCRIPT_DIR/reports"
SONAR_DATA_DIR="$SCRIPT_DIR/sonarqube_data"
SONAR_LOGS_DIR="$SCRIPT_DIR/sonarqube_logs"
POSTGRES_DATA_DIR="$SCRIPT_DIR/postgres"

# --- Flags ---
REMOVE_VOLUMES=false
REMOVE_WORKSPACE=false
REMOVE_TOKENS=false
REMOVE_REPORTS=false
FORCE=false

usage() {
  cat << EOF
Usage: ./teardown.sh [OPTIONS]

Stops SonarQube containers and cleans up environment resources.

Options:
  -v, --volumes      Remove database and SonarQube persistent data volumes
  -w, --workspace    Remove the cloned repositories workspace directory
  -t, --tokens       Remove the stored sonar_tokens directory
  -r, --reports      Remove generated analysis reports
  --all              Full teardown: removes containers, volumes, workspace, tokens, and reports
  -y, --yes, --force Skip confirmation prompts for destructive actions
  -h, --help         Show this help message

Examples:
  ./teardown.sh                  # Stop containers gracefully (retains data)
  ./teardown.sh -w               # Stop containers and remove cloned workspace
  ./teardown.sh --all            # Complete reset: stop containers and delete all data
EOF
  exit 0
}

# Parse command-line arguments
for arg in "$@"; do
  case $arg in
    -h|--help)
      usage
      ;;
    -v|--volumes)
      REMOVE_VOLUMES=true
      ;;
    -w|--workspace)
      REMOVE_WORKSPACE=true
      ;;
    -t|--tokens)
      REMOVE_TOKENS=true
      ;;
    -r|--reports)
      REMOVE_REPORTS=true
      ;;
    --all)
      REMOVE_VOLUMES=true
      REMOVE_WORKSPACE=true
      REMOVE_TOKENS=true
      REMOVE_REPORTS=true
      ;;
    -y|--yes|--force)
      FORCE=true
      ;;
    *)
      echo "Unknown option: $arg"
      echo "Use --help for usage details."
      exit 1
      ;;
  esac
done

echo "=========================================================="
echo "          SonarQube Teardown & Cleanup Script             "
echo "=========================================================="

# 1. Stop and remove Docker containers
if [ -f "$DOCKER_COMPOSE_FILE" ]; then
  echo "Stopping and removing SonarQube containers..."
  docker compose -f "$DOCKER_COMPOSE_FILE" down --remove-orphans
  echo "Containers stopped."
else
  echo "docker-compose.yaml not found at $DOCKER_COMPOSE_FILE. Skipping docker down."
fi

# 2. Confirmation helper for destructive actions
confirm_action() {
  local prompt_msg="$1"
  if [ "$FORCE" = true ]; then
    return 0
  fi
  read -r -p "$prompt_msg [y/N]: " response
  case "$response" in
    [yY][eE][sS]|[yY])
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

# 3. Clean persistent data volumes (PostgreSQL data & SonarQube data/logs)
if [ "$REMOVE_VOLUMES" = true ]; then
  if confirm_action "Are you sure you want to delete all SonarQube and PostgreSQL data volumes?"; then
    echo "Deleting persistent volume directories..."
    rm -rf "$SONAR_DATA_DIR" "$SONAR_LOGS_DIR" "$POSTGRES_DATA_DIR"
    echo "Volumes removed."
  else
    echo "Skipped volume deletion."
  fi
fi

# 4. Clean workspace
if [ "$REMOVE_WORKSPACE" = true ]; then
  if [ -d "$CLONE_DIR" ]; then
    echo "Removing cloned workspace ($CLONE_DIR)..."
    rm -rf "$CLONE_DIR"
    echo "Workspace removed."
  fi
fi

# 5. Clean tokens
if [ "$REMOVE_TOKENS" = true ]; then
  if [ -d "$TOKEN_DIR" ]; then
    echo "Removing stored tokens ($TOKEN_DIR)..."
    rm -rf "$TOKEN_DIR"
    echo "Tokens removed."
  fi
fi

# 6. Clean reports
if [ "$REMOVE_REPORTS" = true ]; then
  if [ -d "$REPORTS_DIR" ]; then
    echo "Removing generated reports ($REPORTS_DIR)..."
    rm -rf "$REPORTS_DIR"
    echo "Reports removed."
  fi
fi

echo "=========================================================="
echo "Teardown completed successfully."
echo "=========================================================="
