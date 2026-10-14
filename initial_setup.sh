#!/bin/bash
set -eo pipefail

# --- Configuration & Variables ---
SONARQUBE_URL="${SONARQUBE_URL:-http://localhost:9001}"
SONARQUBE_USERNAME="${SONARQUBE_USERNAME:-admin}"
SONARQUBE_PASSWORD="${SONARQUBE_PASSWORD:-admin1}"
PROJECT_PREFIX="${PROJECT_PREFIX:-}" # Optional prefix, e.g. "Charter-High-Split"
REPOS=("service1" "service2" "service3" "service4")
TOKEN_DIR="${TOKEN_DIR:-sonar_tokens}"

# --- Check Prerequisites ---
for cmd in curl jq; do
  if ! command -v "$cmd" &> /dev/null; then
    echo "Error: Required tool '$cmd' is not installed or not in PATH."
    exit 1
  fi
done

# --- Check SonarQube Readiness ---
echo "Checking connection to SonarQube at $SONARQUBE_URL..."
STATUS=$(curl -s -f "$SONARQUBE_URL/api/system/status" 2>/dev/null | jq -r '.status // empty' 2>/dev/null || true)
if [ "$STATUS" != "UP" ]; then
  echo "Error: SonarQube server is not ready (Status: '${STATUS:-UNREACHABLE}')."
  echo "Please start SonarQube ('docker compose up -d') and wait until it is fully initialized."
  exit 1
fi
echo "SonarQube is UP and ready."

# Create directory to store tokens securely
mkdir -p "$TOKEN_DIR"
chmod 700 "$TOKEN_DIR"

# --- Create Projects and Generate Tokens ---
for REPO in "${REPOS[@]}"; do
  if [ -n "$PROJECT_PREFIX" ]; then
    PROJECT_KEY="${PROJECT_PREFIX}-${REPO}"
  else
    PROJECT_KEY="${REPO}"
  fi
  
  echo "----------------------------------------"
  echo "Processing: $REPO (Project Key: $PROJECT_KEY)"

  # 1. Check if Project already exists
  SEARCH_RES=$(curl -s -u "$SONARQUBE_USERNAME:$SONARQUBE_PASSWORD" "$SONARQUBE_URL/api/projects/search?projects=$PROJECT_KEY")
  EXISTS=$(echo "$SEARCH_RES" | jq -r '.components | length' 2>/dev/null || echo 0)

  if [ "$EXISTS" -eq 0 ]; then
    echo "Creating project '$PROJECT_KEY'..."
    CREATE_RES=$(curl -s -X POST -u "$SONARQUBE_USERNAME:$SONARQUBE_PASSWORD" \
      -d "name=$PROJECT_KEY&project=$PROJECT_KEY" \
      "$SONARQUBE_URL/api/projects/create")
    if echo "$CREATE_RES" | jq -e '.project' > /dev/null 2>&1; then
      echo "Project '$PROJECT_KEY' created successfully."
    else
      ERR_MSG=$(echo "$CREATE_RES" | jq -r '.errors[0].msg // "Unknown error"')
      echo "Failed to create project '$PROJECT_KEY': $ERR_MSG"
      exit 1
    fi
  else
    echo "Project '$PROJECT_KEY' already exists. Skipping project creation."
  fi

  # 2. Manage Analysis Token (Revoke existing if present to ensure fresh token)
  TOKEN_NAME="${PROJECT_KEY}-token"
  curl -s -X POST -u "$SONARQUBE_USERNAME:$SONARQUBE_PASSWORD" \
    -d "name=$TOKEN_NAME" \
    "$SONARQUBE_URL/api/user_tokens/revoke" > /dev/null 2>&1 || true

  # Try generating project analysis token (SonarQube 9.5+) with fallback to standard token
  GEN_RES=$(curl -s -X POST -u "$SONARQUBE_USERNAME:$SONARQUBE_PASSWORD" \
    -d "name=$TOKEN_NAME&type=PROJECT_ANALYSIS_TOKEN&projectKey=$PROJECT_KEY" \
    "$SONARQUBE_URL/api/user_tokens/generate")

  TOKEN=$(echo "$GEN_RES" | jq -r '.token // empty' 2>/dev/null)
  if [ -z "$TOKEN" ]; then
    # Fallback to standard user token without projectKey parameter
    GEN_RES=$(curl -s -X POST -u "$SONARQUBE_USERNAME:$SONARQUBE_PASSWORD" \
      -d "name=$TOKEN_NAME" \
      "$SONARQUBE_URL/api/user_tokens/generate")
    TOKEN=$(echo "$GEN_RES" | jq -r '.token // empty' 2>/dev/null)
  fi

  if [ -z "$TOKEN" ]; then
    ERR_MSG=$(echo "$GEN_RES" | jq -r '.errors[0].msg // "Unknown error"')
    echo "Error: Failed to generate token for '$REPO'. Response: $ERR_MSG"
    exit 1
  fi

  # Save token to file
  TOKEN_FILE="$TOKEN_DIR/${REPO}_token.txt"
  echo "$TOKEN" > "$TOKEN_FILE"
  chmod 600 "$TOKEN_FILE"
  echo "Generated Token for '$REPO' (saved to $TOKEN_FILE)"
done

echo "========================================"
echo "Initial setup completed successfully for all microservices."
