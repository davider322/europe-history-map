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
    $hit = $false
    if (@($realm.provinces) -contains $feature.id) {
        $admins = $props.regionAdmins
        if (-not $admins -or @($admins) -contains $feature.admin) { $hit = $true }
    }
    if (-not $hit -and $props.regionFilters) {
        foreach ($filter in @($props.regionFilters)) {
            if ($filter.admin -and $filter.admin -ne $feature.admin) { continue }
            if ($filter.geonunit -and $filter.geonunit -ne $feature.geonunit) { continue }
            if ($filter.ids -and @($filter.ids) -notcontains $feature.id) { continue }
            if ($filter.excludeIds -and @($filter.excludeIds) -contains $feature.id) { continue }
            $hit = $true
            break
        }
    }
    if ($hit -and $props.excludeIds -and @($props.excludeIds) -contains $feature.id) {
        return $false
    }
    return $hit
}

function Get-Leader([string]$realm) {
    switch -Regex ($realm) {
        '^(German Reich|Protectorate of Bohemia)' { return 'Adolf Hitler' }
        '^(Soviet Union|Russian SFSR)' { return 'Joseph Stalin' }
        '^(France|French)' { return 'Albert Lebrun (President)' }
        '^(United Kingdom|British)' { return 'George VI' }
        '^(Spanish State|Kingdom of Spain|Spain)' { return 'Francisco Franco' }
        '^(Kingdom of Italy|Italian Albania)' { return 'Victor Emmanuel III' }
        '^(Kingdom of Romania|Romania)' { return 'Carol II' }
        '^(Kingdom of Hungary|Hungarian)' { return 'Miklós Horthy (Regent)' }
        '^(Slovak Republic|Slovakia)' { return 'Jozef Tiso' }
        '^(Republic of Poland|Poland)' { return 'Ignacy Moscicki (President)' }
        '^(Kingdom of Serbs, Croats and Slovenes|Yugoslavia)' { return 'Peter II' }
        '^(Finland|Republic of Finland)' { return 'Kyosti Kallio (President)' }
        '^(Republic of Estonia|Estonia)' { return 'Konstantin Pats' }
        '^(Republic of Latvia|Latvia)' { return 'Karlis Ulmanis' }
        '^(Republic of Lithuania|Lithuania)' { return 'Antanas Smetona' }
        '^(Kingdom of Iraq|Iraq)' { return 'Ghazi I' }
        '^(Kingdom of Saudi Arabia|Saudi Arabia)' { return 'Abdulaziz Ibn Saud' }
        '^(Republic of Turkey|Turkey)' { return 'Ismet Inonu' }
        '^(Kingdom of Egypt|Egypt)' { return 'Farouk I' }
        '^(Kingdom of Greece|Greece)' { return 'George II' }
        '^(Kingdom of Bulgaria|Tsardom of Bulgaria|Bulgaria)' { return 'Boris III' }
        '^(Kingdom of Portugal|Portugal)' { return 'Antonio Oscar Carmona' }
        '^(Kingdom of the Netherlands|Netherlands)' { return 'Wilhelmina' }
        '^Belgium' { return 'Leopold III' }
        default { return 'Local authorities' }
    }
}

$realms = @(Get-Realms '1918')
if ($realms.Count -eq 0) { throw 'The 1918 map contains no resolved realms.' }
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

$sudetenIds = @(
    (([string][char]0x00FA) + 'st' + [char]0x00ED + 'nadlabem'),
    'liberec',
    'karlovyvary'
)
$transferredSlovakIds = @('nitra', ('ko' + [char]0x0161 + 'ice'))
$memelId = 'klaip' + [char]0x0117 + 'da'

$states = @(
    [ordered]@{
        realm = 'German Reich (Anschluss)'; label = ''
        admins = @('Austria'); color = '#8b8f9e'; border = '#4c4f5c'
        leader = 'Adolf Hitler'
        info = 'Austria was annexed by Nazi Germany in the Anschluss of March 1938.'
    },
    [ordered]@{
        realm = 'German Reich (Sudetenland)'; label = ''
        admins = @('Czech Republic'); ids = $sudetenIds
        color = '#8b8f9e'; border = '#4c4f5c'; leader = 'Adolf Hitler'
        info = 'Germany annexed the Sudetenland under the Munich Agreement of 1938; modern regions are used as broad proxies.'
    },
    [ordered]@{
        realm = 'German Reich (Memel)'; label = ''
        admins = @('Lithuania'); ids = @($memelId)
        color = '#8b8f9e'; border = '#4c4f5c'; leader = 'Adolf Hitler'
        info = 'Germany annexed the Memel Territory from Lithuania in March 1939.'
    },
    [ordered]@{
        realm = 'German Reich (Protectorate of Bohemia and Moravia)'; label = ''
        admins = @('Czech Republic'); excludeIds = $sudetenIds
        color = '#8b8f9e'; border = '#4c4f5c'; leader = 'Adolf Hitler'
        info = 'Germany established the Protectorate of Bohemia and Moravia in March 1939; modern administrative regions are approximate.'
    },
    [ordered]@{
        realm = 'Slovak Republic'; label = 'Slovakia'; admins = @('Slovakia')
        excludeIds = $transferredSlovakIds
        color = '#4a8c8a'; border = '#2e5e5c'; leader = 'Jozef Tiso'
        info = 'The Slovak Republic declared independence in March 1939 and was closely aligned with Germany.'
    },
    [ordered]@{
        realm = 'Kingdom of Hungary (Territorial Gains)'; label = ''
        admins = @('Ukraine', 'Slovakia')
        ids = @('zakarpattia') + $transferredSlovakIds
        color = '#8c5b68'; border = '#5a3540'; leader = 'Miklos Horthy (Regent)'
        info = 'Hungary annexed Carpathian Ruthenia and gained southern Slovak territory in 1938-39; modern regions are broad proxies.'
    },
    [ordered]@{
        realm = 'Kingdom of Italy (Albania)'; label = ''
        admins = @('Albania'); color = '#5fa07e'; border = '#2f5e46'
        leader = 'Victor Emmanuel III'
        info = 'Italy invaded and annexed Albania in April 1939; the Albanian crown was held by Victor Emmanuel III.'
    },
    [ordered]@{
        realm = 'Kingdom of Iraq'; label = 'Iraq'; admins = @('Iraq')
        color = '#a28b70'; border = '#695945'; leader = 'Ghazi I'
        info = 'Iraq was an independent kingdom under King Ghazi in 1939.'
    },
    [ordered]@{
        realm = 'French Mandate (Syria and Lebanon)'; label = ''
        admins = @('Syria', 'Lebanon'); color = '#4169a1'; border = '#203b61'
        leader = 'Albert Lebrun (President)'
        info = 'Syria and Lebanon remained under the French Mandate in 1939.'
    },
    [ordered]@{
        realm = 'United Kingdom (Mandate of Palestine)'; label = ''
        admins = @('Israel', 'Palestine'); color = '#c0504d'; border = '#6e2927'
        leader = 'George VI'
        info = 'The British Mandate for Palestine was in force in 1939.'
    },
    [ordered]@{
        realm = 'United Kingdom (Transjordan)'; label = ''
        admins = @('Jordan'); color = '#c0504d'; border = '#6e2927'
        leader = 'George VI'
        info = 'Transjordan was a self-governing emirate under British mandate in 1939.'
    },
    [ordered]@{
        realm = 'Kingdom of Saudi Arabia'; label = 'Saudi Arabia'
        admins = @('Saudi Arabia'); color = '#557b55'; border = '#314b36'
        leader = 'Abdulaziz Ibn Saud'
        info = 'The Kingdom of Saudi Arabia had been unified under Abdulaziz Ibn Saud in 1932.'
    },
    [ordered]@{
        realm = 'Republic of Turkey (Kars, Ardahan and Artvin)'; label = ''
        admins = @('Turkey'); ids = @('kars', 'ardahan', 'artvin')
        color = '#8a9c83'; border = '#465343'; leader = 'Ismet Inonu'
        info = 'Turkey recovered Kars, Ardahan and Artvin from Soviet control under the 1921 Treaty of Kars.'
    }
)

$overrides = [ordered]@{}
$additions = New-Object System.Collections.ArrayList
function Get-Override([string]$name) {
    if (-not $script:overrides.Contains($name)) {
        $script:overrides[$name] = [ordered]@{ properties = [ordered]@{} }
    }
    return $script:overrides[$name]
}

$changedOwners = @{}
$stateTransferIds = New-Object System.Collections.Generic.List[string]
foreach ($state in $states) {
    $hasSpecificIds = $state.Contains('ids')
    $stateIds = @()
    if ($hasSpecificIds) { $stateIds = @($state.ids) }
    foreach ($feature in $features) {
        $matchesState = $state.admins -contains $feature.admin
        if ($hasSpecificIds -and $stateIds -notcontains $feature.id) { $matchesState = $false }
        if (-not $matchesState) { continue }
        if (-not $stateTransferIds.Contains($feature.id)) {
            $stateTransferIds.Add($feature.id)
        }

        $owners = @($realms | Where-Object { Test-FeatureMatch $_ $feature })
        if ($owners.Count -gt 1) {
            throw "1918 overlap for $($feature.admin)/$($feature.id): $($owners.realm -join ', ')."
        }
        if ($owners.Count -eq 0) { continue }
        $oldOwner = $owners[0].realm
        if (-not $changedOwners.ContainsKey($oldOwner)) {
            $changedOwners[$oldOwner] = [System.Collections.Generic.List[string]]::new()
        }
        if (-not $changedOwners[$oldOwner].Contains($feature.id)) {
            $changedOwners[$oldOwner].Add($feature.id)
        }
    }

    $filters = New-Object System.Collections.ArrayList
    foreach ($admin in $state.admins) {
        $filter = [ordered]@{ admin = $admin }
        if ($hasSpecificIds) { $filter.ids = $stateIds }
        if ($state.excludeIds) { $filter.excludeIds = @($state.excludeIds) }
        [void]$filters.Add($filter)
    }
    [void]$additions.Add([ordered]@{
        provinces = @()
        properties = [ordered]@{
            realm = $state.realm
            label = $state.label
            leader = $state.leader
            regionFilters = $filters
            fillColor = $state.color
            borderColor = $state.border
            info = $state.info
        }
    })
}

$sovietDonorPattern = '^(Russian SFSR|Ukrainian People|Democratic Republic of Georgia|First Republic of Armenia|Azerbaijan Democratic Republic)'
$sovietIds = New-Object System.Collections.Generic.List[string]
foreach ($feature in $features) {
    $owners = @($realms | Where-Object { Test-FeatureMatch $_ $feature })
    if ($owners.Count -gt 1) { throw "1918 overlap for $($feature.id): $($owners.realm -join ', ')."}
    if ($owners.Count -eq 1 -and $owners[0].realm -match $sovietDonorPattern -and
        -not $stateTransferIds.Contains($feature.id)) {
        if (-not $sovietIds.Contains($feature.id)) { $sovietIds.Add($feature.id) }
        $oldOwner = $owners[0].realm
        if (-not $changedOwners.ContainsKey($oldOwner)) {
            $changedOwners[$oldOwner] = [System.Collections.Generic.List[string]]::new()
        }
        if (-not $changedOwners[$oldOwner].Contains($feature.id)) {
            $changedOwners[$oldOwner].Add($feature.id)
        }
    }
}
if ($sovietIds.Count -eq 0) { throw 'Could not resolve any 1918 Soviet successor territories.' }
$sovietSource = $realms | Where-Object { $_.realm -eq 'Russian SFSR' } | Select-Object -First 1
if (-not $sovietSource) { throw 'Could not find the base Russian SFSR realm for the Soviet Union.' }
$sovietOverride = Get-Override 'Russian SFSR'
$sovietOverride.provinces = @($sovietIds)
$sovietOverride.properties.realm = 'Soviet Union'
$sovietOverride.properties.label = 'Soviet Union'
$sovietOverride.properties.regionFilters = @()
$sovietOverride.properties.excludeIds = @()
$sovietOverride.properties.leader = 'Joseph Stalin'
$sovietOverride.properties.info = 'The Soviet Union under Joseph Stalin in 1939. The Baltic states remained independent and Poland had not yet been invaded.'
$sovietOverride.properties.fillColor = '#5a0b16'
$sovietOverride.properties.borderColor = '#2e050a'

foreach ($oldOwner in $changedOwners.Keys) {
    $realm = $realms | Where-Object { $_.realm -eq $oldOwner } | Select-Object -First 1
    if (-not $realm) { throw "No 1918 realm found for territory transfer from $oldOwner." }
    $override = Get-Override $oldOwner
    $excluded = @($realm.props.excludeIds) + @($changedOwners[$oldOwner])
    $override.properties.excludeIds = @($excluded | Select-Object -Unique)
}

$sovietOverride.properties.excludeIds = @()

$germanyNames = @($realms | Where-Object {
    $_.realm -eq 'German Republic' -or $_.realm.StartsWith('German Republic (')
} | ForEach-Object { $_.realm })
if ($germanyNames -notcontains 'German Republic') { throw 'Could not find the 1918 German Republic.' }
foreach ($oldName in $germanyNames) {
    $override = Get-Override $oldName
    if ($oldName -eq 'German Republic') {
        $override.properties.realm = 'German Reich'
        $override.properties.label = 'Germany'
    } else {
        $override.properties.realm = $oldName.Replace('German Republic', 'German Reich')
    }
    $override.properties.leader = 'Adolf Hitler'
    $override.properties.info = 'The German Reich under Adolf Hitler in 1939, before the invasion of Poland.'
}

$turkeyNames = @($realms | Where-Object {
    $_.realm -eq 'Ottoman Empire' -or $_.realm.StartsWith('Ottoman Empire ')
} | ForEach-Object { $_.realm })
foreach ($oldName in $turkeyNames) {
    $override = Get-Override $oldName
    if ($oldName -eq 'Ottoman Empire') {
        $override.properties.realm = 'Republic of Turkey'
        $override.properties.label = 'Turkey'
    } elseif ($oldName -eq 'Ottoman Empire (Anatolia)') {
        $override.properties.realm = 'Republic of Turkey (Anatolia)'
    } else {
        $override.properties.realm = $oldName.Replace('Ottoman Empire', 'Republic of Turkey')
    }
    if ($oldName -ne 'Ottoman Empire') { $override.properties.label = '' }
    $override.properties.fillColor = '#8a9c83'
    $override.properties.borderColor = '#465343'
    $override.properties.leader = 'Ismet Inonu'
    $override.properties.info = 'The Republic of Turkey under President Ismet Inonu in 1939.'
}

$spanishRealm = $realms | Where-Object { $_.realm -eq 'Kingdom of Spain' } | Select-Object -First 1
if ($spanishRealm) {
    $spanishOverride = Get-Override 'Kingdom of Spain'
    $spanishOverride.properties.realm = 'Spanish State'
    $spanishOverride.properties.label = 'Spain'
    $spanishOverride.properties.leader = 'Francisco Franco'
    $spanishOverride.properties.info = 'The Spanish Civil War ended in April 1939 with Franco victorious.'
    $spanishFilters = New-Object System.Collections.ArrayList
    foreach ($filter in @($spanishRealm.props.regionFilters)) {
        if ($filter) { [void]$spanishFilters.Add($filter) }
    }
    [void]$spanishFilters.Add([ordered]@{
        admin = 'Spain'
        ids = @('santacruzdetenerife', 'laspalmas')
    })
    $spanishOverride.properties.regionFilters = $spanishFilters
}

foreach ($realm in $realms) {
    $oldName = $realm.realm
    if ($oldName -match $sovietDonorPattern -or $oldName -eq 'German Republic' -or
        $oldName.StartsWith('German Republic (') -or $turkeyNames -contains $oldName -or
        $oldName -eq 'Kingdom of Spain') { continue }
    $override = Get-Override $oldName
    $override.properties.leader = Get-Leader $oldName
    $override.properties.info = "$oldName in 1939, before the German invasion of Poland."
}

$block = [ordered]@{
    baseYear = 1918
    note = 'Europe on 1 September 1939, immediately before the German invasion of Poland. Austria, the Sudetenland and Memel had been annexed by Germany; Bohemia and Moravia were a German protectorate; Slovakia was independent; Albania was under Italian rule. Poland, the Baltic states and Finland were still independent. Modern administrative regions are approximate territorial proxies.'
    overrides = $overrides
    additions = $additions
}
$json = ConvertTo-Json $block -Depth 20
$json = $json -replace '\\u0027', "'"
$fragmentPath = Join-Path $PSScriptRoot 'frag1939.json'
[IO.File]::WriteAllText($fragmentPath, $json, (New-Object Text.UTF8Encoding($false)))
Write-Host "1939 fragment generated: $($overrides.Count) overrides, $($additions.Count) additions."

if ($Insert) {
    $text = [IO.File]::ReadAllText($yearsPath, [Text.Encoding]::UTF8)
    $lastBrace = $text.LastIndexOf('}')
    if ($lastBrace -lt 0) { throw 'Could not find the end of years.json.' }
    $yearMarker = $text.LastIndexOf('"1939"')
    if ($yearMarker -ge 0) {
        $comma = $text.LastIndexOf(',', $yearMarker)
        if ($comma -lt 0) { throw 'Could not locate the existing 1939 year entry.' }
        $updated = $text.Substring(0, $comma) + ",`r`n  `"1939`": $json`r`n}"
    } else {
        $insertText = ",`r`n  `"1939`": $json`r`n"
        $updated = $text.Substring(0, $lastBrace).TrimEnd() + $insertText + '}'
    }
    [IO.File]::WriteAllText($yearsPath, $updated, (New-Object Text.UTF8Encoding($false)))
    Write-Host 'Inserted year 1939 after the final year.'
}
