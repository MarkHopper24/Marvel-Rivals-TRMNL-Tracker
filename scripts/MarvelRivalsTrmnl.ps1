<#
.SYNOPSIS
    Marvel Rivals player statistics tracking script that retrieves data from the Marvel Rivals API and posts it to the TRMNL platform.

.DESCRIPTION
    This script retrieves player statistics from the Marvel Rivals API, processes the data, and posts it to the TRMNL platform.
    It includes functions to update player stats, convert epoch time to date format, retrieve account data, get match history,
    map names, hero names, match details, and post the processed data to TRMNL.

.PARAMETER TrmnlPluginId
    Required. The ID of the TRMNL plugin where the data will be posted.

.PARAMETER APIKey
    Required. The API key for accessing the Marvel Rivals API.

.PARAMETER username
    Required. The username of the player whose statistics are being tracked.

.EXAMPLE
    .\MrTracker.ps1 -TrmnlPluginId "your-plugin-id" -APIKey "your-api-key" -username "playerName"

.NOTES
    File Name      : MrTracker.ps1
    Author         : Mark Hopper
    Prerequisite   : PowerShell 5.1 or later
    
.FUNCTIONALITY
    - Updates player statistics
    - Converts epoch time to readable date format
    - Retrieves and processes account data
    - Gets match history and details
    - Maps hero and map IDs to names
    - Posts processed data to TRMNL

.COMPONENT
    Function Update-Player-Stats
        Updates the player statistics by making an API call.
    
    Function Convert-EpochToDate
        Converts epoch time to a readable date format.
    
    Function Get-AccountData
        Retrieves and processes player account data and match history.
    
    Function Get-HeroName
        Maps hero ID to hero name.
    
    Function Get-MatchHistory
        Retrieves the player's recent match history.
    
    Function Get-MapName
        Maps map ID to map name.
    
    Function Get-MatchDetails
        Retrieves detailed information about a specific match.
    
    Function Invoke-TrmnlPostRequest
        Posts the processed data to the TRMNL platform.
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$TrmnlPluginId,
    [Parameter(Mandatory = $true)]
    [string]$APIKey,
    [Parameter(Mandatory = $true)]
    [string]$username
)

$headers = @{}
$headers.Add("x-api-key", "$APIKey")

Function Update-Player-Stats {
    param(
        [Parameter(Mandatory = $true)]
        [string]$username
    )

    $uri = "https://marvelrivalsapi.com/api/v1/player/$username/update"
    Invoke-RestMethod -Uri $uri -Headers $headers -Method Get -SkipHttpErrorCheck -ErrorAction SilentlyContinue
}

Function Convert-EpochToDate {
    param(
        [Parameter(Mandatory = $true)]
        [string]$epochTime
    )

    $date = (Get-Date -Date ([datetime]'1970-01-01' + [timespan]::FromSeconds($epochTime))).AddHours(-6)
    return $date
}

Function Get-AccountData {
    param(
        [Parameter(Mandatory = $true)]
        [string]$username
    )

    $uri = "https://marvelrivalsapi.com/api/v1/player/$username"

    $AccountResponse = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get -ContentType "application/json"

    #Check if $AccountResponse.updates.last_update_request was more than 1 hour ago
    $LastUpdateRequest = [datetime]$AccountResponse.updates.last_update_request
    $LastUpdateRequest = $LastUpdateRequest.Ticks
    $CurrentTime = [datetime]::Now.Ticks

    # One hour in ticks (10,000,000 ticks per second × 3600 seconds)
    $OneHourInTicks = 36000000000

    $TimeDifference = $CurrentTime - $LastUpdateRequest

    # Compare time difference with one hour in ticks
    if ($TimeDifference -ge $OneHourInTicks) {
        Update-Player-Stats -username $username
        #Even if its not yet updated, it will be the next time the script is run
        $AccountResponse = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get
    }

    $PlayerRank = $AccountResponse.player.rank.rank
    $PlayerLevel = $AccountResponse.player.level

    #Get the most use hero from heroes_ranked
    $MostUsedHero = ($AccountResponse.heroes_ranked | Sort-Object -Property play_time -Descending | Select-Object -First 1).hero_name
    $MostUsedHero = (Get-Culture).TextInfo.ToTitleCase($MostUsedHero.ToLower())


    #Make sure the first letter of the hero name is capitalized. Some hereos have three words
    $MostUsedHero = $MostUsedHero.Substring(0, 1).ToUpper() + $MostUsedHero.Substring(1)
    
    #$TotalGames = $AccountResponse.overall_stats.total_matches
    #$TotalWins = $AccountResponse.overall_stats.total_wins
    #$UnrankedGames = $AccountResponse.overall_stats.unranked.total_matches
    #$UnrankedWins = $AccountResponse.overall_stats.unranked.total_wins
    $RankedGames = $AccountResponse.overall_stats.ranked.total_matches
    $RankedWins = $AccountResponse.overall_stats.ranked.total_wins
    $RankedKills = $AccountResponse.overall_stats.ranked.total_kills
    $RankedDeaths = $AccountResponse.overall_stats.ranked.total_deaths
    $RankedAssists = $AccountResponse.overall_stats.ranked.total_assists

    # Ensure all percentage calculations are whole numbers
    # $OverallWinRate = [math]::Round(($TotalWins / $TotalGames) * 100, 0).ToString() + "%"
    # $UnrankedWinRate = [math]::Round(($UnrankedWins / $UnrankedGames) * 100, 0).ToString() + "%"
    $RankedWinRate = [math]::Round(($RankedWins / $RankedGames) * 100, 0).ToString() + "%"

    #Round the CompKDA to the nearest 2 decimal places
    $CompKDA = [math]::Round(($RankedKills + $RankedAssists) / $RankedDeaths, 2)

    #$Match_history = $AccountResponse.match_history | Select-Object -First 5
    $Match_history = Get-MatchHistory -username $username

    #Create an expandable list to store the parsed match details
    $ParsedMatchDetails = New-Object System.Collections.Generic.List[System.Object]

    #$AccountData = Get-AccountData -username $username
    foreach ($match in $Match_history) {

        #Create a hashtable to store the parsed match information
        $MatchDetails = @{}

        #if game_mode_id eq 2, it is ranked. If 1, it is unranked
        if ($match.game_mode_id -eq 2) {
            $MatchDetails.Add(('Game Mode'), 'Ranked')
        }
        elseif ($match.game_mode_id -eq 1) {
            $MatchDetails.Add(('Game Mode'), 'Unranked')
        }

        $MatchStart = Convert-EpochToDate -epochTime $match.match_time_stamp
        $MatchStart = $MatchStart.AddHours(1)
        $MatchStart = $MatchStart.ToString("MM/dd/yyyy HH:mm")
        $MatchDetails.Add('MatchStart', $MatchStart.ToString())

        $MatchDetails.Add('Map', (Get-MapName -mapId $match.match_map_id))
        $MatchDetails.Add('MatchSeason', $match.match_season)

        $MatchStats = Get-MatchDetails -matchId $match.match_uid

        $PlayerStats = $MatchStats.match_players | Where-Object { $_.nick_name -eq $username }

        if ($PlayerStats.is_win -eq 0) {

            $MatchDetails.Add('Outcome', 'L')
            if ($match.score_info.0 -lt $match.score_info.1) {
                $Score = [string]$match.score_info.0 + " - " + [string]$match.score_info.1
            }
            else {
                $Score = [string]$match.score_info.1 + " - " + [string]$match.score_info.0
            }
        }
        elseif ($PlayerStats.is_win -eq 1) { 
            $MatchDetails.Add('Outcome', 'W')
            if ($match.score_info.0 -gt $match.score_info.1) {
                $Score = [string]$match.score_info.0 + " - " + [string]$match.score_info.1
            }
            else {
                $Score = [string]$match.score_info.1 + " - " + [string]$match.score_info.0
            }
        }
        elseif ($PlayerStats.is_win -eq 2) {
            $MatchDetails.Add('Outcome', 'No Result')
        }

        $MatchDetails.Add('Score', $Score)
        $MatchDetails.Add('Kills', $PlayerStats.kills)
        $MatchDetails.Add('Deaths', $PlayerStats.deaths)
        $MatchDetails.Add('Assists', $PlayerStats.assists)

        
        $TotalDamageTaken = [math]::Round($PlayerStats.total_damage_taken, 0)
        $Healing = [math]::Round($PlayerStats.total_hero_heal, 0)
        $Damage = [math]::Round($PlayerStats.total_hero_damage, 0)
        
        $MatchDetails.Add('DamageTaken', [int32]$TotalDamageTaken)
        $MatchDetails.Add('Healing', [int32]$Healing)
        $MatchDetails.Add('Damage', [int32]$Damage)

        #Get the hero with the most time played
        $MostPlayedHeroId = $PlayerStats.player_heroes | Sort-Object -Property play_time -Descending | Select-Object -First 1 
        $MostPlayedHero = Get-HeroName -heroId $MostPlayedHeroId.hero_id
        $MatchDetails.Add('MostPlayedHero', $MostPlayedHero)

        #Add the parsed match details to the list
        $ParsedMatchDetails.Add($MatchDetails)
    }

    #Sort parsed match details by match start time
    $ParsedMatchDetails = $ParsedMatchDetails | Sort-Object -Property 'Match Start Time' -Descending

    $CuurrentSeason = $Match_history[0].match_season

    ##Create a hashtable to store the account data and parsed match details
    $AccountData = @{
        "Season"        = $CuurrentSeason
        "PlayerName"    = $username
        "PlayerRank"    = $PlayerRank
        "PlayerLevel"   = $PlayerLevel
        "MostUsedHero"  = $MostUsedHero
        #"Total Games"       = $TotalGames
        # "Total Wins"        = $TotalWins
        # "Overall Win Rate"  = $OverallWinRate
        # "Unranked Games"    = $UnrankedGames
        # "Unranked Wins"     = $UnrankedWins
        # "Unranked Win Rate" = $UnrankedWinRate
        "RankedGames"   = $RankedGames
        "RankedWins"    = $RankedWins
        "RankedWinRate" = $RankedWinRate
        "RankedKills"   = $RankedKills
        # "RankedDeaths"  = $RankedDeaths
        # "RankedAssists" = $RankedAssists
        "RankedKDA"     = $CompKDA
        "MatchHistory0" = $ParsedMatchDetails[0]
        "MatchHistory1" = $ParsedMatchDetails[1] 
        "MatchHistory2" = $ParsedMatchDetails[2] 
        "MatchHistory3" = $ParsedMatchDetails[3]
        "MatchHistory4" = $ParsedMatchDetails[4]
    }

    return $AccountData
}

function Get-HeroName {
    param(
        [Parameter(Mandatory = $true)]
        $heroId
    )

    $uri = "https://marvelrivalsapi.com/api/v1/heroes"

    $HeroResponse = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get

    #Filter the hero with the given heroId
    $MostPlayedHero = $HeroResponse | Where-Object { $_.id -eq $heroId }

    $MostPlayedHeroName = (Get-Culture).TextInfo.ToTitleCase($MostPlayedHero.name.ToLower())

    return $MostPlayedHeroName
}

Function Get-MatchHistory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$username
    )

    $uri = "https://marvelrivalsapi.com/api/v1/player/$username/match-history?skip=0&limit=10"

    $MatchHistoryResponse = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get -ContentType "application/json"

    $MatchHistoryResponse.match_history = $MatchHistoryResponse.match_history | Sort-Object -Property match_time_stamp -Descending

    return $MatchHistoryResponse.match_history | Select-Object -First 5
}

Function Get-MapName {
    param(
        [Parameter(Mandatory = $true)]
        [string]$mapId
    )

    $uri = "https://marvelrivalsapi.com/api/v1/maps?limit=50"

    $MapResponse = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get

    $MapResponse = $MapResponse.maps | Where-Object { $_.id -eq $mapId }
    return $MapResponse[0].name
}

Function Get-MatchDetails {
    param(
        [Parameter(Mandatory = $true)]
        [string]$matchId
    )

    $uri = "https://marvelrivalsapi.com/api/v1/match/$matchId"

    $MatchDetailsResponse = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get

    return $MatchDetailsResponse.match_details
}

Function Invoke-TrmnlPostRequest {
    param(
        [Parameter(Mandatory = $true)]
        $Body
    )

    $uri = "https://usetrmnl.com/api/custom_plugins/$TrmnlPluginId"

    #Make sure body1 and body2 are hashtables

    $Body1 = @{}
    $Body2 = @{}


    $Body1.Add('Season', [string]$Body.Season)
    $Body1.Add('PlayerName', [string]$Body.PlayerName)
    $Body1.Add('PlayerRank', [string]$Body.PlayerRank)
    $Body1.Add('PlayerLevel', [string]$Body.PlayerLevel)
    $Body1.Add('MostUsedHero', [string]$Body.MostUsedHero)
    $Body1.Add('RankedGames', [string]$Body.RankedGames)
    $Body1.Add('RankedWins', [string]$Body.RankedWins)
    $Body1.Add('RankedWinRate', [string]$Body.RankedWinRate)
    $Body1.Add('RankedKDA', [string]$Body.RankedKDA)
    $Body1.Add('RankedKills', [string]$Body.RankedKills)

    $Body2.Add('MatchHistory0', [hashtable]$Body.MatchHistory0)
    $Body2.Add('MatchHistory1', [hashtable]$Body.MatchHistory1)
    $Body2.Add('MatchHistory2', [hashtable]$Body.MatchHistory2)
    $Body2.Add('MatchHistory3', [hashtable]$Body.MatchHistory3)
    $Body2.Add('MatchHistory4', [hashtable]$Body.MatchHistory4)

    $TrmnlBody = @{
        "merge_variables" = $Body1
        "deep_merge"      = $true
    }

    $TrmnlBody = $TrmnlBody | ConvertTo-Json -Depth 10

    try {
        Invoke-RestMethod -Uri $uri -Headers $TrmnlHeaders -Method Post -Body $TrmnlBody -contentType "application/json"
    }
    catch {
        Write-Host "Error posting to TRMNL: $_"
        return
    }
    Start-Sleep -Seconds 305

    $TrmnlBody2 = @{
        "merge_variables" = $Body2
        "deep_merge"      = $true
    }
    $TrmnlBody2 = $TrmnlBody2 | ConvertTo-Json -Depth 10

    Invoke-RestMethod -Uri $uri -Headers $TrmnlHeaders -Method Post -Body $TrmnlBody2 -contentType "application/json"
}

$Body = Get-AccountData -username $username -erroraction Stop
Invoke-TrmnlPostRequest -Body $Body
