#!/bin/bash
# Football Monitor Script - Production Version
# Adapted from PowerShell with original formatting

# Configuration - use environment variables
BOT_TOKEN="${BOT_TOKEN}"
CHAT_ID="${CHAT_ID}"
TELEGRAM_URI="https://api.telegram.org/bot$BOT_TOKEN/sendMessage"

# Verify configuration
if [ -z "$BOT_TOKEN" ] || [ -z "$CHAT_ID" ]; then
    echo "❌ Error: BOT_TOKEN and CHAT_ID must be configured"
    echo "Usage: export BOT_TOKEN='your_token' && export CHAT_ID='your_chat_id'"
    exit 1
fi

# API configuration
API_BASE_URL="https://ws.bwappservice.com/service.asmx"
USER_ID="5325664"
REQUEST_ID="600887363328"

# Get current timestamp (Unix epoch)
TIMESTAMP=$(date +%s)

echo "🔍 Fetching today's matches..."

# First API call - Get match list of the day
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

if [ $? -ne 0 ] || [ -z "$MATCH_LIST_RESPONSE" ]; then
    echo "❌ Error getting data from API"
    exit 1
fi

# Check if response is valid JSON
echo "$MATCH_LIST_RESPONSE" | jq . > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "❌ Error: Invalid JSON response"
    exit 1
fi

echo "✅ Match list retrieved successfully"

# Check if we have the expected structure
HAS_D=$(echo "$MATCH_LIST_RESPONSE" | jq 'has("d")' 2>/dev/null)
if [ "$HAS_D" != "true" ]; then
    echo "❌ Error: Response doesn't have expected structure"
    exit 1
fi

# Count leagues and matches
LEAGUES_COUNT=$(echo "$MATCH_LIST_RESPONSE" | jq '.d.leagueMatchs | length' 2>/dev/null)
if [ "$LEAGUES_COUNT" = "0" ] || [ "$LEAGUES_COUNT" = "null" ]; then
    echo "ℹ️ No leagues found in response"
    exit 0
fi

# Extract matches and filter for minute 60-80
echo "🔍 Processing matches..."
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
if [ "$TOTAL_MATCHES" = "0" ]; then
    echo "ℹ️ No matches found in response"
    rm -f "$TEMP_MATCHES"
    exit 0
fi

FILTERED_MATCHES_COUNT=0

# Filter matches (exclude FT, HT, Pen. and those with ":", keep only 60-80 minute range)
while IFS=',' read -r match_id home_team away_team league minute_raw; do
    # Remove quotes
    match_id=$(echo "$match_id" | tr -d '"')
    home_team=$(echo "$home_team" | tr -d '"')
    away_team=$(echo "$away_team" | tr -d '"')
    league=$(echo "$league" | tr -d '"')
    minute_raw=$(echo "$minute_raw" | tr -d '"')
    
    # Skip if minute is FT, HT, Pen., null, or contains ":"
    if [ "$minute_raw" = "FT" ] || [ "$minute_raw" = "HT" ] || [ "$minute_raw" = "Pen." ] || [ "$minute_raw" = "null" ] || [ -z "$minute_raw" ]; then
        continue
    fi
    
    if echo "$minute_raw" | grep -q ":"; then
        continue
    fi
    
    # Check if minute is numeric and between 60-80
    if echo "$minute_raw" | grep -q '^[0-9]\+$'; then
        minute_num="$minute_raw"
        if [ "$minute_num" -ge 10] && [ "$minute_num" -le 80 ]; then
            echo "$match_id,$home_team,$away_team,$league,$minute_num" >> "$TEMP_FILTERED"
            FILTERED_MATCHES_COUNT=$((FILTERED_MATCHES_COUNT + 1))
        fi
    fi
done < "$TEMP_MATCHES"

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
    
    if [ $? -ne 0 ] || [ -z "$STATS_RESPONSE" ]; then
        echo "❌ Error getting statistics for match ID: $match_id"
        continue
    fi
    
    # Check if stats response is valid JSON
    echo "$STATS_RESPONSE" | jq . > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "❌ Invalid JSON in statistics response for match ID: $match_id"
        continue
    fi
    
    # Check if statistics exist
    STATS_COUNT=$(echo "$STATS_RESPONSE" | jq '.d.statistics | length' 2>/dev/null)
    if [ "$STATS_COUNT" = "0" ] || [ "$STATS_COUNT" = "null" ]; then
        echo "⚠️  No statistics available for this match"
        continue
    fi
    
    # Extract ALL statistics with original formatting
    HOME_TEAM_NAME=$(echo "$STATS_RESPONSE" | jq -r '.d.statistics[] | select(.itemName == "ITeam") | .itemValueHome' 2>/dev/null)
    AWAY_TEAM_NAME=$(echo "$STATS_RESPONSE" | jq -r '.d.statistics[] | select(.itemName == "ITeam") | .itemValueAway' 2>/dev/null)
    
    HOME_GOALS=$(echo "$STATS_RESPONSE" | jq -r '.d.statistics[] | select(.itemName == "IGoal") | .itemValueHome' 2>/dev/null)
    AWAY_GOALS=$(echo "$STATS_RESPONSE" | jq -r '.d.statistics[] | select(.itemName == "IGoal") | .itemValueAway' 2>/dev/null)
    
    ON_TARGET_HOME=$(echo "$STATS_RESPONSE" | jq -r '.d.statistics[] | select(.itemName == "IOnTarget") | .itemValueHome' 2>/dev/null)
    ON_TARGET_AWAY=$(echo "$STATS_RESPONSE" | jq -r '.d.statistics[] | select(.itemName == "IOnTarget") | .itemValueAway' 2>/dev/null)
    OFF_TARGET_HOME=$(echo "$STATS_RESPONSE" | jq -r '.d.statistics[] | select(.itemName == "IOffTarget") | .itemValueHome' 2>/dev/null)
    OFF_TARGET_AWAY=$(echo "$STATS_RESPONSE" | jq -r '.d.statistics[] | select(.itemName == "IOffTarget") | .itemValueAway' 2>/dev/null)
    
    ATTACKS_HOME=$(echo "$STATS_RESPONSE" | jq -r '.d.statistics[] | select(.itemName == "IAttacks") | .itemValueHome' 2>/dev/null)
    ATTACKS_AWAY=$(echo "$STATS_RESPONSE" | jq -r '.d.statistics[] | select(.itemName == "IAttacks") | .itemValueAway' 2>/dev/null)
    DANGEROUS_ATTACKS_HOME=$(echo "$STATS_RESPONSE" | jq -r '.d.statistics[] | select(.itemName == "IDangerousAttacks") | .itemValueHome' 2>/dev/null)
    DANGEROUS_ATTACKS_AWAY=$(echo "$STATS_RESPONSE" | jq -r '.d.statistics[] | select(.itemName == "IDangerousAttacks") | .itemValueAway' 2>/dev/null)
    
    POSSESSION_HOME=$(echo "$STATS_RESPONSE" | jq -r '.d.statistics[] | select(.itemName == "IPosession") | .itemValueHome' 2>/dev/null)
    POSSESSION_AWAY=$(echo "$STATS_RESPONSE" | jq -r '.d.statistics[] | select(.itemName == "IPosession") | .itemValueAway' 2>/dev/null)
    
    CORNERS_HOME=$(echo "$STATS_RESPONSE" | jq -r '.d.statistics[] | select(.itemName == "ICorner") | .itemValueHome' 2>/dev/null)
    CORNERS_AWAY=$(echo "$STATS_RESPONSE" | jq -r '.d.statistics[] | select(.itemName == "ICorner") | .itemValueAway' 2>/dev/null)
    
    HOME_YELLOW=$(echo "$STATS_RESPONSE" | jq -r '.d.statistics[] | select(.itemName == "IYellowCard") | .itemValueHome' 2>/dev/null)
    AWAY_YELLOW=$(echo "$STATS_RESPONSE" | jq -r '.d.statistics[] | select(.itemName == "IYellowCard") | .itemValueAway' 2>/dev/null)
    HOME_RED=$(echo "$STATS_RESPONSE" | jq -r '.d.statistics[] | select(.itemName == "IRedCard") | .itemValueHome' 2>/dev/null)
    AWAY_RED=$(echo "$STATS_RESPONSE" | jq -r '.d.statistics[] | select(.itemName == "IRedCard") | .itemValueAway' 2>/dev/null)
    
    SUBSTITUTIONS_HOME=$(echo "$STATS_RESPONSE" | jq -r '.d.statistics[] | select(.itemName == "ISubstitution") | .itemValueHome' 2>/dev/null)
    SUBSTITUTIONS_AWAY=$(echo "$STATS_RESPONSE" | jq -r '.d.statistics[] | select(.itemName == "ISubstitution") | .itemValueAway' 2>/dev/null)
    
    FREE_KICKS_HOME=$(echo "$STATS_RESPONSE" | jq -r '.d.statistics[] | select(.itemName == "IFreeKick") | .itemValueHome' 2>/dev/null)
    FREE_KICKS_AWAY=$(echo "$STATS_RESPONSE" | jq -r '.d.statistics[] | select(.itemName == "IFreeKick") | .itemValueAway' 2>/dev/null)
    
    THROW_INS_HOME=$(echo "$STATS_RESPONSE" | jq -r '.d.statistics[] | select(.itemName == "IThrowIn") | .itemValueHome' 2>/dev/null)
    THROW_INS_AWAY=$(echo "$STATS_RESPONSE" | jq -r '.d.statistics[] | select(.itemName == "IThrowIn") | .itemValueAway' 2>/dev/null)
    
    GOAL_KICKS_HOME=$(echo "$STATS_RESPONSE" | jq -r '.d.statistics[] | select(.itemName == "IGoalKick") | .itemValueHome' 2>/dev/null)
    GOAL_KICKS_AWAY=$(echo "$STATS_RESPONSE" | jq -r '.d.statistics[] | select(.itemName == "IGoalKick") | .itemValueAway' 2>/dev/null)
    
    # Convert to integers (handle null/empty values)
    HOME_GOALS_INT=$(echo "$HOME_GOALS" | grep -E '^[0-9]+$' || echo "0")
    AWAY_GOALS_INT=$(echo "$AWAY_GOALS" | grep -E '^[0-9]+$' || echo "0")
    HOME_YELLOW_INT=$(echo "$HOME_YELLOW" | grep -E '^[0-9]+$' || echo "0")
    AWAY_YELLOW_INT=$(echo "$AWAY_YELLOW" | grep -E '^[0-9]+$' || echo "0")
    HOME_RED_INT=$(echo "$HOME_RED" | grep -E '^[0-9]+$' || echo "0")
    AWAY_RED_INT=$(echo "$AWAY_RED" | grep -E '^[0-9]+$' || echo "0")
    
    ON_TARGET_HOME_INT=$(echo "$ON_TARGET_HOME" | grep -E '^[0-9]+$' || echo "0")
    ON_TARGET_AWAY_INT=$(echo "$ON_TARGET_AWAY" | grep -E '^[0-9]+$' || echo "0")
    OFF_TARGET_HOME_INT=$(echo "$OFF_TARGET_HOME" | grep -E '^[0-9]+$' || echo "0")
    OFF_TARGET_AWAY_INT=$(echo "$OFF_TARGET_AWAY" | grep -E '^[0-9]+$' || echo "0")
    
    ATTACKS_HOME_INT=$(echo "$ATTACKS_HOME" | grep -E '^[0-9]+$' || echo "0")
    ATTACKS_AWAY_INT=$(echo "$ATTACKS_AWAY" | grep -E '^[0-9]+$' || echo "0")
    DANGEROUS_ATTACKS_HOME_INT=$(echo "$DANGEROUS_ATTACKS_HOME" | grep -E '^[0-9]+$' || echo "0")
    DANGEROUS_ATTACKS_AWAY_INT=$(echo "$DANGEROUS_ATTACKS_AWAY" | grep -E '^[0-9]+$' || echo "0")
    
    CORNERS_HOME_INT=$(echo "$CORNERS_HOME" | grep -E '^[0-9]+$' || echo "0")
    CORNERS_AWAY_INT=$(echo "$CORNERS_AWAY" | grep -E '^[0-9]+$' || echo "0")
    
    SUBSTITUTIONS_HOME_INT=$(echo "$SUBSTITUTIONS_HOME" | grep -E '^[0-9]+$' || echo "0")
    SUBSTITUTIONS_AWAY_INT=$(echo "$SUBSTITUTIONS_AWAY" | grep -E '^[0-9]+$' || echo "0")
    
    FREE_KICKS_HOME_INT=$(echo "$FREE_KICKS_HOME" | grep -E '^[0-9]+$' || echo "0")
    FREE_KICKS_AWAY_INT=$(echo "$FREE_KICKS_AWAY" | grep -E '^[0-9]+$' || echo "0")
    
    THROW_INS_HOME_INT=$(echo "$THROW_INS_HOME" | grep -E '^[0-9]+$' || echo "0")
    THROW_INS_AWAY_INT=$(echo "$THROW_INS_AWAY" | grep -E '^[0-9]+$' || echo "0")
    
    GOAL_KICKS_HOME_INT=$(echo "$GOAL_KICKS_HOME" | grep -E '^[0-9]+$' || echo "0")
    GOAL_KICKS_AWAY_INT=$(echo "$GOAL_KICKS_AWAY" | grep -E '^[0-9]+$' || echo "0")
    
    # Create detailed message with EXACT original formatting
    MESSAGE="
══════════════
🏆 $league
⏱️  Minute: ${minute_num}'
🏟️  ${HOME_TEAM_NAME:-$home_team} vs ${AWAY_TEAM_NAME:-$away_team}
══════════════

⚽ SCORE:                ${HOME_GOALS_INT} - ${AWAY_GOALS_INT}

🎯 SHOOTING STATS:
   Shots on target:      ${ON_TARGET_HOME_INT} - ${ON_TARGET_AWAY_INT}
   Shots off target:     ${OFF_TARGET_HOME_INT} - ${OFF_TARGET_AWAY_INT}

⚡ ATTACKS:
   Total attacks:        ${ATTACKS_HOME_INT} - ${ATTACKS_AWAY_INT}
   Dangerous attacks:    ${DANGEROUS_ATTACKS_HOME_INT} - ${DANGEROUS_ATTACKS_AWAY_INT}

🏃 POSSESSION:           ${POSSESSION_HOME:-0}% - ${POSSESSION_AWAY:-0}%

📋 OTHER STATISTICS:
   Corners:              ${CORNERS_HOME_INT} - ${CORNERS_AWAY_INT}
   Yellow cards:         ${HOME_YELLOW_INT} - ${AWAY_YELLOW_INT}
   Red cards:            ${HOME_RED_INT} - ${AWAY_RED_INT}
   Substitutions:        ${SUBSTITUTIONS_HOME_INT} - ${SUBSTITUTIONS_AWAY_INT}
   Free kicks:           ${FREE_KICKS_HOME_INT} - ${FREE_KICKS_AWAY_INT}
   Throw ins:            ${THROW_INS_HOME_INT} - ${THROW_INS_AWAY_INT}
   Goal kicks:           ${GOAL_KICKS_HOME_INT} - ${GOAL_KICKS_AWAY_INT}

"

    # Check condition 1: Both teams have 0 goals (EXACT PowerShell logic)
    if [ "$HOME_GOALS_INT" = "0" ] && [ "$AWAY_GOALS_INT" = "0" ]; then
        echo "🚨 Found 0-0 match: $home_team vs $away_team"
        
        curl -s --compressed -X POST \
            -F "chat_id=$CHAT_ID" \
            -F "text=$MESSAGE" \
            -F "message_thread_id=1241" \
            "$TELEGRAM_URI" > /dev/null
        
        if [ $? -eq 0 ]; then
            echo "✅ 0-0 alert sent to Telegram (thread 1241)"
            FOUND_ALERTS=true
        else
            echo "❌ Error sending 0-0 alert"
        fi
        
        sleep 2
    fi
    
    # Check condition 2: No yellow or red cards for both teams (EXACT PowerShell logic)
    if [ "$HOME_YELLOW_INT" = "0" ] && [ "$AWAY_YELLOW_INT" = "0" ] && [ "$HOME_RED_INT" = "0" ] && [ "$AWAY_RED_INT" = "0" ]; then
        echo "🟨 Found clean match (no cards): $home_team vs $away_team"
        
        curl -s --compressed -X POST \
            -F "chat_id=$CHAT_ID" \
            -F "text=$MESSAGE" \
            -F "message_thread_id=1425" \
            "$TELEGRAM_URI" > /dev/null
        
        if [ $? -eq 0 ]; then
            echo "✅ Clean match alert sent to Telegram (thread 1425)"
            FOUND_ALERTS=true
        else
            echo "❌ Error sending clean match alert"
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
