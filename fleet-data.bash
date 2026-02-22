#!/bin/bash
# OpenClaw Fleet Monitor - Data Collection Script
# Phase 1: Collect fleet status from all agent workspaces

set -euo pipefail

# Output file
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

# Data collection
fleet=()
for agent in "${AGENTS[@]}"; do
    echo "  Processing agent: $agent"
    
    workspace="/root/.openclaw/workspace-${agent}"
    
    # Default values
    status="🟢"  # Green = active
    task="Idle"
    snippet="No recent activity"
    model="unknown"
    tokens=0
    context=0
    last_active=""
    
    # Try to get agent status using openclaw status command
    if command -v openclaw >/dev/null 2>&1; then
        # Try to get status for this specific agent
        status_output=$(openclaw status 2>/dev/null || echo "")
        
        if [ -n "$status_output" ]; then
            # Parse status output for agent info
            # Example format: "agent:roxi:main • updated 2m ago • model: deepseek/deepseek-chat"
            agent_line=$(echo "$status_output" | grep -i "$agent" | head -1)
            
            if [ -n "$agent_line" ]; then
                # Extract status info
                if echo "$agent_line" | grep -q "updated.*ago"; then
                    status="🟢"  # Green = active
                    task="Active"
                    
                    # Try to extract time
                    time_ago=$(echo "$agent_line" | grep -o "updated [^•]*" | sed 's/updated //')
                    last_active="$time_ago ago"
                    
                    # Try to extract model
                    model=$(echo "$agent_line" | grep -o "model: [^ ]*" | cut -d' ' -f2 || echo "unknown")
                fi
            fi
        fi
    fi
    
    # Fallback: Check for recent memory files
    latest_memory=$(find "$workspace" -name "*.md" -type f -exec ls -t {} + 2>/dev/null | head -1)
    if [ -n "$latest_memory" ] && [ -f "$latest_memory" ]; then
        # Get snippet from memory file
        snippet=$(head -3 "$latest_memory" 2>/dev/null | tr '\n' ' ' | sed 's/  */ /g')
        snippet="${snippet:0:100}..."
        
        # Check if memory file is recent (last 30 minutes)
        last_modified=$(stat -c %Y "$latest_memory" 2>/dev/null || echo 0)
        current_time=$(date +%s)
        
        if [ $status = "⚪" ]; then  # Only update if no status from openclaw
            if [ $((current_time - last_modified)) -lt 1800 ]; then  # 30 minutes
                status="🟡"  # Yellow = recent activity
                task="Recent memory"
                last_active=$(date -d "@$last_modified" "+%H:%M" 2>/dev/null || echo "")
            fi
        fi
    fi
    
    # Get memory files for context
    memory_files=$(find "$workspace" -name "*.md" -type f 2>/dev/null | wc -l)
    context=$memory_files
    
    # Create agent entry
    agent_json="{
      \"id\": \"$agent\",
      \"status\": \"$status\",
      \"task\": \"$task\",
      \"snippet\": \"$snippet\",
      \"model\": \"$model\",
      \"tokens\": $tokens,
      \"context\": $context,
      \"last_active\": \"$last_active\",
      \"workspace\": \"$workspace\"
    }"
    
    fleet+=("$agent_json")
done

# Write JSON output
if [ ${#fleet[@]} -eq 0 ]; then
    echo '[]' > "$OUT"
    echo "⚠️  No agents found. Empty fleet.json created."
else
    echo '[' > "$OUT"
    for i in "${!fleet[@]}"; do
        echo -n "${fleet[$i]}" >> "$OUT"
        if [ $i -lt $((${#fleet[@]} - 1)) ]; then
            echo ',' >> "$OUT"
        fi
    done
    echo ']' >> "$OUT"
    echo "✅ fleet.json generated with ${#fleet[@]} agents"
fi

# Validate JSON
if command -v jq >/dev/null 2>&1; then
    if jq empty "$OUT" 2>/dev/null; then
        echo "✅ JSON validation passed"
    else
        echo "❌ JSON validation failed"
        exit 1
    fi
else
    echo "⚠️  jq not installed, skipping JSON validation"
fi

echo "📁 Output: $OUT"
echo "📊 Sample:"
head -c 500 "$OUT"
echo "..."