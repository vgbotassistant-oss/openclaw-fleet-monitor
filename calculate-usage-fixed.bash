#!/bin/bash
# OpenClaw Fleet Monitor - API Usage Calculator (Fixed)
# Phase 7 Fix: Ensure .usage[] array exists with proper structure

set -euo pipefail

OUT="/root/.openclaw/projects/openclaw-fleet-monitor/data/usage.json"
mkdir -p "$(dirname "$OUT")"

echo "💰 Calculating API usage with .usage array..."

# Model prices per 1K tokens (in USD)
declare -A MODEL_PRICES
MODEL_PRICES["deepseek/deepseek-chat"]="0.00014"
MODEL_PRICES["grok-4-1-fast"]="0.001"  
MODEL_PRICES["gpt-4o-mini"]="0.00015"
MODEL_PRICES["anthropic/claude-sonnet-4-6"]="0.003"
MODEL_PRICES["o4-mini"]="0.0025"
MODEL_PRICES["unknown"]="0.0001"

# Check if fleet.json exists
FLEET_FILE="/root/.openclaw/projects/openclaw-fleet-monitor/data/fleet.json"
if [ ! -f "$FLEET_FILE" ]; then
    echo "❌ fleet.json not found. Run fleet-data-enhanced.bash first."
    exit 1
fi

# Read fleet data
fleet_data=$(cat "$FLEET_FILE")

# Initialize usage structure with .usage array
usage_data="{
  \"timestamp\": \"$(date -Iseconds)\",
  \"total_tokens\": 0,
  \"total_cost_usd\": \"0.000000\",
  \"agents\": {},
  \"usage\": []
}"

# Parse as JSON
json_data=$(echo "$usage_data")

# Process each agent
agent_count=$(echo "$fleet_data" | jq 'length')
echo "📊 Processing $agent_count agents for usage calculation..."

total_tokens=0
total_cost=0

for i in $(seq 0 $((agent_count - 1))); do
    agent=$(echo "$fleet_data" | jq -r ".[$i]")
    agent_id=$(echo "$agent" | jq -r '.id')
    model=$(echo "$agent" | jq -r '.model')
    tokens=$(echo "$agent" | jq -r '.tokens')
    
    # Get price for model
    price_per_1k=${MODEL_PRICES["$model"]:-${MODEL_PRICES["unknown"]}}
    
    # Calculate cost
    if [ "$tokens" -gt 0 ]; then
        tokens_in_k=$((tokens / 1000))
        if [ "$tokens_in_k" -eq 0 ]; then
            tokens_in_k=1
        fi
        
        cost=$(echo "$price_per_1k * $tokens_in_k" | bc -l 2>/dev/null || echo "0")
        cost_formatted=$(printf "%.6f" "$cost")
        
        total_tokens=$((total_tokens + tokens))
        total_cost=$(echo "$total_cost + $cost" | bc -l 2>/dev/null || echo "$total_cost")
        
        # Add to agents object
        json_data=$(echo "$json_data" | jq --arg agent "$agent_id" \
            --arg model "$model" \
            --argjson tokens "$tokens" \
            --arg cost "$cost_formatted" \
            '.agents[$agent] = {
                model: $model,
                tokens: $tokens,
                cost_usd: $cost
            }')
        
        # Add to .usage array (CRITICAL FIX)
        json_data=$(echo "$json_data" | jq --arg agent "$agent_id" \
            --arg model "$model" \
            --argjson tokens "$tokens" \
            --arg cost "$cost_formatted" \
            --arg price "$price_per_1k" \
            '.usage += [{
                agent_id: $agent,
                model: $model,
                tokens: $tokens,
                price_per_1k: $price,
                cost_usd: $cost,
                calculated_at: "'$(date -Iseconds)'"
            }]')
        
        echo "  $agent_id: $tokens tokens → \$$cost_formatted ($model)"
    else
        echo "  $agent_id: No tokens found"
        
        # Still add to .usage array with zero values (to ensure array is not empty)
        json_data=$(echo "$json_data" | jq --arg agent "$agent_id" \
            --arg model "$model" \
            '.usage += [{
                agent_id: $agent,
                model: $model,
                tokens: 0,
                price_per_1k: "0.000000",
                cost_usd: "0.000000",
                calculated_at: "'$(date -Iseconds)'"
            }]')
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
    
    # CRITICAL: Verify .usage array length > 0
    usage_length=$(jq '.usage | length' "$OUT")
    if [ "$usage_length" -gt 0 ]; then
        echo "📈 .usage array has $usage_length entries (REQUIREMENT MET)"
    else
        echo "❌ .usage array is empty (REQUIREMENT FAILED)"
        exit 1
    fi
else
    echo "❌ JSON validation failed"
    exit 1
fi

echo "📁 Output: $OUT"
echo "📊 Structure verification:"
jq '{
    timestamp: .timestamp,
    total_tokens: .total_tokens,
    total_cost_usd: .total_cost_usd,
    agents_count: (.agents | length),
    usage_length: (.usage | length),
    usage_sample: .usage[0]
}' "$OUT"

echo "✅ Phase 7 fix complete: .usage array added with $usage_length entries"