#!/bin/bash
# OpenClaw Fleet Monitor - Enhanced Data Collection
# Phase 4: Data quality improvements

set -euo pipefail

OUT="/root/.openclaw/projects/openclaw-fleet-monitor/data/fleet.json"
mkdir -p "$(dirname "$OUT")"

echo "🔍 Collecting enhanced fleet data..."

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
    
    # Check for very old files (offline > 1 hour) - PHASE 4 FIX 3
    last_modified_file=$(find "$workspace" -type f -exec stat -c %Y {} + 2>/dev/null | sort -nr | head -1)
    current_time=$(date +%s)
    
    if [ -n "$last_modified_file" ]; then
        hours_since_modified=$(( (current_time - last_modified_file) / 3600 ))
        if [ "$hours_since_modified" -gt 1 ]; then
            status="⚪"  # White = offline (>1 hour)
            task="Offline"
        elif [ "$recent_files" -eq 0 ]; then
            status="🟡"  # Yellow = idle
            task="Idle"
        fi
    else
        status="⚪"  # White = no files at all
        task="No data"
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
    
    # Calculate token count from JSON files - PHASE 4 FIX 1
    tokens=0
    json_files=$(find "$workspace" -name "*.json" -type f 2>/dev/null)
    for json_file in $json_files; do
        if [ -f "$json_file" ]; then
            # Count lines in JSON file as proxy for tokens
            file_tokens=$(wc -l < "$json_file" 2>/dev/null || echo 0)
            tokens=$((tokens + file_tokens))
        fi
    done
    
    # If no JSON files, use memory file count as proxy
    if [ "$tokens" -eq 0 ] && [ "$memory_count" -gt 0 ]; then
        tokens=$((memory_count * 100))  # Estimate
    fi
    
    # Create JSON entry with generated_at - PHASE 4 FIX 2
    agent_entry="{
      \"id\": \"$agent\",
      \"status\": \"$status\",
      \"task\": \"$task\",
      \"snippet\": \"$snippet\",
      \"model\": \"deepseek/deepseek-chat\",
      \"tokens\": $tokens,
      \"context\": $memory_count,
      \"last_active\": \"$(date '+%H:%M')\",
      \"workspace\": \"$workspace\",
      \"generated_at\": \"$(date -Iseconds)\"
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
jq '.[] | {id, status, task, tokens, generated_at}' "$OUT"

echo "✅ Phase 4 complete: Enhanced fleet.json with token counts and timestamps"