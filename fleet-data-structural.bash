#!/bin/bash
# OpenClaw Fleet Monitor - Structural Data Collector
# Phase 7 Fix: Scan hourly files + new fleet.json structure

set -euo pipefail

OUT="/root/.openclaw/projects/openclaw-fleet-monitor/data/fleet.json"
mkdir -p "$(dirname "$OUT")"

echo "🔍 Scanning agent workspaces for hourly data..."

# Function to map model to provider
get_provider() {
    case "$1" in
        anthropic/*|claude*)
            echo "Anthropic"
            ;;
        deepseek/*)
            echo "DeepSeek"
            ;;
        gpt*|o4*|openai/*)
            echo "OpenAI"
            ;;
        grok*)
            echo "xAI"
            ;;
        *)
            echo "Unknown"
            ;;
    esac
}

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

# Initialize arrays
agents_array="[]"
usage_array="[]"

# Track usage by agent/provider for aggregation
declare -A sessions_map=()
declare -A tokens_map=()
declare -A models_map=()

# Process each agent
for agent in "${AGENTS[@]}"; do
    echo "  Processing agent: $agent"
    
    workspace="/root/.openclaw/workspace-${agent}"
    
    # Default values for agent
    status="🟢"
    task="Monitoring"
    snippet="No recent activity"
    model="deepseek/deepseek-chat"
    tokens=0
    context=0
    last_active=""
    sessions=0
    
    # Scan all project subfolders within the workspace
    memory_dirs=$(find "$workspace" -type d -name "hourly" 2>/dev/null)
    
    # Process each hourly directory found
    for memory_dir in $memory_dirs; do
        # Get all JSON files
        json_files=$(find "$memory_dir" -name "*.json" -type f 2>/dev/null)
        session_count=$(echo "$json_files" | wc -w)
        sessions=$session_count
        
        # Process each JSON file
        for json_file in $json_files; do
            if [ -f "$json_file" ]; then
                # Extract data from JSON
                if command -v jq >/dev/null 2>&1; then
                    # Get model from this file
                    file_model=$(jq -r '.model // .source // ""' "$json_file" 2>/dev/null || echo "")
                    if [ -n "$file_model" ] && [ "$file_model" != "null" ]; then
                        model="$file_model"
                    fi
                    
                    # Get tokens from this file - dual format parser
                    # Try tokens_total first
                    file_tokens=$(jq -r '.tokens_total // 0' "$json_file" 2>/dev/null || echo "0")
                    
                    # If 0, try summing tokens_in + tokens_out
                    if [ "$file_tokens" = "0" ] || [ "$file_tokens" = "null" ]; then
                        t_in=$(jq -r '.sessions[]?.tokens_in // 0' "$json_file" 2>/dev/null | awk '{s+=$1} END{print s+0}')
                        t_out=$(jq -r '.sessions[]?.tokens_out // 0' "$json_file" 2>/dev/null | awk '{s+=$1} END{print s+0}')
                        file_tokens=$((t_in + t_out))
                    fi
                    
                    # If still 0, try parsing string format "946 in / 628 out"
                    if [ "$file_tokens" = "0" ]; then
                        token_str=$(jq -r '.sessions[]?.tokens // ""' "$json_file" 2>/dev/null | head -1)
                        if [ -n "$token_str" ]; then
                            t_in=$(echo "$token_str" | grep -oP '[\d.]+(?=k? in)' | awk '{if($0~/k/)print $0*1000;else print $0}')
                            t_out=$(echo "$token_str" | grep -oP '[\d.]+(?=k? out)' | awk '{if($0~/k/)print $0*1000;else print $0}')
                            file_tokens=$(echo "${t_in:-0} ${t_out:-0}" | awk '{print int($1+$2)}')
                        fi
                    fi
                    
                    if [ "$file_tokens" != "0" ] && [ "$file_tokens" != "null" ]; then
                        tokens=$((tokens + file_tokens))
                        
                        # Track for usage aggregation
                        provider=$(get_provider "$model")
                        key="${agent}:${provider}:${model}"
                        
                        # Check if key exists in sessions_map
                        if [[ -z "${sessions_map[$key]+x}" ]]; then
                            sessions_map[$key]=1
                            tokens_map[$key]=$file_tokens
                            models_map[$key]="$model"
                        else
                            sessions_map[$key]=$((sessions_map[$key] + 1))
                            tokens_map[$key]=$((tokens_map[$key] + file_tokens))
                        fi
                    fi
                    
                    # Get snippet from latest file
                    if [ -z "$snippet" ] || [ "$snippet" = "No recent activity" ]; then
                        json_memory=$(jq -r '.memory // .snippet // ""' "$json_file" 2>/dev/null || echo "")
                        if [ -n "$json_memory" ] && [ "$json_memory" != "null" ]; then
                            snippet="${json_memory:0:100}..."
                        fi
                    fi
                fi
                
                # Check file age for status
                last_modified=$(stat -c %Y "$json_file" 2>/dev/null || echo 0)
                current_time=$(date +%s)
                hours_since_modified=$(( (current_time - last_modified) / 3600 ))
                
                if [ "$hours_since_modified" -gt 1 ]; then
                    status="⚪"
                    task="Offline (>1h)"
                elif [ "$hours_since_modified" -gt 0 ]; then
                    status="🟡"
                    task="Idle"
                fi
                
                if [ -z "$last_active" ]; then
                    last_active=$(date -d "@$last_modified" "+%H:%M" 2>/dev/null || echo "")
                fi
            fi
        done
    done
    
    # Count memory files for context
    context=$(find "$workspace" -name "*.md" -type f 2>/dev/null | wc -l)
    
    # If no hourly data found at all
    if [ "$sessions" -eq 0 ]; then
        status="⚪"
        task="No hourly data"
    fi
    
    # Add to agents array
    agents_array=$(echo "$agents_array" | jq --arg agent "$agent" \
        --arg status "$status" \
        --arg task "$task" \
        --arg snippet "$snippet" \
        --arg model "$model" \
        --argjson tokens "$tokens" \
        --argjson context "$context" \
        --arg last_active "$last_active" \
        --arg workspace "$workspace" \
        '. += [{
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
    
    echo "    ✓ $sessions sessions, $tokens tokens"
done

# Build usage array from aggregated data
echo "📈 Building usage array from aggregated data..."

for key in "${!sessions_map[@]}"; do
    IFS=':' read -r agent provider model <<< "$key"
    sessions=${sessions_map[$key]}
    tokens=${tokens_map[$key]}
    
    # Get price per 1K tokens based on model
    case "$model" in
        deepseek/*)
            price_per_1k="0.00014"
            ;;
        grok*)
            price_per_1k="0.001"
            ;;
        gpt*|o4*)
            price_per_1k="0.00015"
            ;;
        claude*)
            price_per_1k="0.003"
            ;;
        *)
            price_per_1k="0.0001"
            ;;
    esac
    
    # Calculate cost
    tokens_in_k=$((tokens / 1000))
    if [ "$tokens_in_k" -eq 0 ]; then
        tokens_in_k=1
    fi
    cost=$(echo "$price_per_1k * $tokens_in_k" | bc -l 2>/dev/null || echo "0")
    cost_formatted=$(printf "%.6f" "$cost")
    
    # Add to usage array
    usage_array=$(echo "$usage_array" | jq --arg agent "$agent" \
        --arg provider "$provider" \
        --arg model "$model" \
        --argjson sessions "$sessions" \
        --argjson tokens "$tokens" \
        --arg price "$price_per_1k" \
        --arg cost "$cost_formatted" \
        '. += [{
            agent: $agent,
            provider: $provider,
            model: $model,
            sessions: $sessions,
            tokens: $tokens,
            price_per_1k: $price,
            cost_usd: $cost,
            calculated_at: "'$(date -Iseconds)'"
        }]')
    
    echo "    📊 $agent ($provider): $sessions sessions, $tokens tokens → \$$cost_formatted"
done

# If no usage data found, add at least one entry
if [ -z "${sessions_map[*]}" ] || [ "${#sessions_map[@]}" -eq 0 ]; then
    echo "⚠️  No hourly data found, adding placeholder entry"
    usage_array=$(echo "$usage_array" | jq '. += [{
        agent: "none",
        provider: "Unknown",
        model: "unknown",
        sessions: 0,
        tokens: 0,
        price_per_1k: "0.000000",
        cost_usd: "0.000000",
        calculated_at: "'$(date -Iseconds)'"
    }]')
fi

# Write final JSON structure
echo "📁 Writing structured data to $OUT"
cat > "$OUT" <<EOF
{
  "generated_at": "$(date -Iseconds)",
  "agents": $agents_array,
  "usage": $usage_array
}
EOF

# Validate JSON
if jq empty "$OUT" 2>/dev/null; then
    echo "✅ JSON validation passed"
    
    # Verify structure
    agents_count=$(jq '.agents | length' "$OUT")
    usage_count=$(jq '.usage | length' "$OUT")
    
    echo "📊 Structure:"
    echo "  - agents array: $agents_count entries"
    echo "  - usage array: $usage_count entries"
    
    if [ "$usage_count" -gt 0 ]; then
        echo "✅ .usage array has $usage_count entries (REQUIREMENT MET)"
    else
        echo "❌ .usage array is empty (REQUIREMENT FAILED)"
        exit 1
    fi
else
    echo "❌ JSON validation failed"
    exit 1
fi

echo "🎉 Structural data collection complete!"
echo "📊 Sample output:"
jq '{
    generated_at: .generated_at,
    agents_count: (.agents | length),
    usage_count: (.usage | length),
    usage_sample: .usage[0]
}' "$OUT"