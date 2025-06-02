# Clear console
Clear-Host

# Configuration using environment variables (GitHub Secrets)
$botToken = $env:BOT_TOKEN
$chatID = $env:CHAT_ID

# Verify that variables are configured
if ([string]::IsNullOrEmpty($botToken) -or [string]::IsNullOrEmpty($chatID)) {
    Write-Host "❌ Error: BOT_TOKEN and CHAT_ID must be configured as secrets" -ForegroundColor Red
    Write-Host "Configure TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID in Repository Secrets" -ForegroundColor Yellow
    exit 1
}

$uri = "https://api.telegram.org/bot$botToken/sendMessage"

# Configure security protocol
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Write-Host "🔍 Consulting live matches (searching for 0-0 between minute 10-80)..." -ForegroundColor Cyan

try {
    # Get data from API
    $response = Invoke-RestMethod -Uri "https://mobileapi.365scores.com/Data/Games/Live/?startdate=$((Get-Date -Format "dd/MM/yyyy") -replace "/", "%2F")&enddate=&FullCurrTime=true&onlyvideos=false&sports=1&withExpanded=true&light=true&ShowNAOdds=true&OddsFormat=1&AppVersion=1417&theme=dark&tz=75&uc=112&athletesSupported=true&StoreVersion=1417&lang=29&AppType=2" -Method Get
    
    Write-Host "✅ Data obtained from API" -ForegroundColor Green
    Write-Host "📊 Matches found: $($response.Games.Count)" -ForegroundColor Blue
    
    $message = @()
    $foundMatches = 0
    
    foreach ($match in $response.Games) {
        $gameTime = $match.GT
        
        # Search for matches between minute 10-80 with score 0-0
        if (($match.GT -ge 10) -and ($match.GT -le 80)) {
            if (([int]$match.Scrs[0] -eq 0) -and ([int]$match.Scrs[1] -eq 0)) {
                $matchInfo = "$($match.Comps[0].Name) - $($match.Comps[1].Name) ($($match.GT)')"
                $message += "$matchInfo`n"
                $foundMatches++
                Write-Host "⚽ Found: $matchInfo" -ForegroundColor Green
            }
        }
    }
    
    # Send message only if there are matches that meet criteria
    if ($message.Count -gt 0) {
        $finalMessage = "🚨 Matches 0-0 between minute 10-80:`n" + [String]::Join("", $message)
        
        $body = @{
            chat_id = $chatID
            text = $finalMessage
            message_thread_id = 1241
        }
        
        # Send message
        try {
            Invoke-RestMethod -Uri $uri -Method Post -Body $body
            Write-Host "✅ Message sent successfully to Telegram" -ForegroundColor Green
            Write-Host "📤 Matches reported: $foundMatches" -ForegroundColor Blue
        }
        catch {
            Write-Host "❌ Error sending message to Telegram: $_" -ForegroundColor Red
        }
    }
    else {
        Write-Host "ℹ️  No 0-0 matches found between minute 10-80" -ForegroundColor Yellow
        
        # Debug: show some matches in range to verify
        $debugMatches = $response.Games | Where-Object { $_.GT -ge 10 -and $_.GT -le 80 } | Select-Object -First 3
        if ($debugMatches) {
            Write-Host "🔍 Sample matches in range 10-80 min:" -ForegroundColor Magenta
            foreach ($match in $debugMatches) {
                Write-Host "  - $($match.Comps[0].Name) vs $($match.Comps[1].Name) ($($match.GT)') Score: $($match.Scrs[0])-$($match.Scrs[1])" -ForegroundColor DarkGray
            }
        }
    }
}
catch {
    Write-Host "❌ Error getting data from API: $_" -ForegroundColor Red
    exit 1
}

Write-Host "🏁 Script completed" -ForegroundColor Green
