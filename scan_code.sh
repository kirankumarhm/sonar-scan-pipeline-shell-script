#!/bin/bash

# Variables
GITLAB_URL="https://gitlab.com/yourapp"
REPOS=("service1" "service2" "service3" "service4")
CLONE_DIR="./java-workspace"
SONARQUBE_URL="http://localhost:9001"
DOCKER_NETWORK="sonarqube_default"
SONARQUBE_USERNAME="admin"
SONARQUBE_PASSWORD="admin1"
TOKEN="squ_e11f441d4e6e754e6e4ef197f1faf65d56f7c87d"

# --- Utility Functions ---
# Function to check if the specific service container is currently running.
# This function is used internally by check_sonarqube_status and start_sonarqube.
_is_sonarqube_running() {
    # 'docker compose ps -q <service_name>' returns the container ID if running, or nothing if not.
    # We explicitly use './docker-compose.yaml' as per user's request.
    local running_id=$(docker compose -f "./docker-compose.yaml" ps -q "$SERVICE_NAME")
    if [ -n "$running_id" ]; then
        return 0 # Sonarqube is running
    else
        return 1 # Sonarqube is not running
    fi
}

# Function to check if sonarqube is running after 'docker compose up'
check_sonarqube_status() {
    local attempts=0
    local max_attempts=3 # Max 3 attempts to check after 'up'
    local wait_time=10   # Wait 10 seconds between checks for individual service status

    echo "Verifying '$SERVICE_NAME' container status..."
    while [ "$attempts" -lt "$max_attempts" ]; do
        if _is_sonarqube_running; then
            echo "'$SERVICE_NAME' container is now running."
            return 0 # Success
        else
            echo "Waiting for '$SERVICE_NAME' container to come up (attempt $((attempts+1))/$max_attempts)..."
            sleep "$wait_time"
            attempts=$((attempts+1))
        fi
    done
    echo "Timed out waiting for '$SERVICE_NAME' container to come up."
    return 1 # Failure
}

# Function to bring up Docker containers with retry logic
start_sonarqube() {
    echo "Attempting to bring up Docker containers..."
    # First attempt to bring up the containers
    # We explicitly use './docker-compose.yaml' as per user's request.
    docker compose -f "./docker-compose.yaml" up -d

    # Check if the sonarqube service is running after the first attempt
    if check_sonarqube_status; then
        echo "Docker containers are now up and running in detached mode, and '$SERVICE_NAME' is active."
        echo "Current status of all containers:"
        docker compose -f "./docker-compose.yaml" ps
    else
        echo "First attempt to bring up containers succeeded but '$SERVICE_NAME' did not become active. Waiting 30 seconds before retrying 'docker compose up'..."
        sleep 30 # User requested 30 seconds wait for retry

        echo "Retrying to bring up Docker containers..."
        # Second attempt to bring up the containers
        docker compose -f "./docker-compose.yaml" up -d

        # Check if the sonarqube service is running after the second attempt
        if check_sonarqube_status; then
            echo "Docker containers are now up and running after retry, and '$SERVICE_NAME' is active."
            echo "Current status of all containers:"
            docker compose -f "./docker-compose.yaml" ps
        else
            echo "Error: Second attempt to bring up Docker containers also failed or '$SERVICE_NAME' did not become active."
            echo "Please check your 'docker-compose.yaml' file, Docker daemon status, and container logs for issues."
            exit 1
        fi
    fi
}


# start_sonarqube() {
#   if ! docker compose -f ./docker-compose.yaml ps | grep -q 'Up'; then
#     docker compose -f ./docker-compose.yaml up -d
#     sleep 1m
#     docker compose -f ./docker-compose.yaml up -d
#     sleep 1m
#   else
#     echo "SonarQube docker compose services are already running. Skipping start and wait."
#   fi
# }

create_project() {
  for REPO in "${REPOS[@]}"; do
    local exists
    exists=$(curl -s -u "$SONARQUBE_USERNAME:$SONARQUBE_PASSWORD" "$SONARQUBE_URL/api/projects/search?projects=$REPO" | jq -r '.components | length' 2>/dev/null)
    if ! [[ "$exists" =~ ^[0-9]+$ ]]; then
      exists=0
    fi
    if [ "$exists" -eq 0 ]; then
      response=$(curl -s -X POST -u "$SONARQUBE_USERNAME:$SONARQUBE_PASSWORD" \
        -d "name=$REPO&project=$REPO" \
        "$SONARQUBE_URL/api/projects/create")
      if echo "$response" | grep -q 'project'; then
        echo "Project $REPO created as private."
      else
        echo "Failed to create project $REPO. Response: $response"
      fi
    else
      echo "Project $REPO already exists. No action taken."
    fi
  done
}

delete_project() {
  for REPO in "${REPOS[@]}"; do
    curl -s -X POST -u "$SONARQUBE_USERNAME:$SONARQUBE_PASSWORD" "$SONARQUBE_URL/api/projects/delete?project=$REPO" > /dev/null
    echo "Project $REPO deleted."
  done
}

clone_or_update_repo() {
  cd "$CLONE_DIR"
  for REPO in "${REPOS[@]}"; do
    if [ -d "$CLONE_DIR/$REPO" ]; then
      cd "$CLONE_DIR/$REPO"
      # git checkout offshore
      # git fetch origin offshore
      git pull
    else
      # git clone -b offshore "$GITLAB_URL/$REPO.git"
      git clone "$GITLAB_URL/$REPO.git"
    fi
  done
  cd ../
}



build_project() {
  for REPO in "${REPOS[@]}"; do
    cd "$CLONE_DIR/$REPO"
    mvn clean package jacoco:report
    cd - > /dev/null
  done 
}


run_sonar_scanner() {
  cd "$CLONE_DIR"
  for REPO in "${REPOS[@]}"; do
    cd "$REPO"
    mvn clean verify sonar:sonar \
      -Dsonar.projectKey=$REPO \
      -Dsonar.projectName=$REPO \
      -Dsonar.host.url=http://localhost:9001 \
      -Dsonar.login=$TOKEN
    cd ../
  done
  cd ../
}

take_report() {
  for REPO in "${REPOS[@]}"; do
    java -jar sonar-cnes-report-4.2.0.jar -t $TOKEN -s http://localhost:9001 -p $REPO -o $REPO
  done
}  
    # java -jar sonar-cnes-report-5.0.0.jar -t $TOKEN -s http://localhost:9001 -p $REPO -o $REPO


# --- Main Script ---
mkdir -p "$CLONE_DIR"

# start_sonarqube
# Main script logic starts here

# Check if the specific service container is currently running.
if _is_sonarqube_running; then
    echo "The '$SERVICE_NAME' container is already running. No action needed."
    echo "Current status of all containers in the project:"
    docker compose -f "./docker-compose.yaml" ps
    # exit 0 # Exit if already running
else
    echo "The '$SERVICE_NAME' container is NOT found running."
    # Call the start_sonarqube function to bring up containers if needed
    start_sonarqube
fi

echo "Starting SonarScanner analysis for all microservices..."

# # Uncomment to delete all projects first
# This is required because some times the project is not 
#  deleted from SonarQube and old status is shown

echo "Deleting project ..."
delete_project

echo "Creating project ..."
create_project

echo "Cloning or updating repository ..."
clone_or_update_repo

run_sonar_scanner

# take_report

# # docker compose -f ./docker-compose.yaml down
rm -rf $CLONE_DIR



#   rm -rf "$TOKEN_DIR/${REPO}_token.txt"
# java -jar sonar-cnes-report-5.0.0.jar -t squ_a40960ab8d2a8b27d433a2e621486eabf0c751ef -s http://localhost:9001 -p config-manager-service -r ./template.docx

echo "SonarScanner analysis completed for all microservices."
