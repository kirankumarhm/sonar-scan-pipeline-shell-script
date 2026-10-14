# Microservices SonarQube Analysis Automation

## Overview

This setup automates the local SonarQube environment, project onboarding, token generation, and code quality scanning for multiple microservices.

### Prerequisites

- **Docker & Docker Compose** (running)
- **Java 17+ or 21** & **Maven 3.8+** (available locally)
- `curl` and `jq` installed on your system
- GitLab repository access

---

## 1. Directory Structure

```text
├── docker-compose.yaml        # SonarQube & PostgreSQL services
├── initial_setup.sh           # Onboards projects and generates tokens
├── scan_code.sh               # Clones/updates repos and runs Sonar analysis
├── sonar_tokens/              # Generated tokens for each microservice
├── sonarqube_plugins/         # Community plugins mounted to /opt/sonarqube/extensions/plugins
│   └── conflicting_or_unextracted/  # Isolated duplicate built-in analyzers and archives
```

---

## 2. ⚙️ Configuration: What You Need to Change

Before running the scripts, you must configure your repository names, Git base URL, and credentials. You can either edit the variables directly at the top of the scripts or pass them as environment variables.

### Variables Summary

| Variable | File(s) | Default / Example Value | Description |
| :--- | :--- | :--- | :--- |
| `REPOS` | `initial_setup.sh`<br>`scan_code.sh` | `("service1" "service2" "service3")` | **Must change**: The array of repository/microservice folder names to onboard and scan. |
| `GITLAB_URL` | `scan_code.sh` | `https://gitlab.com/yourapp` | **Must change**: The base Git URL (GitLab/GitHub/Bitbucket) from which repos are cloned. Repos will be cloned as `${GITLAB_URL}/${REPO}.git`. |
| `SONARQUBE_PASSWORD` | `initial_setup.sh`<br>`scan_code.sh` | `admin1` | The password for the SonarQube `admin` user. (Default on first boot is `admin`). |
| `SONARQUBE_URL` | `initial_setup.sh`<br>`scan_code.sh` | `http://localhost:9001` | The HTTP URL of your SonarQube server. Change if running on a remote host or different port. |
| `PROJECT_PREFIX` | `initial_setup.sh`<br>`scan_code.sh` | `""` (empty) | *Optional*: Prefix added to project keys (e.g. `MyOrg-service1`). If empty, project key is just the repo name. |
| `TOKEN` | `scan_code.sh` | `""` (empty) | *Optional*: Static analysis token fallback if not using per-repo tokens generated in `sonar_tokens/`. |

---

### Where to Edit in the Scripts

#### 1. In `initial_setup.sh` (Lines 5–10):
```bash
# --- Configuration & Variables ---
SONARQUBE_URL="${SONARQUBE_URL:-http://localhost:9001}"
SONARQUBE_USERNAME="${SONARQUBE_USERNAME:-admin}"
SONARQUBE_PASSWORD="${SONARQUBE_PASSWORD:-your-password}"     # <-- Change to your password
PROJECT_PREFIX="${PROJECT_PREFIX:-}"                         # <-- Optional prefix (e.g. "MyApp")
REPOS=("config-server" "inventory-service" "pricing-service") # <-- Change to your repo names
TOKEN_DIR="${TOKEN_DIR:-sonar_tokens}"
```

#### 2. In `scan_code.sh` (Lines 11–17):
```bash
# --- Configuration & Variables ---
GITLAB_URL="${GITLAB_URL:-https://github.com/your-username}"  # <-- Change to your Git base URL
REPOS=("config-server" "inventory-service" "pricing-service") # <-- Must match initial_setup.sh
SONARQUBE_URL="${SONARQUBE_URL:-http://localhost:9001}"
SONARQUBE_USERNAME="${SONARQUBE_USERNAME:-admin}"
SONARQUBE_PASSWORD="${SONARQUBE_PASSWORD:-your-password}"     # <-- Change to your password
PROJECT_PREFIX="${PROJECT_PREFIX:-}"
SERVICE_NAME="sonarqube"
```

> [!TIP]
> **No code editing needed if using environment variables**:
> You can also run the scripts without modifying them by exporting environment variables:
> ```bash
> GITLAB_URL="https://github.com/my-org" SONARQUBE_PASSWORD="my-password" ./scan_code.sh
> ```

---

## 3. Starting the SonarQube Environment

The `docker-compose.yaml` utilizes the local `postgres:17.6` image and mounts community plugins directly into SonarQube.

Start services:
```bash
docker compose up -d
```

Check status:
```bash
docker compose ps
```

Access the web interface at [http://localhost:9001](http://localhost:9001).
Default credentials for a fresh instance: `admin` / `admin` (you will be prompted to change it on first login).

---

## 4. Initial Setup (`initial_setup.sh`)

Run this script once to create SonarQube projects and generate per-service analysis tokens:

```bash
chmod +x initial_setup.sh
./initial_setup.sh
```

### Features:
- **Idempotent**: Safe to run repeatedly; revokes and regenerates tokens if projects already exist.
- **Secure token storage**: Stores each service token in `sonar_tokens/<service>_token.txt` with restricted `600` file permissions.
- **Configurable**: Override defaults via environment variables:
  ```bash
  SONARQUBE_URL="http://localhost:9001" SONARQUBE_PASSWORD="admin1" ./initial_setup.sh
  ```

---

## 5. Code Scanning (`scan_code.sh`)

Analyze all microservices automatically:

```bash
chmod +x scan_code.sh
./scan_code.sh
```

### Script Execution Flow:
1. **Container & API Readiness**: Automatically verifies Docker containers are up and polls `http://localhost:9001/api/system/status` until SonarQube is `UP`.
2. **Project Validation**: Ensures projects exist in SonarQube.
3. **Repository Sync**: Uses `git pull` if the repo was already cloned, or `git clone` if first run.
4. **Analysis Execution**: Runs `mvn clean verify sonar:sonar` using each service's specific token from `sonar_tokens/`.
5. **Non-Destructive by Default**: Preserves historical quality trends, baselines, and quality gates across runs.

### Optional Flags:
- `--clean-projects`: Deletes projects from SonarQube prior to scanning (wipes history).
- `--clean-workspace`: Removes `./java-workspace` after the scan completes.
- `--report`: Generates CNES reports using `sonar-cnes-report` in `sonarqube_plugins/`.

Example:
```bash
./scan_code.sh --report
```
