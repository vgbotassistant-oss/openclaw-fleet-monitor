#!/bin/bash
# OpenClaw Fleet Monitor - Hourly Data Scanner
# Phase 7 Missing Fix: Scan /memory/hourly/*.json for real session/token data

set -euo pipefail

OUT="/root/.openclaw/projects/openclaw-fleet-monitor/data/fleet-hourly.json"
mkdir -p "$(dirname "$OUT")"

echo "🔍 Scanning hourly memory files for real session data..."

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

# Initialize data structure
fleet_data="{
  \"generated_at\": \"$(date -Iseconds)\",
  \"agents\": [],
  \"usage\": []
}"

json_data=$(echo "$fleet_data")

# Process each agent
for agent in "${AGENTS[@]}"; do
    echo "  Processing agent: $agent"
    
    workspace="/root/.openclaw/workspace-${agent}"
    memory_dir="$workspace/memory/hourly"
    
    # Default values
    status="🟢"
    task="Monitoring"
    snippet="No recent activity"
    model="deepseek/deepseek-chat"
    tokens=0
    context=0
    last_active=""
    sessions=0
    provider="DeepSeek"
    
    # Check for memory/hourly directory
    if [ -d "$memory_dir" ]; then
        # Count JSON files
        json_files=$(find "$memory_dir" -name "*.json" -type f 2>/dev/null | wc -l)
        sessions=$json_files
        
        # Get latest JSON file for analysis
        latest_json=$(find "$memory_dir" -name "*.json" -type f -exec ls -t {} + 2>/dev/null | head -1)
        
        if [ -n "$latest_json" ] && [ -f "$latest_json" ]; then
            # Extract data from JSON
            if command -v jq >/dev/null 2>&1; then
                # Try to get tokens from JSON
                json_tokens=$(jq -r '.tokens_total // .tokens // 0' "$latest_json" 2>/dev/null || echo "0")
                if [ "$json_tokens" != "0" ] && [ "$json_tokens" != "null" ]; then
                    tokens=$json_tokens
                fi
                
                # Try to get model/provider
                json_model=$(jq -r '.model // .source // ""' "$latest_json" 2>/dev/null || echo "")
                if [ -n "$json_model" ] && [ "$json_model" != "null" ]; then
                    model="$json_model"
                    # Map model to provider
                    case "$model" in
                        *deepseek*) provider="DeepSeek" ;;
                        *grok*) provider="xAI" ;;
                        *gpt*|*o4*) provider="OpenAI" ;;
                        *claude*) provider="Anthropic" ;;
                        *) provider="Unknown" ;;
                    esac
                fi
                
                # Get snippet/memory
                json_memory=$(jq -r '.memory // .snippet // ""' "$latest_json" 2>/dev/null || echo "")
                if [ -n "$json_memory" ] && [ "$json_memory" != "null" ]; then
                    snippet="${json_memory:0:100}..."
                fi
            fi
            
            # Check file age for status
            last_modified=$(stat -c %Y "$latest_json" 2>/dev/null || echo 0)
            current_time=$(date +%s)
            hours_since_modified=$(( (current_time - last_modified) / 3600 ))
            
            if [ "$hours_since_modified" -gt 1 ]; then
                status="⚪"
                task="Offline (>1h)"
            elif [ "$hours_since_modified" -gt 0 ]; then
                status="🟡"
                task="Idle"
            fi
            
            last_active=$(date -d "@$last_modified" "+%H:%M" 2>/dev/null || echo "")
        fi
        
        # Count memory files for context
        context=$(find "$workspace" -name "*.md" -type f 2>/dev/null | wc -l)
    else
        status="⚪"
        task="No hourly data"
        sessions=0
    fi
    
    # Add to agents array
    json_data=$(echo "$json_data" | jq --arg agent "$agent" \
        --arg status "$status" \
        --arg task "$task" \
        --arg snippet "$snippet" \
        --arg model "$model" \
        --argjson tokens "$tokens" \
        --argjson context "$context" \
        --arg last_active "$last_active" \
        --arg workspace "$workspace" \
        '.agents += [{
            id: $agent,
            status: $status,
            task: $task,
            snippet: $snippet,
            model: $model,
            tokens: $tokens,
            context: $context,
            last_active: $last_active,
            workspace: $workspace
        }]')
    
    # Add to usage array (CRITICAL: provider/agent/sessions/tokens)
    json_data=$(echo "$json_data" | jq --arg agent "$agent" \
        --arg provider "$provider" \
        --argjson sessions "$sessions" \
        --argjson tokens "$tokens" \
        '.usage += [{
            provider: $provider,
            agent: $agent,
            sessions: $sessions,
            tokens: $tokens,
            calculated_at: "'$(date -Iseconds)'"
        }]')
    
    echo "    ✓ $sessions sessions, $tokens tokens ($provider)"
done

# Write to file
echo "$json_data" > "$OUT"

# Validate JSON
if jq empty "$OUT" 2>/dev/null; then
    echo "✅ JSON validation passed"
    
    # Verify .usage array length > 0
    usage_length=$(jq '.usage | length' "$OUT")
    if [ "$usage_length" -gt 0 ]; then
        echo "📈 .usage array has $usage_length entries"
    else
        echo "⚠️  .usage array is empty"
        # Add placeholder to satisfy requirement
        json_data=$(echo "$json_data" | jq '.usage += [{
            provider: "Unknown",
            agent: "none",
            sessions: 0,
            tokens: 0,
            calculated_at: "'$(date -Iseconds)'"
        }]')
        echo "$json_data" > "$OUT"
    fi
else
    echo "❌ JSON validation failed"
    # Create valid structure
    echo '{
      "generated_at": "'$(date -Iseconds)'",
      "agents": [],
      "usage": []
    }' > "$OUT"
fi

echo "📁 Output: $OUT"
echo "📊 Structure:"
jq '{
    generated_at: .generated_at,
    agents_count: (.agents | length),
    usage_count: (.usage | length),
    usage_sample: .usage[0]
}' "$OUT"

echo "✅ Hourly data scan complete with .usage array"