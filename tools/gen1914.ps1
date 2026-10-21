param([switch]$Insert)
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$root = Split-Path $PSScriptRoot -Parent
$dataRoot = Join-Path $root 'data'
$yearsPath = Join-Path $dataRoot 'years.json'
$db = Get-Content -LiteralPath $yearsPath -Raw -Encoding UTF8 | ConvertFrom-Json

function Get-Realms([string]$year) {
    $cfg = $db.$year
    if (-not $cfg) { throw "No data for base year $year." }
    if ($cfg.countries) {
        $result = @()
        foreach ($country in $cfg.countries) {
            $path = Join-Path $root $country.file
            $feature = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
            $props = [ordered]@{}
            $feature.properties.PSObject.Properties | ForEach-Object {
                $props[$_.Name] = $_.Value
            }
            $result += [pscustomobject]@{
                realm = $feature.properties.realm
                provinces = @($feature.provinces)
                props = $props
            }
        }
        return $result
    }

    $base = Get-Realms ([string]$cfg.baseYear)
    $map = [ordered]@{}
    foreach ($realm in $base) { $map[$realm.realm] = $realm }
    foreach ($oldName in $cfg.overrides.PSObject.Properties.Name) {
        if (-not $map.Contains($oldName)) {
            throw "Year $year overrides unknown realm $oldName."
        }
        $realm = $map[$oldName]
        $override = $cfg.overrides.$oldName
        if ($null -ne $override.provinces) {
            $realm.provinces = @($override.provinces)
        }
        if ($override.properties) {
            $override.properties.PSObject.Properties | ForEach-Object {
                $realm.props[$_.Name] = $_.Value
            }
        }
        $newName = $realm.props.realm
        if ($newName -and $newName -ne $oldName) {
            $realm.realm = $newName
            $map.Remove($oldName)
            if ($map.Contains($newName)) { throw "Duplicate realm $newName in $year." }
            $map[$newName] = $realm
        }
    }

    $result = @($map.Values)
    foreach ($addition in $cfg.additions) {
        $props = [ordered]@{}
        $addition.properties.PSObject.Properties | ForEach-Object {
            $props[$_.Name] = $_.Value
        }
        $result += [pscustomobject]@{
            realm = $addition.properties.realm
            provinces = @($addition.provinces)
            props = $props
        }
    }
    return $result
}

function Test-FeatureMatch($realm, $feature) {
    $props = $realm.props
    $id = $feature.id
    $hit = $false
    if (@($realm.provinces) -contains $id) {
        $admins = $props.regionAdmins
        if (-not $admins -or @($admins) -contains $feature.admin) { $hit = $true }
    }
    if (-not $hit -and $props.regionFilters) {
        foreach ($filter in @($props.regionFilters)) {
            if ($filter.admin -and $filter.admin -ne $feature.admin) { continue }
            if ($filter.geonunit -and $filter.geonunit -ne $feature.geonunit) { continue }
            if ($filter.ids -and @($filter.ids) -notcontains $id) { continue }
            if ($filter.excludeIds -and @($filter.excludeIds) -contains $id) { continue }
            $hit = $true
            break
        }
    }
    if ($hit -and $props.excludeIds -and @($props.excludeIds) -contains $id) {
        return $false
    }
    return $hit
}

function Get-1914Owner($feature) {
    switch ($feature.admin) {
        'Albania' { return 'Principality of Albania' }
        'Greece' { return 'Kingdom of Greece' }
        'Kosovo' { return 'Kingdom of Serbia' }
        'Macedonia' { return 'Kingdom of Serbia' }
        'Libya' { return 'Kingdom of Italy (Libya)' }
        'Norway' { return 'Kingdom of Norway' }
        'Sweden' { return 'Kingdom of Sweden' }
        'Bulgaria' {
            if (@('dobrich', 'silistra') -contains $feature.id) {
                return 'Kingdom of Romania'
            }
        }
    }
    return $null
}

function Get-Leader([string]$realm) {
    switch -Regex ($realm) {
        '^Russian Empire' { return 'Nicholas II' }
        '^(German Empire|Prussia)' { return 'Wilhelm II' }
        '^(Austria-Hungary|Austrian Empire|Royal Hungary|Hungarian crown|Kingdom of Bohemia)' { return 'Franz Joseph I' }
        '^(France|French)' { return 'Raymond Poincaré (President)' }
        '^(United Kingdom|British)' { return 'George V' }
        '^Kingdom of Italy' { return 'Victor Emmanuel III' }
        '^(Kingdom of Sweden|Sweden)' { return 'Gustaf V' }
        '^(Kingdom of Norway|Norway)' { return 'Haakon VII' }
        '^(Denmark|Kingdom of Denmark)' { return 'Christian X' }
        '^(Ottoman Empire|Ottoman)' { return 'Mehmed V' }
        '^(Kingdom of Greece|Greece)' { return 'Constantine I' }
        '^(Kingdom of Serbia|Serbia)' { return 'Peter I' }
        '^(Kingdom of Romania|Romania)' { return 'Carol I' }
        '^(Principality of Bulgaria|Kingdom of Bulgaria|Tsardom of Bulgaria|Bulgaria)' { return 'Ferdinand I' }
        '^(Principality of Montenegro|Kingdom of Montenegro|Montenegro)' { return 'Nicholas I' }
        '^(Netherlands|Kingdom of the Netherlands)' { return 'Wilhelmina' }
        '^Belgium' { return 'Albert I' }
        '^(Kingdom of Portugal|Portugal)' { return 'Manuel de Arriaga (President)' }
        '^(Kingdom of Spain|Spain)' { return 'Alfonso XIII' }
        '^(Alaouite Sultanate|Morocco)' { return 'Yusef' }
        '^(Egypt|Khedivate of Egypt)' { return 'Abbas II (Khedive)' }
        '^(Qajar Iran|Iran)' { return 'Ahmad Shah Qajar' }
        '^(Grand Duchy of Finland|Russian Empire \(Finland\))' { return 'Nicholas II (Grand Duke)' }
        default { return 'Local authorities' }
    }
}

$realms = @(Get-Realms '1900')
if ($realms.Count -eq 0) { throw 'The 1900 map contains no resolved realms.' }
$features = @()
foreach ($file in @(
    'europe-provinces.geojson',
    'europe-kosovo.geojson',
    'europe-small-islands.geojson',
    'middle-east-caucasus-provinces.geojson',
    'europe-microstates.geojson',
    'europe-historical-regions.geojson'
)) {
    $geo = Get-Content -LiteralPath (Join-Path $dataRoot $file) -Raw -Encoding UTF8 | ConvertFrom-Json
    $features += $geo.features | ForEach-Object { $_.properties }
}

$overrides = [ordered]@{}
$additions = @()
function Get-Override([string]$name) {
    if (-not $script:overrides.Contains($name)) {
        $script:overrides[$name] = [ordered]@{ properties = [ordered]@{} }
    }
    return $script:overrides[$name]
}

$changedOwners = @{}
$specialSwedenNorway = 'Sweden' + [char]0x2013 + 'Norway'
foreach ($feature in $features) {
    $newOwner = Get-1914Owner $feature
    if (-not $newOwner) { continue }
    $matches = @($realms | Where-Object { Test-FeatureMatch $_ $feature })
    if ($matches.Count -gt 1) {
        throw "1900 overlap for $($feature.admin)/$($feature.id): $($matches.realm -join ', ')."
    }
    if ($matches.Count -eq 0) { continue }
    $oldOwner = $matches[0].realm
    if ($oldOwner -eq $newOwner -or $oldOwner -eq $specialSwedenNorway) { continue }
    if (-not $changedOwners.ContainsKey($oldOwner)) {
        $changedOwners[$oldOwner] = [System.Collections.Generic.List[string]]::new()
    }
    if (-not $changedOwners[$oldOwner].Contains($feature.id)) {
        $changedOwners[$oldOwner].Add($feature.id)
    }
}

foreach ($oldOwner in $changedOwners.Keys) {
    $realm = $realms | Where-Object { $_.realm -eq $oldOwner } | Select-Object -First 1
    $override = Get-Override $oldOwner
    $excluded = @($realm.props.excludeIds) + @($changedOwners[$oldOwner])
    $override.properties.excludeIds = @($excluded | Select-Object -Unique)
}

$leaderInfo = @{
    $specialSwedenNorway = @(
        'Kingdom of Sweden', 'Sweden', '#102548', '#06142b', 'Gustaf V',
        'Sweden was an independent kingdom under Gustaf V after the union with Norway dissolved in 1905.'
    )
    'Kingdom of Serbia' = @(
        'Kingdom of Serbia', 'Serbia', '#8e6aa8', '#4f3a63', 'Peter I',
        'Serbia had gained Kosovo and most of Vardar Macedonia in the Balkan Wars; modern provinces are approximate borders.'
    )
    'Kingdom of Greece' = @(
        'Kingdom of Greece', 'Greece', '#6fa8d8', '#35607f', 'Constantine I',
        'Greece expanded into Epirus, Macedonia, Crete and the Aegean islands after the Balkan Wars of 1912-13.'
    )
    'Kingdom of Romania' = @(
        'Kingdom of Romania', 'Romania', '#cc8f6a', '#7a4a32', 'Carol I',
        'Romania acquired southern Dobruja from Bulgaria in 1913; modern provinces are approximate borders.'
    )
    'Principality of Bulgaria' = @(
        'Tsardom of Bulgaria', 'Bulgaria', '#5f9ea0', '#2f5e60', 'Ferdinand I',
        'Bulgaria had become a tsardom in 1908 and ceded southern Dobruja to Romania after the Second Balkan War.'
    )
    'Principality of Montenegro' = @(
        'Kingdom of Montenegro', 'Montenegro', '#b0607a', '#63303f', 'Nicholas I',
        'Montenegro became a kingdom in 1910 and expanded in the Balkan Wars.'
    )
}

$realmsByName = @{}
foreach ($realm in $realms) { $realmsByName[$realm.realm] = $realm }
foreach ($oldName in $realmsByName.Keys) {
    $realm = $realmsByName[$oldName]
    $newName = $oldName
    $label = [string]$realm.props.label
    if ($leaderInfo.ContainsKey($oldName)) {
        $details = $leaderInfo[$oldName]
        $newName = $details[0]
        $label = $details[1]
        $override = Get-Override $oldName
        $override.properties.realm = $newName
        $override.properties.label = $label
        $override.properties.fillColor = $details[2]
        $override.properties.borderColor = $details[3]
        $leader = $details[4]
        $info = $details[5]
    } else {
        $leader = Get-Leader $newName
        $info = "$newName in 1914. Modern administrative regions are used as approximate map units, not exact historical frontiers."
    }
    $override = Get-Override $oldName
    $override.properties.leader = $leader
    $override.properties.info = $info
}

$swedenOverride = Get-Override $specialSwedenNorway
$swedenOverride.provinces = @()
$swedenOverride.properties.regionFilters = @([ordered]@{ admin = 'Sweden' })

$serbiaOverride = Get-Override 'Kingdom of Serbia'
$serbiaRealm = $realmsByName['Kingdom of Serbia']
$serbiaFilters = New-Object System.Collections.ArrayList
foreach ($filter in @($serbiaRealm.props.regionFilters)) {
    if ($filter) { [void]$serbiaFilters.Add($filter) }
}
[void]$serbiaFilters.Add([ordered]@{ admin = 'Kosovo' })
[void]$serbiaFilters.Add([ordered]@{ admin = 'Macedonia' })
$serbiaOverride.properties.regionFilters = $serbiaFilters
$greeceOverride = Get-Override 'Kingdom of Greece'
$greeceFilters = New-Object System.Collections.ArrayList
[void]$greeceFilters.Add([ordered]@{ admin = 'Greece' })
$greeceOverride.properties.regionFilters = $greeceFilters
$romaniaOverride = Get-Override 'Kingdom of Romania'
$romaniaFilters = New-Object System.Collections.ArrayList
foreach ($filter in @($realmsByName['Kingdom of Romania'].props.regionFilters)) {
    if ($filter) { [void]$romaniaFilters.Add($filter) }
}
[void]$romaniaFilters.Add([ordered]@{
    admin = 'Bulgaria'
    ids = @('dobrich', 'silistra')
})
$romaniaOverride.properties.regionFilters = $romaniaFilters

$additions = @(
    [ordered]@{
        provinces = @()
        properties = [ordered]@{
            realm = 'Kingdom of Norway'
            label = 'Norway'
            leader = 'Haakon VII'
            regionFilters = @([ordered]@{ admin = 'Norway' })
            excludeIds = @('svalbard', 'bouvetisland')
            fillColor = '#3d7891'
            borderColor = '#214654'
            info = 'Norway was an independent kingdom under Haakon VII after the dissolution of its union with Sweden in 1905.'
        }
    },
    [ordered]@{
        provinces = @()
        properties = [ordered]@{
            realm = 'Principality of Albania'
            label = 'Albania'
            leader = 'William of Wied'
            regionFilters = @([ordered]@{ admin = 'Albania' })
            fillColor = '#d49771'
            borderColor = '#82533b'
            info = 'Albania was recognised as an independent principality in 1913; William of Wied arrived in 1914. Modern provinces are approximate borders.'
        }
    },
    [ordered]@{
        provinces = @()
        properties = [ordered]@{
            realm = 'Kingdom of Italy (Libya)'
            label = ''
            leader = 'Victor Emmanuel III'
            regionFilters = @([ordered]@{ admin = 'Libya' })
            fillColor = '#5fa07e'
            borderColor = '#2f5e46'
            info = 'Italy occupied Tripolitania and Cyrenaica in 1911-12; control in the interior remained contested.'
        }
    }
)

$block = [ordered]@{
    baseYear = 1900
    note = 'Europe in 1914 after the Balkan Wars and before the First World War: independent Norway and Albania, enlarged Serbia, Greece and Romania, and Italian Libya. Modern provinces are approximate territorial proxies.'
    overrides = $overrides
    additions = $additions
}
$json = ConvertTo-Json $block -Depth 20
$json = $json -replace '\\u0027', "'"
$fragmentPath = Join-Path $PSScriptRoot 'frag1914.json'
[IO.File]::WriteAllText($fragmentPath, $json, (New-Object Text.UTF8Encoding($false)))
Write-Host "1914 fragment generated: $($overrides.Count) overrides, $($additions.Count) additions."

if ($Insert) {
    $text = [IO.File]::ReadAllText($yearsPath, [Text.Encoding]::UTF8)
    $lastBrace = $text.LastIndexOf('}')
    if ($lastBrace -lt 0) { throw 'Could not find the end of years.json.' }
    $yearMarker = $text.LastIndexOf('"1914"')
    if ($yearMarker -ge 0) {
        $comma = $text.LastIndexOf(',', $yearMarker)
        if ($comma -lt 0) { throw 'Could not locate the existing 1914 year entry.' }
        $updated = $text.Substring(0, $comma) + ",`r`n  `"1914`": $json`r`n}"
    } else {
        $insertText = ",`r`n  `"1914`": $json`r`n"
        $updated = $text.Substring(0, $lastBrace).TrimEnd() + $insertText + '}'
    }
    [IO.File]::WriteAllText($yearsPath, $updated, (New-Object Text.UTF8Encoding($false)))
    Write-Host 'Inserted year 1914 after the final year.'
}
