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

    try {
        $AccountResponse = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get -ContentType "application/json" -ErrorAction Continue
    }
    catch {
        Update-Player-Stats -username $username
        #Retry fetching the account data after updating stats
        #wait for 10 minutes before retrying
        Start-Sleep -Seconds 600
        $AccountResponse = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get -ContentType "application/json" -ErrorAction Stop
    }
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
        #$AccountResponse = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get
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
    if ($MapResponse.Count -eq 0) {
        return "Unknown Map"
    }
    else {
        return $MapResponse[0].name
    }
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

    $Body1 = @{}
    $Body2 = @{}

    $Match0Outcome = $Body.MatchHistory0.Outcome
    $Match1Outcome = $Body.MatchHistory1.Outcome
    $Match2Outcome = $Body.MatchHistory2.Outcome
    $Match3Outcome = $Body.MatchHistory3.Outcome
    $Match4Outcome = $Body.MatchHistory4.Outcome

    $Mach0Score = $Body.MatchHistory0.Score
    $Mach1Score = $Body.MatchHistory1.Score
    $Mach2Score = $Body.MatchHistory2.Score
    $Mach3Score = $Body.MatchHistory3.Score
    $Mach4Score = $Body.MatchHistory4.Score

    $Match0Start = $Body.MatchHistory0.MatchStart
    $Match1Start = $Body.MatchHistory1.MatchStart
    $Match2Start = $Body.MatchHistory2.MatchStart
    $Match3Start = $Body.MatchHistory3.MatchStart
    $Match4Start = $Body.MatchHistory4.MatchStart

    $Match0Map = $Body.MatchHistory0.Map
    $Match1Map = $Body.MatchHistory1.Map
    $Match2Map = $Body.MatchHistory2.Map
    $Match3Map = $Body.MatchHistory3.Map
    $Match4Map = $Body.MatchHistory4.Map

    $Match0MostPlayedHero = $Body.MatchHistory0.MostPlayedHero
    $Match1MostPlayedHero = $Body.MatchHistory1.MostPlayedHero
    $Match2MostPlayedHero = $Body.MatchHistory2.MostPlayedHero
    $Match3MostPlayedHero = $Body.MatchHistory3.MostPlayedHero
    $Match4MostPlayedHero = $Body.MatchHistory4.MostPlayedHero

    $Match0Kills = $Body.MatchHistory0.Kills
    $Match1Kills = $Body.MatchHistory1.Kills
    $Match2Kills = $Body.MatchHistory2.Kills
    $Match3Kills = $Body.MatchHistory3.Kills
    $Match4Kills = $Body.MatchHistory4.Kills

    $Match0Deaths = $Body.MatchHistory0.Deaths
    $Match1Deaths = $Body.MatchHistory1.Deaths
    $Match2Deaths = $Body.MatchHistory2.Deaths
    $Match3Deaths = $Body.MatchHistory3.Deaths
    $Match4Deaths = $Body.MatchHistory4.Deaths

    $Match0Assists = $Body.MatchHistory0.Assists
    $Match1Assists = $Body.MatchHistory1.Assists
    $Match2Assists = $Body.MatchHistory2.Assists
    $Match3Assists = $Body.MatchHistory3.Assists
    $Match4Assists = $Body.MatchHistory4.Assists

    $Match0Damage = $Body.MatchHistory0.Damage
    $Match1Damage = $Body.MatchHistory1.Damage
    $Match2Damage = $Body.MatchHistory2.Damage
    $Match3Damage = $Body.MatchHistory3.Damage
    $Match4Damage = $Body.MatchHistory4.Damage

    $Match0Healing = $Body.MatchHistory0.Healing
    $Match1Healing = $Body.MatchHistory1.Healing
    $Match2Healing = $Body.MatchHistory2.Healing
    $Match3Healing = $Body.MatchHistory3.Healing
    $Match4Healing = $Body.MatchHistory4.Healing

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

    $Body2.Add('MatchHistory0Outcome', [string]$Match0Outcome)
    $Body2.Add('MatchHistory1Outcome', [string]$Match1Outcome)
    $Body2.Add('MatchHistory2Outcome', [string]$Match2Outcome)
    $Body2.Add('MatchHistory3Outcome', [string]$Match3Outcome)
    $Body2.Add('MatchHistory4Outcome', [string]$Match4Outcome)
    $Body2.Add('MatchHistory0Score', [string]$Mach0Score)
    $Body2.Add('MatchHistory1Score', [string]$Mach1Score)
    $Body2.Add('MatchHistory2Score', [string]$Mach2Score)
    $Body2.Add('MatchHistory3Score', [string]$Mach3Score)
    $Body2.Add('MatchHistory4Score', [string]$Mach4Score)
    $Body2.Add('MatchHistory0Start', [string]$Match0Start)
    $Body2.Add('MatchHistory1Start', [string]$Match1Start)
    $Body2.Add('MatchHistory2Start', [string]$Match2Start)
    $Body2.Add('MatchHistory3Start', [string]$Match3Start)
    $Body2.Add('MatchHistory4Start', [string]$Match4Start)
    $Body2.Add('MatchHistory0Map', [string]$Match0Map)
    $Body2.Add('MatchHistory1Map', [string]$Match1Map)
    $Body2.Add('MatchHistory2Map', [string]$Match2Map)
    $Body2.Add('MatchHistory3Map', [string]$Match3Map)
    $Body2.Add('MatchHistory4Map', [string]$Match4Map)
    $Body2.Add('MatchHistory0MostPlayedHero', [string]$Match0MostPlayedHero)
    $Body2.Add('MatchHistory1MostPlayedHero', [string]$Match1MostPlayedHero)
    $Body2.Add('MatchHistory2MostPlayedHero', [string]$Match2MostPlayedHero)
    $Body2.Add('MatchHistory3MostPlayedHero', [string]$Match3MostPlayedHero)
    $Body2.Add('MatchHistory4MostPlayedHero', [string]$Match4MostPlayedHero)
    $Body2.Add('MatchHistory0Kills', [string]$Match0Kills)
    $Body2.Add('MatchHistory1Kills', [string]$Match1Kills)
    $Body2.Add('MatchHistory2Kills', [string]$Match2Kills)
    $Body2.Add('MatchHistory3Kills', [string]$Match3Kills)
    $Body2.Add('MatchHistory4Kills', [string]$Match4Kills)
    $Body2.Add('MatchHistory0Deaths', [string]$Match0Deaths)
    $Body2.Add('MatchHistory1Deaths', [string]$Match1Deaths)
    $Body2.Add('MatchHistory2Deaths', [string]$Match2Deaths)
    $Body2.Add('MatchHistory3Deaths', [string]$Match3Deaths)
    $Body2.Add('MatchHistory4Deaths', [string]$Match4Deaths)
    $Body2.Add('MatchHistory0Assists', [string]$Match0Assists)
    $Body2.Add('MatchHistory1Assists', [string]$Match1Assists)
    $Body2.Add('MatchHistory2Assists', [string]$Match2Assists)
    $Body2.Add('MatchHistory3Assists', [string]$Match3Assists)
    $Body2.Add('MatchHistory4Assists', [string]$Match4Assists)
    $Body2.Add('MatchHistory0Damage', [string]$Match0Damage)
    $Body2.Add('MatchHistory1Damage', [string]$Match1Damage)
    $Body2.Add('MatchHistory2Damage', [string]$Match2Damage)
    $Body2.Add('MatchHistory3Damage', [string]$Match3Damage)
    $Body2.Add('MatchHistory4Damage', [string]$Match4Damage)
    $Body2.Add('MatchHistory0Healing', [string]$Match0Healing)
    $Body2.Add('MatchHistory1Healing', [string]$Match1Healing)
    $Body2.Add('MatchHistory2Healing', [string]$Match2Healing)
    $Body2.Add('MatchHistory3Healing', [string]$Match3Healing)
    $Body2.Add('MatchHistory4Healing', [string]$Match4Healing)

    $TrmnlBody = @{
        "merge_variables" = $Body1
        "deep_merge"      = $true
    }

    $TrmnlBody = $TrmnlBody | ConvertTo-Json -Depth 10

    Invoke-RestMethod -Uri $uri -Headers $TrmnlHeaders -Method Post -Body $TrmnlBody -contentType "application/json"
    
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
