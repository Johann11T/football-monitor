#!/bin/bash

# Configuración
BOT_TOKEN="7610496109:AAETDKarqYLdhU8NU2EF5Zt9q4xEWDgXpzQ"
CHAT_ID="-1002372039350"
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
    echo "Error al obtener datos de la API"
    exit 1
fi

# Procesar partidos y filtrar
MESSAGE=""
FOUND_MATCHES=false

# Usar jq para procesar JSON y filtrar partidos
FILTERED_MATCHES=$(echo "$RESPONSE" | jq -r '
    .Games[] | 
    select(.GT >= 60 and .GT <= 80) |
    select(.Scrs[0] == "0" and .Scrs[1] == "0") |
    "\(.Comps[0].Name) - \(.Comps[1].Name) (\(.GT)'"'"')"
')

# Construir mensaje
if [ ! -z "$FILTERED_MATCHES" ]; then
    MESSAGE="$FILTERED_MATCHES"
    FOUND_MATCHES=true
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
