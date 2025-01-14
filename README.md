# Microservices SonarQube Analysis Automation

## Problem Statement

We need to automate the process of analyzing multiple Spring Boot microservices using SonarQube. The automation should include the following steps:

1. **Initial Setup**:
   - Create SonarQube projects for each microservice.
   - Generate and store SonarQube tokens for each microservice.

2. **Code Scanning**:
   - Clone or pull the latest code for each microservice from GitLab.
   - Run SonarScanner CLI using Docker to analyze the code and generate reports.

## Prerequisites

- Git
- Docker
- SonarQube server
- SonarQube user credentials with permissions to create projects and generate tokens
- `curl` and `jq` installed on your system

## Initial Setup

The initial setup script creates SonarQube projects and generates tokens for each microservice. This script should be run once.

### Script: `initial_setup.sh`

```bash
#!/bin/bash

# Variables
SONARQUBE_URL="http://your-sonarqube-server"
SONARQUBE_USERNAME="your-username"
SONARQUBE_PASSWORD="your-password"
PROJECT_NAME="High-Split"  # Replace spaces with hyphens or underscores
REPOS=("source-of-truth-service" "config-manager-service" "job-management-service" "workflow-service")
TOKEN_DIR="sonar_tokens"

# Create a directory to store tokens
mkdir -p $TOKEN_DIR

# Create SonarQube projects and generate tokens
for REPO in "${REPOS[@]}"; do
  PROJECT_KEY="${PROJECT_NAME}-${REPO}"
  
  # Create SonarQube project
  curl -X POST -u $SONARQUBE_USERNAME:$SONARQUBE_PASSWORD -d "name=$PROJECT_KEY&project=$PROJECT_KEY" "$SONARQUBE_URL/api/projects/create"

  # Generate SonarQube token for each microservice
  TOKEN_NAME="${REPO}-token"
  RESPONSE=$(curl -X POST -u $SONARQUBE_USERNAME:$SONARQUBE_PASSWORD -d "name=$TOKEN_NAME" "$SONARQUBE_URL/api/user_tokens/generate")
  TOKEN=$(echo $RESPONSE | jq -r '.token')

  if [ "$TOKEN" == "null" ]; then
    echo "Failed to generate token for $REPO. Please check your credentials and SonarQube server."
    exit 1
  fi

  echo "Generated Token for $REPO: $TOKEN"

  # Store the token in a file
  echo $TOKEN > $TOKEN_DIR/${REPO}_token.txt
done

echo "Initial setup completed for all microservices."




Running the Initial Setup Script
Make the script executable:
chmod +x initial_setup.sh

Run the script:
./initial_setup.sh

Code Scanning
The code scanning script clones or pulls the latest code for each microservice and runs SonarScanner using Docker.

Script: scan_code.sh
#!/bin/bash

# Variables
GITLAB_URL="https://gitlab.com/your-username"
REPOS=("source-of-truth-service" "config-manager-service" "job-management-service" "workflow-service")
CLONE_DIR="microservices"
SONARQUBE_URL="http://your-sonarqube-server"
PROJECT_NAME="High-Split"  # Replace spaces with hyphens or underscores
TOKEN_DIR="sonar_tokens"

# Create a directory for all microservices
mkdir -p $CLONE_DIR

# Clone or pull the latest code for each repository
for REPO in "${REPOS[@]}"; do
  if [ -d "$CLONE_DIR/$REPO" ]; then
    cd $CLONE_DIR/$REPO
    git pull
    cd -
  else
    git clone $GITLAB_URL/$REPO.git $CLONE_DIR/$REPO
  fi
done

# Run SonarScanner on each microservice using Docker
for REPO in "${REPOS[@]}"; do
  PROJECT_KEY="${PROJECT_NAME}-${REPO}"
  TOKEN=$(cat $TOKEN_DIR/${REPO}_token.txt)

  cd $CLONE_DIR/$REPO
  docker run --rm \
    -e SONAR_HOST_URL="$SONARQUBE_URL" \
    -e SONAR_LOGIN="$TOKEN" \
    -v "$(pwd):/usr/src" \
    sonarsource/sonar-scanner-cli
  cd -
done

echo "SonarScanner analysis completed for all microservices."

Running the Code Scanning Script
Make the script executable:
chmod +x scan_code.sh

Run the script:
./scan_code.sh

Conclusion
These scripts automate the process of setting up SonarQube projects, generating tokens, and running code analysis for multiple Spring Boot microservices. Ensure that you replace the placeholder values with your actual details before running the scripts.