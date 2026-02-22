#!/bin/bash
# OpenClaw Fleet Monitor - Simple Data Collection
# Phase 1: Basic fleet status collection

set -euo pipefail

OUT="/root/.openclaw/projects/openclaw-fleet-monitor/data/fleet.json"
mkdir -p "$(dirname "$OUT")"

echo "🔍 Collecting fleet data..."

# Get all agent workspaces
AGENTS=()
if [ -d "/root/.openclaw" ]; then
    for workspace in /root/.openclaw/workspace-*; do
        if [ -d "$workspace" ]; then
            agent=$(basename "$workspace" | sed 's/workspace-//')
            AGENTS+=("$agent")
        fi
    done
fi

echo "📊 Found ${#AGENTS[@]} agents: ${AGENTS[*]:-none}"

# Data collection array
fleet_data="["

for i in "${!AGENTS[@]}"; do
    agent="${AGENTS[$i]}"
    workspace="/root/.openclaw/workspace-${agent}"
    
    echo "  Processing: $agent"
    
    # Determine status based on workspace activity
    status="🟢"  # Default: active
    task="Monitoring"
    
    # Check for memory files
    memory_count=$(find "$workspace" -name "*.md" -type f 2>/dev/null | wc -l)
    
    # Check for recent files (last hour)
    recent_files=$(find "$workspace" -type f -mmin -60 2>/dev/null | wc -l)
    
    if [ "$recent_files" -eq 0 ]; then
        status="🟡"  # Yellow = idle
        task="Idle"
    fi
    
    if [ "$memory_count" -eq 0 ]; then
        status="⚪"  # White = no data
        task="No data"
    fi
    
    # Get a snippet from the latest memory file
    snippet="No recent activity"
    latest_md=$(find "$workspace" -name "*.md" -type f -exec ls -t {} + 2>/dev/null | head -1)
    if [ -n "$latest_md" ] && [ -f "$latest_md" ]; then
        # Get first line as snippet
        first_line=$(head -1 "$latest_md" 2>/dev/null || echo "")
        if [ -n "$first_line" ]; then
            snippet="${first_line:0:80}..."
        fi
    fi
    
    # Create JSON entry
    agent_entry="{
      \"id\": \"$agent\",
      \"status\": \"$status\",
      \"task\": \"$task\",
      \"snippet\": \"$snippet\",
      \"model\": \"deepseek/deepseek-chat\",
      \"tokens\": 0,
      \"context\": $memory_count,
      \"last_active\": \"$(date '+%H:%M')\",
      \"workspace\": \"$workspace\"
    }"
    
    fleet_data+="$agent_entry"
    
    # Add comma if not last element
    if [ $i -lt $((${#AGENTS[@]} - 1)) ]; then
        fleet_data+=","
    fi
done

fleet_data+="]"

# Write to file
echo "$fleet_data" > "$OUT"

# Validate JSON
if jq empty "$OUT" 2>/dev/null; then
    echo "✅ JSON validation passed"
else
    echo "❌ JSON validation failed"
    # Create valid empty JSON as fallback
    echo '[]' > "$OUT"
fi

echo "📁 Output: $OUT"
echo "📊 Data sample:"
jq '.[] | {id, status, task}' "$OUT"

echo "✅ Phase 1 complete: fleet.json generated with ${#AGENTS[@]} agents"