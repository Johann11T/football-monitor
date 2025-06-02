#!/bin/bash

# Configuración - usar variables de entorno desde GitHub Secrets
BOT_TOKEN="${BOT_TOKEN}"
CHAT_ID="${CHAT_ID}"

# Verificar que las variables estén configuradas
if [ -z "$BOT_TOKEN" ] || [ -z "$CHAT_ID" ]; then
    echo "❌ Error: BOT_TOKEN y CHAT_ID deben estar configurados como secrets"
    echo "Configura TELEGRAM_BOT_TOKEN y TELEGRAM_CHAT_ID en Repository Secrets"
    exit 1
fi
TELEGRAM_URI="https://api.telegram.org/bot$BOT_TOKEN/sendMessage"

# Obtener fecha actual en formato dd%2FMM%2Fyyyy
CURRENT_DATE=$(date +"%d%%2F%m%%2F%Y")

# URL de la API
API_URL="https://mobileapi.365scores.com/Data/Games/Live/?startdate=${CURRENT_DATE}&enddate=&FullCurrTime=true&onlyvideos=false&sports=1&withExpanded=true&light=true&ShowNAOdds=true&OddsFormat=1&AppVersion=1417&theme=dark&tz=75&uc=112&athletesSupported=true&StoreVersion=1417&lang=29&AppType=2"

echo "Consultando partidos en vivo..."

# Realizar petición HTTP y procesar JSON
RESPONSE=$(curl -s "$API_URL")

# Verificar si la respuesta es válida
if [ $? -ne 0 ] || [ -z "$RESPONSE" ]; then
    echo "❌ Error al obtener datos de la API"
    exit 1
fi

echo "✅ Datos obtenidos de la API"

# Debug: mostrar estructura básica
echo "🔍 Verificando estructura de datos..."
GAMES_COUNT=$(echo "$RESPONSE" | jq '.Games | length' 2>/dev/null)
echo "Partidos encontrados: $GAMES_COUNT"

# Si hay pocos partidos, mostrar algunos para debug
if [ "$GAMES_COUNT" -le 5 ] && [ "$GAMES_COUNT" -gt 0 ]; then
    echo "📊 Muestra de partidos (para debug):"
    echo "$RESPONSE" | jq -r '.Games[0:2][] | "ID: \(.ID?) - GT: \(.GT?) - Scores: \(.Scrs?) - Teams: [\(.Comps[0].Name?), \(.Comps[1].Name?)]"' 2>/dev/null || echo "Error procesando muestra"
fi

# Procesar partidos y filtrar
MESSAGE=""
FOUND_MATCHES=false

# Usar jq para procesar JSON y filtrar partidos
FILTERED_MATCHES=$(echo "$RESPONSE" | jq -r '
    .Games[]? | 
    select(.GT? >= 10 and .GT? <= 80) |
    select((.Scrs? | length) >= 2) |
    select((.Scrs[0] | tonumber) == 0 and (.Scrs[1] | tonumber) == 0) |
    select((.Comps? | length) >= 2) |
    "\(.Comps[0].Name?) - \(.Comps[1].Name?) (\(.GT?)'"'"')"
' 2>/dev/null)

# Construir mensaje
if [ ! -z "$FILTERED_MATCHES" ]; then
    MESSAGE="🚨 Partidos 0-0 entre minuto -80:
$FILTERED_MATCHES"
    FOUND_MATCHES=true
    echo "⚽ Partidos encontrados que cumplen criterios:"
    echo "$FILTERED_MATCHES"
else
    echo "ℹ️  No se encontraron partidos 0-0 entre minuto -80"
    
    # Debug adicional: mostrar partidos en el rango de tiempo
    echo "🔍 Partidos en rango -80 minutos (cualquier score):"
    echo "$RESPONSE" | jq -r '
        .Games[]? | 
        select(.GT? >= 10 and .GT? <= 80) |
        "- \(.Comps[0].Name? // "N/A") vs \(.Comps[1].Name? // "N/A") (\(.GT?)'"'"') - Score: \(.Scrs[0]? // "N/A")-\(.Scrs[1]? // "N/A")"
    ' 2>/dev/null | head -3
fi

# Enviar mensaje a Telegram si hay partidos
if [ "$FOUND_MATCHES" = true ]; then
    # Preparar datos para Telegram
    JSON_PAYLOAD=$(jq -n \
        --arg chat_id "$CHAT_ID" \
        --arg text "$MESSAGE" \
        --argjson thread_id 1241 \
        '{
            chat_id: $chat_id,
            text: $text,
            message_thread_id: $thread_id
        }')
    
    # Enviar mensaje
    TELEGRAM_RESPONSE=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -d "$JSON_PAYLOAD" \
        "$TELEGRAM_URI")
    
    # Verificar respuesta
    if echo "$TELEGRAM_RESPONSE" | jq -e '.ok' > /dev/null; then
        echo "✅ Mensaje enviado exitosamente"
        echo "Partidos encontrados:"
        echo "$MESSAGE"
    else
        echo "❌ Error enviando mensaje:"
        echo "$TELEGRAM_RESPONSE" | jq -r '.description // "Error desconocido"'
    fi
else
    echo "ℹ️  No se encontraron partidos 0-0 entre minuto 60-80"
fi
