#!/bin/bash

# Football Monitor Script for GitHub Actions
# Searches for 0-0 matches between minute 10-80

# Configuration - use environment variables from GitHub Secrets
BOT_TOKEN="${BOT_TOKEN}"
CHAT_ID="${CHAT_ID}"
TELEGRAM_URI="https://api.telegram.org/bot$BOT_TOKEN/sendMessage"

# Verify that variables are configured
if [ -z "$BOT_TOKEN" ] || [ -z "$CHAT_ID" ]; then
    echo "❌ Error: BOT_TOKEN and CHAT_ID must be configured as secrets"
    echo "Configure TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID in Repository Secrets"
    exit 1
fi

# API URL - Updated to new endpoint
API_URL="https://mobileapi.365scores.com/Data/Games/Live/?FullCurrTime=true&onlyvideos=false&sports=1&withExpanded=true&light=true&ShowNAOdds=true&OddsFormat=1&AppVersion=1417&theme=dark&tz=75&uc=112&athletesSupported=true&StoreVersion=1417&lang=29&AppType=2"

echo "🔍 Consulting live matches (searching for 0-0 between minute 10-80)..."

# Make HTTP request and get JSON response
RESPONSE=$(curl -s "$API_URL")

# Verify if response is valid
if [ $? -ne 0 ] || [ -z "$RESPONSE" ]; then
    echo "❌ Error getting data from API"
    exit 1
fi

echo "✅ Data obtained from API"

# Debug: show basic structure
GAMES_COUNT=$(echo "$RESPONSE" | jq '.Games | length' 2>/dev/null)
echo "📊 Total matches found: $GAMES_COUNT"

# Process matches and filter for 0-0 games between minute 10-80
echo "🔍 Processing matches..."

FOUND_MATCHES=false
MESSAGE_CONTENT=""

# Create a simpler jq query that returns formatted strings directly
cat > /tmp/jq_simple.jq << 'EOF'
.Games[] | 
select(.GT != null and .GT >= 10 and .GT <= 80) |
select(.Scrs != null and (.Scrs | length) >= 2) |
select((.Scrs[0] | tonumber) == 0 and (.Scrs[1] | tonumber) == 0) |
select(.Comps != null and (.Comps | length) >= 2) |
"\(.Comps[0].Name) - \(.Comps[1].Name) (\(.GT)min)"
EOF

# Execute jq and get formatted match lines
MATCH_LINES=$(echo "$RESPONSE" | jq -r -f /tmp/jq_simple.jq 2>/dev/null)

# Check if we found any matches
if [ ! -z "$MATCH_LINES" ] && [ "$MATCH_LINES" != "null" ]; then
    echo "⚽ Found 0-0 matches!"
    
    # Build message content
    MESSAGE_CONTENT="🚨 0-0 Matches between minute 10-80:"
    
    # Add each match line
    while IFS= read -r line; do
        if [ ! -z "$line" ]; then
            MESSAGE_CONTENT="$MESSAGE_CONTENT"

# Send message to Telegram if matches were found
if [ "$FOUND_MATCHES" = true ]; then
    echo "📤 Sending message to Telegram..."
    
    # Send using curl with form data (simpler than JSON)
    TELEGRAM_RESPONSE=$(curl -s -X POST \
        -F "chat_id=$CHAT_ID" \
        -F "text=$MESSAGE_CONTENT" \
        -F "message_thread_id=1241" \
        "$TELEGRAM_URI")
    
    # Check response from Telegram
    if echo "$TELEGRAM_RESPONSE" | jq -e '.ok' > /dev/null 2>&1; then
        echo "✅ Message sent successfully to Telegram"
        echo "📋 Message sent:"
        echo "$MESSAGE_CONTENT"
    else
        echo "❌ Error sending message to Telegram:"
        echo "$TELEGRAM_RESPONSE" | jq -r '.description // "Unknown error"' 2>/dev/null || echo "Failed to parse error response"
    fi
else
    echo "ℹ️  No 0-0 matches found between minute 10-80"
    
    # Debug: show some matches in the time range for verification
    echo "🔍 Sample matches in range 10-80 minutes (any score):"
    
    # Create debug query file
    cat > /tmp/debug_query.jq << 'EOF'
.Games[] | 
select(.GT != null and .GT >= 10 and .GT <= 80) |
select(.Comps != null and (.Comps | length) >= 2) |
select(.Scrs != null and (.Scrs | length) >= 2) |
"  - \(.Comps[0].Name // "N/A") vs \(.Comps[1].Name // "N/A") (\(.GT)min) Score: \(.Scrs[0] // "N/A")-\(.Scrs[1] // "N/A")"
EOF
    
    SAMPLE_MATCHES=$(echo "$RESPONSE" | jq -r -f /tmp/debug_query.jq 2>/dev/null)
    
    if [ ! -z "$SAMPLE_MATCHES" ]; then
        echo "$SAMPLE_MATCHES" | head -5
    else
        echo "  No matches in range to display"
        
        # Show any matches at all for debugging
        echo "🔍 All matches (any minute, any score):"
        echo "$RESPONSE" | jq -r '.Games[0:3][] | "  - \(.Comps[0].Name // "N/A") vs \(.Comps[1].Name // "N/A") (\(.GT // "N/A")min) Score: \(.Scrs[0] // "N/A")-\(.Scrs[1] // "N/A")"' 2>/dev/null || echo "  Error processing match data"
    fi
fi

# Cleanup temp files
rm -f /tmp/jq_simple.jq /tmp/debug_query.jq

echo "🏁 Script completed successfully"\n'"$line"
            echo "⚽ Found: $line"
            FOUND_MATCHES=true
        fi
    done <<< "$MATCH_LINES"
fi

# Send message to Telegram if matches were found
if [ "$FOUND_MATCHES" = true ] && [ -f /tmp/matches_found.txt ] && [ -s /tmp/matches_found.txt ]; then
    echo "📤 Sending message to Telegram..."
    
    # Send using curl with form data (simpler than JSON)
    TELEGRAM_RESPONSE=$(curl -s -X POST \
        -F "chat_id=$CHAT_ID" \
        -F "text=$MESSAGE_CONTENT" \
        -F "message_thread_id=1241" \
        "$TELEGRAM_URI")
    
    # Check response from Telegram
    if echo "$TELEGRAM_RESPONSE" | jq -e '.ok' > /dev/null 2>&1; then
        echo "✅ Message sent successfully to Telegram"
        
        # Show what was sent
        echo "📋 Message content:"
        cat /tmp/matches_found.txt
    else
        echo "❌ Error sending message to Telegram:"
        echo "$TELEGRAM_RESPONSE" | jq -r '.description // "Unknown error"' 2>/dev/null || echo "Failed to parse error response"
    fi
else
    echo "ℹ️  No 0-0 matches found between minute 10-80"
    
    # Debug: show some matches in the time range for verification
    echo "🔍 Sample matches in range 10-80 minutes (any score):"
    
    # Create debug query file
    cat > /tmp/debug_query.jq << 'EOF'
.Games[] | 
select(.GT != null and .GT >= 10 and .GT <= 80) |
select(.Comps != null and (.Comps | length) >= 2) |
select(.Scrs != null and (.Scrs | length) >= 2) |
"  - \(.Comps[0].Name // "N/A") vs \(.Comps[1].Name // "N/A") (\(.GT)min) Score: \(.Scrs[0] // "N/A")-\(.Scrs[1] // "N/A")"
EOF
    
    SAMPLE_MATCHES=$(echo "$RESPONSE" | jq -r -f /tmp/debug_query.jq 2>/dev/null)
    
    if [ ! -z "$SAMPLE_MATCHES" ]; then
        echo "$SAMPLE_MATCHES" | head -5
    else
        echo "  No matches in range to display"
        
        # Show any matches at all for debugging
        echo "🔍 All matches (any minute, any score):"
        echo "$RESPONSE" | jq -r '.Games[0:3][] | "  - \(.Comps[0].Name // "N/A") vs \(.Comps[1].Name // "N/A") (\(.GT // "N/A")min) Score: \(.Scrs[0] // "N/A")-\(.Scrs[1] // "N/A")"' 2>/dev/null || echo "  Error processing match data"
    fi
fi

# Cleanup temp files
rm -f /tmp/jq_query.jq /tmp/debug_query.jq /tmp/matches_found.txt

echo "🏁 Script completed successfully"
