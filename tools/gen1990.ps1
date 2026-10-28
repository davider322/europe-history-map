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

function Get-Override([string]$name) {
    if (-not $script:overrides.Contains($name)) {
        $script:overrides[$name] = [ordered]@{ properties = [ordered]@{} }
    }
    return $script:overrides[$name]
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

$realms = @(Get-Realms '1955')
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
foreach ($realm in $realms) {
    $override = Get-Override $realm.realm
    $override.properties.leader = 'National government'
    $override.properties.info = "$($realm.realm) at the end of 1990."
}

$germanIds = @($features | Where-Object { $_.admin -eq 'Germany' } | ForEach-Object { $_.id })
if ($germanIds.Count -ne 16) { throw "Expected 16 German map regions, found $($germanIds.Count)." }

$eastGermany = $realms | Where-Object { $_.realm -eq 'German Democratic Republic' } | Select-Object -First 1
$westGermany = $realms | Where-Object { $_.realm -eq 'Federal Republic of Germany' } | Select-Object -First 1
$saar = $realms | Where-Object { $_.realm -eq 'Saar Protectorate' } | Select-Object -First 1
if (-not $eastGermany -or -not $westGermany -or -not $saar) {
    throw 'Could not find the 1955 German states to unify.'
}

$eastOverride = Get-Override $eastGermany.realm
$eastOverride.provinces = @()
$eastOverride.properties.label = ''
$eastOverride.properties.regionFilters = @()
$eastOverride.properties.excludeIds = @()
$eastOverride.properties.info = 'The German Democratic Republic acceded to the Federal Republic of Germany on 3 October 1990.'

$westOverride = Get-Override $westGermany.realm
$westOverride.provinces = @()
$westOverride.properties.realm = 'Federal Republic of Germany'
$westOverride.properties.label = 'Germany'
$westOverride.properties.leader = 'Helmut Kohl (Federal Chancellor)'
$westOverride.properties.info = 'Germany was reunified on 3 October 1990, when the German Democratic Republic acceded to the Federal Republic. Berlin is shown as one region because the available map data has no separate city sectors.'
$westOverride.properties.regionFilters = @([ordered]@{ admin = 'Germany'; ids = $germanIds })
$westOverride.properties.excludeIds = @()
$westOverride.properties.fillColor = '#8b8f9e'
$westOverride.properties.borderColor = '#4c4f5c'

$saarOverride = Get-Override $saar.realm
$saarOverride.provinces = @()
$saarOverride.properties.label = ''
$saarOverride.properties.regionFilters = @()
$saarOverride.properties.excludeIds = @()
$saarOverride.properties.leader = 'Former protectorate'
$saarOverride.properties.info = 'The Saar Protectorate had joined the Federal Republic of Germany in 1957.'

foreach ($realm in $realms | Where-Object { $_.realm -like 'Soviet Union*' }) {
    $override = Get-Override $realm.realm
    $override.properties.leader = 'Mikhail Gorbachev (President)'
    $override.properties.info = "$($realm.realm) within the Soviet Union at the end of 1990."
}

$yearSpecific = @(
    [ordered]@{
        name = 'Soviet Union'
        leader = 'Mikhail Gorbachev (President)'
        info = 'The Soviet Union remained intact at the end of 1990, although several republics had declared sovereignty.'
    },
    [ordered]@{
        name = 'Polish People''s Republic'
        realm = 'Republic of Poland'
        label = 'Poland'
        leader = 'Lech Walesa (President-elect)'
        info = 'Poland had completed its transition to a multiparty democracy. Lech Walesa was elected president in December 1990.'
    },
    [ordered]@{
        name = 'Hungarian People''s Republic'
        realm = 'Republic of Hungary'
        label = 'Hungary'
        leader = 'Arpad Goncz (President)'
        info = 'Hungary became a multiparty republic in 1989 and held free parliamentary elections in 1990.'
    },
    [ordered]@{
        name = 'People''s Republic of Bulgaria'
        realm = 'Republic of Bulgaria'
        label = 'Bulgaria'
        leader = 'Zhelyu Zhelev (President)'
        info = 'Bulgaria began its transition from communist rule in 1989; the state became the Republic of Bulgaria in 1990.'
    },
    [ordered]@{
        name = 'Kingdom of Romania (Greater Romania)'
        realm = 'Romania'
        label = 'Romania'
        leader = 'Ion Iliescu (President)'
        info = 'The Romanian Revolution overthrew the communist government in December 1989. Ion Iliescu was elected president in 1990.'
    },
    [ordered]@{
        name = 'Czechoslovakia'
        leader = 'Vaclav Havel (President)'
        info = 'The Velvet Revolution ended communist rule in 1989. Czechoslovakia remained a single state at the end of 1990.'
    },
    [ordered]@{
        name = 'Federal People''s Republic of Yugoslavia'
        realm = 'Socialist Federal Republic of Yugoslavia'
        label = 'Yugoslavia'
        leader = 'Ante Markovic (Prime Minister)'
        info = 'Yugoslavia remained a federation at the end of 1990, though its constituent republics were moving toward independence.'
    },
    [ordered]@{
        name = 'United Kingdom'
        leader = 'John Major (Prime Minister)'
        info = 'The United Kingdom at the end of 1990.'
    },
    [ordered]@{
        name = 'France'
        leader = 'Francois Mitterrand (President)'
        info = 'France at the end of 1990.'
    },
    [ordered]@{
        name = 'Republic of Austria'
        leader = 'Kurt Waldheim (President)'
        info = 'Austria remained a sovereign, permanently neutral republic.'
    },
    [ordered]@{
        name = 'German Democratic Republic'
        leader = 'Former state'
        info = 'The German Democratic Republic acceded to the Federal Republic of Germany on 3 October 1990.'
    },
    [ordered]@{
        name = 'Saar Protectorate'
        leader = 'Former protectorate'
        info = 'The Saar Protectorate had joined the Federal Republic of Germany in 1957.'
    }
)
foreach ($state in $yearSpecific) {
    $realm = $realms | Where-Object { $_.realm -eq $state.name } | Select-Object -First 1
    if (-not $realm) { throw "Expected realm not found for 1990 update: $($state.name)." }
    $override = Get-Override $state.name
    foreach ($property in $state.Keys) {
        if ($property -eq 'name') { continue }
        $override.properties[$property] = $state[$property]
    }
}

$inactiveNorthAfricanRealms = @(
    [ordered]@{
        name = 'France (Africa)'
        info = 'French rule over Algeria and the Tunisian protectorate had ended before 1990.'
    },
    [ordered]@{
        name = 'Kingdom of Libya'
        info = 'Libya had been independent since 1951; the 1990 map uses its own state entry.'
    },
    [ordered]@{
        name = 'Republic of Egypt'
        info = 'Egypt had been an independent republic since 1953; the former British base presence ended in 1956.'
    },
    [ordered]@{
        name = 'Spanish Sahara'
        info = 'Spain withdrew from Western Sahara in 1975. Its status remained disputed at the end of 1990.'
    },
    [ordered]@{
        name = 'Saharan Frontier and Tribal Lands'
        info = 'No separate Saharan frontier territory is represented by the available regional boundaries in 1990.'
    }
)
foreach ($state in $inactiveNorthAfricanRealms) {
    $realm = $realms | Where-Object { $_.realm -eq $state.name } | Select-Object -First 1
    if (-not $realm) { throw "Expected North African predecessor realm not found: $($state.name)." }
    $override = Get-Override $state.name
    $override.provinces = @()
    $override.properties.label = ''
    $override.properties.leader = 'Former state or administration'
    $override.properties.info = $state.info
    $override.properties.regionFilters = @()
    $override.properties.excludeIds = @()
}

$morocco = $realms | Where-Object { $_.realm -eq 'Alaouite Sultanate' } | Select-Object -First 1
if (-not $morocco) { throw 'Expected Alaouite Sultanate predecessor not found.' }
$moroccoIds = @($features | Where-Object { $_.admin -eq 'Morocco' } | ForEach-Object { [string]$_.id })
if ($moroccoIds.Count -ne 16) { throw "Expected 16 Moroccan map regions, found $($moroccoIds.Count)." }
$moroccoOverride = Get-Override $morocco.realm
$moroccoOverride.provinces = @()
$moroccoOverride.properties.realm = 'Kingdom of Morocco'
$moroccoOverride.properties.label = 'Morocco'
$moroccoOverride.properties.leader = 'Hassan II (King)'
$moroccoOverride.properties.info = 'Morocco was independent under King Hassan II. It administered most of Western Sahara, whose sovereignty was disputed by the Sahrawi Arab Democratic Republic and the Polisario Front. Available modern administrative regions cannot show the separation line or the Sahrawi-controlled area.'
$moroccoOverride.properties.regionFilters = @([ordered]@{ admin = 'Morocco'; ids = $moroccoIds })
$moroccoOverride.properties.excludeIds = @()

$northAfricanStates = @(
    [ordered]@{
        realm = 'Algeria'; label = 'Algeria'; admin = 'Algeria'
        leader = 'Chadli Bendjedid (President)'
        info = 'Algeria had been independent since 1962. President Chadli Bendjedid remained in office at the end of 1990.'
        fill = '#4169a1'; border = '#203b61'
    },
    [ordered]@{
        realm = 'Tunisia'; label = 'Tunisia'; admin = 'Tunisia'
        leader = 'Zine El Abidine Ben Ali (President)'
        info = 'Tunisia had been independent since 1956. Zine El Abidine Ben Ali had been president since 1987.'
        fill = '#4169a1'; border = '#203b61'
    },
    [ordered]@{
        realm = 'Libya'; label = 'Libya'; admin = 'Libya'
        leader = 'Muammar Gaddafi (Leader)'
        info = 'Libya was an independent state under Muammar Gaddafi.'
        fill = '#5fa07e'; border = '#2f5e46'
    },
    [ordered]@{
        realm = 'Egypt'; label = 'Egypt'; admin = 'Egypt'
        leader = 'Hosni Mubarak (President)'
        info = 'Egypt was an independent republic under President Hosni Mubarak.'
        fill = '#d08a86'; border = '#7a4a48'
    }
)
foreach ($state in $northAfricanStates) {
    if (@($realms | Where-Object { $_.realm -eq $state.realm }).Count -gt 0) {
        throw "North African state $($state.realm) already exists in the 1955 base."
    }
    $ids = @($features | Where-Object { $_.admin -eq $state.admin } | ForEach-Object { [string]$_.id })
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
    baseYear = 1955
    note = 'Europe and North Africa at the end of 1990. Algeria, Tunisia, Libya and Egypt are independent states; Morocco administers most of Western Sahara, whose status remained disputed. Germany was reunified on 3 October, while the Soviet Union remained intact. Borders use available administrative regions and cannot show the Sahrawi-controlled area or the separation line.'
    overrides = $overrides
    additions = @($additions.ToArray())
}
$json = ConvertTo-Json $block -Depth 20
$json = $json -replace '\\u0027', "'"
$fragmentPath = Join-Path $PSScriptRoot 'frag1990.json'
[IO.File]::WriteAllText($fragmentPath, $json, (New-Object Text.UTF8Encoding($false)))
Write-Host "1990 fragment generated: $($overrides.Count) overrides."

if ($Insert) {
    $text = [IO.File]::ReadAllText($yearsPath, [Text.Encoding]::UTF8)
    $updated = Set-YearEntry $text '1990' $json
    [IO.File]::WriteAllText($yearsPath, $updated, (New-Object Text.UTF8Encoding($false)))
    Write-Host 'Inserted or updated year 1990 in years.json.'
}
