

# 🚀 Ostad Monitoring - CI/CD & Observability Setup

This repository contains the deployment pipeline and monitoring setup for the **ostad_monitoring** project. It uses GitHub Actions to automatically deploy the Frontend and Node.js Backend to an AWS EC2 instance. Additionally, it configures system observability using **Prometheus**, **Grafana**, and **Node Exporter**.

## 📌 Prerequisites (GitHub Secrets)
To allow GitHub Actions to SSH into your EC2 instance, you must configure the following secrets in your GitHub Repository (`Settings` -> `Secrets and variables` -> `Actions`):

*   `SSH_HOST`: The Public IP address of your EC2 instance.
*   `SSH_USER`: The SSH username (usually `ubuntu` for Ubuntu AMIs).
*   `SSH_PRIVATE_KEY`: The private key (`.pem` file content) used to log into the EC2 instance.

---

## ⚙️ GitHub Actions Workflow
Save the following code in `.github/workflows/deploy.yml`. This workflow copies the code to the server, installs backend dependencies, starts the Node.js app using PM2, and restarts the monitoring services.

```yaml
name: ostad_monitoring

on:
  push:
    branches:
      - main

jobs:
  deploy-and-monitor:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout Code
        uses: actions/checkout@v4
        
      - name: List Local Files
        run: ls -la

      # ✅ STEP 1: Copy frontend folder to EC2
      - name: SCP frontend to EC2
        uses: appleboy/scp-action@v0.1.7
        with:
          host: ${{ secrets.SSH_HOST }}
          username: ${{ secrets.SSH_USER }}
          key: ${{ secrets.SSH_PRIVATE_KEY }}
          port: 22
          source: "Front_end"
          target: "/home/ubuntu/"

      # ✅ STEP 2: Copy backend folder to EC2
      - name: SCP backend to EC2
        uses: appleboy/scp-action@v0.1.7
        with:
          host: ${{ secrets.SSH_HOST }}
          username: ${{ secrets.SSH_USER }}
          key: ${{ secrets.SSH_PRIVATE_KEY }}
          port: 22
          source: "Back_end"
          target: "/home/ubuntu/"

      # ✅ STEP 3: Connect via SSH to Deploy & Manage Services
      - name: Deploy App & Manage Monitoring via SSH
        uses: appleboy/ssh-action@v1.2.0
        with:
          host: ${{ secrets.SSH_HOST }}
          username: ${{ secrets.SSH_USER }}
          key: ${{ secrets.SSH_PRIVATE_KEY }}
          port: 22
          script: |
            echo "=== System Info ==="
            uname -a
            whoami
            pwd
            
            echo "=== Deploying Frontend ==="
            cd /home/ubuntu/Front_end
            sudo cp -r . /var/www/html/
            
            echo "=== Deploying Backend (Node.js) ==="
            cd /home/ubuntu/Back_end
            npm install --production
            # Running/Restarting the backend server using PM2
            pm2 restart ostad_backend || pm2 start index.js --name ostad_backend
            pm2 save
            
            echo "=== Restarting Monitoring Services ==="
            sudo systemctl restart node_exporter
            sudo systemctl restart prometheus
            sudo systemctl restart grafana-server
            
            echo "✅ Deployment and Monitoring setup completed successfully!"
```

---

## 📊 One-Time EC2 Monitoring Setup
Before the CI/CD pipeline can restart the monitoring services, you need to install **Node Exporter**, **Prometheus**, and **Grafana** on your EC2 instance manually.

*(Note: Make sure ports `9100`, `9090`, and `3000` are open in your EC2 Security Group).*

### 1. Node Exporter Setup
```bash
# Create system user
sudo useradd --no-create-home --shell /bin/false node_exporter

# Download and extract
cd /tmp
wget https://github.com/prometheus/node_exporter/releases/download/v1.7.0/node_exporter-1.7.0.linux-amd64.tar.gz
tar -xf node_exporter-1.7.0.linux-amd64.tar.gz

# Install binary
sudo cp -f node_exporter-1.7.0.linux-amd64/node_exporter /usr/local/bin/
sudo chown node_exporter:node_exporter /usr/local/bin/node_exporter

# Clean up
rm -rf node_exporter-1.7.0.linux-amd64*

# Create systemd service
sudo tee /etc/systemd/system/node_exporter.service > /dev/null <<'EOF'
[Unit]
Description=Node Exporter
After=network.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter

[Install]
WantedBy=multi-user.target
EOF

# Start and enable Node Exporter
sudo systemctl daemon-reload
sudo systemctl enable node_exporter
sudo systemctl start node_exporter
```

### 2. Prometheus Setup
```bash
#!/bin/bash
#===============================================================================
# Prometheus Installation Script with Error Handling & Best Practices
# Author: Masudur Rahman
# Date: $(date +%Y-%m-%d)
# Purpose: Production-ready Prometheus setup with systemd
#===============================================================================

set -euo pipefail  # Exit on error, undefined vars, or pipe failures

#-------------------------------------------------------------------------------
# 🎨 Color Codes for Output
#-------------------------------------------------------------------------------
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

#-------------------------------------------------------------------------------
# ⚙️ Configuration Variables (Customize Here)
#-------------------------------------------------------------------------------
readonly PROMETHEUS_VERSION="2.48.0"
readonly PROMETHEUS_USER="prometheus"
readonly PROMETHEUS_GROUP="prometheus"
readonly INSTALL_DIR="/usr/local/bin"
readonly CONFIG_DIR="/etc/prometheus"
readonly DATA_DIR="/var/lib/prometheus"
readonly PROMETHEUS_URL="https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz"
readonly CHECKSUM_URL="${PROMETHEUS_URL}.sha256"
readonly TMP_DIR="/tmp/prometheus-install-$$"
readonly LOG_FILE="/var/log/prometheus-install.log"

#-------------------------------------------------------------------------------
# 🪵 Logging Functions
#-------------------------------------------------------------------------------
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "${LOG_FILE}"
}

info()  { log "INFO"  "${BLUE}ℹ️  $*${NC}"; }
success(){ log "SUCCESS" "${GREEN}✅ $*${NC}"; }
warn()  { log "WARN"  "${YELLOW}⚠️  $*${NC}"; }
error() { log "ERROR" "${RED}❌ $*${NC}"; }

#-------------------------------------------------------------------------------
# 🚨 Error Handler & Cleanup
#-------------------------------------------------------------------------------
cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        error "Script failed with exit code: $exit_code"
        warn "Cleaning up temporary files..."
        [[ -d "${TMP_DIR}" ]] && rm -rf "${TMP_DIR}"
        error "Check ${LOG_FILE} for details."
    fi
}
trap cleanup EXIT INT TERM

#-------------------------------------------------------------------------------
# 🔍 Pre-flight Checks
#-------------------------------------------------------------------------------
preflight_checks() {
    info "Running pre-flight checks..."

    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root or with sudo."
        exit 1
    fi

    # Check required commands
    for cmd in wget tar systemctl; do
        if ! command -v "${cmd}" &> /dev/null; then
            error "Required command '${cmd}' not found. Please install it first."
            exit 1
        fi
    done

    # Check disk space (minimum 1GB free in /var)
    local available_space=$(df -BG /var | awk 'NR==2 {print $4}' | tr -d 'G')
    if [[ ${available_space%.*} -lt 1 ]]; then
        error "Insufficient disk space in /var. At least 1GB required."
        exit 1
    fi

    # Check if Prometheus user already exists
    if id "${PROMETHEUS_USER}" &>/dev/null; then
        warn "User '${PROMETHEUS_USER}' already exists. Skipping creation."
    fi

    success "Pre-flight checks passed."
}

#-------------------------------------------------------------------------------
# 👤 Create System User
#-------------------------------------------------------------------------------
create_prometheus_user() {
    if id "${PROMETHEUS_USER}" &>/dev/null; then
        info "User ${PROMETHEUS_USER} already exists."
        return 0
    fi

    info "Creating system user: ${PROMETHEUS_USER}"
    sudo useradd --no-create-home --shell /bin/false "${PROMETHEUS_USER}" \
        || { error "Failed to create user"; exit 1; }
    success "User ${PROMETHEUS_USER} created successfully."
}

#-------------------------------------------------------------------------------
# 📁 Create Directories
#-------------------------------------------------------------------------------
setup_directories() {
    info "Setting up directories..."
    for dir in "${CONFIG_DIR}" "${DATA_DIR}"; do
        if [[ ! -d "${dir}" ]]; then
            sudo mkdir -p "${dir}" || { error "Failed to create ${dir}"; exit 1; }
            info "Created directory: ${dir}"
        fi
        sudo chown "${PROMETHEUS_USER}:${PROMETHEUS_GROUP}" "${dir}" \
            || { error "Failed to set ownership for ${dir}"; exit 1; }
    done
    success "Directories configured."
}

#-------------------------------------------------------------------------------
# 📥 Download & Verify Prometheus
#-------------------------------------------------------------------------------
download_prometheus() {
    info "Downloading Prometheus v${PROMETHEUS_VERSION}..."
    mkdir -p "${TMP_DIR}"
    cd "${TMP_DIR}"

    # Download binary and checksum
    wget -q --show-progress "${PROMETHEUS_URL}" || { error "Download failed"; exit 1; }
    wget -q "${CHECKSUM_URL}" || { warn "Checksum file not found, skipping verification"; return 0; }

    # Verify SHA256
    if [[ -f "$(basename ${CHECKSUM_URL})" ]]; then
        info "Verifying SHA256 checksum..."
        if echo "$(cat $(basename ${CHECKSUM_URL}))" | sha256sum -c --status 2>/dev/null; then
            success "Checksum verified."
        else
            error "Checksum verification failed! Possible tampering."
            exit 1
        fi
    fi
}

#-------------------------------------------------------------------------------
# 📦 Install Binaries & Configs
#-------------------------------------------------------------------------------
install_prometheus() {
    info "Extracting and installing Prometheus..."
    local extract_dir="prometheus-${PROMETHEUS_VERSION}.linux-amd64"

    tar -xf "prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz" \
        || { error "Extraction failed"; exit 1; }

    # Copy binaries
    sudo cp -f "${extract_dir}/prometheus" "${extract_dir}/promtool" "${INSTALL_DIR}/" \
        || { error "Failed to copy binaries"; exit 1; }

    # Copy default config (backup existing if any)
    if [[ -f "${CONFIG_DIR}/prometheus.yml" ]]; then
        sudo cp "${CONFIG_DIR}/prometheus.yml" "${CONFIG_DIR}/prometheus.yml.bak.$(date +%F)"
        warn "Backed up existing prometheus.yml"
    fi
    sudo cp "${extract_dir}/prometheus.yml" "${CONFIG_DIR}/" \
        || { error "Failed to copy config"; exit 1; }

    # Copy console templates
    sudo cp -rf "${extract_dir}/consoles" "${extract_dir}/console_libraries" "${CONFIG_DIR}/" \
        || { error "Failed to copy console assets"; exit 1; }

    # Set ownership
    sudo chown -R "${PROMETHEUS_USER}:${PROMETHEUS_GROUP}" \
        "${INSTALL_DIR}/prometheus" "${INSTALL_DIR}/promtool" "${CONFIG_DIR}" "${DATA_DIR}" \
        || { error "Failed to set ownership"; exit 1; }

    success "Prometheus installed successfully."
}

#-------------------------------------------------------------------------------
# ⚙️ Create Systemd Service
#-------------------------------------------------------------------------------
setup_systemd_service() {
    info "Creating systemd service..."
    sudo tee /etc/systemd/system/prometheus.service > /dev/null << EOF
[Unit]
Description=Prometheus Monitoring System
Wants=network-online.target
After=network-online.target

[Service]
User=${PROMETHEUS_USER}
Group=${PROMETHEUS_GROUP}
Type=simple
ExecStart=${INSTALL_DIR}/prometheus \
  --config.file ${CONFIG_DIR}/prometheus.yml \
  --storage.tsdb.path ${DATA_DIR}/ \
  --web.console.templates=${CONFIG_DIR}/consoles \
  --web.console.libraries=${CONFIG_DIR}/console_libraries
Restart=on-failure
RestartSec=5s
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

    success "Systemd service file created."
}

#-------------------------------------------------------------------------------
# 🚀 Enable & Start Service
#-------------------------------------------------------------------------------
start_prometheus() {
    info "Reloading systemd daemon..."
    sudo systemctl daemon-reload

    info "Enabling Prometheus service..."
    sudo systemctl enable prometheus

    info "Starting Prometheus..."
    sudo systemctl start prometheus

    # Verify service status
    if sudo systemctl is-active --quiet prometheus; then
        success "✅ Prometheus is running!"
        echo -e "\n${GREEN}📊 Access Prometheus at: http://<your-server-ip>:9090${NC}"
    else
        error "❌ Prometheus failed to start. Check logs:"
        echo -e "${YELLOW}sudo journalctl -u prometheus -f${NC}"
        exit 1
    fi
}

#-------------------------------------------------------------------------------
# 🧹 Cleanup Temporary Files
#-------------------------------------------------------------------------------
cleanup_temp() {
    info "Cleaning up temporary files..."
    [[ -d "${TMP_DIR}" ]] && rm -rf "${TMP_DIR}"
    success "Cleanup complete."
}

#-------------------------------------------------------------------------------
# 🏁 Main Execution
#-------------------------------------------------------------------------------
main() {
    echo -e "${BLUE}🚀 Starting Prometheus Installation v${PROMETHEUS_VERSION}${NC}\n"
    
    preflight_checks
    create_prometheus_user
    setup_directories
    download_prometheus
    install_prometheus
    setup_systemd_service
    start_prometheus
    cleanup_temp

    echo -e "\n${GREEN}✨ Installation completed successfully!${NC}"
    echo -e "${YELLOW}📝 Logs saved to: ${LOG_FILE}${NC}"
}

# Run main function
main "$@"
```

### 3. Grafana Setup
```bash
#!/bin/bash
# Author: Masudur Rahman | Date: 2026

set -e  # Error হলে script stoে

echo "🔄 System updating..."
sudo apt-get update
sudo apt-get install -y apt-transport-https wget gnupg

echo "🔑 GPG key importing..."
sudo mkdir -p /etc/apt/keyrings
sudo wget -O /etc/apt/keyrings/grafana.asc https://apt.grafana.com/gpg-full.key
sudo chmod 644 /etc/apt/keyrings/grafana.asc

echo "📦 Repository adding..."
echo "deb [signed-by=/etc/apt/keyrings/grafana.asc] https://apt.grafana.com stable main" | sudo tee /etc/apt/sources.list.d/grafana.list

echo "⬇️  Grafana installing..."
sudo apt-get update
sudo apt-get install -y grafana

echo "🔧 Service configuring..."
sudo systemctl daemon-reload
sudo systemctl start grafana-server
sudo systemctl enable grafana-server

echo "✅ Installation complete!"
echo "🌐 Access Grafana at: http://$(hostname -I | awk '{print $1}'):3000"
echo "🔐 Default credentials: admin / admin (change on first login!)"
```
* **Grafana** will run on port `3000` (Default login: `admin`/`admin`)
* **Prometheus** will run on port `9090`
* **Node Exporter** will run on port `9100`

---

## 📸 Implementation Screenshots



***


# Project File Structure

| # | File Name | Screenshot |
|---|-----------|------------|
| 1 | Frontend | ![Frontend](screenshots/Frontend.png) |
| 2 | Frontend_database | ![Frontend_database](screenshots/Frontend_database.png) |
| 3 | Github_action | ![Github_action](screenshots/Github_action.png) |
| 4 | github_action_status | ![github_action_status](screenshots/github_action_status.png) |
| 5 | grafana_dashboard | ![grafana_dashboard](screenshots/grafana_dashboard.png) |
| 6 | Grafana_install | ![Grafana_install](screenshots/Grafana_install.png) |
| 7 | grafana_storage | ![grafana_storage](screenshots/grafana_storage.png) |
| 8 | node_exporter_data | ![node_exporter_data](screenshots/node_exporter_data.png) |
| 9 | node_exporter_install | ![node_exporter_install](screenshots/node_exporter_install.png) |
| 10 | Prometheus_dashboard | ![Prometheus_dashboard](screenshots/Prometheus_dashboard.png) |
| 11 | prometheus_install | ![prometheus_install](screenshots/prometheus_install.png) |
| 12 | prometheus_running | ![prometheus_running](screenshots/prometheus_running.png) |
