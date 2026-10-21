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

function Test-TransferFilter($filter, $feature) {
    if ($filter.admin -and $filter.admin -ne $feature.admin) { return $false }
    if ($filter.geonunit -and $filter.geonunit -ne $feature.geonunit) { return $false }
    if ($filter.ids -and @($filter.ids) -notcontains $feature.id) { return $false }
    return $true
}

function Get-Override([string]$name) {
    if (-not $script:overrides.Contains($name)) {
        $script:overrides[$name] = [ordered]@{ properties = [ordered]@{} }
    }
    return $script:overrides[$name]
}

function Get-Leader([string]$realm) {
    switch -Regex ($realm) {
        '^Soviet Union' { return 'Joseph Stalin' }
        '^(United Kingdom|British)' { return 'Clement Attlee' }
        '^(France|French)' { return 'Charles de Gaulle (President of the Provisional Government)' }
        '^(Finland|Republic of Finland)' { return 'Carl Gustaf Emil Mannerheim (President)' }
        '^(Republic of Poland|Poland)' { return 'Boleslaw Bierut (Chairman of the State National Council)' }
        '^(Kingdom of Romania|Romania)' { return 'Michael I' }
        '^(Kingdom of Hungary|Hungarian|Hungary)' { return 'Zoltan Tildy (President)' }
        '^(Czechoslovakia)' { return 'Edvard Benes (President)' }
        '^(Kingdom of Serbs, Croats and Slovenes|Yugoslavia|Democratic Federal Yugoslavia)' { return 'Josip Broz Tito' }
        '^(Kingdom of Italy|Italian)' { return 'Victor Emmanuel III' }
        '^(Kingdom of Greece|Greece)' { return 'Archbishop Damaskinos (Regent)' }
        '^(Kingdom of Bulgaria|Tsardom of Bulgaria|Bulgaria)' { return 'Simeon II (under the Regency Council)' }
        '^(German Reich|German Republic)' { return 'Allied occupation authorities' }
        '^(Spanish State|Kingdom of Spain|Spain)' { return 'Francisco Franco' }
        '^(Kingdom of Saudi Arabia|Saudi Arabia)' { return 'Abdulaziz Ibn Saud' }
        '^Republic of Turkey|^Turkey' { return 'Ismet Inonu' }
        '^(Kingdom of Egypt|Egypt)' { return 'Farouk I' }
        '^(Kingdom of Portugal|Portugal)' { return 'Antonio Oscar Carmona' }
        '^(Kingdom of the Netherlands|Netherlands)' { return 'Wilhelmina' }
        '^Belgium' { return 'Charles of Belgium (Prince Regent)' }
        default { return 'Local authorities' }
    }
}

$realms = @(Get-Realms '1939')
if ($realms.Count -eq 0) { throw 'The 1939 map contains no resolved realms.' }
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
$changedOwners = @{}
$badenWurttembergId = 'baden-w' + [char]0x00FC + 'rttemberg'

$transfers = @(
    [ordered]@{
        realm = 'Soviet Occupation Zone (Germany)'; label = 'Soviet Zone'
        filters = @([ordered]@{ admin = 'Germany'; ids = @('saxony', 'saxony-anhalt', 'thuringia', 'brandenburg', 'mecklenburg-westernpomerania', 'berlin') })
        fill = '#5a0b16'; border = '#2e050a'; leader = 'Soviet occupation authorities'
        info = 'The Soviet occupation zone in Germany, including Berlin as a whole-region proxy for its four postwar sectors.'
    },
    [ordered]@{
        realm = 'British Occupation Zone (Germany)'; label = 'British Zone'
        filters = @([ordered]@{ admin = 'Germany'; ids = @('schleswig-holstein', 'lowersaxony', 'northrhine-westphalia', 'hamburg') })
        fill = '#c0504d'; border = '#6e2927'; leader = 'British occupation authorities'
        info = 'The British occupation zone in Germany, shown with modern state boundaries as approximate proxies.'
    },
    [ordered]@{
        realm = 'United States Occupation Zone (Germany)'; label = 'US Zone'
        filters = @([ordered]@{ admin = 'Germany'; ids = @('bavaria', 'hesse', $badenWurttembergId, 'freehanseaticbremen') })
        fill = '#4169a1'; border = '#203b61'; leader = 'United States occupation authorities'
        info = 'The United States occupation zone in Germany. The combined modern Baden-Wurttemberg region is assigned as a broad proxy.'
    },
    [ordered]@{
        realm = 'French Occupation Zone (Germany)'; label = 'French Zone'
        filters = @([ordered]@{ admin = 'Germany'; ids = @('rhineland-palatinate', 'saarland') })
        fill = '#8b8f9e'; border = '#4c4f5c'; leader = 'French occupation authorities'
        info = 'The French occupation zone in Germany, approximated by modern Rhineland-Palatinate and Saarland.'
    },
    [ordered]@{
        realm = 'Soviet Occupation Zone (Austria)'; label = ''
        filters = @([ordered]@{ admin = 'Austria'; ids = @('loweraustria', 'burgenland', 'vienna') })
        fill = '#5a0b16'; border = '#2e050a'; leader = 'Soviet occupation authorities'
        info = 'The Soviet occupation zone in Austria. Vienna is shown whole in this zone because the map has no sector-level city polygons.'
    },
    [ordered]@{
        realm = 'United States Occupation Zone (Austria)'; label = ''
        filters = @([ordered]@{ admin = 'Austria'; ids = @('upperaustria', 'salzburg') })
        fill = '#4169a1'; border = '#203b61'; leader = 'United States occupation authorities'
        info = 'The United States occupation zone in Austria, approximated by modern Upper Austria and Salzburg.'
    },
    [ordered]@{
        realm = 'British Occupation Zone (Austria)'; label = ''
        filters = @([ordered]@{ admin = 'Austria'; ids = @('carinthia', 'styria') })
        fill = '#c0504d'; border = '#6e2927'; leader = 'British occupation authorities'
        info = 'The British occupation zone in Austria, approximated by modern Carinthia and Styria.'
    },
    [ordered]@{
        realm = 'French Occupation Zone (Austria)'; label = ''
        filters = @([ordered]@{ admin = 'Austria'; ids = @('tyrol', 'vorarlberg') })
        fill = '#8b8f9e'; border = '#4c4f5c'; leader = 'French occupation authorities'
        info = 'The French occupation zone in Austria, approximated by modern Tyrol and Vorarlberg.'
    },
    [ordered]@{
        realm = 'Czechoslovakia'; label = 'Czechoslovakia'
        filters = @(
            [ordered]@{ admin = 'Czech Republic' },
            [ordered]@{ admin = 'Slovakia' }
        )
        fill = '#4a8c8a'; border = '#2e5e5c'; leader = 'Edvard Benes (President)'
        info = 'Czechoslovakia was restored in 1945. Its borders are shown using modern Czech and Slovak administrative regions.'
    },
    [ordered]@{
        realm = 'Soviet Union (Baltic Republics)'; label = ''
        filters = @(
            [ordered]@{ admin = 'Estonia' },
            [ordered]@{ admin = 'Latvia' },
            [ordered]@{ admin = 'Lithuania' }
        )
        fill = '#5a0b16'; border = '#2e050a'; leader = 'Joseph Stalin'
        info = 'Estonia, Latvia and Lithuania had been occupied and annexed by the Soviet Union. Modern administrative regions are used as proxies.'
    },
    [ordered]@{
        realm = 'Soviet Union (Postwar Acquisitions)'; label = ''
        filters = @(
            [ordered]@{ admin = 'Russia'; ids = @('kaliningrad') },
            [ordered]@{ admin = 'Moldova' },
            [ordered]@{ admin = 'Finland'; ids = @('northkarelia', 'southkarelia') },
            [ordered]@{ admin = 'Ukraine'; ids = @('zakarpattia') }
        )
        fill = '#5a0b16'; border = '#2e050a'; leader = 'Joseph Stalin'
        info = 'Soviet postwar gains include northern East Prussia, Bessarabia, the Karelian territories and Carpathian Ruthenia; modern regions are approximate.'
    },
    [ordered]@{
        realm = 'France (Alsace-Lorraine Restored)'; label = ''
        filters = @([ordered]@{ admin = 'France'; ids = @('bas-rhin', 'haut-rhin', 'moselle') })
        fill = '#4169a1'; border = '#203b61'; leader = 'Charles de Gaulle (President of the Provisional Government)'
        info = 'France regained Alsace-Lorraine after the German defeat. Modern administrative regions are approximate proxies.'
    },
    [ordered]@{
        realm = 'Tsardom of Bulgaria (Southern Dobruja)'; label = ''
        filters = @([ordered]@{ admin = 'Bulgaria'; ids = @('dobrich', 'silistra') })
        fill = '#5f9ea0'; border = '#2f5e60'; leader = 'Simeon II (under the Regency Council)'
        info = 'Southern Dobruja had returned to Bulgaria in 1940; modern provinces Dobrich and Silistra are broad proxies.'
    },
    [ordered]@{
        realm = 'Democratic Government of Albania'; label = 'Albania'
        filters = @([ordered]@{ admin = 'Albania' })
        fill = '#5b8c55'; border = '#36533a'; leader = 'Enver Hoxha (Prime Minister)'
        info = 'Albania was governed by Enver Hoxha''s Democratic Government at the end of 1945.'
    }
)

$claimedFeatures = @{}
foreach ($state in $transfers) {
    $matchedFeatures = @($features | Where-Object {
        $feature = $_
        @($state.filters | Where-Object { Test-TransferFilter $_ $feature }).Count -gt 0
    })
    if ($matchedFeatures.Count -eq 0) {
        throw "No map regions matched transfer realm $($state.realm)."
    }

    $filterIdsByAdmin = @{}
    foreach ($feature in $matchedFeatures) {
        $featureKey = "$($feature.admin)|$($feature.id)"
        if ($claimedFeatures.ContainsKey($featureKey)) {
            if ($claimedFeatures[$featureKey] -eq $state.realm) { continue }
            throw "Transfer regions overlap: $featureKey belongs to both $($claimedFeatures[$featureKey]) and $($state.realm)."
        }
        $claimedFeatures[$featureKey] = $state.realm

        $owners = @($realms | Where-Object { Test-FeatureMatch $_ $feature })
        if ($owners.Count -gt 1) {
            throw "1939 overlap for $($feature.admin)/$($feature.id): $($owners.realm -join ', ')."
        }
        if ($owners.Count -eq 1) {
            $oldOwner = $owners[0].realm
            if (-not $changedOwners.ContainsKey($oldOwner)) {
                $changedOwners[$oldOwner] = New-Object System.Collections.ArrayList
            }
            [void]$changedOwners[$oldOwner].Add([pscustomobject]@{
                admin = $feature.admin
                id = $feature.id
            })
        }
        if (-not $filterIdsByAdmin.ContainsKey($feature.admin)) {
            $filterIdsByAdmin[$feature.admin] = [System.Collections.Generic.List[string]]::new()
        }
        if (-not $filterIdsByAdmin[$feature.admin].Contains($feature.id)) {
            $filterIdsByAdmin[$feature.admin].Add($feature.id)
        }
    }

    $filters = New-Object System.Collections.ArrayList
    foreach ($admin in $filterIdsByAdmin.Keys) {
        [void]$filters.Add([ordered]@{
            admin = $admin
            ids = @($filterIdsByAdmin[$admin])
        })
    }
    $existingRealm = $realms | Where-Object { $_.realm -eq $state.realm } | Select-Object -First 1
    if ($existingRealm) {
        $override = Get-Override $state.realm
        $override.provinces = @()
        $override.properties.realm = $state.realm
        $override.properties.label = $state.label
        $override.properties.leader = $state.leader
        $override.properties.regionFilters = $filters
        $override.properties.excludeIds = @()
        $override.properties.fillColor = $state.fill
        $override.properties.borderColor = $state.border
        $override.properties.info = $state.info
    } else {
        [void]$additions.Add([ordered]@{
            provinces = @()
            properties = [ordered]@{
                realm = $state.realm
                label = $state.label
                leader = $state.leader
                regionFilters = $filters
                fillColor = $state.fill
                borderColor = $state.border
                info = $state.info
            }
        })
    }
}

foreach ($oldOwner in $changedOwners.Keys) {
    $realm = $realms | Where-Object { $_.realm -eq $oldOwner } | Select-Object -First 1
    if (-not $realm) { throw "No 1939 realm found for territory transfer from $oldOwner." }
    $override = Get-Override $oldOwner
    $globalExcluded = New-Object System.Collections.Generic.List[string]
    foreach ($id in @($realm.props.excludeIds)) {
        if ($id -and -not $globalExcluded.Contains([string]$id)) {
            $globalExcluded.Add([string]$id)
        }
    }
    $regionalExclusions = @{}
    foreach ($transfer in $changedOwners[$oldOwner]) {
        $retainedDuplicate = @($features | Where-Object {
            $_.id -eq $transfer.id -and $_.admin -ne $transfer.admin -and
            -not $claimedFeatures.ContainsKey("$($_.admin)|$($_.id)") -and
            (Test-FeatureMatch $realm $_)
        }).Count -gt 0
        if ($retainedDuplicate) {
            if (-not $regionalExclusions.ContainsKey($transfer.admin)) {
                $regionalExclusions[$transfer.admin] = New-Object System.Collections.Generic.List[string]
            }
            if (-not $regionalExclusions[$transfer.admin].Contains($transfer.id)) {
                $regionalExclusions[$transfer.admin].Add($transfer.id)
            }
        } elseif (-not $globalExcluded.Contains($transfer.id)) {
            $globalExcluded.Add($transfer.id)
        }
    }
    foreach ($admin in $regionalExclusions.Keys) {
        [void]$globalExcluded.RemoveAll([Predicate[string]]{
            param($id)
            $regionalExclusions[$admin].Contains($id)
        })
    }
    $override.properties.excludeIds = @($globalExcluded)
    if ($regionalExclusions.Count -gt 0) {
        $updatedFilters = New-Object System.Collections.ArrayList
        $unmatchedAdmins = @($regionalExclusions.Keys)
        foreach ($filter in @($realm.props.regionFilters)) {
            $copy = [ordered]@{}
            $filter.PSObject.Properties | ForEach-Object { $copy[$_.Name] = $_.Value }
            if ($regionalExclusions.ContainsKey([string]$filter.admin)) {
                $excluded = @($copy.excludeIds) + @($regionalExclusions[[string]$filter.admin])
                $copy.excludeIds = @($excluded | Select-Object -Unique)
                $unmatchedAdmins = @($unmatchedAdmins | Where-Object { $_ -ne $filter.admin })
            }
            [void]$updatedFilters.Add($copy)
        }
        if ($unmatchedAdmins.Count -gt 0) {
            throw "Cannot safely exclude duplicate IDs by admin for $($oldOwner): $($unmatchedAdmins -join ', ')."
        }
        $override.properties.regionFilters = $updatedFilters
    }
}

$poland = $realms | Where-Object { $_.realm -eq 'Republic of Poland' } | Select-Object -First 1
if ($poland) {
    $override = Get-Override 'Republic of Poland'
    $override.properties.leader = 'Boleslaw Bierut (Chairman of the State National Council)'
    $override.properties.info = 'The Provisional Government of National Unity governed Poland at the end of 1945. The western and northern borders were provisional and are approximated by modern regions.'
}

$hungary = $realms | Where-Object { $_.realm -eq 'Hungarian People''s Republic' } | Select-Object -First 1
if ($hungary) {
    $override = Get-Override 'Hungarian People''s Republic'
    $override.properties.realm = 'Hungarian Republic'
    $override.properties.label = 'Hungary'
    $override.properties.leader = 'Zoltan Tildy (President)'
    $override.properties.info = 'Hungary was a republic at the end of 1945, with Zoltan Tildy elected president.'
}

$yugoslavia = $realms | Where-Object {
    $_.realm -eq 'Kingdom of Serbs, Croats and Slovenes' -or
    $_.realm -eq 'Kingdom of Yugoslavia'
} | Select-Object -First 1
if ($yugoslavia) {
    $override = Get-Override $yugoslavia.realm
    $override.properties.realm = 'Democratic Federal Yugoslavia'
    $override.properties.label = 'Yugoslavia'
    $override.properties.leader = 'Josip Broz Tito (Prime Minister)'
    $override.properties.info = 'The monarchy had been abolished and Democratic Federal Yugoslavia was proclaimed in 1945 under Josip Broz Tito.'
}

$romania = $realms | Where-Object {
    $_.realm -eq 'Kingdom of Romania (Greater Romania)' -or $_.realm -eq 'Kingdom of Romania'
} | Select-Object -First 1
if ($romania) {
    $override = Get-Override $romania.realm
    $override.properties.leader = 'Michael I'
    $override.properties.info = 'Romania remained a kingdom under King Michael I at the end of 1945; the country was under growing Soviet influence.'
}

$balticUpdates = @(
    [ordered]@{ name = 'Republic of Estonia'; leader = 'Joseph Stalin'; note = 'Estonia had been occupied and incorporated into the Soviet Union.' },
    [ordered]@{ name = 'Republic of Latvia'; leader = 'Joseph Stalin'; note = 'Latvia had been occupied and incorporated into the Soviet Union.' },
    [ordered]@{ name = 'Republic of Lithuania'; leader = 'Joseph Stalin'; note = 'Lithuania had been occupied and incorporated into the Soviet Union.' }
)
foreach ($state in $balticUpdates) {
    $realm = $realms | Where-Object { $_.realm -eq $state.name } | Select-Object -First 1
    if ($realm) {
        $override = Get-Override $state.name
        $override.properties.label = ''
        $override.properties.leader = $state.leader
        $override.properties.info = $state.note
    }
}

foreach ($realm in $realms) {
    if ($realm.realm -eq 'Republic of Poland' -or
        $realm.realm -eq 'Czechoslovakia' -or
        $realm.realm -eq 'Hungarian People''s Republic' -or
        $realm.realm -eq 'Kingdom of Serbs, Croats and Slovenes' -or
        $realm.realm -eq 'Kingdom of Yugoslavia' -or
        $realm.realm -eq 'Kingdom of Romania (Greater Romania)' -or
        $realm.realm -eq 'Kingdom of Romania' -or
        $realm.realm -in @('Republic of Estonia', 'Republic of Latvia', 'Republic of Lithuania')) {
        continue
    }
    $override = Get-Override $realm.realm
    $override.properties.leader = Get-Leader $realm.realm
    $override.properties.info = "$($realm.realm) at the end of 1945."
}

$block = [ordered]@{
    baseYear = 1939
    note = 'Europe at the end of 1945. Germany and Austria were divided into Allied occupation zones; the Baltic states were incorporated into the Soviet Union; Czechoslovakia was restored; and Albania, Bulgaria, Finland, Poland and Romania reflected postwar territorial changes. Berlin and Vienna are shown as whole regions rather than divided sectors, and modern administrative regions are approximate proxies for several unsettled borders.'
    overrides = $overrides
    additions = $additions
}
$json = ConvertTo-Json $block -Depth 20
$json = $json -replace '\\u0027', "'"
$fragmentPath = Join-Path $PSScriptRoot 'frag1945.json'
[IO.File]::WriteAllText($fragmentPath, $json, (New-Object Text.UTF8Encoding($false)))
Write-Host "1945 fragment generated: $($overrides.Count) overrides, $($additions.Count) additions."

if ($Insert) {
    $text = [IO.File]::ReadAllText($yearsPath, [Text.Encoding]::UTF8)
    $lastBrace = $text.LastIndexOf('}')
    if ($lastBrace -lt 0) { throw 'Could not find the end of years.json.' }
    $yearMarker = $text.LastIndexOf('"1945"')
    if ($yearMarker -ge 0) {
        $comma = $text.LastIndexOf(',', $yearMarker)
        if ($comma -lt 0) { throw 'Could not locate the existing 1945 year entry.' }
        $updated = $text.Substring(0, $comma) + ",`r`n  `"1945`": $json`r`n}"
    } else {
        $insertText = ",`r`n  `"1945`": $json`r`n"
        $updated = $text.Substring(0, $lastBrace).TrimEnd() + $insertText + '}'
    }
    [IO.File]::WriteAllText($yearsPath, $updated, (New-Object Text.UTF8Encoding($false)))
    Write-Host 'Inserted year 1945 after the final year.'
}
