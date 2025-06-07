#!/bin/bash
# Football Monitor Script - Debug Version
# Adapted from PowerShell with extensive debugging

# Configuration - use environment variables
BOT_TOKEN="${BOT_TOKEN}"
CHAT_ID="${CHAT_ID}"
TELEGRAM_URI="https://api.telegram.org/bot$BOT_TOKEN/sendMessage"

# Debug mode - set to 0 to reduce output
DEBUG=0

debug_print() {
    if [ "$DEBUG" = "1" ]; then
        echo "🐛 DEBUG: $1"
    fi
}

# Verify configuration
if [ -z "$BOT_TOKEN" ] || [ -z "$CHAT_ID" ]; then
    echo "❌ Error: BOT_TOKEN and CHAT_ID must be configured"
    echo "Usage: export BOT_TOKEN='your_token' && export CHAT_ID='your_chat_id'"
    exit 1
fi

debug_print "Bot token configured (length: ${#BOT_TOKEN})"
debug_print "Chat ID: $CHAT_ID"

# API configuration
API_BASE_URL="https://ws.bwappservice.com/service.asmx"
USER_ID="5325664"
REQUEST_ID="600887363328"

# Get current timestamp (Unix epoch)
TIMESTAMP=$(date +%s)
debug_print "Timestamp: $TIMESTAMP"

echo "🔍 Fetching today's matches..."

# First API call - Get match list of the day
debug_print "Making first API call to GetMatchListOfDay..."

MATCH_LIST_RESPONSE=$(curl -s --compressed -X POST \
    -H "Accept: application/json" \
    -H "Accept-Encoding: gzip" \
    -H "Content-Type: application/json" \
    -H "DT: Android" \
    -H "Host: ws.bwappservice.com" \
    -H "L: en" \
    -H "mMecilW: $REQUEST_ID" \
    -H "PdnwSaa: GetMatchListOfDay" \
    -H "sportType: 1" \
    -H "User-Agent: Dalvik/2.1.0 (Linux; U; Android 7.0; Pixel 9 Build/NBD92Y)" \
    -H "xpAelZg: n7YDsi35eLS302z" \
    -H "yCtoqLc: $USER_ID" \
    -d "{\"userId\":\"$USER_ID\",\"matchdate\":\"$TIMESTAMP\",\"requestId\":\"$REQUEST_ID\"}" \
    "$API_BASE_URL/GetMatchListOfDay")

CURL_EXIT_CODE=$?
debug_print "Curl exit code: $CURL_EXIT_CODE"

if [ $CURL_EXIT_CODE -ne 0 ]; then
    echo "❌ Error: Curl failed with exit code $CURL_EXIT_CODE"
    exit 1
fi

if [ -z "$MATCH_LIST_RESPONSE" ]; then
    echo "❌ Error: Empty response from API"
    exit 1
fi

debug_print "Response length: ${#MATCH_LIST_RESPONSE}"
debug_print "First 200 chars of response: ${MATCH_LIST_RESPONSE:0:200}..."

# Check if response is valid JSON
echo "$MATCH_LIST_RESPONSE" | jq . > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "❌ Error: Invalid JSON response"
    echo "Full response: $MATCH_LIST_RESPONSE"
    exit 1
fi

echo "✅ Match list retrieved successfully"

# Check if we have the expected structure
HAS_D=$(echo "$MATCH_LIST_RESPONSE" | jq 'has("d")' 2>/dev/null)
debug_print "Has 'd' property: $HAS_D"

if [ "$HAS_D" != "true" ]; then
    echo "❌ Error: Response doesn't have expected 'd' property"
    echo "Response structure: $(echo "$MATCH_LIST_RESPONSE" | jq 'keys' 2>/dev/null)"
    exit 1
fi

# Count leagues and matches
LEAGUES_COUNT=$(echo "$MATCH_LIST_RESPONSE" | jq '.d.leagueMatchs | length' 2>/dev/null)
debug_print "Number of leagues: $LEAGUES_COUNT"

if [ "$LEAGUES_COUNT" = "0" ] || [ "$LEAGUES_COUNT" = "null" ]; then
    echo "ℹ️ No leagues found in response"
    exit 0
fi

# Extract all matches and filter
echo "🔍 Processing matches..."
PROCESSED_MATCHES=0
LIVE_MATCHES_COUNT=0
FILTERED_MATCHES_COUNT=0

# Create temporary file for match processing
TEMP_MATCHES="/tmp/matches_$$"
TEMP_FILTERED="/tmp/filtered_$$"

# Extract all matches
echo "$MATCH_LIST_RESPONSE" | jq -r '
.d.leagueMatchs[]? | 
.matchs[]? | 
select(.matchId != null) |
[.matchId, .teamHomeName, .teamAwayName, .leagueName, .matchMinute] |
@csv
' > "$TEMP_MATCHES" 2>/dev/null

TOTAL_MATCHES=$(wc -l < "$TEMP_MATCHES" 2>/dev/null || echo "0")
debug_print "Total matches extracted: $TOTAL_MATCHES"

if [ "$TOTAL_MATCHES" = "0" ]; then
    echo "ℹ️ No matches found in response"
    rm -f "$TEMP_MATCHES"
    exit 0
fi

# Filter matches (exclude FT, HT, Pen. and those with ":")
while IFS=',' read -r match_id home_team away_team league minute_raw; do
    # Remove quotes
    match_id=$(echo "$match_id" | tr -d '"')
    home_team=$(echo "$home_team" | tr -d '"')
    away_team=$(echo "$away_team" | tr -d '"')
    league=$(echo "$league" | tr -d '"')
    minute_raw=$(echo "$minute_raw" | tr -d '"')
    
    PROCESSED_MATCHES=$((PROCESSED_MATCHES + 1))
    
    # Skip if minute is FT, HT, Pen., null, or contains ":"
    if [ "$minute_raw" = "FT" ] || [ "$minute_raw" = "HT" ] || [ "$minute_raw" = "Pen." ] || [ "$minute_raw" = "null" ] || [ -z "$minute_raw" ]; then
        debug_print "Skipping finished match: $home_team vs $away_team ($minute_raw)"
        continue
    fi
    
    if echo "$minute_raw" | grep -q ":"; then
        debug_print "Skipping match with time format: $home_team vs $away_team ($minute_raw)"
        continue
    fi
    
    LIVE_MATCHES_COUNT=$((LIVE_MATCHES_COUNT + 1))
    
    # Check if minute is numeric and between 60-80
    if echo "$minute_raw" | grep -q '^[0-9]\+$'; then
        minute_num="$minute_raw"
        if [ "$minute_num" -ge 10 ] && [ "$minute_num" -le 80 ]; then
            echo "$match_id,$home_team,$away_team,$league,$minute_num" >> "$TEMP_FILTERED"
            FILTERED_MATCHES_COUNT=$((FILTERED_MATCHES_COUNT + 1))
            debug_print "Match in range: $home_team vs $away_team (${minute_num}')"
        fi
    fi
done < "$TEMP_MATCHES"

debug_print "Processed: $PROCESSED_MATCHES, Live: $LIVE_MATCHES_COUNT, Filtered (60-80): $FILTERED_MATCHES_COUNT"

if [ "$FILTERED_MATCHES_COUNT" = "0" ]; then
    echo "ℹ️ No live matches found between minute 60-80"
    rm -f "$TEMP_MATCHES" "$TEMP_FILTERED"
    exit 0
fi

echo "🔍 Found $FILTERED_MATCHES_COUNT matches between minute 60-80, checking statistics..."

FOUND_ALERTS=false

# Process filtered matches
while IFS=',' read -r match_id home_team away_team league minute_num; do
    echo "📊 Getting statistics for: $home_team vs $away_team (${minute_num}')"
    
    # Second API call - Get live statistics
    debug_print "Making API call for match ID: $match_id"
    
    STATS_RESPONSE=$(curl -s --compressed -X POST \
        -H "Accept: application/json" \
        -H "Accept-Encoding: gzip" \
        -H "Content-Type: application/json" \
        -H "DT: Android" \
        -H "Host: ws.bwappservice.com" \
        -H "L: en" \
        -H "mMecilW: $REQUEST_ID" \
        -H "PdnwSaa: GetLiveInPlayStatistics" \
        -H "sportType: 1" \
        -H "User-Agent: Dalvik/2.1.0 (Linux; U; Android 7.0; Pixel 9 Build/NBD92Y)" \
        -H "xpAelZg: n7YDsi35eLS302z" \
        -H "yCtoqLc: $USER_ID" \
        -d "{\"userId\":\"$USER_ID\",\"matchId\":\"$match_id\"}" \
        "$API_BASE_URL/GetLiveInPlayStatistics")
    
    STATS_CURL_EXIT=$?
    debug_print "Stats API curl exit code: $STATS_CURL_EXIT"
    
    if [ $STATS_CURL_EXIT -ne 0 ]; then
        echo "❌ Error getting statistics for match ID: $match_id (curl error: $STATS_CURL_EXIT)"
        continue
    fi
    
    if [ -z "$STATS_RESPONSE" ]; then
        echo "❌ Empty statistics response for match ID: $match_id"
        continue
    fi
    
    debug_print "Stats response length: ${#STATS_RESPONSE}"
    debug_print "Stats response preview: ${STATS_RESPONSE:0:200}..."
    
    # Check if stats response is valid JSON
    echo "$STATS_RESPONSE" | jq . > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "❌ Invalid JSON in statistics response for match ID: $match_id"
        debug_print "Stats response: $STATS_RESPONSE"
        continue
    fi
    
    # Check if statistics exist
    STATS_COUNT=$(echo "$STATS_RESPONSE" | jq '.d.statistics | length' 2>/dev/null)
    debug_print "Statistics count: $STATS_COUNT"
    
    if [ "$STATS_COUNT" = "0" ] || [ "$STATS_COUNT" = "null" ]; then
        echo "⚠️  No statistics available for this match"
        continue
    fi
    
    # Extract key statistics
    HOME_GOALS=$(echo "$STATS_RESPONSE" | jq -r '.d.statistics[] | select(.itemName == "IGoal") | .itemValueHome' 2>/dev/null)
    AWAY_GOALS=$(echo "$STATS_RESPONSE" | jq -r '.d.statistics[] | select(.itemName == "IGoal") | .itemValueAway' 2>/dev/null)
    
    HOME_YELLOW=$(echo "$STATS_RESPONSE" | jq -r '.d.statistics[] | select(.itemName == "IYellowCard") | .itemValueHome' 2>/dev/null)
    AWAY_YELLOW=$(echo "$STATS_RESPONSE" | jq -r '.d.statistics[] | select(.itemName == "IYellowCard") | .itemValueAway' 2>/dev/null)
    HOME_RED=$(echo "$STATS_RESPONSE" | jq -r '.d.statistics[] | select(.itemName == "IRedCard") | .itemValueHome' 2>/dev/null)
    AWAY_RED=$(echo "$STATS_RESPONSE" | jq -r '.d.statistics[] | select(.itemName == "IRedCard") | .itemValueAway' 2>/dev/null)
    
    debug_print "Goals: $HOME_GOALS - $AWAY_GOALS"
    debug_print "Yellow cards: $HOME_YELLOW - $AWAY_YELLOW"
    debug_print "Red cards: $HOME_RED - $HOME_RED"
    
    # Convert to integers (handle null/empty values)
    HOME_GOALS_INT=$(echo "$HOME_GOALS" | grep -E '^[0-9]+$' || echo "0")
    AWAY_GOALS_INT=$(echo "$AWAY_GOALS" | grep -E '^[0-9]+$' || echo "0")
    HOME_YELLOW_INT=$(echo "$HOME_YELLOW" | grep -E '^[0-9]+$' || echo "0")
    AWAY_YELLOW_INT=$(echo "$AWAY_YELLOW" | grep -E '^[0-9]+$' || echo "0")
    HOME_RED_INT=$(echo "$HOME_RED" | grep -E '^[0-9]+$' || echo "0")
    AWAY_RED_INT=$(echo "$AWAY_RED" | grep -E '^[0-9]+$' || echo "0")
    
    # Build detailed message (simplified for testing)
    MESSAGE="🏆 $league
⏱️  Minute: ${minute_num}'
🏟️  $home_team vs $away_team
⚽ SCORE: ${HOME_GOALS_INT} - ${AWAY_GOALS_INT}
🟨 Yellow cards: ${HOME_YELLOW_INT} - ${AWAY_YELLOW_INT}
🟥 Red cards: ${HOME_RED_INT} - ${AWAY_RED_INT}"
    
    # Check condition 1: Both teams have 0 goals
    if [ "$HOME_GOALS_INT" = "0" ] && [ "$AWAY_GOALS_INT" = "0" ]; then
        echo "🚨 Found 0-0 match: $home_team vs $away_team"
        
        curl -s --compressed -X POST \
            -F "chat_id=$CHAT_ID" \
            -F "text=🚨 0-0 Match Alert:
$MESSAGE" \
            -F "message_thread_id=1241" \
            "$TELEGRAM_URI"
        
        SEND_RESULT=$?
        if [ $SEND_RESULT -eq 0 ]; then
            echo "✅ 0-0 alert sent to Telegram (thread 1241)"
            FOUND_ALERTS=true
        else
            echo "❌ Error sending 0-0 alert (curl exit: $SEND_RESULT)"
        fi
        
        sleep 2
    fi
    
    # Check condition 2: No yellow or red cards for both teams
    if [ "$HOME_YELLOW_INT" = "0" ] && [ "$AWAY_YELLOW_INT" = "0" ] && [ "$HOME_RED_INT" = "0" ] && [ "$AWAY_RED_INT" = "0" ]; then
        echo "🟨 Found clean match (no cards): $home_team vs $away_team"
        
        curl -s --compressed -X POST \
            -F "chat_id=$CHAT_ID" \
            -F "text=🟨 Clean Match Alert (No Cards):
$MESSAGE" \
            -F "message_thread_id=1425" \
            "$TELEGRAM_URI"
        
        SEND_RESULT=$?
        if [ $SEND_RESULT -eq 0 ]; then
            echo "✅ Clean match alert sent to Telegram (thread 1425)"
            FOUND_ALERTS=true
        else
            echo "❌ Error sending clean match alert (curl exit: $SEND_RESULT)"
        fi
        
        sleep 2
    fi
    
    # Small delay between requests
    sleep 1
    
done < "$TEMP_FILTERED"

# Cleanup
rm -f "$TEMP_MATCHES" "$TEMP_FILTERED"

if [ "$FOUND_ALERTS" = false ]; then
    echo "ℹ️ No matches found matching alert conditions"
fi

echo "🏁 Script completed"
