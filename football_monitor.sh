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

# First, let's see exactly how the data looks
echo "🔍 Analyzing data structure..."
echo "$RESPONSE" | jq '.Games[0] | {GT, Scrs, Comps}' 2>/dev/null

# Process matches and filter for 0-0 games between minute 10-80
echo "🔍 Processing matches..."

FOUND_MATCHES=false
MESSAGE_CONTENT=""

# Find 0-0 matches using a simple approach
MATCH_LINES=""

# Process each game individually
for i in $(seq 0 $((GAMES_COUNT - 1))); do
    # Extract game data
    GAME=$(echo "$RESPONSE" | jq ".Games[$i]" 2>/dev/null)
    
    if [ ! -z "$GAME" ] && [ "$GAME" != "null" ]; then
        # Extract individual fields
        GT=$(echo "$GAME" | jq -r '.GT // empty' 2>/dev/null)
        TEAM1=$(echo "$GAME" | jq -r '.Comps[0].Name // empty' 2>/dev/null)
        TEAM2=$(echo "$GAME" | jq -r '.Comps[1].Name // empty' 2>/dev/null)
        SCORE1=$(echo "$GAME" | jq -r '.Scrs[0] // empty' 2>/dev/null)
        SCORE2=$(echo "$GAME" | jq -r '.Scrs[1] // empty' 2>/dev/null)
        
        # Debug: show this match data
        echo "🔍 Match $i: $TEAM1 vs $TEAM2 ($GT min) - Score: $SCORE1-$SCORE2"
        
        # Check if this match meets our criteria
        if [ ! -z "$GT" ] && [ ! -z "$TEAM1" ] && [ ! -z "$TEAM2" ] && [ ! -z "$SCORE1" ] && [ ! -z "$SCORE2" ]; then
            # Check if GT is between 10-80 and scores are 0-0
            if [ "$GT" -ge 10 ] && [ "$GT" -le 80 ]; then
                # Convert scores to integers for comparison
                SCORE1_INT=$(echo "$SCORE1" | cut -d. -f1)
                SCORE2_INT=$(echo "$SCORE2" | cut -d. -f1)
                
                if [ "$SCORE1_INT" = "0" ] && [ "$SCORE2_INT" = "0" ]; then
                    MATCH_LINE="$TEAM1 - $TEAM2 (${GT}min)"
                    MATCH_LINES="$MATCH_LINES$MATCH_LINE"$'\n'
                    echo "⚽ Found 0-0 match: $MATCH_LINE"
                    FOUND_MATCHES=true
                fi
            fi
        fi
    fi
done

# Send message to Telegram if matches were found
if [ "$FOUND_MATCHES" = true ]; then
    MESSAGE_CONTENT="🚨 0-0 Matches between minute 10-80:"$'\n'"$MATCH_LINES"
    
    echo "📤 Sending message to Telegram..."
    echo "📋 Message to send:"
    echo "$MESSAGE_CONTENT"
    
    # Send using curl with form data
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
    
    # Debug: show all matches in range
    echo "🔍 All matches in range 10-80 minutes:"
    for i in $(seq 0 $((GAMES_COUNT - 1))); do
        GAME=$(echo "$RESPONSE" | jq ".Games[$i]" 2>/dev/null)
        
        if [ ! -z "$GAME" ] && [ "$GAME" != "null" ]; then
            GT=$(echo "$GAME" | jq -r '.GT // empty' 2>/dev/null)
            TEAM1=$(echo "$GAME" | jq -r '.Comps[0].Name // empty' 2>/dev/null)
            TEAM2=$(echo "$GAME" | jq -r '.Comps[1].Name // empty' 2>/dev/null)
            SCORE1=$(echo "$GAME" | jq -r '.Scrs[0] // empty' 2>/dev/null)
            SCORE2=$(echo "$GAME" | jq -r '.Scrs[1] // empty' 2>/dev/null)
            
            if [ ! -z "$GT" ] && [ "$GT" -ge 10 ] && [ "$GT" -le 80 ]; then
                echo "  - $TEAM1 vs $TEAM2 (${GT}min) Score: $SCORE1-$SCORE2"
            fi
        fi
    done
fi

echo "🏁 Script completed successfully"
