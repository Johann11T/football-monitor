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
        # Additional safety check - ensure minute_num is actually a number
        if [ -n "$minute_num" ] && [ "$minute_num" -eq "$minute_num" ] 2>/dev/null; then
            if [ "$minute_num" -ge 10 ] && [ "$minute_num" -le 80 ]; then
                echo "$match_id,$home_team,$away_team,$league,$minute_num" >> "$TEMP_FILTERED"
                FILTERED_MATCHES_COUNT=$((FILTERED_MATCHES_COUNT + 1))
            fi
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
    echo "📊 Getting statistics for: $home_team vs $away_team (${minute_num}min)"
    
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
    
    # Create temporary file for stats processing
    TEMP_STATS="/tmp/stats_$$"
    echo "$STATS_RESPONSE" | jq -r '.d.statistics[] | [.itemName, .itemValueHome, .itemValueAway] | @csv' > "$TEMP_STATS" 2>/dev/null
    
    # Function to get stat value
    get_stat() {
        local stat_name="$1"
        local home_away="$2"  # "home" or "away"
        local column=2
        if [ "$home_away" = "away" ]; then
            column=3
        fi
        
        grep "\"$stat_name\"" "$TEMP_STATS" | cut -d',' -f"$column" | tr -d '"' | head -1
    }
    
    # Extract key statistics
    HOME_TEAM_NAME=$(get_stat "ITeam" "home")
    AWAY_TEAM_NAME=$(get_stat "ITeam" "away")
    HOME_GOALS=$(get_stat "IGoal" "home")
    AWAY_GOALS=$(get_stat "IGoal" "away")
    HOME_YELLOW=$(get_stat "IYellowCard" "home")
    AWAY_YELLOW=$(get_stat "IYellowCard" "away")
    HOME_RED=$(get_stat "IRedCard" "home")
    AWAY_RED=$(get_stat "IRedCard" "away")
    
    # Get all other stats for display
    ON_TARGET_HOME=$(get_stat "IOnTarget" "home")
    ON_TARGET_AWAY=$(get_stat "IOnTarget" "away")
    OFF_TARGET_HOME=$(get_stat "IOffTarget" "home")
    OFF_TARGET_AWAY=$(get_stat "IOffTarget" "away")
    ATTACKS_HOME=$(get_stat "IAttacks" "home")
    ATTACKS_AWAY=$(get_stat "IAttacks" "away")
    DANGEROUS_ATTACKS_HOME=$(get_stat "IDangerousAttacks" "home")
    DANGEROUS_ATTACKS_AWAY=$(get_stat "IDangerousAttacks" "away")
    POSSESSION_HOME=$(get_stat "IPosession" "home")
    POSSESSION_AWAY=$(get_stat "IPosession" "away")
    CORNERS_HOME=$(get_stat "ICorner" "home")
    CORNERS_AWAY=$(get_stat "ICorner" "away")
    SUBSTITUTIONS_HOME=$(get_stat "ISubstitution" "home")
    SUBSTITUTIONS_AWAY=$(get_stat "ISubstitution" "away")
    FREE_KICKS_HOME=$(get_stat "IFreeKick" "home")
    FREE_KICKS_AWAY=$(get_stat "IFreeKick" "away")
    THROW_INS_HOME=$(get_stat "IThrowIn" "home")
    THROW_INS_AWAY=$(get_stat "IThrowIn" "away")
    GOAL_KICKS_HOME=$(get_stat "IGoalKick" "home")
    GOAL_KICKS_AWAY=$(get_stat "IGoalKick" "away")
    
    # Convert to integers (handle null/empty values)
    HOME_GOALS_INT=$(echo "$HOME_GOALS" | grep -E '^[0-9]+$' || echo "0")
    AWAY_GOALS_INT=$(echo "$AWAY_GOALS" | grep -E '^[0-9]+$' || echo "0")
    HOME_YELLOW_INT=$(echo "$HOME_YELLOW" | grep -E '^[0-9]+$' || echo "0")
    AWAY_YELLOW_INT=$(echo "$AWAY_YELLOW" | grep -E '^[0-9]+$' || echo "0")
    HOME_RED_INT=$(echo "$HOME_RED" | grep -E '^[0-9]+$' || echo "0")
    AWAY_RED_INT=$(echo "$AWAY_RED" | grep -E '^[0-9]+$' || echo "0")
    
    # Create detailed message with EXACT original formatting
    MESSAGE="
══════════════
🏆 $league
⏱️  Minute: ${minute_num}'
🏟️  ${HOME_TEAM_NAME:-$home_team} vs ${AWAY_TEAM_NAME:-$away_team}
══════════════

⚽ SCORE:                ${HOME_GOALS_INT} - ${AWAY_GOALS_INT}

🎯 SHOOTING STATS:
   Shots on target:      ${ON_TARGET_HOME:-0} - ${ON_TARGET_AWAY:-0}
   Shots off target:     ${OFF_TARGET_HOME:-0} - ${OFF_TARGET_AWAY:-0}

⚡ ATTACKS:
   Total attacks:        ${ATTACKS_HOME:-0} - ${ATTACKS_AWAY:-0}
   Dangerous attacks:    ${DANGEROUS_ATTACKS_HOME:-0} - ${DANGEROUS_ATTACKS_AWAY:-0}

🏃 POSSESSION:           ${POSSESSION_HOME:-0}% - ${POSSESSION_AWAY:-0}%

📋 OTHER STATISTICS:
   Corners:              ${CORNERS_HOME:-0} - ${CORNERS_AWAY:-0}
   Yellow cards:         ${HOME_YELLOW_INT} - ${AWAY_YELLOW_INT}
   Red cards:            ${HOME_RED_INT} - ${AWAY_RED_INT}
   Substitutions:        ${SUBSTITUTIONS_HOME:-0} - ${SUBSTITUTIONS_AWAY:-0}
   Free kicks:           ${FREE_KICKS_HOME:-0} - ${FREE_KICKS_AWAY:-0}
   Throw ins:            ${THROW_INS_HOME:-0} - ${THROW_INS_AWAY:-0}
   Goal kicks:           ${GOAL_KICKS_HOME:-0} - ${GOAL_KICKS_AWAY:-0}

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
    
    # Cleanup temp stats file
    rm -f "$TEMP_STATS"
    
    # Small delay between requests
    sleep 1
    
done < "$TEMP_FILTERED"

# Cleanup
rm -f "$TEMP_MATCHES" "$TEMP_FILTERED"

if [ "$FOUND_ALERTS" = false ]; then
    echo "ℹ️ No matches found matching alert conditions"
fi

echo "🏁 Script completed"
