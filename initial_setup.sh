#!/bin/bash

# Variables
SONARQUBE_URL="http://localhost:9001"
SONARQUBE_USERNAME="admin"
SONARQUBE_PASSWORD="yourpassword"
PROJECT_NAME="Charter-High-Split"
REPOS=("source-of-truth-service" "config-manager-service" "job-management-service" "workflow-service")
TOKEN_DIR="sonar_tokens"

# Create a directory to store tokens
mkdir -p $TOKEN_DIR

# Create SonarQube projects and generate tokens
for REPO in "${REPOS[@]}"; do
  PROJECT_KEY="${REPO}"
  
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
