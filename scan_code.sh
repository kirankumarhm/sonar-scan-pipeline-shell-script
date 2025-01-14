#!/bin/bash

# Variables
GITLAB_URL="https://gitlab.spectrumflow.net/force"
REPOS=("source-of-truth-service" "config-manager-service" "job-management-service" "workflow-service")
CLONE_DIR="microservices"
SONARQUBE_URL="http://sonarqube:9000"
PROJECT_NAME="Charter-High-Split"
TOKEN_DIR="sonar_tokens"
DOCKER_NETWORK="sonarqube_default"  # Replace with your Docker network name if needed


# Create a directory for all microservices
mkdir -p $CLONE_DIR

git clone https://gitlab.spectrumflow.net/force/charter-common-libs.git
cd charter-common-libs
mvn clean install
cd -

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
    PROJECT_KEY="${REPO}"
    TOKEN=$(cat $TOKEN_DIR/${REPO}_token.txt)

    # Create sonar-project.properties file
    # sonar.java.binaries=target/classes  # Path to the compiled classes
  # Create sonar-project.properties file
  cat <<EOL > $CLONE_DIR/$REPO/sonar-project.properties
sonar.projectKey=$PROJECT_KEY
sonar.projectName=$PROJECT_KEY
sonar.projectVersion=1.0
sonar.sources=.
sonar.host.url=$SONARQUBE_URL
sonar.login=$TOKEN
sonar.java.binaries=target/classes
EOL
    cd $CLONE_DIR/$REPO

    # Compile the project using Maven
    mvn clean install

    # Run SonarScanner using Docker
    docker run --rm \
        --network $DOCKER_NETWORK \
        -e SONAR_HOST_URL="$SONARQUBE_URL" \
        -e SONAR_LOGIN="$TOKEN" \
        -v "$(pwd):/usr/src" \
        sonarsource/sonar-scanner-cli
    cd -
done

echo "SonarScanner analysis completed for all microservices."
