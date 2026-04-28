#!/bin/bash

################################################################################
# PanelX V3.0.0 PRO - DOCKER-FRIENDLY Auto-Installer
# ✅ Optimized for Docker Containers & Ubuntu/Debian
# ✅ No systemctl dependency
# ✅ Auto-injects Database URL
################################################################################

set -e
set -o pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Logging functions
log_info() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[!]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }
log_step() { echo -e "\n${CYAN}${BOLD}[STEP $1/15]${NC} $2"; }

# Banner
clear
echo -e "${CYAN}PanelX V3.0.0 PRO - Docker Optimized Edition${NC}"

# ============================================================================
# STEP 1: System Update
# ============================================================================
log_step 1 "Updating system packages"
apt-get update -qq && apt-get upgrade -y -qq
log_info "System packages updated"

# ============================================================================
# STEP 2: Install Node.js 20
# ============================================================================
log_step 2 "Installing Node.js 20"
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y nodejs
log_info "Node.js $(node -v) installed"

# ============================================================================
# STEP 3: Install PostgreSQL
# ============================================================================
log_step 3 "Installing PostgreSQL"
apt-get install -y postgresql postgresql-contrib
/etc/init.d/postgresql restart
log_info "PostgreSQL is running"

# ============================================================================
# STEP 4: Install Nginx
# ============================================================================
log_step 4 "Installing Nginx"
apt-get install -y nginx
/etc/init.d/nginx restart
log_info "Nginx installed"

# ============================================================================
# STEP 5: Install System Dependencies
# ============================================================================
log_step 5 "Installing system dependencies"
apt-get install -y ffmpeg curl wget git build-essential net-tools
log_info "Dependencies installed"

# ============================================================================
# STEP 6: Create System User 'panelx'
# ============================================================================
log_step 6 "Setting up user"
id -u panelx &>/dev/null || useradd -m -s /bin/bash panelx
sudo -u panelx mkdir -p /home/panelx/logs /home/panelx/backups
log_info "User panelx ready"

# ============================================================================
# STEP 7: Setup PostgreSQL Database
# ============================================================================
log_step 7 "Configuring database"
cd /
sudo -u postgres psql -c "DROP DATABASE IF EXISTS panelx;" || true
sudo -u postgres psql -c "DROP USER IF EXISTS panelx;" || true
sudo -u postgres psql -c "CREATE USER panelx WITH PASSWORD 'panelx123';"
sudo -u postgres psql -c "CREATE DATABASE panelx OWNER panelx;"
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE panelx TO panelx;"
log_info "Database created"

# ============================================================================
# STEP 8: Clone Project
# ============================================================================
log_step 8 "Cloning project"
PROJECT_DIR="/home/panelx/webapp"
rm -rf "$PROJECT_DIR"
# এখানে তোমার গিটহাব ইউজারনেম বসিয়ে দিও
sudo -u panelx git clone -q https://github.com/utbdofficial/PanelX-V3.0.0-PRO.git "$PROJECT_DIR"
cd "$PROJECT_DIR"

# ============================================================================
# STEP 9: Install Dependencies & Build
# ============================================================================
log_step 9 "Building Application"
sudo -u panelx npm install
log_info "Building frontend..."
sudo -u panelx bash -c "cd $PROJECT_DIR && npm run build"

# ============================================================================
# STEP 10: Environment Configuration
# ============================================================================
log_step 10 "Creating .env"
DB_URL="postgresql://panelx:panelx123@localhost:5432/panelx"
sudo -u panelx tee "$PROJECT_DIR/.env" > /dev/null <<EOF
DATABASE_URL=$DB_URL
PORT=5000
NODE_ENV=production
SESSION_SECRET=$(openssl rand -base64 32)
EOF

# ============================================================================
# STEP 11: PM2 Setup
# ============================================================================
log_step 11 "Starting PM2"
npm install -g pm2
cd "$PROJECT_DIR"
sudo -u panelx DATABASE_URL=$DB_URL pm2 start "npx tsx server/index.ts" --name panelx
sudo -u panelx pm2 save
log_info "PM2 process started"

# ============================================================================
# STEP 12: Database Schema & Seed
# ============================================================================
log_step 12 "Database Push"
sudo -u panelx DATABASE_URL=$DB_URL npx drizzle-kit push --force || true
# Manual Admin Insert (Bulletproof)
sudo -u postgres psql -d panelx -c "INSERT INTO users (username, password, role, enabled, credits) VALUES ('admin', '\$2y\$10\$y8w96Ditl9szKeh1dnpEm.qZPB7O8hqQfXDII63d726kbi/kyKt8C', 'admin', true, 0) ON CONFLICT (username) DO NOTHING;"

# ============================================================================
# STEP 13: Nginx Proxy Config
# ============================================================================
log_step 13 "Configuring Nginx Proxy"
cat <<EOF > /etc/nginx/sites-enabled/default
server {
    listen 80;
    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
    }
}
EOF
/etc/init.d/nginx restart
log_info "Nginx restarted on port 80"

echo -e "\n${GREEN}${BOLD}✅ SUCCESS! Panel is live at http://$(curl -s ifconfig.me)${NC}"
echo -e "Login with your admin credentials."
