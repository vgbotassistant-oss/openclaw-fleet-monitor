#!/bin/bash
# OpenClaw Fleet Monitor - Production Deployment
# Phase 8: Secure Remote deployment to vgbots.duckdns.org

set -euo pipefail

SERVER="5.75.139.78"
USER="root"
PASSWORD="Airhelly1"
DOMAIN="vgbots.duckdns.org"

echo "🚀 Deploying OpenClaw Fleet Monitor to production..."
echo "📡 Server: $SERVER"
echo "🌐 Domain: $DOMAIN"
echo "🔐 Credentials: victor/Airhelly1"

# Function to run remote commands
remote_cmd() {
    sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no "$USER@$SERVER" "$1"
}

# Function to copy files
remote_copy() {
    local src="$1"
    local dst="$2"
    sshpass -p "$PASSWORD" scp -o StrictHostKeyChecking=no -r "$src" "$USER@$SERVER:$dst"
}

echo "📦 Step 1: Checking server connectivity..."
remote_cmd "echo '✅ Server connection established'"

echo "📁 Step 2: Creating project directory on server..."
remote_cmd "mkdir -p /root/openclaw-fleet-monitor"

echo "📤 Step 3: Copying project files to server..."
remote_copy "/root/.openclaw/projects/openclaw-fleet-monitor/" "/root/"

echo "🔧 Step 4: Making scripts executable on server..."
remote_cmd "chmod +x /root/openclaw-fleet-monitor/*.bash /root/openclaw-fleet-monitor/*.sh"

echo "🛠️ Step 5: Running server setup..."
# Run the setup script on the server
remote_cmd "cd /root/openclaw-fleet-monitor && ./setup-server.sh"

echo "📊 Step 6: Starting Fleet Monitor services..."
remote_cmd "cd /root/openclaw-fleet-monitor && nohup ./start-server.sh > /var/log/fleet-monitor.log 2>&1 &"

echo "⏰ Step 7: Setting up cron job for data updates..."
remote_cmd "(crontab -l | grep -v 'fleet-data-structural.bash') && echo '*/1 * * * * cd /root/openclaw-fleet-monitor && bash fleet-data-structural.bash >> /tmp/fleet-cron.log 2>&1' | crontab -"

echo "🧪 Step 8: Verifying deployment..."
echo "Waiting 10 seconds for services to start..."
sleep 10

# Test the deployment
echo "🔍 Running deployment tests..."
remote_cmd "curl -s -o /dev/null -w '%{http_code}' http://localhost:8081/health" | grep -q "200" && echo "✅ Health check passed" || echo "❌ Health check failed"
remote_cmd "curl -s -o /dev/null -w '%{http_code}' http://localhost:8081/data/fleet.json" | grep -q "200" && echo "✅ Data API working" || echo "❌ Data API failed"

echo ""
echo "🎉 DEPLOYMENT COMPLETE!"
echo ""
echo "📊 Production URLs:"
echo "  - Dashboard: https://$DOMAIN/"
echo "  - Health check: https://$DOMAIN/health"
echo "  - Data API: https://$DOMAIN/data/fleet.json"
echo ""
echo "🔐 Authentication:"
echo "  - Username: victor"
echo "  - Password: Airhelly1"
echo ""
echo "🔧 Server Info:"
echo "  - SSH: ssh root@$SERVER"
echo "  - Logs: /var/log/fleet-monitor.log"
echo "  - Cron logs: /tmp/fleet-cron.log"
echo ""
echo "✅ Phase 8: Secure Remote deployment complete!"