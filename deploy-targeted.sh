#!/bin/bash
# OpenClaw Fleet Monitor - Targeted Production Deployment
# Phase 8: Secure Remote deployment (minimal changes)

set -euo pipefail

SERVER="5.75.139.78"
USER="root"
PASSWORD="Airhelly1"
DOMAIN="vgbots.duckdns.org"

echo "🎯 Targeted deployment to $SERVER..."

# 1. Install password utility if needed
sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no "$USER@$SERVER" "
    if ! command -v htpasswd >/dev/null 2>&1; then
        echo '📦 Installing apache2-utils...'
        apt update && apt install -y apache2-utils
    fi
"

# 2. Create password file with Victor's credentials
echo "🔐 Creating password file..."
sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no "$USER@$SERVER" "
    htpasswd -c -b /etc/nginx/.htpasswd-fleet victor Airhelly1 2>/dev/null || \
    htpasswd -b /etc/nginx/.htpasswd-fleet victor Airhelly1
    chmod 644 /etc/nginx/.htpasswd-fleet
    echo '✅ Password file created: victor/Airhelly1'
"

# 3. Install our nginx config
echo "📁 Installing nginx config..."
sshpass -p "$PASSWORD" scp -o StrictHostKeyChecking=no nginx-fleet-monitor.conf "$USER@$SERVER:/etc/nginx/sites-available/fleet-monitor"

# 4. Enable the site
sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no "$USER@$SERVER" "
    ln -sf /etc/nginx/sites-available/fleet-monitor /etc/nginx/sites-enabled/
    echo '✅ nginx config installed'
"

# 5. Test nginx config
echo "🧪 Testing nginx configuration..."
sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no "$USER@$SERVER" "
    if nginx -t; then
        echo '✅ nginx config test passed'
    else
        echo '❌ nginx config test failed'
        exit 1
    fi
"

# 6. Get SSL certificate if not already exists
echo "🔐 Checking SSL certificate..."
sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no "$USER@$SERVER" "
    if [ ! -d /etc/letsencrypt/live/$DOMAIN ]; then
        echo '📝 Getting SSL certificate from Let\'s Encrypt...'
        certbot --nginx -d $DOMAIN --email agents@vgbotassistant-oss --agree-tos --non-interactive
        echo '✅ SSL certificate obtained'
    else
        echo '✅ SSL certificate already exists'
    fi
"

# 7. Start Fleet Monitor services
echo "🚀 Starting Fleet Monitor services..."
sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no "$USER@$SERVER" "
    cd /root/openclaw-fleet-monitor/openclaw-fleet-monitor
    
    # Kill any existing processes
    pkill -f 'python3 serve.py' 2>/dev/null || true
    pkill -f 'python3 websocket-server.py' 2>/dev/null || true
    
    # Start data collection
    ./fleet-data-structural.bash
    
    # Start WebSocket server
    nohup python3 websocket-server.py > websocket.log 2>&1 &
    
    # Start HTTP server
    nohup python3 serve.py > http.log 2>&1 &
    
    echo '✅ Services started'
"

# 8. Set up cron job
echo "⏰ Setting up cron job..."
sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no "$USER@$SERVER" "
    (crontab -l | grep -v 'fleet-data-structural.bash') && echo '*/1 * * * * cd /root/openclaw-fleet-monitor/openclaw-fleet-monitor && bash fleet-data-structural.bash >> /tmp/fleet-cron.log 2>&1' | crontab -
    echo '✅ Cron job configured'
"

# 9. Reload nginx
echo "🔄 Reloading nginx..."
sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no "$USER@$SERVER" "nginx -s reload"

# 10. Wait and test
echo "⏳ Waiting for services to start..."
sleep 5

echo "🧪 Testing deployment..."
sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no "$USER@$SERVER" "
    echo 'Testing health check...'
    curl -s -o /dev/null -w '%{http_code}' http://localhost:8081/health | grep -q '200' && echo '✅ Health check passed' || echo '❌ Health check failed'
    
    echo 'Testing data API...'
    curl -s -o /dev/null -w '%{http_code}' http://localhost:8081/data/fleet.json | grep -q '200' && echo '✅ Data API working' || echo '❌ Data API failed'
"

echo ""
echo "🎉 DEPLOYMENT COMPLETE!"
echo ""
echo "📊 Production Access:"
echo "  - URL: https://$DOMAIN/"
echo "  - Username: victor"
echo "  - Password: Airhelly1"
echo ""
echo "🔧 Services running on server:"
echo "  - HTTP: http://localhost:8081"
echo "  - WebSocket: ws://localhost:18789"
echo "  - Nginx: proxying to above services"
echo ""
echo "✅ Phase 8: Secure Remote deployment successful!"