param([switch]$Insert)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$dataRoot = Join-Path $root 'data'
$yearsPath = Join-Path $dataRoot 'years.json'
$db = Get-Content -LiteralPath $yearsPath -Raw -Encoding UTF8 | ConvertFrom-Json

function Get-Realms([string]$year) {
    $config = $db.$year
    if (-not $config) { throw "No data for base year $year." }
    if ($config.countries) {
        $result = @()
        foreach ($country in $config.countries) {
            $path = Join-Path $root $country.file
            $feature = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
            $properties = [ordered]@{}
            foreach ($property in $feature.properties.PSObject.Properties) {
                $properties[$property.Name] = $property.Value
            }
            $result += [pscustomobject]@{
                realm = $feature.properties.realm
                provinces = @($feature.provinces)
                props = $properties
            }
        }
        return $result
    }

    $map = [ordered]@{}
    foreach ($realm in (Get-Realms ([string]$config.baseYear))) {
        $map[$realm.realm] = $realm
    }
    foreach ($oldName in $config.overrides.PSObject.Properties.Name) {
        if (-not $map.Contains($oldName)) {
            throw "Year $year overrides unknown realm $oldName."
        }
        $realm = $map[$oldName]
        $override = $config.overrides.$oldName
        if ($null -ne $override.provinces) {
            $realm.provinces = @($override.provinces)
        }
        if ($override.properties) {
            foreach ($property in $override.properties.PSObject.Properties) {
                $realm.props[$property.Name] = $property.Value
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
    foreach ($addition in $config.additions) {
        $properties = [ordered]@{}
        foreach ($property in $addition.properties.PSObject.Properties) {
            $properties[$property.Name] = $property.Value
        }
        $result += [pscustomobject]@{
            realm = $addition.properties.realm
            provinces = @($addition.provinces)
            props = $properties
        }
    }
    return $result
}

function Test-FeatureMatch($realm, $feature) {
    $hit = $realm.provinces -contains $feature.id
    if ($hit -and $realm.props.regionAdmins -and
        $feature.admin -notin $realm.props.regionAdmins) {
        $hit = $false
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
    if ($hit -and $realm.props.excludeIds -and $feature.id -in $realm.props.excludeIds) {
        $hit = $false
    }
    return $hit
}

function Get-YearEntry([string]$text, [string]$year, [string]$json) {
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
        return $text.Substring(0, $match.Index) +
            "  `"$year`": $json" + $text.Substring($end)
    }

    $lastBrace = $text.LastIndexOf('}')
    if ($lastBrace -lt 0) { throw 'Could not find the end of years.json.' }
    return $text.Substring(0, $lastBrace).TrimEnd() +
        ",`r`n  `"$year`": $json`r`n}"
}

$leaderByRealm = @{
    'Denmark' = 'Margrethe II (Queen)'
    'Norway' = 'Harald V (King)'
    'Andorra' = 'Joan Enric Vives i Sicilia and Emmanuel Macron (Co-Princes)'
    'San Marino' = 'Alessandro Cardelli and Grazia Zafferani (Captains Regent)'
    'Monaco' = 'Albert II (Prince)'
    'Sweden' = 'Stefan Lofven (Prime Minister)'
    'Netherlands' = 'Mark Rutte (Prime Minister)'
    'Switzerland' = 'Simonetta Sommaruga (President)'
    'France' = 'Emmanuel Macron (President)'
    'United Kingdom' = 'Elizabeth II (Queen)'
    'Belgium' = 'Philippe (King)'
    'Luxembourg' = 'Henri (Grand Duke)'
    'Liechtenstein' = 'Hans-Adam II (Prince)'
    'Finland' = 'Sauli Niinisto (President)'
    'Romania' = 'Klaus Iohannis (President)'
    'Algeria' = 'Abdelmadjid Tebboune (President)'
    'Tunisia' = 'Kais Saied (President)'
    'Libya' = 'Fayez al-Sarraj (Prime Minister and Chairman of the Presidential Council)'
    'Egypt' = 'Abdel Fattah el-Sisi (President)'
    'Albania' = 'Ilir Meta (President)'
    'Armenia' = 'Armen Sarkissian (President)'
    'Austria' = 'Alexander Van der Bellen (President)'
    'Azerbaijan' = 'Ilham Aliyev (President)'
    'Bahrain' = 'Hamad bin Isa Al Khalifa (King)'
    'Belarus' = 'Alexander Lukashenko (President)'
    'Bosnia and Herzegovina' = 'Milorad Dodik (Chair of the Presidency)'
    'Bulgaria' = 'Rumen Radev (President)'
    'Croatia' = 'Zoran Milanovic (President)'
    'Cyprus' = 'Nicos Anastasiades (President)'
    'Czech Republic' = 'Milos Zeman (President)'
    'Estonia' = 'Kersti Kaljulaid (President)'
    'Federal Republic of Yugoslavia' = 'Aleksandar Vucic (President)'
    'Georgia' = 'Salome Zourabichvili (President)'
    'Germany' = 'Frank-Walter Steinmeier (President)'
    'Greece' = 'Katerina Sakellaropoulou (President)'
    'Hungary' = 'Janos Ader (President)'
    'Iceland' = 'Gudni Th. Johannesson (President)'
    'Iran' = 'Ali Khamenei (Supreme Leader)'
    'Iraq' = 'Barham Salih (President)'
    'Ireland' = 'Michael D. Higgins (President)'
    'Israel' = 'Reuven Rivlin (President)'
    'Italy' = 'Sergio Mattarella (President)'
    'Jordan' = 'Abdullah II (King)'
    'Kosovo under UN administration' = 'Vjosa Osmani (Acting President)'
    'Latvia' = 'Egils Levits (President)'
    'Lebanon' = 'Michel Aoun (President)'
    'Lithuania' = 'Gitanas Nauseda (President)'
    'Malta' = 'George Vella (President)'
    'Moldova' = 'Maia Sandu (President)'
    'Morocco' = 'Mohammed VI (King)'
    'Palestinian National Authority' = 'Mahmoud Abbas (President)'
    'Poland' = 'Andrzej Duda (President)'
    'Portugal' = 'Marcelo Rebelo de Sousa (President)'
    'Republic of Macedonia' = 'Stevo Pendarovski (President)'
    'Russian Federation' = 'Vladimir Putin (President)'
    'Saudi Arabia' = 'Salman bin Abdulaziz Al Saud (King)'
    'Slovakia' = 'Zuzana Caputova (President)'
    'Slovenia' = 'Borut Pahor (President)'
    'Spain' = 'Felipe VI (King)'
    'Syria' = 'Bashar al-Assad (President)'
    'Turkey' = 'Recep Tayyip Erdogan (President)'
    'Ukraine' = 'Volodymyr Zelenskyy (President)'
}

$features = @()
foreach ($file in @(
    'europe-provinces.geojson',
    'europe-kosovo.geojson',
    'europe-small-islands.geojson',
    'middle-east-caucasus-provinces.geojson',
    'europe-microstates.geojson',
    'europe-historical-regions.geojson',
    'europe-pomerania-1700.geojson'
)) {
    $geo = Get-Content -LiteralPath (Join-Path $dataRoot $file) -Raw -Encoding UTF8 |
        ConvertFrom-Json
    $features += @($geo.features | ForEach-Object { $_.properties })
}

$realms = @(Get-Realms '2000')
$activeNames = @{}
foreach ($feature in $features) {
    if ($feature.activeYears -and $feature.activeYears -notcontains '2000') { continue }
    if ($feature.inactiveYears -and $feature.inactiveYears -contains '2000') { continue }
    $owners = @($realms | Where-Object { Test-FeatureMatch $_ $feature })
    if ($owners.Count -gt 1) {
        throw "Overlapping 2000 owners for $($feature.id): $(($owners.realm) -join ', ')."
    }
    if ($owners.Count -eq 1) {
        $activeNames[$owners[0].realm] = $true
    }
}

$overrides = [ordered]@{}
foreach ($realm in $realms) {
    if (-not $activeNames.ContainsKey($realm.realm)) { continue }
    if (-not $leaderByRealm.ContainsKey($realm.realm)) {
        throw "No 2020 leader has been defined for active realm $($realm.realm)."
    }
    $info = "$($realm.realm) at the end of 2020. Boundaries use available administrative regions as approximate map units."
    if ($realm.realm -eq 'Ireland') {
        $info = 'Ireland was an independent republic at the end of 2020.'
    } elseif ($realm.realm -eq 'United Kingdom') {
        $info = 'The United Kingdom at the end of 2020, including Scotland as a constituent country.'
    }
    $overrides[$realm.realm] = [ordered]@{
        properties = [ordered]@{
            leader = $leaderByRealm[$realm.realm]
            info = $info
        }
    }
}

$serbia = $overrides['Federal Republic of Yugoslavia']
$serbia.properties.realm = 'Serbia'
$serbia.properties.label = 'Serbia'
$serbia.properties.leader = 'Aleksandar Vucic (President)'
$serbia.properties.info = 'Serbia was independent from Montenegro after their 2006 separation. Kosovo declared independence in 2008; Serbia did not recognize it. The map shows Kosovo separately and uses modern administrative boundaries.'
$serbia.properties.fillColor = '#8e6aa8'
$serbia.properties.borderColor = '#4f3a63'
$serbia.properties.regionFilters = @(
    [ordered]@{
        admin = 'Republic of Serbia'
        ids = @($features | Where-Object { $_.admin -eq 'Republic of Serbia' } |
            ForEach-Object { [string]$_.id } | Sort-Object -Unique)
    }
)
$serbia.properties.excludeIds = @()

$montenegroIds = @($features | Where-Object { $_.admin -eq 'Montenegro' } |
    ForEach-Object { [string]$_.id } | Sort-Object -Unique)
if ($montenegroIds.Count -eq 0) { throw 'No mapped regions found for Montenegro.' }

$kosovo = $overrides['Kosovo under UN administration']
$kosovo.properties.realm = 'Kosovo'
$kosovo.properties.label = 'Kosovo'
$kosovo.properties.leader = 'Vjosa Osmani (Acting President)'
$kosovo.properties.info = 'Kosovo declared independence in 2008 and was governed by its own institutions at the end of 2020. Its status was not universally recognized; the map uses the available Kosovo boundary data.'
$kosovo.properties.fillColor = '#d6b55d'
$kosovo.properties.borderColor = '#8a7030'

$northMacedonia = $overrides['Republic of Macedonia']
$northMacedonia.properties.realm = 'North Macedonia'
$northMacedonia.properties.label = 'North Macedonia'
$northMacedonia.properties.leader = 'Stevo Pendarovski (President)'
$northMacedonia.properties.info = 'The country adopted the name North Macedonia in 2019 under the Prespa Agreement.'

$modernColors = @{
    'Albania' = @('#d18a4a', '#744923')
    'Bosnia and Herzegovina' = @('#557b9b', '#314b61')
    'Croatia' = @('#c0504d', '#6e2927')
    'Serbia' = @('#c2ad83', '#756547')
    'Montenegro' = @('#641f35', '#35101c')
    'Kosovo' = @('#4b83c6', '#2d4d75')
    'North Macedonia' = @('#d6b55d', '#8a7030')
    'Slovenia' = @('#5f9ea0', '#2f5e60')
    'Slovakia' = @('#d9894a', '#75451f')
}
foreach ($overrideKey in $overrides.Keys) {
    $override = $overrides[$overrideKey]
    $realmName = if ($override.properties.realm) {
        $override.properties.realm
    } else {
        $overrideKey
    }
    if ($modernColors.ContainsKey($realmName)) {
        $override.properties.fillColor = $modernColors[$realmName][0]
        $override.properties.borderColor = $modernColors[$realmName][1]
    }
}

$specialInfo = @{
    'Ukraine' = 'Ukraine remained internationally recognized within its borders, including Crimea, which Russia had occupied and claimed to annex since 2014. The map cannot show the frontline in eastern Ukraine.'
    'Morocco' = 'Morocco administered most of Western Sahara at the end of 2020, while the Sahrawi Arab Democratic Republic and Polisario Front maintained a competing claim. Available administrative boundaries cannot show the separation line or areas of control.'
    'Libya' = 'Libya remained divided amid civil conflict. Fayez al-Sarraj headed the internationally recognized Government of National Accord; the map uses whole administrative regions and cannot show the fragmented front lines.'
    'Palestinian National Authority' = 'The Palestinian Authority administered parts of the West Bank, while Hamas governed Gaza. The mapped regions are broad approximations and do not represent the complex boundaries of control.'
    'Cyprus' = 'The Republic of Cyprus controlled the south of the island; the north was administered by the self-declared Turkish Republic of Northern Cyprus, recognized only by Turkey. The island is divided using the available administrative regions.'
    'Moldova' = 'Moldova remained internationally recognized within its borders, while Transnistria continued to function as a de facto separate administration. The map cannot show this internal division.'
    'Bosnia and Herzegovina' = 'Bosnia and Herzegovina retained its post-Dayton structure of two entities and the Brcko District. These internal boundaries are not represented by the available regional map units.'
    'Turkey' = 'Turkey at the end of 2020. The map uses available administrative regions as approximate map units.'
}
foreach ($realmName in $specialInfo.Keys) {
    if ($overrides.Contains($realmName)) {
        $overrides[$realmName].properties.info = $specialInfo[$realmName]
    }
}

$additions = New-Object System.Collections.ArrayList
$newStates = @(
    [ordered]@{
        realm = 'Montenegro'
        label = 'Montenegro'
        leader = 'Milo Djukanovic (President)'
        info = 'Montenegro became independent from Serbia in 2006. The map uses its modern administrative regions.'
        admin = 'Montenegro'
        ids = $montenegroIds
        fill = '#641f35'
        border = '#35101c'
    },
    [ordered]@{
        realm = 'Kuwait'
        label = 'Kuwait'
        leader = 'Nawaf Al-Ahmad Al-Jaber Al-Sabah (Emir)'
        info = 'Nawaf Al-Ahmad Al-Jaber Al-Sabah became Emir of Kuwait in September 2020.'
        admin = 'Kuwait'
        fill = '#a28b70'
        border = '#695945'
    },
    [ordered]@{
        realm = 'Oman'
        label = 'Oman'
        leader = 'Haitham bin Tariq (Sultan)'
        info = 'Haitham bin Tariq became Sultan of Oman in January 2020.'
        admin = 'Oman'
        fill = '#5f9a79'
        border = '#345c48'
    },
    [ordered]@{
        realm = 'Qatar'
        label = 'Qatar'
        leader = 'Tamim bin Hamad Al Thani (Emir)'
        info = 'Qatar at the end of 2020. Boundaries use available administrative regions as approximate map units.'
        admin = 'Qatar'
        fill = '#9a4a6a'
        border = '#5a2640'
    },
    [ordered]@{
        realm = 'United Arab Emirates'
        label = 'United Arab Emirates'
        leader = 'Khalifa bin Zayed Al Nahyan (President)'
        info = 'The United Arab Emirates at the end of 2020. Boundaries use available administrative regions as approximate map units.'
        admin = 'United Arab Emirates'
        fill = '#557b55'
        border = '#314b36'
    },
    [ordered]@{
        realm = 'Yemen'
        label = 'Yemen'
        leader = 'Abdrabbuh Mansur Hadi (President)'
        info = 'Yemen remained divided by civil war at the end of 2020. The map shows the internationally recognized state outline and cannot represent the changing areas of control.'
        admin = 'Yemen'
        fill = '#d08a86'
        border = '#7a4a48'
    }
)
foreach ($state in $newStates) {
    if ($state.realm -ne 'Montenegro' -and @($realms | Where-Object {
        $_.realm -eq $state.realm -and $activeNames.ContainsKey($_.realm)
    }).Count -gt 0) {
        throw "State $($state.realm) already exists in the 2000 base."
    }
    $ids = @($state.ids)
    if ($state.realm -ne 'Montenegro') {
        $ids = @($features | Where-Object { $_.admin -eq $state.admin } |
            ForEach-Object { [string]$_.id } | Sort-Object -Unique)
    }
    if ($ids.Count -eq 0) { throw "No mapped regions found for $($state.realm)." }
    [void]$additions.Add([ordered]@{
        provinces = @()
        properties = [ordered]@{
            realm = $state.realm
            label = $state.label
            leader = $state.leader
            info = $state.info
            fillColor = $state.fill
            borderColor = $state.border
            regionFilters = @([ordered]@{ admin = $state.admin; ids = $ids })
            excludeIds = @()
        }
    })
}

$block = [ordered]@{
    baseYear = 2000
    note = 'Europe and adjoining mapped regions at the end of 2020. Montenegro had been independent from Serbia since 2006; Kosovo declared independence in 2008, though its status remained disputed; and the country formerly known as the Republic of Macedonia became North Macedonia in 2019. Crimea remained internationally recognized as part of Ukraine but was occupied and claimed by Russia. Western Sahara remained disputed. The map uses modern administrative regions as approximations and cannot show every disputed boundary or area of control.'
    overrides = $overrides
    additions = @($additions.ToArray())
}
$json = ConvertTo-Json $block -Depth 30
$json = $json -replace '\\u0027', "'"
$fragmentPath = Join-Path $PSScriptRoot 'frag2020.json'
[IO.File]::WriteAllText($fragmentPath, $json, (New-Object Text.UTF8Encoding($false)))
Write-Host "2020 fragment generated: $($overrides.Count) overrides, $($additions.Count) additions."

if ($Insert) {
    $text = [IO.File]::ReadAllText($yearsPath, [Text.Encoding]::UTF8)
    $updated = Get-YearEntry $text '2020' $json
    [IO.File]::WriteAllText($yearsPath, $updated, (New-Object Text.UTF8Encoding($false)))
    Write-Host 'Inserted or updated year 2020 in years.json.'
}
