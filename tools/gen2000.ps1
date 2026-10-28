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
            $feature.properties.PSObject.Properties | ForEach-Object { $props[$_.Name] = $_.Value }
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
            $override.properties.PSObject.Properties | ForEach-Object { $realm.props[$_.Name] = $_.Value }
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
        $addition.properties.PSObject.Properties | ForEach-Object { $props[$_.Name] = $_.Value }
        $result += [pscustomobject]@{
            realm = $addition.properties.realm
            provinces = @($addition.provinces)
            props = $props
        }
    }
    return $result
}

function Test-FeatureMatch($realm, $feature) {
    $hit = $realm.provinces -contains $feature.id
    if ($hit) {
        $regionAdmins = $realm.props.regionAdmins
        if ($regionAdmins -and $feature.admin -notin $regionAdmins) { $hit = $false }
    }
    if (-not $hit) {
        foreach ($filter in $realm.props.regionFilters) {
            $matches = $true
            if ($filter.admin -and $filter.admin -ne $feature.admin) { $matches = $false }
            if ($filter.geonunit -and $filter.geonunit -ne $feature.geonunit) { $matches = $false }
            if ($filter.ids -and $feature.id -notin $filter.ids) { $matches = $false }
            if ($filter.excludeIds -and $feature.id -in $filter.excludeIds) { $matches = $false }
            if ($matches) { $hit = $true; break }
        }
    }
    if ($hit -and $realm.props.excludeIds -and $feature.id -in $realm.props.excludeIds) { $hit = $false }
    return $hit
}

function Get-Owner($feature) {
    $owners = @($script:realms | Where-Object { Test-FeatureMatch $_ $feature })
    if ($owners.Count -gt 1) { throw "Overlapping 1990 owners for $($feature.id): $(($owners.realm) -join ', ')." }
    if ($owners.Count -eq 1) { return $owners[0].realm }
    return $null
}

function Get-StateForFeature($feature) {
    $adminToState = @{
        'Albania' = 'Albania'; 'Algeria' = 'Algeria'; 'Armenia' = 'Armenia'; 'Austria' = 'Austria'
        'Azerbaijan' = 'Azerbaijan'; 'Bahrain' = 'Bahrain'; 'Belarus' = 'Belarus'; 'Belgium' = 'Belgium'
        'Bosnia and Herzegovina' = 'Bosnia and Herzegovina'; 'Bulgaria' = 'Bulgaria'; 'Croatia' = 'Croatia'
        'Cyprus' = 'Cyprus'; 'Czech Republic' = 'Czech Republic'; 'Denmark' = 'Denmark'; 'Egypt' = 'Egypt'
        'Estonia' = 'Estonia'; 'Finland' = 'Finland'; 'France' = 'France'; 'Georgia' = 'Georgia'
        'Germany' = 'Germany'; 'Greece' = 'Greece'; 'Hungary' = 'Hungary'; 'Iceland' = 'Iceland'
        'Iran' = 'Iran'; 'Iraq' = 'Iraq'; 'Ireland' = 'Ireland'; 'Israel' = 'Israel'; 'Italy' = 'Italy'
        'Jordan' = 'Jordan'; 'Kosovo' = 'Kosovo under UN administration'; 'Kuwait' = 'Kuwait'
        'Lebanon' = 'Lebanon'; 'Libya' = 'Libya'; 'Lithuania' = 'Lithuania'; 'Luxembourg' = 'Luxembourg'
        'Latvia' = 'Latvia'
        'Macedonia' = 'Republic of Macedonia'; 'Malta' = 'Malta'; 'Moldova' = 'Moldova'
        'Montenegro' = 'Federal Republic of Yugoslavia'; 'Morocco' = 'Morocco'; 'Netherlands' = 'Netherlands'
        'Norway' = 'Norway'; 'Oman' = 'Oman'; 'Palestine' = 'Palestinian National Authority'
        'Poland' = 'Poland'; 'Portugal' = 'Portugal'; 'Qatar' = 'Qatar'
        'Republic of Serbia' = 'Federal Republic of Yugoslavia'; 'Romania' = 'Romania'
        'Russia' = 'Russian Federation'; 'Saudi Arabia' = 'Saudi Arabia'; 'Slovakia' = 'Slovakia'
        'Slovenia' = 'Slovenia'; 'Spain' = 'Spain'; 'Sweden' = 'Sweden'; 'Switzerland' = 'Switzerland'
        'Syria' = 'Syria'; 'Tunisia' = 'Tunisia'; 'Turkey' = 'Turkey'; 'Ukraine' = 'Ukraine'
        'United Arab Emirates' = 'United Arab Emirates'; 'United Kingdom' = 'United Kingdom'; 'Yemen' = 'Yemen'
    }
    if ($adminToState.ContainsKey($feature.admin)) { return $adminToState[$feature.admin] }

    if ($feature.admin -eq 'Supplemental Historical Regions') {
        switch -Regex ($feature.id) {
            '^(it-|it_)' { return 'Italy' }
            '^fr-' { return 'France' }
            '^eng-' { return 'United Kingdom' }
            '^latvia-' { return 'Latvia' }
            '^hu-' { return 'Hungary' }
            '^ib-cordoba-portugal-|^ib-leon-portugal-' { return 'Portugal' }
            '^ib-cordoba-spain-|^ib-leon-spain-' { return 'Spain' }
            '^bn-belgium-' { return 'Belgium' }
            '^bn-netherlands-' { return 'Netherlands' }
            '^bn-luxembourg$' { return 'Luxembourg' }
            '^no-norway-' { return 'Norway' }
            '^md-balanced-' { return 'Moldova' }
            '^bg-balanced-' { return 'Bulgaria' }
            '^hr-balanced-' { return 'Croatia' }
            '^ba-balanced-' { return 'Bosnia and Herzegovina' }
            '^mk-' { return 'Republic of Macedonia' }
            '^kosovo-' { return 'Kosovo under UN administration' }
        }
    }
    if ($feature.admin -in @('European Islands', 'Supplemental Islands')) {
        switch ($feature.id) {
            'faroe-islands' { return 'Denmark' }
            'aland' { return 'Finland' }
            'isle-of-man' { return 'United Kingdom' }
            'guernsey' { return 'United Kingdom' }
            'jersey' { return 'United Kingdom' }
        }
    }
    if ($feature.admin -in @('European microstates', 'Supplemental Microstates')) {
        switch ($feature.id) {
            'andorra' { return 'Andorra' }
            'liechtenstein' { return 'Liechtenstein' }
            'monaco' { return 'Monaco' }
            'san-marino' { return 'San Marino' }
        }
    }
    throw "No 2000 state mapping for assigned feature $($feature.id) (admin: $($feature.admin))."
}

function Get-StateLabel([string]$state) {
    switch ($state) {
        'Russian Federation' { return 'Russia' }
        'Republic of Macedonia' { return 'Macedonia' }
        'Federal Republic of Yugoslavia' { return 'Yugoslavia' }
        'Kosovo under UN administration' { return 'Kosovo (UN administration)' }
        'Palestinian National Authority' { return 'Palestinian Authority' }
        default { return $state }
    }
}

function Get-StateLeader([string]$state) {
    switch ($state) {
        'Albania' { return 'Rexhep Meidani (President)' }
        'Algeria' { return 'Abdelaziz Bouteflika (President)' }
        'Armenia' { return 'Robert Kocharyan (President)' }
        'Austria' { return 'Thomas Klestil (President)' }
        'Azerbaijan' { return 'Heydar Aliyev (President)' }
        'Bahrain' { return 'Hamad bin Isa Al Khalifa (Emir)' }
        'Belarus' { return 'Alexander Lukashenko (President)' }
        'Belgium' { return 'Guy Verhofstadt (Prime Minister)' }
        'Bosnia and Herzegovina' { return 'Presidency of Bosnia and Herzegovina' }
        'Bulgaria' { return 'Petar Stoyanov (President)' }
        'Croatia' { return 'Stjepan Mesic (President)' }
        'Cyprus' { return 'Glafcos Clerides (President)' }
        'Czech Republic' { return 'Vaclav Havel (President)' }
        'Denmark' { return 'Poul Nyrup Rasmussen (Prime Minister)' }
        'Egypt' { return 'Hosni Mubarak (President)' }
        'Estonia' { return 'Lennart Meri (President)' }
        'Federal Republic of Yugoslavia' { return 'Vojislav Kostunica (President)' }
        'Finland' { return 'Tarja Halonen (President)' }
        'France' { return 'Jacques Chirac (President)' }
        'Georgia' { return 'Eduard Shevardnadze (President)' }
        'Germany' { return 'Gerhard Schroder (Federal Chancellor)' }
        'Greece' { return 'Costas Simitis (Prime Minister)' }
        'Hungary' { return 'Ferenc Madl (President)' }
        'Iceland' { return 'Olafur Ragnar Grimsson (President)' }
        'Iran' { return 'Mohammad Khatami (President)' }
        'Iraq' { return 'Saddam Hussein (President)' }
        'Ireland' { return 'Mary McAleese (President)' }
        'Israel' { return 'Ehud Barak (Prime Minister)' }
        'Italy' { return 'Carlo Azeglio Ciampi (President)' }
        'Jordan' { return 'Abdullah II (King)' }
        'Kosovo under UN administration' { return 'Bernard Kouchner (UN Special Representative)' }
        'Latvia' { return 'Vaira Vike-Freiberga (President)' }
        'Lebanon' { return 'Emile Lahoud (President)' }
        'Libya' { return 'Muammar Gaddafi (Leader)' }
        'Lithuania' { return 'Valdas Adamkus (President)' }
        'Luxembourg' { return 'Jean (Grand Duke)' }
        'Malta' { return 'Guido de Marco (President)' }
        'Moldova' { return 'Petru Lucinschi (President)' }
        'Monaco' { return 'Rainier III (Prince)' }
        'Morocco' { return 'Mohammed VI (King)' }
        'Netherlands' { return 'Wim Kok (Prime Minister)' }
        'Norway' { return 'Jens Stoltenberg (Prime Minister)' }
        'Palestinian National Authority' { return 'Yasser Arafat (President)' }
        'Poland' { return 'Aleksander Kwasniewski (President)' }
        'Portugal' { return 'Jorge Sampaio (President)' }
        'Republic of Macedonia' { return 'Boris Trajkovski (President)' }
        'Romania' { return 'Ion Iliescu (President)' }
        'Russian Federation' { return 'Vladimir Putin (President)' }
        'Saudi Arabia' { return 'Fahd bin Abdulaziz (King)' }
        'San Marino' { return 'Captains Regent' }
        'Slovakia' { return 'Rudolf Schuster (President)' }
        'Slovenia' { return 'Milan Kucan (President)' }
        'Spain' { return 'Jose Maria Aznar (Prime Minister)' }
        'Sweden' { return 'Goran Persson (Prime Minister)' }
        'Switzerland' { return 'Swiss Federal Council' }
        'Syria' { return 'Bashar al-Assad (President)' }
        'Tunisia' { return 'Zine El Abidine Ben Ali (President)' }
        'Turkey' { return 'Ahmet Necdet Sezer (President)' }
        'Ukraine' { return 'Leonid Kuchma (President)' }
        'United Kingdom' { return 'Tony Blair (Prime Minister)' }
        'Andorra' { return 'Marc Forne Molne (Head of Government)' }
        'Liechtenstein' { return 'Hans-Adam II (Prince)' }
        default { return 'National government' }
    }
}

function Get-StateColors([string]$state) {
    $established = @{
        'Albania' = @('#5b8c55', '#36533a')
        'Algeria' = @('#4169a1', '#203b61')
        'Andorra' = @('#d9894a', '#75451f')
        'Armenia' = @('#bb7878', '#734949')
        'Austria' = @('#ffffff', '#8a8576')
        'Azerbaijan' = @('#5f9a79', '#345c48')
        'Bahrain' = @('#557b55', '#314b36')
        'Belarus' = @('#1c3a22', '#0b1a10')
        'Belgium' = @('#c2b04a', '#6b6125')
        'Bosnia and Herzegovina' = @('#8e6aa8', '#4f3a63')
        'Bulgaria' = @('#5f9ea0', '#2f5e60')
        'Croatia' = @('#8e6aa8', '#4f3a63')
        'Cyprus' = @('#c0504d', '#6e2927')
        'Czech Republic' = @('#4a8c8a', '#2e5e5c')
        'Denmark' = @('#8b1e2d', '#4b0d16')
        'Egypt' = @('#d08a86', '#7a4a48')
        'Estonia' = @('#547f9d', '#2e4d60')
        'Federal Republic of Yugoslavia' = @('#8e6aa8', '#4f3a63')
        'Finland' = @('#ffffff', '#8a8576')
        'France' = @('#4169a1', '#203b61')
        'Georgia' = @('#ad735a', '#684436')
        'Germany' = @('#8b8f9e', '#4c4f5c')
        'Greece' = @('#6fa8d8', '#35607f')
        'Hungary' = @('#8c5b68', '#5a3540')
        'Iceland' = @('#8b1e2d', '#4b0d16')
        'Ireland' = @('#c0504d', '#6e2927')
        'Iran' = @('#9a4a6a', '#5a2640')
        'Iraq' = @('#a28b70', '#695945')
        'Israel' = @('#c0504d', '#6e2927')
        'Italy' = @('#5fa07e', '#2f5e46')
        'Jordan' = @('#c0504d', '#6e2927')
        'Kosovo under UN administration' = @('#8e6aa8', '#4f3a63')
        'Latvia' = @('#8466a6', '#4f3a65')
        'Lebanon' = @('#4169a1', '#203b61')
        'Libya' = @('#5fa07e', '#2f5e46')
        'Liechtenstein' = @('#d9894a', '#75451f')
        'Lithuania' = @('#ffeb00', '#8a7600')
        'Luxembourg' = @('#8fb0c9', '#4b6478')
        'Malta' = @('#c0504d', '#6e2927')
        'Moldova' = @('#c4783a', '#6e4018')
        'Monaco' = @('#d9894a', '#75451f')
        'Morocco' = @('#a8704f', '#6b432e')
        'Netherlands' = @('#d98a3d', '#7a4a1d')
        'Norway' = @('#3d7891', '#214654')
        'Palestinian National Authority' = @('#c0504d', '#6e2927')
        'Poland' = @('#f08080', '#a84646')
        'Portugal' = @('#2f6b3a', '#163d1e')
        'Republic of Macedonia' = @('#8e6aa8', '#4f3a63')
        'Romania' = @('#cc8f6a', '#7a4a32')
        'Russian Federation' = @('#1c3a22', '#0b1a10')
        'San Marino' = @('#d9894a', '#75451f')
        'Saudi Arabia' = @('#557b55', '#314b36')
        'Slovakia' = @('#4a8c8a', '#2e5e5c')
        'Slovenia' = @('#8e6aa8', '#4f3a63')
        'Spain' = @('#a37d45', '#654d2b')
        'Sweden' = @('#102548', '#06142b')
        'Switzerland' = @('#c9726b', '#7a403c')
        'Syria' = @('#4169a1', '#203b61')
        'Tunisia' = @('#4169a1', '#203b61')
        'Turkey' = @('#8a9c83', '#465343')
        'Ukraine' = @('#d6b55d', '#8a7030')
        'United Kingdom' = @('#c0504d', '#6e2927')
    }
    if (-not $established.ContainsKey($state)) { throw "No established color pair for 2000 state $state." }
    return [pscustomobject]@{ fill = $established[$state][0]; border = $established[$state][1] }
}

$script:realms = @(Get-Realms '1990')
if ($script:realms.Count -eq 0) { throw 'The 1990 map contains no resolved realms.' }

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
    $features += @($geo.features | ForEach-Object { $_.properties })
}

$groups = @{}
foreach ($feature in $features) {
    $oldOwner = Get-Owner $feature
    if (-not $oldOwner) { continue }
    $state = Get-StateForFeature $feature
    if (-not $groups.ContainsKey($state)) { $groups[$state] = @{} }
    if (-not $groups[$state].ContainsKey($feature.admin)) {
        $groups[$state][$feature.admin] = New-Object System.Collections.ArrayList
    }
    [void]$groups[$state][$feature.admin].Add([string]$feature.id)
}
if ($groups.Count -eq 0) { throw 'No assigned 1990 regions could be mapped to 2000 states.' }

$overrides = [ordered]@{}
foreach ($realm in $script:realms) {
    $overrides[$realm.realm] = [ordered]@{
        provinces = @()
        properties = [ordered]@{
            label = ''
            leader = 'Former government'
            info = "$($realm.realm) no longer governed territory shown on the map at the end of 2000."
            regionFilters = @()
            excludeIds = @()
        }
    }
}

$additions = New-Object System.Collections.ArrayList
$sortedStates = @($groups.Keys | Sort-Object)
foreach ($state in $sortedStates) {
    $filters = @()
    foreach ($admin in @($groups[$state].Keys | Sort-Object)) {
        $ids = @($groups[$state][$admin] | Sort-Object -Unique)
        if ($ids.Count -eq 0) { continue }
        $filters += [ordered]@{ admin = $admin; ids = $ids }
    }
    if ($filters.Count -eq 0) { throw "State $state has no mapped regions." }
    $colors = Get-StateColors $state
    $info = "$state at the end of 2000. Boundaries use the available administrative map regions as approximations."
    if ($state -eq 'Federal Republic of Yugoslavia') {
        $info = 'The Federal Republic of Yugoslavia consisted of Serbia and Montenegro at the end of 2000. Kosovo was under United Nations administration following Security Council Resolution 1244.'
    } elseif ($state -eq 'Kosovo under UN administration') {
        $info = 'Kosovo was administered by the United Nations Interim Administration Mission in Kosovo under Security Council Resolution 1244; it was not yet an independent state.'
    } elseif ($state -eq 'Russian Federation') {
        $info = 'The Russian Federation was an independent state after the dissolution of the Soviet Union in 1991.'
    } elseif ($state -eq 'Republic of Macedonia') {
        $info = 'The Republic of Macedonia was independent after the breakup of Yugoslavia. Its constitutional name at the time was Republic of Macedonia.'
    } elseif ($state -eq 'Palestinian National Authority') {
        $info = 'The Palestinian National Authority administered parts of the West Bank and Gaza Strip under the Oslo agreements.'
    } elseif ($state -eq 'Morocco') {
        $info = 'Morocco administered most of Western Sahara at the end of 2000, while the Sahrawi Arab Democratic Republic and Polisario Front maintained a competing claim. The 1991 UN-brokered ceasefire had not led to a final settlement. Available modern regional boundaries cannot show the separation line or the Sahrawi-controlled area.'
    } elseif ($state -eq 'Algeria') {
        $info = 'Algeria was an independent republic under President Abdelaziz Bouteflika, elected in 1999.'
    } elseif ($state -eq 'Tunisia') {
        $info = 'Tunisia was an independent republic under President Zine El Abidine Ben Ali.'
    } elseif ($state -eq 'Libya') {
        $info = 'Libya was governed by Muammar Gaddafi and remained an independent state.'
    } elseif ($state -eq 'Egypt') {
        $info = 'Egypt was an independent republic under President Hosni Mubarak.'
    }

    $properties = [ordered]@{
        label = Get-StateLabel $state
        leader = Get-StateLeader $state
        info = $info
        fillColor = $colors.fill
        borderColor = $colors.border
        regionFilters = $filters
        excludeIds = @()
    }
    if (@($script:realms | Where-Object { $_.realm -eq $state }).Count -gt 0) {
        $overrides[$state] = [ordered]@{
            provinces = @()
            properties = $properties
        }
    } else {
        [void]$additions.Add([ordered]@{
            provinces = @()
            properties = [ordered]@{
                realm = $state
                label = $properties.label
                leader = $properties.leader
                info = $properties.info
                fillColor = $properties.fillColor
                borderColor = $properties.borderColor
                regionFilters = $properties.regionFilters
                excludeIds = @()
            }
        })
    }
}

$block = [ordered]@{
    baseYear = 1990
    note = 'Europe, North Africa and the adjoining mapped regions at the end of 2000. Algeria, Tunisia, Libya and Egypt were independent; Morocco administered most of Western Sahara, whose status remained unresolved after the 1991 ceasefire. The Soviet Union and Yugoslavia had dissolved. Borders use available modern administrative regions and cannot show the Sahrawi-controlled area or the separation line.'
    overrides = $overrides
    additions = $additions
}
$json = ConvertTo-Json $block -Depth 20
$json = $json -replace '\\u0027', "'"
$fragmentPath = Join-Path $PSScriptRoot 'frag2000.json'
[IO.File]::WriteAllText($fragmentPath, $json, (New-Object Text.UTF8Encoding($false)))
Write-Host "2000 fragment generated: $($overrides.Count) overrides, $($additions.Count) additions."

if ($Insert) {
    $text = [IO.File]::ReadAllText($yearsPath, [Text.Encoding]::UTF8)
    $yearMarker = $text.LastIndexOf('"2000"')
    if ($yearMarker -ge 0) {
        $comma = $text.LastIndexOf(',', $yearMarker)
        if ($comma -lt 0) { throw 'Could not locate the existing 2000 year entry.' }
        $updated = $text.Substring(0, $comma) + ",`r`n  `"2000`": $json`r`n}"
    } else {
        $lastBrace = $text.LastIndexOf('}')
        if ($lastBrace -lt 0) { throw 'Could not find the end of years.json.' }
        $updated = $text.Substring(0, $lastBrace).TrimEnd() + ",`r`n  `"2000`": $json`r`n}"
    }
    [IO.File]::WriteAllText($yearsPath, $updated, (New-Object Text.UTF8Encoding($false)))
    Write-Host 'Inserted or updated year 2000 after the final year.'
}
