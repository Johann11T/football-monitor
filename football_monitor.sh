#!/bin/bash
# Football Monitor Script - Fast and Simple
# Searches for 0-0 matches between minute 60-80
# Configuration - use environment variables from GitHub Secrets
BOT_TOKEN="${BOT_TOKEN}"
CHAT_ID="${CHAT_ID}"
TELEGRAM_URI="https://api.telegram.org/bot$BOT_TOKEN/sendMessage"
# Verify configuration
if [ -z "$BOT_TOKEN" ] || [ -z "$CHAT_ID" ]; then
    echo "❌ Error: BOT_TOKEN and CHAT_ID must be configured as secrets"
    exit 1
fi
# API URL
API_URL="https://mobileapi.365scores.com/Data/Games/Live/?FullCurrTime=true&onlyvideos=false&sports=1&withExpanded=true&light=true&ShowNAOdds=true&OddsFormat=1&AppVersion=1417&theme=dark&tz=75&uc=112&athletesSupported=true&StoreVersion=1417&lang=29&AppType=2"
# Get data from API
RESPONSE=$(curl -s "$API_URL")
if [ $? -ne 0 ] || [ -z "$RESPONSE" ]; then
    echo "❌ Error getting data from API"
    exit 1
fi
# Get total games count
GAMES_COUNT=$(echo "$RESPONSE" | jq '.Games | length' 2>/dev/null)
# Process games and find 0-0 matches
FOUND_MATCHES=false
for i in $(seq 0 $((GAMES_COUNT - 1))); do
    MATCH_LINE=""
    GAME=$(echo "$RESPONSE" | jq ".Games[$i]" 2>/dev/null)
    
    if [ ! -z "$GAME" ] && [ "$GAME" != "null" ]; then
        GT=$(echo "$GAME" | jq -r '.GT // empty' 2>/dev/null)
        TEAM1=$(echo "$GAME" | jq -r '.Comps[0].Name // empty' 2>/dev/null)
        TEAM2=$(echo "$GAME" | jq -r '.Comps[1].Name // empty' 2>/dev/null)
        SCORE1=$(echo "$GAME" | jq -r '.Scrs[0] // empty' 2>/dev/null)
        SCORE2=$(echo "$GAME" | jq -r '.Scrs[1] // empty' 2>/dev/null)
        COMP_ID=$(echo "$GAME" | jq -r '.Comp // empty' 2>/dev/null)
        
        # Check criteria: minute 60-80, scores 0-0
        if [ ! -z "$GT" ] && [ ! -z "$TEAM1" ] && [ ! -z "$TEAM2" ] && [ ! -z "$SCORE1" ] && [ ! -z "$SCORE2" ]; then
            if [ "$GT" -ge 60 ] && [ "$GT" -le 80 ]; then
                SCORE1_INT=$(echo "$SCORE1" | cut -d. -f1)
                SCORE2_INT=$(echo "$SCORE2" | cut -d. -f1)
                
                if [ "$SCORE1_INT" = "0" ] && [ "$SCORE2_INT" = "0" ]; then
                    # Get competition name
                    COMP_NAME=$(echo "$RESPONSE" | jq -r --arg comp_id "$COMP_ID" '.Competitions[] | select(.ID == ($comp_id | tonumber)) | .Name // empty' 2>/dev/null)
                    if [ ! -z "$COMP_NAME" ]; then
                        MATCH_LINE="($COMP_NAME) $TEAM1 - $TEAM2 (${GT}min)"$'\n'
                    else
                        MATCH_LINE="$TEAM1 - $TEAM2 (${GT}min)"$'\n'
                    fi
                    FOUND_MATCHES=true
                    # Send message
                    MESSAGE_CONTENT="🚨 0-0 Match between minute 60-80:"$'\n'"$MATCH_LINE"

                    curl -s -X POST \
                    -F "chat_id=$CHAT_ID" \
                    -F "text=$MESSAGE_CONTENT" \
                    -F "message_thread_id=1241" \
                    "$TELEGRAM_URI" > /dev/null
                        
                    echo "✅ Message sent to Telegram"
                fi
            fi
        fi
    fi
done
if [ "$FOUND_MATCHES" = false ]; then
    echo "ℹ️ No 0-0 matches found"
fi
