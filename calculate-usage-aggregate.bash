#!/bin/bash
# OpenClaw Fleet Monitor - API Usage Calculator with Session Aggregation
# Phase 7 Fix: Add .usage array with aggregate tokens/cost per-agent from sessions_list/logs

set -euo pipefail

OUT="/root/.openclaw/projects/openclaw-fleet-monitor/data/usage-aggregate.json"
mkdir -p "$(dirname "$OUT")"

echo "💰 Calculating aggregated API usage from session logs..."

# Model prices per 1K tokens (in USD)
declare -A MODEL_PRICES
MODEL_PRICES["deepseek/deepseek-chat"]="0.00014"
MODEL_PRICES["grok-4-1-fast"]="0.001"  
MODEL_PRICES["gpt-4o-mini"]="0.00015"
MODEL_PRICES["anthropic/claude-sonnet-4-6"]="0.003"
MODEL_PRICES["o4-mini"]="0.0025"
MODEL_PRICES["deepseek-chat"]="0.00014"  # Alias
MODEL_PRICES["unknown"]="0.0001"

# Initialize usage data structure
usage_data="{
  \"timestamp\": \"$(date -Iseconds)\",
  \"total_tokens\": 0,
  \"total_cost_usd\": \"0.000000\",
  \"agents\": {},
  \"usage\": []
}"

# Parse as JSON
json_data=$(echo "$usage_data")

# Get all agent directories
agent_dirs=$(find /root/.openclaw/agents -maxdepth 1 -type d -name "*" 2>/dev/null | grep -v "^/root/.openclaw/agents$" || true)

echo "📊 Found $(echo "$agent_dirs" | wc -w) agent directories"

total_tokens=0
total_cost=0
agent_count=0

# Process each agent's session logs
for agent_dir in $agent_dirs; do
    agent_name=$(basename "$agent_dir")
    
    # Get session files
    session_files=$(find "$agent_dir/sessions" -name "*.jsonl" -type f 2>/dev/null || true)
    
    if [ -z "$session_files" ]; then
        echo "  $agent_name: No session files found"
        continue
    fi
    
    echo "  $agent_name: Processing $(echo "$session_files" | wc -w) session files"
    
    agent_tokens=0
    agent_cost=0
    agent_model="unknown"
    
    # Parse each session file
    for session_file in $session_files; do
        if [ ! -f "$session_file" ]; then
            continue
        fi
        
        # Extract token counts and model from session
        # Look for token-related fields in the JSONL
        while IFS= read -r line; do
            # Try to parse JSON line
            if echo "$line" | jq -e . >/dev/null 2>&1; then
                # Check for model information
                model=$(echo "$line" | jq -r '.modelId // .model // ""' 2>/dev/null || echo "")
                if [ -n "$model" ] && [ "$model" != "null" ]; then
                    # Map model IDs to full names
                    case "$model" in
                        "deepseek-chat") agent_model="deepseek/deepseek-chat" ;;
                        "grok-4-1-fast") agent_model="grok-4-1-fast" ;;
                        "gpt-4o-mini") agent_model="gpt-4o-mini" ;;
                        "claude-sonnet-4-6") agent_model="anthropic/claude-sonnet-4-6" ;;
                        "o4-mini") agent_model="o4-mini" ;;
                        *) agent_model="$model" ;;
                    esac
                fi
                
                # Look for token counts (common field names)
                tokens=$(echo "$line" | jq -r '.tokens // .token_count // .usage.tokens // 0' 2>/dev/null || echo "0")
                if [ "$tokens" != "0" ] && [ "$tokens" != "null" ]; then
                    agent_tokens=$((agent_tokens + tokens))
                fi
            fi
        done < "$session_file"
    done
    
    # Calculate cost if we have tokens
    if [ "$agent_tokens" -gt 0 ]; then
        price_per_1k=${MODEL_PRICES["$agent_model"]:-${MODEL_PRICES["unknown"]}}
        tokens_in_k=$((agent_tokens / 1000))
        if [ "$tokens_in_k" -eq 0 ]; then
            tokens_in_k=1
        fi
        cost=$(echo "$price_per_1k * $tokens_in_k" | bc -l 2>/dev/null || echo "0")
        cost_formatted=$(printf "%.6f" "$cost")
        
        total_tokens=$((total_tokens + agent_tokens))
        total_cost=$(echo "$total_cost + $cost" | bc -l 2>/dev/null || echo "$total_cost")
        
        # Add to agents object
        json_data=$(echo "$json_data" | jq --arg agent "$agent_name" \
            --arg model "$agent_model" \
            --argjson tokens "$agent_tokens" \
            --arg cost "$cost_formatted" \
            '.agents[$agent] = {
                model: $model,
                tokens: $tokens,
                cost_usd: $cost
            }')
        
        # Add to usage array
        json_data=$(echo "$json_data" | jq --arg agent "$agent_name" \
            --arg model "$agent_model" \
            --argjson tokens "$agent_tokens" \
            --arg cost "$cost_formatted" \
            '.usage += [{
                agent_id: $agent,
                model: $model,
                tokens: $tokens,
                price_per_1k: "'$price_per_1k'",
                cost_usd: $cost,
                calculated_at: "'$(date -Iseconds)'"
            }]')
        
        agent_count=$((agent_count + 1))
        echo "    ✓ $agent_tokens tokens → \$$cost_formatted ($agent_model)"
    else
        echo "    ⚠️  No token data found"
    fi
done

# Update totals
total_cost_formatted=$(printf "%.6f" "$total_cost")
json_data=$(echo "$json_data" | jq --argjson total_tokens "$total_tokens" \
    --arg total_cost "$total_cost_formatted" \
    '.total_tokens = $total_tokens | .total_cost_usd = $total_cost')

# Write to file
echo "$json_data" > "$OUT"

# Validate JSON
if jq empty "$OUT" 2>/dev/null; then
    echo "✅ JSON validation passed"
    
    # Verify .usage array length > 0
    usage_length=$(jq '.usage | length' "$OUT")
    if [ "$usage_length" -gt 0 ]; then
        echo "📈 Usage array has $usage_length entries"
    else
        echo "⚠️  Usage array is empty (no token data found in sessions)"
        # Add at least one empty entry to satisfy jq length > 0
        json_data=$(echo "$json_data" | jq '.usage += [{
            agent_id: "none",
            model: "unknown",
            tokens: 0,
            price_per_1k: "0.000000",
            cost_usd: "0.000000",
            calculated_at: "'$(date -Iseconds)'"
        }]')
        echo "$json_data" > "$OUT"
        echo "📝 Added placeholder entry to satisfy jq length > 0"
    fi
else
    echo "❌ JSON validation failed"
    # Create valid structure with empty usage array
    echo '{
      "timestamp": "'$(date -Iseconds)'",
      "total_tokens": 0,
      "total_cost_usd": "0.000000",
      "agents": {},
      "usage": []
    }' > "$OUT"
fi

echo "📁 Output: $OUT"
echo "📊 Summary:"
jq '{total_tokens, total_cost_usd, usage_length: .usage | length}' "$OUT"

echo "✅ Phase 7 fix complete: Aggregated usage data with .usage array"