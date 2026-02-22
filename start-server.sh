#!/bin/bash
# Start Fleet Monitor servers

set -euo pipefail

cd "$(dirname "$0")"

echo "🚀 Starting OpenClaw Fleet Monitor..."

# Check if Python is available
if ! command -v python3 >/dev/null 2>&1; then
    echo "❌ Python3 is required but not installed"
    exit 1
fi

# Create data directory if it doesn't exist
mkdir -p data

# Run data collection once to ensure we have initial data
echo "📊 Running initial data collection..."
if [ -f "fleet-data-simple.bash" ]; then
    bash fleet-data-simple.bash
else
    echo "⚠️  fleet-data-simple.bash not found, creating empty data file"
    echo '[]' > data/fleet.json
fi

# Start HTTP server
echo "🌐 Starting HTTP server on port 8081..."
echo "📊 Dashboard: http://localhost:8081/"
echo "📁 Data API: http://localhost:8081/data/fleet.json"
echo ""
echo "Press Ctrl+C to stop all servers"
echo ""

# Start the HTTP server
python3 serve.py