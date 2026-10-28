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
        if (-not $map.Contains($oldName)) { throw "Year $year overrides unknown realm $oldName." }
        $realm = $map[$oldName]
        $override = $cfg.overrides.$oldName
        if ($null -ne $override.provinces) { $realm.provinces = @($override.provinces) }
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

function Get-Override([string]$name) {
    if (-not $script:overrides.Contains($name)) {
        $script:overrides[$name] = [ordered]@{ properties = [ordered]@{} }
    }
    return $script:overrides[$name]
}

function Get-Leader1955([string]$realm) {
    switch -Regex ($realm) {
        '^Soviet Union' { return 'Nikita Khrushchev (First Secretary)' }
        '^(United Kingdom|British)' { return 'Anthony Eden (Prime Minister)' }
        '^(France|French)' { return 'Edgar Faure (Prime Minister)' }
        '^(Finland|Republic of Finland)' { return 'Urho Kekkonen (President)' }
        '^(Republic of Poland|Poland|Polish People)' { return 'Boleslaw Bierut (Chairman of the Council of State)' }
        '^(Kingdom of Romania|Romania|Romanian People)' { return 'Gheorghe Gheorghiu-Dej (First Secretary)' }
        '^(Kingdom of Hungary|Hungarian|Hungary)' { return 'Matyas Rakosi (General Secretary)' }
        '^(Czechoslovakia)' { return 'Antonin Zapotocky (President)' }
        '^(Kingdom of Serbs, Croats and Slovenes|Yugoslavia|Democratic Federal Yugoslavia)' { return 'Josip Broz Tito (President)' }
        '^(Kingdom of Italy|Italian)' { return 'Giovanni Gronchi (President)' }
        '^(Kingdom of Greece|Greece)' { return 'Paul of Greece (King)' }
        '^(Kingdom of Bulgaria|Tsardom of Bulgaria|Bulgaria)' { return 'Valko Chervenkov (Prime Minister)' }
        '^(German Reich|German Republic|Federal Republic of Germany|German Democratic Republic|Saar Protectorate)' { return 'Government of the respective German state' }
        '^(Spanish State|Kingdom of Spain|Spain)' { return 'Francisco Franco' }
        '^(Kingdom of Saudi Arabia|Saudi Arabia)' { return 'Saud of Saudi Arabia (King)' }
        '^Republic of Turkey|^Turkey' { return 'Celal Bayar (President)' }
        '^(Kingdom of Egypt|Egypt)' { return 'Gamal Abdel Nasser (Prime Minister)' }
        '^(Kingdom of Portugal|Portugal)' { return 'António de Oliveira Salazar (Prime Minister)' }
        '^(Kingdom of the Netherlands|Netherlands)' { return 'Juliana (Queen)' }
        '^Belgium' { return 'Baudouin (King)' }
        '^(Republic of Austria|Austria)$' { return 'Adolf Schaerf (President)' }
        default { return 'National government' }
    }
}

$realms = @(Get-Realms '1945')
if ($realms.Count -eq 0) { throw 'The 1945 map contains no resolved realms.' }
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
$additions = New-Object System.Collections.ArrayList

function Add-State([string]$name, [string]$label, [string]$leader, [string]$info, [string]$fill, [string]$border, $filters) {
    if (@($script:realms | Where-Object { $_.realm -eq $name }).Count -gt 0) {
        throw "Realm $name already exists in the 1945 base."
    }
    [void]$script:additions.Add([ordered]@{
        provinces = @()
        properties = [ordered]@{
            realm = $name
            label = $label
            leader = $leader
            info = $info
            fillColor = $fill
            borderColor = $border
            regionFilters = @($filters)
        }
    })
}

function Set-YearEntry([string]$text, [string]$year, [string]$json) {
    $pattern = '(?m)^  "' + [regex]::Escape($year) + '"\s*:\s*'
    $match = [regex]::Match($text, $pattern)
    if ($match.Success) {
        $openBrace = $text.IndexOf('{', $match.Index + $match.Length)
        if ($openBrace -lt 0) { throw "Could not find the start of year $year data." }
        $depth = 0
        $inString = $false
        $escaped = $false
        $end = -1
        for ($i = $openBrace; $i -lt $text.Length; $i++) {
            $character = $text[$i]
            if ($inString) {
                if ($escaped) { $escaped = $false }
                elseif ($character -eq '\') { $escaped = $true }
                elseif ($character -eq '"') { $inString = $false }
                continue
            }
            if ($character -eq '"') { $inString = $true }
            elseif ($character -eq '{') { $depth++ }
            elseif ($character -eq '}') {
                $depth--
                if ($depth -eq 0) { $end = $i + 1; break }
            }
        }
        if ($end -lt 0) { throw "Could not find the end of year $year data." }
        return $text.Substring(0, $match.Index) + "  `"$year`": $json" + $text.Substring($end)
    }

    $lastBrace = $text.LastIndexOf('}')
    if ($lastBrace -lt 0) { throw 'Could not find the end of years.json.' }
    return $text.Substring(0, $lastBrace).TrimEnd() + ",`r`n  `"$year`": $json`r`n}"
}

foreach ($realm in $realms) {
    $override = Get-Override $realm.realm
    $override.properties.leader = Get-Leader1955 $realm.realm
    $override.properties.info = "$($realm.realm) at the end of 1955."
}

$zoneNames = @(
    'Soviet Occupation Zone (Germany)',
    'British Occupation Zone (Germany)',
    'United States Occupation Zone (Germany)',
    'French Occupation Zone (Germany)',
    'Soviet Occupation Zone (Austria)',
    'United States Occupation Zone (Austria)',
    'British Occupation Zone (Austria)',
    'French Occupation Zone (Austria)'
)
foreach ($zoneName in $zoneNames) {
    $realm = $realms | Where-Object { $_.realm -eq $zoneName } | Select-Object -First 1
    if (-not $realm) { throw "Expected occupation zone not found: $zoneName." }
    $override = Get-Override $zoneName
    $override.provinces = @()
    $override.properties.label = ''
    $override.properties.regionFilters = @()
    $override.properties.excludeIds = @()
    $override.properties.info = 'The Allied occupation ended in 1955.'
}

$germanIds = @($features | Where-Object { $_.admin -eq 'Germany' } | ForEach-Object { $_.id })
$eastIds = @('saxony', 'saxony-anhalt', 'thuringia', 'brandenburg', 'mecklenburg-westernpomerania', 'berlin')
$saarIds = @('saarland')
$westIds = @($germanIds | Where-Object { $_ -notin $eastIds -and $_ -notin $saarIds })
if (@($germanIds | Where-Object { $_ -notin $eastIds -and $_ -notin $saarIds -and $_ -notin $westIds }).Count -gt 0 -or
    @($eastIds | Where-Object { $_ -notin $germanIds }).Count -gt 0 -or
    @($saarIds | Where-Object { $_ -notin $germanIds }).Count -gt 0) {
    throw 'German state partition does not match the map regions.'
}

Add-State 'German Democratic Republic' 'East Germany' 'Walter Ulbricht (First Secretary)' `
    'The German Democratic Republic was established in 1949 and joined the Warsaw Pact in 1955. Berlin is shown as a whole-region proxy; its sectors cannot be separated with the available map data.' `
    '#5a0b16' '#2e050a' ([ordered]@{ admin = 'Germany'; ids = $eastIds })
Add-State 'Federal Republic of Germany' 'West Germany' 'Konrad Adenauer (Federal Chancellor)' `
    'The Federal Republic of Germany joined NATO in 1955. Modern German state boundaries approximate the western federal territory.' `
    '#8b8f9e' '#4c4f5c' ([ordered]@{ admin = 'Germany'; ids = $westIds })
Add-State 'Saar Protectorate' 'Saar' 'Heinrich Welsch (Minister-President)' `
    'The Saar Protectorate remained separate at the end of 1955. The Saar statute was rejected in a referendum that year; union with West Germany followed in 1957.' `
    '#4169a1' '#203b61' ([ordered]@{ admin = 'Germany'; ids = $saarIds })

$austrianIds = @($features | Where-Object { $_.admin -eq 'Austria' } | ForEach-Object { $_.id })
if ($austrianIds.Count -eq 0) { throw 'No Austrian map regions were found.' }
Add-State 'Republic of Austria' 'Austria' 'Adolf Schaerf (President)' `
    'Austria regained full sovereignty under the State Treaty of 1955 and declared permanent neutrality. Vienna is shown as a whole-region proxy rather than divided occupation sectors.' `
    '#ffffff' '#8a8576' ([ordered]@{ admin = 'Austria'; ids = $austrianIds })

$saharanFrontier = $realms | Where-Object { $_.realm -eq 'Saharan Frontier and Tribal Lands' } | Select-Object -First 1
if (-not $saharanFrontier) { throw 'Expected Saharan frontier realm not found.' }
$saharanOverride = Get-Override $saharanFrontier.realm
$saharanOverride.provinces = @()
$saharanOverride.properties.label = ''
$saharanOverride.properties.regionFilters = @()
$saharanOverride.properties.excludeIds = @()
$saharanOverride.properties.leader = 'Former frontier polities'
$saharanOverride.properties.info = 'The available modern administrative regions cannot represent the historic Saharan frontier as a separate political territory in 1955.'

$moroccoIds = @($features | Where-Object { $_.admin -eq 'Morocco' } | ForEach-Object { [string]$_.id })
$spanishSaharaIds = @('oueded-dahab')
if ($moroccoIds.Count -ne 16 -or @($spanishSaharaIds | Where-Object { $_ -notin $moroccoIds }).Count -gt 0) {
    throw 'Moroccan region data does not match the expected 1955 partition.'
}
Add-State 'Spanish Sahara' 'Spanish Sahara' 'Francisco Franco (Head of State)' `
    'Rio de Oro, including the Dakhla region proxy, was administered by Spain as Spanish Sahara. The available modern region is only an approximate boundary.' `
    '#a37d45' '#654d2b' ([ordered]@{ admin = 'Morocco'; ids = $spanishSaharaIds })

$renames = @(
    [ordered]@{ old = 'Republic of Poland'; new = 'Polish People''s Republic'; label = 'Poland'; leader = 'Boleslaw Bierut (Chairman of the Council of State)'; info = 'The Polish People''s Republic was established in 1952. Its western borders are shown with modern administrative regions.' },
    [ordered]@{ old = 'Hungarian Republic'; new = 'Hungarian People''s Republic'; label = 'Hungary'; leader = 'Matyas Rakosi (General Secretary)'; info = 'Hungary was a one-party socialist state and a founding member of the Warsaw Pact in 1955.' },
    [ordered]@{ old = 'Tsardom of Bulgaria'; new = 'People''s Republic of Bulgaria'; label = 'Bulgaria'; leader = 'Valko Chervenkov (Prime Minister)'; info = 'Bulgaria was a one-party socialist state and a founding member of the Warsaw Pact in 1955.' },
    [ordered]@{ old = 'Democratic Government of Albania'; new = 'People''s Republic of Albania'; label = 'Albania'; leader = 'Enver Hoxha (Prime Minister)'; info = 'Albania was a one-party socialist state and a founding member of the Warsaw Pact in 1955.' },
    [ordered]@{ old = 'Democratic Federal Yugoslavia'; new = 'Federal People''s Republic of Yugoslavia'; label = 'Yugoslavia'; leader = 'Josip Broz Tito (President)'; info = 'Yugoslavia followed an independent socialist path outside the Soviet-led Warsaw Pact.' },
    [ordered]@{ old = 'Kingdom of Italy (Libya)'; new = 'Kingdom of Libya'; label = 'Libya'; leader = 'Idris I (King)'; info = 'The Kingdom of Libya had been independent since 24 December 1951 under King Idris I.' },
    [ordered]@{ old = 'Egypt (British occupation)'; new = 'Republic of Egypt'; label = 'Egypt'; leader = 'Gamal Abdel Nasser (Prime Minister)'; info = 'Egypt was a republic under Gamal Abdel Nasser. The 1954 Anglo-Egyptian agreement provided for British withdrawal from the Suez Canal base; the final troops left in 1956.' }
)
foreach ($state in $renames) {
    $realm = $realms | Where-Object { $_.realm -eq $state.old } | Select-Object -First 1
    if (-not $realm) { throw "Expected realm not found for 1955 update: $($state.old)." }
    $override = Get-Override $state.old
    $override.properties.realm = $state.new
    $override.properties.label = $state.label
    $override.properties.leader = $state.leader
    $override.properties.info = $state.info
}

$morocco = $realms | Where-Object { $_.realm -eq 'Alaouite Sultanate' } | Select-Object -First 1
if (-not $morocco) { throw 'Expected Alaouite Sultanate realm not found.' }
$moroccoOverride = Get-Override $morocco.realm
$moroccoOverride.properties.leader = 'Mohammed V (Sultan)'
$moroccoOverride.properties.info = 'The Sultan returned from exile in November 1955. Morocco remained under French and Spanish protectorates at year-end; independence followed in 1956. The map shows the Sultanate as a proxy and cannot distinguish the protectorate zones.'

$franceAfrica = $realms | Where-Object { $_.realm -eq 'France (Africa)' } | Select-Object -First 1
if (-not $franceAfrica) { throw 'Expected France (Africa) realm not found.' }
$franceAfricaOverride = Get-Override $franceAfrica.realm
$franceAfricaOverride.properties.info = 'French rule continued in Algeria, where the war of independence had begun in 1954. Tunisia received internal autonomy in 1955 but remained a French protectorate until independence in March 1956.'

foreach ($state in @(
    [ordered]@{ old = 'Kingdom of Romania (Greater Romania)'; leader = 'Gheorghe Gheorghiu-Dej (First Secretary)'; info = 'Romania became a one-party socialist state in 1947. Its postwar borders are shown with modern administrative regions.' },
    [ordered]@{ old = 'Kingdom of Romania'; leader = 'Gheorghe Gheorghiu-Dej (First Secretary)'; info = 'Romania became a one-party socialist state in 1947.' },
    [ordered]@{ old = 'Kingdom of Hungary (Territorial Gains)'; leader = 'Matyas Rakosi (General Secretary)'; info = 'This 1945 territorial-gains overlay no longer applies after the postwar borders were settled.' },
    [ordered]@{ old = 'Tsardom of Bulgaria (Southern Dobruja)'; leader = 'Valko Chervenkov (Prime Minister)'; info = 'Southern Dobruja remained part of Bulgaria in 1955.' }
)) {
    $realm = $realms | Where-Object { $_.realm -eq $state.old } | Select-Object -First 1
    if (-not $realm) { throw "Expected realm not found for 1955 update: $($state.old)." }
    $override = Get-Override $state.old
    $override.properties.leader = $state.leader
    $override.properties.info = $state.info
    if ($state.old -eq 'Kingdom of Hungary (Territorial Gains)') {
        $override.provinces = @()
        $override.properties.regionFilters = @()
        $override.properties.excludeIds = @()
    }
    if ($state.old -eq 'Tsardom of Bulgaria (Southern Dobruja)') {
        $override.properties.realm = 'People''s Republic of Bulgaria (Southern Dobruja)'
    }
}

$block = [ordered]@{
    baseYear = 1945
    note = 'Europe and North Africa at the end of 1955. Libya was independent, Egypt was a republic with the British Suez base withdrawal still underway, Morocco remained under French and Spanish protectorates, Tunisia had internal autonomy under French protection, and Algeria remained French amid the war of independence. The map uses modern administrative regions as approximate historical boundaries.'
    overrides = $overrides
    additions = $additions
}
$json = ConvertTo-Json $block -Depth 20
$json = $json -replace '\\u0027', "'"
$fragmentPath = Join-Path $PSScriptRoot 'frag1955.json'
[IO.File]::WriteAllText($fragmentPath, $json, (New-Object Text.UTF8Encoding($false)))
Write-Host "1955 fragment generated: $($overrides.Count) overrides, $($additions.Count) additions."

if ($Insert) {
    $text = [IO.File]::ReadAllText($yearsPath, [Text.Encoding]::UTF8)
    $updated = Set-YearEntry $text '1955' $json
    [IO.File]::WriteAllText($yearsPath, $updated, (New-Object Text.UTF8Encoding($false)))
    Write-Host 'Inserted or updated year 1955 in years.json.'
}
