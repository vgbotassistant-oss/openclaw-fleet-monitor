#!/bin/bash
# OpenClaw Fleet Monitor - Server Setup Script
# Phase 7/8: Nginx + SSL + Authentication setup

set -euo pipefail

echo "🚀 Setting up Fleet Monitor server..."

# 1. Install dependencies
echo "📦 Installing dependencies..."
apt update
apt install -y certbot python3-certbot-nginx apache2-utils

# 2. Create password file with Victor's credentials
echo "🔐 Creating password file with Victor's credentials..."
htpasswd -c -b /etc/nginx/.htpasswd-fleet victor Airhelly1
chmod 644 /etc/nginx/.htpasswd-fleet
echo "✅ Password file created at /etc/nginx/.htpasswd-fleet"

# 3. Place the nginx config
echo "📁 Installing nginx config..."
cp nginx-fleet-monitor.conf /etc/nginx/sites-available/fleet-monitor
ln -sf /etc/nginx/sites-available/fleet-monitor /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# 4. Test nginx config
echo "🧪 Testing nginx configuration..."
nginx -t
if [ $? -eq 0 ]; then
    echo "✅ nginx configuration test passed"
else
    echo "❌ nginx configuration test failed"
    exit 1
fi

# 5. Run certbot for SSL
echo "🔐 Setting up SSL certificate..."
certbot --nginx -d vgbots.duckdns.org --email agents@vgbotassistant-oss --agree-tos --non-interactive

# 6. Add auto-renewal cron
echo "⏰ Setting up SSL auto-renewal..."
echo "0 3 * * * root certbot renew --quiet && nginx -s reload" >> /etc/cron.d/certbot-renew

# 7. Reload nginx
echo "🔄 Reloading nginx..."
nginx -s reload

echo "🎉 Server setup complete!"
echo ""
echo "📊 Access URLs:"
echo "  - HTTPS: https://vgbots.duckdns.org/"
echo "  - Username: fleet"
echo "  - Password: [provided during setup]"
echo ""
echo "🔧 Services:"
echo "  - Dashboard: http://127.0.0.1:8081"
echo "  - WebSocket: ws://127.0.0.1:18789"
echo "  - Health check: https://vgbots.duckdns.org/health"
echo ""
echo "✅ Fleet Monitor server is ready for production!"