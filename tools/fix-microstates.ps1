$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$dataRoot = Join-Path $root 'data'
$yearsPath = Join-Path $dataRoot 'years.json'
$db = Get-Content -LiteralPath $yearsPath -Raw -Encoding UTF8 | ConvertFrom-Json

function Write-JsonFile([string]$path, $value) {
    $json = ConvertTo-Json -InputObject $value -Depth 100 -Compress
    $builder = New-Object Text.StringBuilder
    $depth = 0
    $inString = $false
    $escaped = $false
    for ($i = 0; $i -lt $json.Length; $i++) {
        $character = $json[$i]
        if ($inString) {
            [void]$builder.Append($character)
            if ($escaped) { $escaped = $false }
            elseif ($character -eq [char]92) { $escaped = $true }
            elseif ($character -eq [char]34) { $inString = $false }
            continue
        }
        if ($character -eq [char]34) {
            $inString = $true
            [void]$builder.Append($character)
        }
        elseif ($character -eq '{' -or $character -eq '[') {
            [void]$builder.Append($character)
            $closingCharacter = if ($character -eq '{') { '}' } else { ']' }
            if ($i + 1 -ge $json.Length -or $json[$i + 1] -ne $closingCharacter) {
                $depth++
                [void]$builder.Append("`r`n" + ('  ' * $depth))
            }
        }
        elseif ($character -eq '}' -or $character -eq ']') {
            $openingCharacter = if ($character -eq '}') { '{' } else { '[' }
            if ($i -eq 0 -or $json[$i - 1] -ne $openingCharacter) {
                $depth--
                [void]$builder.Append("`r`n" + ('  ' * $depth))
            }
            [void]$builder.Append($character)
        }
        elseif ($character -eq ',') {
            [void]$builder.Append(",`r`n" + ('  ' * $depth))
        }
        elseif ($character -eq ':') {
            [void]$builder.Append(': ')
        }
        elseif (-not [char]::IsWhiteSpace($character)) {
            [void]$builder.Append($character)
        }
    }
    [IO.File]::WriteAllText($path, $builder.ToString() + "`r`n", (New-Object Text.UTF8Encoding($false)))
}

function Add-BaseRegionFilter([string]$realmName, [string[]]$ids) {
    foreach ($country in $db.'1000'.countries) {
        $path = Join-Path $root $country.file
        $feature = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($feature.properties.realm -ne $realmName) { continue }
        $filters = @($feature.properties.regionFilters | Where-Object { $_ })
        $existing = @($filters | Where-Object {
            $_.admin -eq 'Supplemental Microstates' -and -not $_.geonunit -and -not $_.excludeIds
        }) | Select-Object -First 1
        if ($existing) {
            $existing.ids = @(@($existing.ids) + $ids | Sort-Object -Unique)
        }
        else {
            $filters += [pscustomobject]@{
                admin = 'Supplemental Microstates'
                ids = @($ids | Sort-Object -Unique)
            }
        }
        $feature.properties | Add-Member -NotePropertyName regionFilters -NotePropertyValue $filters -Force
        Write-JsonFile $path $feature
        return
    }
    throw "Base realm not found: $realmName"
}

function Get-ResolvedRealms([string]$year) {
    $config = $db.$year
    if ($config.countries) {
        $result = @()
        foreach ($country in $config.countries) {
            $path = Join-Path $root $country.file
            $feature = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
            $props = [ordered]@{}
            foreach ($property in $feature.properties.PSObject.Properties) {
                $props[$property.Name] = $property.Value
            }
            $result += [pscustomobject]@{
                realm = $feature.properties.realm
                props = $props
            }
        }
        return $result
    }

    $map = [ordered]@{}
    foreach ($realm in (Get-ResolvedRealms ([string]$config.baseYear))) {
        $map[$realm.realm] = $realm
    }
    foreach ($overrideProperty in $config.overrides.PSObject.Properties) {
        if (-not $map.Contains($overrideProperty.Name)) { continue }
        $realm = $map[$overrideProperty.Name]
        $override = $overrideProperty.Value
        if ($override.properties) {
            foreach ($property in $override.properties.PSObject.Properties) {
                $realm.props[$property.Name] = $property.Value
            }
        }
        $newName = $realm.props['realm']
        if ($newName -and $newName -ne $overrideProperty.Name) {
            $realm.realm = $newName
            $map.Remove($overrideProperty.Name)
            $map[$newName] = $realm
        }
    }
    $result = @($map.Values)
    foreach ($addition in $config.additions) {
        $props = [ordered]@{}
        foreach ($property in $addition.properties.PSObject.Properties) {
            $props[$property.Name] = $property.Value
        }
        $result += [pscustomobject]@{
            realm = $addition.properties.realm
            props = $props
        }
    }
    return $result
}

function Ensure-YearOverride([string]$year, [string]$realmName) {
    $config = $db.$year
    if (-not $config.overrides) {
        $config | Add-Member -NotePropertyName overrides -NotePropertyValue ([pscustomobject]@{})
    }
    $renameOverride = @($config.overrides.PSObject.Properties | Where-Object {
        $_.Value.properties -and $_.Value.properties.realm -eq $realmName
    }) | Select-Object -First 1
    $overrideKey = if ($renameOverride) { $renameOverride.Name } else { $realmName }
    $override = $config.overrides.PSObject.Properties[$overrideKey]
    if (-not $override) {
        $config.overrides | Add-Member -NotePropertyName $overrideKey -NotePropertyValue ([pscustomobject]@{})
        $override = $config.overrides.PSObject.Properties[$overrideKey]
    }
    if (-not $override.Value.properties) {
        $override.Value | Add-Member -NotePropertyName properties -NotePropertyValue ([pscustomobject]@{})
    }
    return $override.Value.properties
}

function Add-YearRegionFilter([string]$year, [string]$realmName, [string[]]$ids) {
    $config = $db.$year
    $realm = Get-ResolvedRealms $year | Where-Object { $_.realm -eq $realmName } | Select-Object -First 1
    if (-not $realm) { throw "Year $year has no realm named $realmName." }
    $filters = @($realm.props['regionFilters'] | Where-Object { $_ })
    $wanted = @($ids | Sort-Object -Unique)
    $existing = @($filters | Where-Object {
        $_.admin -eq 'Supplemental Microstates' -and -not $_.geonunit -and
        -not (@($_.excludeIds) | Where-Object { $_ -in $wanted })
    }) | Select-Object -First 1
    if ($existing) {
        $existing.ids = @(@($existing.ids) + $wanted | Sort-Object -Unique)
    }
    else {
        $filters += [pscustomobject]@{
            admin = 'Supplemental Microstates'
            ids = $wanted
        }
    }
    $addition = @($config.additions | Where-Object { $_.properties.realm -eq $realmName }) | Select-Object -First 1
    if ($addition) {
        $addition.properties | Add-Member -NotePropertyName regionFilters -NotePropertyValue $filters -Force
        return
    }
    $properties = Ensure-YearOverride $year $realmName
    $properties | Add-Member -NotePropertyName regionFilters -NotePropertyValue $filters -Force
}

function Remove-YearOverride([string]$year, [string]$realmName) {
    $config = $db.$year
    if ($config.overrides -and $config.overrides.PSObject.Properties[$realmName]) {
        $config.overrides.PSObject.Properties.Remove($realmName)
    }
}

function Add-YearExclusions([string]$year, [string]$realmName, [string[]]$ids) {
    $realm = Get-ResolvedRealms $year | Where-Object { $_.realm -eq $realmName } | Select-Object -First 1
    if (-not $realm) { throw "Year $year has no realm named $realmName." }
    $exclusions = @(@($realm.props['excludeIds'] | Where-Object { $_ }) + $ids | Sort-Object -Unique)
    $properties = Ensure-YearOverride $year $realmName
    $properties | Add-Member -NotePropertyName excludeIds -NotePropertyValue $exclusions -Force
}

function Remove-YearRegionFilterIds([string]$year, [string]$realmName, [string[]]$ids) {
    $realm = Get-ResolvedRealms $year | Where-Object { $_.realm -eq $realmName } | Select-Object -First 1
    if (-not $realm) { throw "Year $year has no realm named $realmName." }
    $filters = @($realm.props['regionFilters'] | Where-Object { $_ })
    foreach ($filter in $filters) {
        if ($filter.admin -eq 'Supplemental Microstates') {
            $filter.ids = @($filter.ids | Where-Object { $_ -notin $ids })
        }
    }
    $properties = Ensure-YearOverride $year $realmName
    $properties | Add-Member -NotePropertyName regionFilters -NotePropertyValue $filters -Force
}

function Set-YearRealmProperties([string]$year, [string]$realmName, [string]$leader, [string]$info, [string]$id) {
    $properties = Ensure-YearOverride $year $realmName
    $properties | Add-Member -NotePropertyName label -NotePropertyValue $realmName -Force
    $properties | Add-Member -NotePropertyName leader -NotePropertyValue $leader -Force
    $properties | Add-Member -NotePropertyName info -NotePropertyValue $info -Force
    $properties | Add-Member -NotePropertyName fillColor -NotePropertyValue '#d9894a' -Force
    $properties | Add-Member -NotePropertyName borderColor -NotePropertyValue '#75451f' -Force
    $properties | Add-Member -NotePropertyName regionFilters -NotePropertyValue @(
        [pscustomobject]@{
            admin = 'Supplemental Microstates'
            ids = @($id)
        }
    ) -Force
    $properties | Add-Member -NotePropertyName excludeIds -NotePropertyValue @() -Force
}

function Upsert-State([string]$year, [string]$state, [string]$leader, [string]$info, [string]$id) {
    $config = $db.$year
    $inherited = @()
    if ($config.baseYear) {
        $inherited = @(Get-ResolvedRealms ([string]$config.baseYear) | Where-Object { $_.realm -eq $state })
    }
    if ($inherited.Count -gt 0) {
        if ($config.PSObject.Properties['additions']) {
            $config.additions = @($config.additions | Where-Object { $_.properties.realm -ne $state })
        }
        Set-YearRealmProperties $year $state $leader $info $id
        return
    }

    $currentAddition = @($config.additions | Where-Object { $_.properties.realm -eq $state }) | Select-Object -First 1
    if ($currentAddition) {
        $properties = $currentAddition.properties
        $properties | Add-Member -NotePropertyName realm -NotePropertyValue $state -Force
        $properties | Add-Member -NotePropertyName label -NotePropertyValue $state -Force
        $properties | Add-Member -NotePropertyName leader -NotePropertyValue $leader -Force
        $properties | Add-Member -NotePropertyName info -NotePropertyValue $info -Force
        $properties | Add-Member -NotePropertyName fillColor -NotePropertyValue '#d9894a' -Force
        $properties | Add-Member -NotePropertyName borderColor -NotePropertyValue '#75451f' -Force
        $properties | Add-Member -NotePropertyName regionFilters -NotePropertyValue @(
            [pscustomobject]@{ admin = 'Supplemental Microstates'; ids = @($id) }
        ) -Force
        $properties | Add-Member -NotePropertyName excludeIds -NotePropertyValue @() -Force
        return
    }

    $addition = [pscustomobject]@{
        provinces = @()
        properties = [pscustomobject]@{
            realm = $state
            label = $state
            leader = $leader
            info = $info
            fillColor = '#d9894a'
            borderColor = '#75451f'
            regionFilters = @(
                [pscustomobject]@{ admin = 'Supplemental Microstates'; ids = @($id) }
            )
            excludeIds = @()
        }
    }
    if ($config.PSObject.Properties['additions']) {
        $config.additions = @($config.additions) + @($addition)
    }
    else {
        $config | Add-Member -NotePropertyName additions -NotePropertyValue @($addition)
    }
}

function Deactivate-Monaco([string]$year) {
    $properties = Ensure-YearOverride $year 'Monaco'
    $properties | Add-Member -NotePropertyName label -NotePropertyValue '' -Force
    $properties | Add-Member -NotePropertyName leader -NotePropertyValue 'Under French rule' -Force
    $properties | Add-Member -NotePropertyName info -NotePropertyValue 'Monaco was annexed by France from 1793 to 1814; the mapped territory is shown under France.' -Force
    $properties | Add-Member -NotePropertyName regionFilters -NotePropertyValue @() -Force
    $properties | Add-Member -NotePropertyName excludeIds -NotePropertyValue @() -Force
}

function Remove-HistoricalMicrostates([string]$year) {
    $config = $db.$year
    if ($config.overrides -and $config.overrides.PSObject.Properties['Historical Microstates']) {
        $config.overrides.PSObject.Properties.Remove('Historical Microstates')
    }
    if ($config.PSObject.Properties['additions']) {
        $config.additions = @($config.additions | Where-Object { $_.properties.realm -ne 'Historical Microstates' })
    }
}

$db.'1000'.countries = @($db.'1000'.countries | Where-Object { $_.file -ne 'data/microstates/1000.geojson' })
Add-BaseRegionFilter 'Duchy of Swabia' @('liechtenstein')
Add-BaseRegionFilter 'Holy Roman Empire' @('monaco')
Add-BaseRegionFilter 'County of Barcelona' @('andorra')
Add-BaseRegionFilter 'Papal States' @('san-marino')

$years = @('867', '900', '962', '1000', '1066', '1100', '1200', '1300', '1400', '1500', '1600', '1700', '1800', '1815', '1871', '1900', '1914', '1918', '1939', '1945', '1955', '1990', '2000')
foreach ($year in $years) { Remove-HistoricalMicrostates $year }

foreach ($year in @('867', '900', '962')) {
    Add-YearRegionFilter $year 'Duchy of Swabia' @('liechtenstein')
    Add-YearRegionFilter $year 'Kingdom of Italy' @('monaco')
    Add-YearRegionFilter $year 'County of Barcelona' @('andorra')
    Add-YearRegionFilter $year 'Papal States' @('san-marino')
}
Remove-YearOverride '900' 'Kingdom of Italy'
Add-YearExclusions '962' 'Holy Roman Empire' @('liechtenstein', 'monaco')

foreach ($year in @('1066', '1100')) {
    Add-YearRegionFilter $year 'County of Barcelona' @('andorra')
    Add-YearRegionFilter $year 'Papal States' @('san-marino')
    Add-YearRegionFilter $year 'Duchy of Swabia' @('liechtenstein')
    Add-YearRegionFilter $year 'Holy Roman Empire' @('monaco')
    Remove-YearRegionFilterIds $year 'Holy Roman Empire' @('liechtenstein')
}
Add-YearRegionFilter '1200' 'Crown of Aragon' @('andorra')
Add-YearRegionFilter '1200' 'Papal States' @('san-marino')
Add-YearRegionFilter '1200' 'Duchy of Swabia' @('liechtenstein')
Add-YearRegionFilter '1200' 'Holy Roman Empire' @('monaco')
Remove-YearRegionFilterIds '1200' 'Holy Roman Empire' @('liechtenstein')

foreach ($year in @('1300', '1400', '1500', '1600', '1700', '1800', '1815')) {
    Add-YearExclusions $year 'Papal States' @('san-marino')
}

foreach ($entry in @(
    @{ year = '1300'; realm = 'Crown of Aragon' },
    @{ year = '1400'; realm = 'Crown of Aragon' },
    @{ year = '1500'; realm = 'Crown of Aragon' },
    @{ year = '1600'; realm = 'Spanish Monarchy (Aragon)' },
    @{ year = '1700'; realm = 'Spanish Monarchy (Aragon)' },
    @{ year = '1800'; realm = 'Spanish Monarchy (Aragon)' },
    @{ year = '1815'; realm = 'Spanish Monarchy (Aragon)' },
    @{ year = '1871'; realm = 'Spanish Monarchy (Aragon)' },
    @{ year = '1900'; realm = 'Spanish Monarchy (Aragon)' },
    @{ year = '1914'; realm = 'Spanish Monarchy (Aragon)' },
    @{ year = '1918'; realm = 'Spanish Monarchy (Aragon)' },
    @{ year = '1939'; realm = 'Spanish Monarchy (Aragon)' },
    @{ year = '1945'; realm = 'Spanish Monarchy (Aragon)' },
    @{ year = '1955'; realm = 'Spanish Monarchy (Aragon)' },
    @{ year = '1990'; realm = 'Spanish Monarchy (Aragon)' },
    @{ year = '2000'; realm = 'Spanish Monarchy (Aragon)' }
)) {
    Add-YearExclusions $entry.year $entry.realm @('andorra')
}

foreach ($year in @('1300', '1400')) {
    Add-YearRegionFilter $year 'Holy Roman Empire' @('liechtenstein', 'monaco')
}
foreach ($year in @('1500', '1600', '1700', '1800')) {
    Add-YearExclusions $year 'Holy Roman Empire' @('monaco')
    Add-YearRegionFilter $year 'Holy Roman Empire' @('liechtenstein')
}
foreach ($year in @('1300', '1400', '1500', '1600', '1700', '1800')) {
    Add-YearExclusions $year 'Duchy of Swabia' @('liechtenstein')
}
Add-YearRegionFilter '1800' 'French Republic' @('monaco')
Deactivate-Monaco '1800'

foreach ($year in @('1815', '1871', '1900', '1914', '1918', '1939', '1945', '1955', '1990', '2000')) {
    Add-YearExclusions $year 'Holy Roman Empire' @('liechtenstein', 'monaco')
}
foreach ($year in @('1871', '1900', '1914', '1918', '1939', '1945', '1955', '1990', '2000')) {
    Add-YearExclusions $year 'Switzerland' @('liechtenstein')
    Add-YearExclusions $year 'France' @('monaco')
}

Remove-YearOverride '1200' 'Crown of Aragon'
Remove-YearOverride '962' 'Holy Roman Empire'
Remove-YearOverride '1600' 'Spanish Monarchy (Aragon)'
Remove-YearOverride '1800' 'French Republic'
Remove-YearOverride '1900' 'France'
Remove-YearOverride '1900' 'Switzerland'

foreach ($year in @('1300', '1400', '1500', '1600', '1700', '1800', '1815', '1900', '1871', '1914', '1918', '1939', '1945', '1955', '1990', '2000')) {
    $andorraLeader = 'Bishop of Urgell and Count of Foix (co-princes)'
    if ([int]$year -ge 1600) { $andorraLeader = 'Bishop of Urgell and French head of state (co-princes)' }
    if ($year -eq '2000') { $andorraLeader = 'Marc Forné Molné (Head of Government); Joan Martí i Alanis and Jacques Chirac (co-princes)' }
    Upsert-State $year 'Andorra' $andorraLeader "Andorra in $year. The co-principality was governed jointly by the Bishop of Urgell and the Count of Foix; the French head of state later inherited the French co-prince's role." 'andorra'
    $sanMarinoLeader = 'Captains Regent'
    if ($year -eq '2000') { $sanMarinoLeader = 'Gianfranco Terenzi and Enzo Colombini (Captains Regent)' }
    Upsert-State $year 'San Marino' $sanMarinoLeader "The Republic of San Marino in $year, governed by its elected Captains Regent." 'san-marino'
}

foreach ($year in @('1500', '1600', '1700', '1815', '1900', '1871', '1914', '1918', '1939', '1945', '1955', '1990', '2000')) {
    $leader = switch ($year) {
        '1500' { 'Jean II Grimaldi (Lord of Monaco)' }
        '1600' { 'Hercule Grimaldi (Lord of Monaco)' }
        '1700' { 'Louis I (Prince of Monaco)' }
        '1815' { 'Honore IV (Prince of Monaco)' }
        '1871' { 'Charles III (Prince of Monaco)' }
        '1900' { 'Albert I (Prince of Monaco)' }
        '1914' { 'Albert I (Prince of Monaco)' }
        '1918' { 'Albert I (Prince of Monaco)' }
        '1939' { 'Louis II (Prince of Monaco)' }
        '1945' { 'Louis II (Prince of Monaco)' }
        '1955' { 'Rainier III (Prince of Monaco)' }
        '1990' { 'Rainier III (Prince of Monaco)' }
        '2000' { 'Rainier III (Prince of Monaco)' }
    }
    Upsert-State $year 'Monaco' $leader "Monaco in $year. The mapped territory uses its modern boundary as an approximate map unit." 'monaco'
}

foreach ($year in @('1815', '1900', '1871', '1914', '1918', '1939', '1945', '1955', '1990', '2000')) {
    $leader = switch ($year) {
        '1815' { 'Johann I (Prince of Liechtenstein)' }
        '1871' { 'Johann II (Prince of Liechtenstein)' }
        '1900' { 'Johann II (Prince of Liechtenstein)' }
        '1914' { 'Johann II (Prince of Liechtenstein)' }
        '1918' { 'Johann II (Prince of Liechtenstein)' }
        '1939' { 'Franz Josef II (Prince of Liechtenstein)' }
        '1945' { 'Franz Josef II (Prince of Liechtenstein)' }
        '1955' { 'Franz Josef II (Prince of Liechtenstein)' }
        '1990' { 'Hans-Adam II (Prince of Liechtenstein)' }
        '2000' { 'Hans-Adam II (Prince of Liechtenstein)' }
    }
    Upsert-State $year 'Liechtenstein' $leader "The Principality of Liechtenstein in $year. Its modern boundary is shown as an approximate map unit." 'liechtenstein'
}

Write-JsonFile $yearsPath $db
