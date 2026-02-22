#!/bin/bash
# OpenClaw Fleet Monitor - API Usage Calculator
# Phase 7.1: Calculate API usage costs from token counts

set -euo pipefail

OUT="/root/.openclaw/projects/openclaw-fleet-monitor/data/usage.json"
mkdir -p "$(dirname "$OUT")"

echo "💰 Calculating API usage costs..."

# Model prices per 1K tokens (in USD)
declare -A MODEL_PRICES
MODEL_PRICES["deepseek/deepseek-chat"]="0.00014"    # $0.14 per 1M tokens
MODEL_PRICES["grok-4-1-fast"]="0.001"              # $1.00 per 1M tokens  
MODEL_PRICES["gpt-4o-mini"]="0.00015"              # $0.15 per 1M tokens
MODEL_PRICES["anthropic/claude-sonnet-4-6"]="0.003" # $3.00 per 1M tokens
MODEL_PRICES["o4-mini"]="0.0025"                   # $2.50 per 1M tokens
MODEL_PRICES["unknown"]="0.0001"                   # Default price

# Check if fleet.json exists
FLEET_FILE="/root/.openclaw/projects/openclaw-fleet-monitor/data/fleet.json"
if [ ! -f "$FLEET_FILE" ]; then
    echo "❌ fleet.json not found. Run fleet-data-enhanced.bash first."
    exit 1
fi

# Read fleet data
fleet_data=$(cat "$FLEET_FILE")

# Initialize usage array
usage_data="["

# Process each agent
agent_count=$(echo "$fleet_data" | jq 'length')
echo "📊 Processing $agent_count agents for usage calculation..."

for i in $(seq 0 $((agent_count - 1))); do
    agent=$(echo "$fleet_data" | jq -r ".[$i]")
    agent_id=$(echo "$agent" | jq -r '.id')
    model=$(echo "$agent" | jq -r '.model')
    tokens=$(echo "$agent" | jq -r '.tokens')
    
    # Get price for model (default to unknown if not found)
    price_per_1k=${MODEL_PRICES["$model"]:-${MODEL_PRICES["unknown"]}}
    
    # Calculate cost
    if [ "$tokens" -gt 0 ]; then
        # Convert to thousands of tokens
        tokens_in_k=$((tokens / 1000))
        if [ "$tokens_in_k" -eq 0 ]; then
            tokens_in_k=1  # Minimum 1K for calculation
        fi
        
        # Calculate cost: price_per_1k * tokens_in_k
        cost=$(echo "$price_per_1k * $tokens_in_k" | bc -l 2>/dev/null || echo "0")
        # Format to 6 decimal places
        cost_formatted=$(printf "%.6f" "$cost")
    else
        cost_formatted="0.000000"
    fi
    
    # Create usage entry
    usage_entry="{
      \"agent_id\": \"$agent_id\",
      \"model\": \"$model\",
      \"tokens\": $tokens,
      \"price_per_1k\": \"$price_per_1k\",
      \"cost_usd\": \"$cost_formatted\",
      \"calculated_at\": \"$(date -Iseconds)\"
    }"
    
    usage_data+="$usage_entry"
    
    # Add comma if not last element
    if [ $i -lt $((agent_count - 1)) ]; then
        usage_data+=","
    fi
    
    echo "  $agent_id: $tokens tokens → \$$cost_formatted ($model)"
done

usage_data+="]"

# Write to file
echo "$usage_data" > "$OUT"

# Validate JSON
if jq empty "$OUT" 2>/dev/null; then
    echo "✅ JSON validation passed"
    
    # Verify length > 0
    usage_length=$(jq 'length' "$OUT")
    if [ "$usage_length" -gt 0 ]; then
        echo "📈 Usage data has $usage_length entries"
    else
        echo "⚠️  Usage data is empty"
    fi
else
    echo "❌ JSON validation failed"
    # Create valid empty JSON as fallback
    echo '[]' > "$OUT"
fi

echo "📁 Output: $OUT"
echo "📊 Sample:"
jq '.[] | {agent_id, model, tokens, cost_usd}' "$OUT" | head -3

echo "✅ Phase 7.1 complete: API usage costs calculated"