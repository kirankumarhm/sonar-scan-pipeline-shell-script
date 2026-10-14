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

## 2. Starting the SonarQube Environment

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
Default credentials for a fresh instance: `admin` / `admin` (or configured `admin1`).

---

## 3. Initial Setup (`initial_setup.sh`)

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

## 4. Code Scanning (`scan_code.sh`)

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
