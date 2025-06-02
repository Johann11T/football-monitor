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

# Use jq to find and format matches directly
MATCH_LINES=$(echo "$RESPONSE" | jq -r '
.Games[] | 
select(.GT != null and .GT >= 10 and .GT <= 80) |
select(.Scrs != null and (.Scrs | length) >= 2) |
select(.Scrs[0] == 0 and .Scrs[1] == 0) |
select(.Comps != null and (.Comps | length) >= 2) |
"\(.Comps[0].Name) - \(.Comps[1].Name) (\(.GT)min)"
' 2>/dev/null)

# Check if we found any matches
if [ ! -z "$MATCH_LINES" ]; then
    echo "⚽ Found matches that meet criteria:"
    
    # Build message content
    MESSAGE_CONTENT="🚨 0-0 Matches between minute 10-80:"
    
    # Add each match line
    while IFS= read -r line; do
        if [ ! -z "$line" ]; then
            MESSAGE_CONTENT="$MESSAGE_CONTENT"

# Send message to Telegram if matches were found
if [ "$FOUND_MATCHES" = true ]; then
    echo "📤 Sending message to Telegram..."
    
    # Prepare message for Telegram (replace newlines for proper JSON)
    TELEGRAM_MESSAGE=$(echo "$MESSAGE_CONTENT" | sed ':a;N;$!ba;s/\n/\\n/g')
    
    # Send using curl with form data (simpler than JSON)
    TELEGRAM_RESPONSE=$(curl -s -X POST \
        -F "chat_id=$CHAT_ID" \
        -F "text=$MESSAGE_CONTENT" \
        -F "message_thread_id=1241" \
        "$TELEGRAM_URI")
    
    # Check response from Telegram
    if echo "$TELEGRAM_RESPONSE" | jq -e '.ok' > /dev/null 2>&1; then
        echo "✅ Message sent successfully to Telegram"
    else
        echo "❌ Error sending message to Telegram:"
        echo "$TELEGRAM_RESPONSE" | jq -r '.description // "Unknown error"' 2>/dev/null || echo "Failed to parse error response"
    fi
else
    echo "ℹ️  No 0-0 matches found between minute 10-80"
    
    # Debug: show some matches in the time range for verification
    echo "🔍 Sample matches in range 10-80 minutes (any score):"
    SAMPLE_MATCHES=$(echo "$RESPONSE" | jq -r '
    .Games[] | 
    select(.GT != null and .GT >= 10 and .GT <= 80) |
    select(.Comps != null and (.Comps | length) >= 2) |
    select(.Scrs != null and (.Scrs | length) >= 2) |
    "  - \(.Comps[0].Name // "N/A") vs \(.Comps[1].Name // "N/A") (\(.GT)min) Score: \(.Scrs[0] // "N/A")-\(.Scrs[1] // "N/A")"
    ' 2>/dev/null)
    
    if [ ! -z "$SAMPLE_MATCHES" ]; then
        echo "$SAMPLE_MATCHES" | head -5
    else
        echo "  No matches in range to display"
        
        # Show any matches at all for debugging
        echo "🔍 All matches (any minute, any score):"
        echo "$RESPONSE" | jq -r '
        .Games[0:3][] | 
        "  - \(.Comps[0].Name // "N/A") vs \(.Comps[1].Name // "N/A") (\(.GT // "N/A")min) Score: \(.Scrs[0] // "N/A")-\(.Scrs[1] // "N/A")"
        ' 2>/dev/null || echo "  Error processing match data"
    fi
fi

echo "🏁 Script completed successfully"\n'"$line"
            echo "⚽ Found: $line"
            FOUND_MATCHES=true
        fi
    done <<< "$MATCH_LINES"
fi

# Send message to Telegram if matches were found
if [ "$FOUND_MATCHES" = true ]; then
    echo "📤 Sending message to Telegram..."
    
    # Prepare JSON payload for Telegram
    JSON_PAYLOAD=$(jq -n \
        --arg chat_id "$CHAT_ID" \
        --arg text "$MESSAGE_CONTENT" \
        --argjson thread_id 1241 \
        '{
            chat_id: $chat_id,
            text: $text,
            message_thread_id: $thread_id
        }')
    
    # Send message to Telegram
    TELEGRAM_RESPONSE=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -d "$JSON_PAYLOAD" \
        "$TELEGRAM_URI")
    
    # Check response from Telegram
    if echo "$TELEGRAM_RESPONSE" | jq -e '.ok' > /dev/null 2>&1; then
        echo "✅ Message sent successfully to Telegram"
    else
        echo "❌ Error sending message to Telegram:"
        echo "$TELEGRAM_RESPONSE" | jq -r '.description // "Unknown error"' 2>/dev/null || echo "Failed to parse error response"
    fi
else
    echo "ℹ️  No 0-0 matches found between minute 10-80"
    
    # Debug: show some matches in the time range for verification
    echo "🔍 Sample matches in range 10-80 minutes (any score):"
    echo "$RESPONSE" | jq -r '
    .Games[] | 
    select(.GT != null and .GT >= 10 and .GT <= 80) |
    select(.Comps != null and (.Comps | length) >= 2) |
    select(.Scrs != null and (.Scrs | length) >= 2) |
    "  - \(.Comps[0].Name // "N/A") vs \(.Comps[1].Name // "N/A") (\(.GT)'"'"') Score: \(.Scrs[0] // "N/A")-\(.Scrs[1] // "N/A")"
    ' 2>/dev/null | head -5 || echo "  No matches in range to display"
fi

echo "🏁 Script completed successfully"
