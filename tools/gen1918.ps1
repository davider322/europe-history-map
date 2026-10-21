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
        '^(Russian Empire|Russian SFSR)' { return 'Vladimir Lenin' }
        '^(German Empire|German Republic)' { return 'Friedrich Ebert (Chairman)' }
        '^Austria-Hungary' { return 'Karl Renner (State Chancellor)' }
        '^Republic of Austria' { return 'Karl Renner (State Chancellor)' }
        '^Kingdom of Hungary|^Hungary' { return 'Mihaly Karolyi (President)' }
        '^Czechoslovakia' { return 'Tomas G. Masaryk' }
        '^(France|French)' { return 'Raymond Poincare (President)' }
        '^(United Kingdom|British)' { return 'George V' }
        '^Kingdom of Italy' { return 'Victor Emmanuel III' }
        '^(Kingdom of Sweden|Sweden)' { return 'Gustaf V' }
        '^(Kingdom of Norway|Norway)' { return 'Haakon VII' }
        '^(Denmark|Kingdom of Denmark)' { return 'Christian X' }
        '^(Ottoman Empire|Ottoman)' { return 'Mehmed VI' }
        '^(Kingdom of Greece|Greece)' { return 'Constantine I' }
        '^(Kingdom of Serbia|Serbia)' { return 'Peter I' }
        '^(Kingdom of Romania|Romania)' { return 'Ferdinand I' }
        '^(Principality of Bulgaria|Kingdom of Bulgaria|Tsardom of Bulgaria|Bulgaria)' { return 'Ferdinand I' }
        '^(Principality of Montenegro|Kingdom of Montenegro|Montenegro)' { return 'Nicholas I' }
        '^(Netherlands|Kingdom of the Netherlands)' { return 'Wilhelmina' }
        '^Belgium' { return 'Albert I' }
        '^(Kingdom of Portugal|Portugal)' { return 'Joao do Canto e Castro (President)' }
        '^(Kingdom of Spain|Spain)' { return 'Alfonso XIII' }
        '^(Alaouite Sultanate|Morocco)' { return 'Yusef' }
        '^(Egypt|Khedivate of Egypt)' { return 'Hussein Kamel (Sultan)' }
        '^(Qajar Iran|Iran)' { return 'Ahmad Shah Qajar' }
        '^Grand Duchy of Finland' { return 'Pehr Evind Svinhufvud (Regent)' }
        default { return 'Local authorities' }
    }
}

$realms = @(Get-Realms '1914')
if ($realms.Count -eq 0) { throw 'The 1914 map contains no resolved realms.' }
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

$states = @(
    [ordered]@{
        realm = 'Republic of German-Austria'; label = 'Austria'; admins = @('Austria')
        fillColor = '#ffffff'; borderColor = '#8a8576'; leader = 'Karl Renner (State Chancellor)'
        info = 'The Republic of German-Austria was proclaimed in November 1918 after the dissolution of Austria-Hungary. Its borders were provisional.'
    },
    [ordered]@{
        realm = 'Hungarian People''s Republic'; label = 'Hungary'; admins = @('Hungary')
        fillColor = '#8c5b68'; borderColor = '#5a3540'; leader = 'Mihaly Karolyi (President)'
        info = 'Hungary declared itself a republic in November 1918. Its postwar borders had not yet been settled.'
    },
    [ordered]@{
        realm = 'Czechoslovakia'; label = 'Czechoslovakia'; admins = @('Czech Republic', 'Slovakia')
        fillColor = '#4a8c8a'; borderColor = '#2e5e5c'; leader = 'Tomas G. Masaryk'
        info = 'Czechoslovakia declared independence in October 1918, joining the Czech lands and Slovakia. Borders were provisional.'
    },
    [ordered]@{
        realm = 'Kingdom of Serbs, Croats and Slovenes'; label = 'Yugoslavia'
        admins = @('Slovenia', 'Croatia', 'Bosnia and Herzegovina', 'Montenegro', 'Republic of Serbia', 'Kosovo', 'Macedonia')
        fillColor = '#8e6aa8'; borderColor = '#4f3a63'; leader = 'Peter I'
        info = 'The Kingdom of Serbs, Croats and Slovenes was proclaimed in December 1918, uniting Serbia, Montenegro and South Slavic lands of the former Austria-Hungary. Borders were provisional.'
    },
    [ordered]@{
        realm = 'Republic of Poland'; label = 'Poland'; admins = @('Poland')
        fillColor = '#f08080'; borderColor = '#a84646'; leader = 'Jozef Pilsudski (Chief of State)'
        info = 'Poland was restored as an independent state in November 1918. Its borders remained disputed and provisional.'
    },
    [ordered]@{
        realm = 'Kingdom of Romania (Greater Romania)'; label = 'Romania'
        admins = @('Romania', 'Moldova')
        fillColor = '#cc8f6a'; borderColor = '#7a4a32'; leader = 'Ferdinand I'
        info = 'Romania claimed Transylvania and united with Bessarabia in 1918; these borders were not yet internationally settled.'
    },
    [ordered]@{
        realm = 'Kingdom of Italy (Former Austrian Lands)'; label = ''
        admins = @('Italy'); ids = @('trentino-southtyrol', 'trentino', 'gorizia', 'trieste')
        fillColor = '#5fa07e'; borderColor = '#2f5e46'; leader = 'Victor Emmanuel III'
        info = 'Italian forces occupied Trentino, South Tyrol, Gorizia and Trieste in November 1918; formal borders were settled later.'
    },
    [ordered]@{
        realm = 'France (Alsace-Lorraine)'; label = ''
        admins = @('France'); ids = @('bas-rhin', 'haut-rhin', 'moselle')
        fillColor = '#4169a1'; borderColor = '#203b61'; leader = 'Raymond Poincare (President)'
        info = 'France resumed control of Alsace-Lorraine after the German armistice in November 1918.'
    },
    [ordered]@{
        realm = 'Finland'; label = 'Finland'; admins = @('Finland')
        fillColor = '#ffffff'; borderColor = '#8a8576'; leader = 'Carl Gustaf Emil Mannerheim (Regent)'
        info = 'Finland declared independence from Russia in December 1917. The proposed Finnish king abdicated in December 1918, leaving Mannerheim as regent.'
    },
    [ordered]@{
        realm = 'Republic of Estonia'; label = 'Estonia'; admins = @('Estonia')
        fillColor = '#547f9d'; borderColor = '#2e4d60'; leader = 'Konstantin Pats'
        info = 'Estonia had declared independence in February 1918, although foreign troops and the ensuing War of Independence made control contested.'
    },
    [ordered]@{
        realm = 'Republic of Latvia'; label = 'Latvia'; admins = @('Latvia')
        fillColor = '#8466a6'; borderColor = '#4f3a65'; leader = 'Karlis Ulmanis'
        info = 'Latvia declared independence in November 1918. German forces and the ongoing War of Independence made control contested.'
    },
    [ordered]@{
        realm = 'Republic of Lithuania'; label = 'Lithuania'; admins = @('Lithuania')
        fillColor = '#ffeb00'; borderColor = '#8a7600'; leader = 'Antanas Smetona'
        info = 'Lithuania declared independence in February 1918; German occupation and subsequent fighting left control contested.'
    },
    [ordered]@{
        realm = 'Ukrainian People''s Republic'; label = 'Ukraine'; admins = @('Ukraine')
        fillColor = '#d6b55d'; borderColor = '#8a7030'; leader = 'Symon Petliura'
        info = 'The Ukrainian People''s Republic was restored in December 1918 after the Hetmanate fell. Its territory was contested in the civil war.'
    },
    [ordered]@{
        realm = 'Democratic Republic of Georgia'; label = 'Georgia'; admins = @('Georgia')
        fillColor = '#ad735a'; borderColor = '#684436'; leader = 'Noe Zhordania'
        info = 'Georgia declared independence in May 1918 after the collapse of the Russian Empire.'
    },
    [ordered]@{
        realm = 'First Republic of Armenia'; label = 'Armenia'; admins = @('Armenia')
        fillColor = '#bb7878'; borderColor = '#734949'; leader = 'Hovhannes Katchaznouni'
        info = 'The First Republic of Armenia declared independence in May 1918 amid war and disputed borders.'
    },
    [ordered]@{
        realm = 'Azerbaijan Democratic Republic'; label = 'Azerbaijan'; admins = @('Azerbaijan')
        fillColor = '#5f9a79'; borderColor = '#345c48'; leader = 'Fatali Khan Khoyski'
        info = 'The Azerbaijan Democratic Republic declared independence in May 1918; its borders remained contested.'
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
foreach ($state in $states) {
    $hasSpecificIds = $state.Contains('ids')
    $stateIds = @()
    if ($hasSpecificIds) { $stateIds = @($state.ids) }
    foreach ($feature in $features) {
        $matchesState = $state.admins -contains $feature.admin
        if ($hasSpecificIds -and $stateIds -notcontains $feature.id) { $matchesState = $false }
        if (-not $matchesState) { continue }

        $owners = @($realms | Where-Object { Test-FeatureMatch $_ $feature })
        if ($owners.Count -gt 1) {
            throw "1914 overlap for $($feature.admin)/$($feature.id): $($owners.realm -join ', ')."
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
        [void]$filters.Add($filter)
    }
    [void]$additions.Add([ordered]@{
        provinces = @()
        properties = [ordered]@{
            realm = $state.realm
            label = $state.label
            leader = $state.leader
            regionFilters = $filters
            fillColor = $state.fillColor
            borderColor = $state.borderColor
            info = $state.info
        }
    })
}

foreach ($oldOwner in $changedOwners.Keys) {
    $realm = $realms | Where-Object { $_.realm -eq $oldOwner } | Select-Object -First 1
    if (-not $realm) { throw "No 1914 realm found for territory transfer from $oldOwner." }
    $override = Get-Override $oldOwner
    $excluded = @($realm.props.excludeIds) + @($changedOwners[$oldOwner])
    $override.properties.excludeIds = @($excluded | Select-Object -Unique)
}

foreach ($realm in $realms) {
    $oldName = $realm.realm
    $newName = $oldName
    $label = [string]$realm.props.label
    if ($oldName -eq 'German Empire') {
        $newName = 'German Republic'
        $label = 'Germany'
    } elseif ($oldName.StartsWith('German Empire (')) {
        $newName = $oldName.Replace('German Empire', 'German Republic')
    } elseif ($oldName -eq 'Russian Empire') {
        $newName = 'Russian SFSR'
        $label = 'Russia'
    } elseif ($oldName.StartsWith('Russian Empire (')) {
        $newName = $oldName.Replace('Russian Empire', 'Russian SFSR')
    }

    $override = Get-Override $oldName
    if ($newName -ne $oldName) { $override.properties.realm = $newName }
    if ($label -ne [string]$realm.props.label) { $override.properties.label = $label }
    $override.properties.leader = Get-Leader $newName
    $override.properties.info = "$newName at the end of 1918. Boundaries and territorial control remained unsettled after the First World War."
    if ($newName -eq 'Russian SFSR' -or $newName.StartsWith('Russian SFSR (')) {
        $override.properties.fillColor = '#5a0b16'
        $override.properties.borderColor = '#2e050a'
    }
}

$romaniaOverride = Get-Override 'Kingdom of Romania'
$romaniaOverride.properties.label = ''

$block = [ordered]@{
    baseYear = 1914
    note = 'Europe at the end of 1918 after the Armistice: the German and Austro-Hungarian empires have collapsed, Poland and several successor states have emerged, and borders remain provisional or contested. Modern administrative regions are approximate territorial proxies.'
    overrides = $overrides
    additions = $additions
}
$json = ConvertTo-Json $block -Depth 20
$json = $json -replace '\\u0027', "'"
$fragmentPath = Join-Path $PSScriptRoot 'frag1918.json'
[IO.File]::WriteAllText($fragmentPath, $json, (New-Object Text.UTF8Encoding($false)))
Write-Host "1918 fragment generated: $($overrides.Count) overrides, $($additions.Count) additions."

if ($Insert) {
    $text = [IO.File]::ReadAllText($yearsPath, [Text.Encoding]::UTF8)
    $lastBrace = $text.LastIndexOf('}')
    if ($lastBrace -lt 0) { throw 'Could not find the end of years.json.' }
    $yearMarker = $text.LastIndexOf('"1918"')
    if ($yearMarker -ge 0) {
        $comma = $text.LastIndexOf(',', $yearMarker)
        if ($comma -lt 0) { throw 'Could not locate the existing 1918 year entry.' }
        $updated = $text.Substring(0, $comma) + ",`r`n  `"1918`": $json`r`n}"
    } else {
        $insertText = ",`r`n  `"1918`": $json`r`n"
        $updated = $text.Substring(0, $lastBrace).TrimEnd() + $insertText + '}'
    }
    [IO.File]::WriteAllText($yearsPath, $updated, (New-Object Text.UTF8Encoding($false)))
    Write-Host 'Inserted year 1918 after the final year.'
}
