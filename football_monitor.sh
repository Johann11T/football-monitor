#!/bin/bash
# Football Monitor Script - Adapted from PowerShell
# Monitors live matches and sends alerts for specific conditions

# Configuration - use environment variables from GitHub Secrets
BOT_TOKEN="${BOT_TOKEN}"
CHAT_ID="${CHAT_ID}"
TELEGRAM_URI="https://api.telegram.org/bot$BOT_TOKEN/sendMessage"

# Verify configuration
if [ -z "$BOT_TOKEN" ] || [ -z "$CHAT_ID" ]; then
    echo "❌ Error: BOT_TOKEN and CHAT_ID must be configured as secrets"
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
MATCH_LIST_RESPONSE=$(curl -s -X POST \
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
    echo "❌ Error getting match list from API"
    exit 1
fi

echo "✅ Match list retrieved successfully"

# Extract live matches (excluding FT, HT, Pen. and matches with ":" in minute)
# Parse JSON and filter matches
LIVE_MATCHES=$(echo "$MATCH_LIST_RESPONSE" | jq -r '
.d.leagueMatchs[]?.matchs[]? | 
select(.matchMinute != null and .matchMinute != "FT" and .matchMinute != "HT" and .matchMinute != "Pen." and (.matchMinute | tostring | contains(":") | not)) |
{
    matchId: .matchId,
    homeTeam: .teamHomeName,
    awayTeam: .teamAwayName,
    league: .leagueName,
    matchMinute: (.matchMinute | tonumber)
} |
select(.matchMinute >= 10 and .matchMinute <= 80) |
@json
' 2>/dev/null)

if [ -z "$LIVE_MATCHES" ]; then
    echo "ℹ️ No live matches found between minute 60-80"
    exit 0
fi

echo "🔍 Found matches between minute 60-80, checking statistics..."

FOUND_ALERTS=false

# Process each match
while IFS= read -r match_json; do
    if [ ! -z "$match_json" ] && [ "$match_json" != "null" ]; then
        MATCH_ID=$(echo "$match_json" | jq -r '.matchId')
        HOME_TEAM=$(echo "$match_json" | jq -r '.homeTeam')
        AWAY_TEAM=$(echo "$match_json" | jq -r '.awayTeam')
        LEAGUE=$(echo "$match_json" | jq -r '.league')
        MATCH_MINUTE=$(echo "$match_json" | jq -r '.matchMinute')
        
        echo "📊 Getting statistics for: $HOME_TEAM vs $AWAY_TEAM (${MATCH_MINUTE}')"
        
        # Second API call - Get live statistics for this match
        STATS_RESPONSE=$(curl -s -X POST \
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
            -d "{\"userId\":\"$USER_ID\",\"matchId\":\"$MATCH_ID\"}" \
            "$API_BASE_URL/GetLiveInPlayStatistics")
        
        if [ $? -eq 0 ] && [ ! -z "$STATS_RESPONSE" ]; then
            # Parse statistics
            STATS=$(echo "$STATS_RESPONSE" | jq -r '.d.statistics[]? | {(.itemName): {home: .itemValueHome, away: .itemValueAway}} | to_entries[] | "\(.key)|\(.value.home)|\(.value.away)"' 2>/dev/null)
            
            if [ ! -z "$STATS" ]; then
                # Extract specific statistics
                HOME_GOALS=$(echo "$STATS" | grep "^IGoal|" | cut -d'|' -f2 | head -1)
                AWAY_GOALS=$(echo "$STATS" | grep "^IGoal|" | cut -d'|' -f3 | head -1)
                HOME_TEAM_NAME=$(echo "$STATS" | grep "^ITeam|" | cut -d'|' -f2 | head -1)
                AWAY_TEAM_NAME=$(echo "$STATS" | grep "^ITeam|" | cut -d'|' -f3 | head -1)
                
                HOME_YELLOW=$(echo "$STATS" | grep "^IYellowCard|" | cut -d'|' -f2 | head -1)
                AWAY_YELLOW=$(echo "$STATS" | grep "^IYellowCard|" | cut -d'|' -f3 | head -1)
                HOME_RED=$(echo "$STATS" | grep "^IRedCard|" | cut -d'|' -f2 | head -1)
                AWAY_RED=$(echo "$STATS" | grep "^IRedCard|" | cut -d'|' -f3 | head -1)
                
                ON_TARGET_HOME=$(echo "$STATS" | grep "^IOnTarget|" | cut -d'|' -f2 | head -1)
                ON_TARGET_AWAY=$(echo "$STATS" | grep "^IOnTarget|" | cut -d'|' -f3 | head -1)
                OFF_TARGET_HOME=$(echo "$STATS" | grep "^IOffTarget|" | cut -d'|' -f2 | head -1)
                OFF_TARGET_AWAY=$(echo "$STATS" | grep "^IOffTarget|" | cut -d'|' -f3 | head -1)
                
                ATTACKS_HOME=$(echo "$STATS" | grep "^IAttacks|" | cut -d'|' -f2 | head -1)
                ATTACKS_AWAY=$(echo "$STATS" | grep "^IAttacks|" | cut -d'|' -f3 | head -1)
                DANGEROUS_ATTACKS_HOME=$(echo "$STATS" | grep "^IDangerousAttacks|" | cut -d'|' -f2 | head -1)
                DANGEROUS_ATTACKS_AWAY=$(echo "$STATS" | grep "^IDangerousAttacks|" | cut -d'|' -f3 | head -1)
                
                POSSESSION_HOME=$(echo "$STATS" | grep "^IPosession|" | cut -d'|' -f2 | head -1)
                POSSESSION_AWAY=$(echo "$STATS" | grep "^IPosession|" | cut -d'|' -f3 | head -1)
                
                CORNERS_HOME=$(echo "$STATS" | grep "^ICorner|" | cut -d'|' -f2 | head -1)
                CORNERS_AWAY=$(echo "$STATS" | grep "^ICorner|" | cut -d'|' -f3 | head -1)
                
                SUBSTITUTIONS_HOME=$(echo "$STATS" | grep "^ISubstitution|" | cut -d'|' -f2 | head -1)
                SUBSTITUTIONS_AWAY=$(echo "$STATS" | grep "^ISubstitution|" | cut -d'|' -f3 | head -1)
                
                FREE_KICKS_HOME=$(echo "$STATS" | grep "^IFreeKick|" | cut -d'|' -f2 | head -1)
                FREE_KICKS_AWAY=$(echo "$STATS" | grep "^IFreeKick|" | cut -d'|' -f3 | head -1)
                
                THROW_INS_HOME=$(echo "$STATS" | grep "^IThrowIn|" | cut -d'|' -f2 | head -1)
                THROW_INS_AWAY=$(echo "$STATS" | grep "^IThrowIn|" | cut -d'|' -f3 | head -1)
                
                GOAL_KICKS_HOME=$(echo "$STATS" | grep "^IGoalKick|" | cut -d'|' -f2 | head -1)
                GOAL_KICKS_AWAY=$(echo "$STATS" | grep "^IGoalKick|" | cut -d'|' -f3 | head -1)
                
                # Create detailed message
                MESSAGE="
══════════════
🏆 $LEAGUE
⏱️  Minute: ${MATCH_MINUTE}'
🏟️  ${HOME_TEAM_NAME:-$HOME_TEAM} vs ${AWAY_TEAM_NAME:-$AWAY_TEAM}
══════════════

⚽ SCORE:                ${HOME_GOALS:-0} - ${AWAY_GOALS:-0}

🎯 SHOOTING STATS:
   Shots on target:      ${ON_TARGET_HOME:-0} - ${ON_TARGET_AWAY:-0}
   Shots off target:     ${OFF_TARGET_HOME:-0} - ${OFF_TARGET_AWAY:-0}

⚡ ATTACKS:
   Total attacks:        ${ATTACKS_HOME:-0} - ${ATTACKS_AWAY:-0}
   Dangerous attacks:    ${DANGEROUS_ATTACKS_HOME:-0} - ${DANGEROUS_ATTACKS_AWAY:-0}

🏃 POSSESSION:           ${POSSESSION_HOME:-0}% - ${POSSESSION_AWAY:-0}%

📋 OTHER STATISTICS:
   Corners:              ${CORNERS_HOME:-0} - ${CORNERS_AWAY:-0}
   Yellow cards:         ${HOME_YELLOW:-0} - ${AWAY_YELLOW:-0}
   Red cards:            ${HOME_RED:-0} - ${AWAY_RED:-0}
   Substitutions:        ${SUBSTITUTIONS_HOME:-0} - ${SUBSTITUTIONS_AWAY:-0}
   Free kicks:           ${FREE_KICKS_HOME:-0} - ${FREE_KICKS_AWAY:-0}
   Throw ins:            ${THROW_INS_HOME:-0} - ${THROW_INS_AWAY:-0}
   Goal kicks:           ${GOAL_KICKS_HOME:-0} - ${GOAL_KICKS_AWAY:-0}
"

                # Check condition 1: Both teams have 0 goals
                if [ "${HOME_GOALS:-0}" = "0" ] && [ "${AWAY_GOALS:-0}" = "0" ]; then
                    echo "🚨 Found 0-0 match: $HOME_TEAM vs $AWAY_TEAM"
                    
                    curl -s -X POST \
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
                
                # Check condition 2: No yellow or red cards for both teams
                if [ "${HOME_YELLOW:-0}" = "0" ] && [ "${AWAY_YELLOW:-0}" = "0" ] && [ "${HOME_RED:-0}" = "0" ] && [ "${AWAY_RED:-0}" = "0" ]; then
                    echo "🟨 Found clean match (no cards): $HOME_TEAM vs $AWAY_TEAM"
                    
                    curl -s -X POST \
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
            else
                echo "⚠️  No statistics available for this match"
            fi
        else
            echo "❌ Error getting statistics for match ID: $MATCH_ID"
        fi
        
        # Small delay between requests
        sleep 1
    fi
done <<< "$LIVE_MATCHES"

if [ "$FOUND_ALERTS" = false ]; then
    echo "ℹ️ No matches found matching alert conditions"
fi

echo "🏁 Script completed"
