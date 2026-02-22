#!/bin/bash
# OpenClaw Fleet Monitor - Daily Cost History Archiver
# Phase 10: Preserve daily usage summaries for historical chart data

set -euo pipefail

FLEET_FILE="/root/.openclaw/projects/openclaw-fleet-monitor/data/fleet.json"
HISTORY_DIR="/root/.openclaw/projects/openclaw-fleet-monitor/data/history"
TODAY=$(date +%Y-%m-%d)

echo "📦 Archiving daily cost history for $TODAY..."

# Create history directory if it doesn't exist
mkdir -p "$HISTORY_DIR"

# Check fleet.json exists and has correct structure
if [ ! -f "$FLEET_FILE" ]; then
    echo "❌ fleet.json not found"
    exit 1
fi

# Verify it has usage array
usage_count=$(jq '.usage | length' "$FLEET_FILE" 2>/dev/null || echo "0")
if [ "$usage_count" -eq 0 ]; then
    echo "⚠️ No usage data found in fleet.json, skipping archive"
    exit 0
fi

# Build today's archive entry per model
echo "📊 Processing $usage_count usage entries..."

archive_data=$(jq --arg date "$TODAY" '
{
  date: $date,
  archived_at: now | todate,
  models: [
    .usage[] | {
      model: .model,
      provider: .provider,
      agent: .agent,
      sessions: .sessions,
      tokens: .tokens,
      price_per_1k: .price_per_1k,
      cost_usd: .cost_usd,
      date_data: (.date_breakdown[$date] // {sessions: .sessions, tokens: .tokens, cost: .cost_usd})
    }
  ],
  totals: {
    sessions: [.usage[].sessions] | add,
    tokens: [.usage[].tokens] | add,
    cost_usd: ([.usage[].cost_usd | tonumber] | add | tostring)
  }
}' "$FLEET_FILE")

# Write to history file (overwrites if same day runs twice)
ARCHIVE_FILE="$HISTORY_DIR/$TODAY.json"
echo "$archive_data" > "$ARCHIVE_FILE"

echo "✅ Archived to $ARCHIVE_FILE"
echo "📊 Summary:"
echo "$archive_data" | jq '{date, totals}'