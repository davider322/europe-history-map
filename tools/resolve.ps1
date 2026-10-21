param([string]$Year = "1200", [string]$Mode = "list", [string]$Admin = "")
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$root = "c:\Users\David\Documents\World Map\data"
$db = Get-Content "$root\years.json" -Raw -Encoding UTF8 | ConvertFrom-Json

function Get-Realms($y) {
    $cfg = $db.$y
    if ($cfg.countries) {
        $list = @()
        foreach ($c in $cfg.countries) {
            $f = Get-Content "c:\Users\David\Documents\World Map\$($c.file)" -Raw -Encoding UTF8 | ConvertFrom-Json
            $props = @{}
            $f.properties.PSObject.Properties | ForEach-Object { $props[$_.Name] = $_.Value }
            $list += [pscustomobject]@{ realm = $f.properties.realm; provinces = @($f.provinces); props = $props }
        }
        return $list
    }
    $base = Get-Realms ([string]$cfg.baseYear)
    $map = [ordered]@{}
    foreach ($r in $base) { $map[$r.realm] = $r }
    foreach ($on in $cfg.overrides.PSObject.Properties.Name) {
        if (-not $map.Contains($on)) { Write-Host "UNKNOWN OVERRIDE $on in $y"; continue }
        $o = $cfg.overrides.$on
        $r = $map[$on]
        if ($null -ne $o.provinces) { $r.provinces = @($o.provinces) }
        if ($o.properties) { $o.properties.PSObject.Properties | ForEach-Object { $r.props[$_.Name] = $_.Value } }
        $newName = $r.props["realm"]
        if ($newName -and $newName -ne $on) { $r.realm = $newName; $map.Remove($on); $map[$newName] = $r }
    }
    $res = @($map.Values)
    foreach ($a in $cfg.additions) {
        $props = @{}
        $a.properties.PSObject.Properties | ForEach-Object { $props[$_.Name] = $_.Value }
        $res += [pscustomobject]@{ realm = $a.properties.realm; provinces = @($a.provinces); props = $props }
    }
    return $res
}

$realms = Get-Realms $Year
if ($Mode -eq "list") {
    foreach ($r in $realms) {
        $rf = $r.props["regionFilters"]
        $fs = ""
        if ($rf) {
            $fs = ($rf | ForEach-Object {
                $s = "admin=" + $_.admin
                if ($_.geonunit) { $s += " geo=" + $_.geonunit }
                if ($_.ids) { $s += " ids=" + $_.ids.Count }
                if ($_.excludeIds) { $s += " excl=" + $_.excludeIds.Count }
                $s }) -join " | "
        }
        "{0} :: prov={1} :: {2}" -f $r.realm, $r.provinces.Count, $fs
    }
}
if ($Mode -eq "check" -or $Mode -eq "assign" -or $Mode -eq "summary") {
    $feats = @()
    foreach ($f in "europe-provinces","europe-kosovo","europe-small-islands","middle-east-caucasus-provinces","europe-microstates","europe-historical-regions") {
        $g = Get-Content "$root\$f.geojson" -Raw -Encoding UTF8 | ConvertFrom-Json
        $feats += $g.features.properties
    }
    $over = @{}; $none = @(); $sum=@{}
    foreach ($p in $feats) {
        $m = @()
        foreach ($r in $realms) {
            $hit = $false
            if ($r.provinces -contains $p.id) { $ra = $r.props["regionAdmins"]; if (-not $ra -or ($ra -contains $p.admin)) { $hit = $true } }
            $rf = $r.props["regionFilters"]
            if (-not $hit -and $rf) {
                foreach ($f in $rf) {
                    $ok = $true
                    if ($f.admin -and $f.admin -ne $p.admin) { $ok = $false }
                    if ($f.geonunit -and $f.geonunit -ne $p.geonunit) { $ok = $false }
                    if ($f.ids -and ($f.ids -notcontains $p.id)) { $ok = $false }
                    if ($f.excludeIds -and ($f.excludeIds -contains $p.id)) { $ok = $false }
                    if ($ok) { $hit = $true; break }
                }
            }
            $rx = $r.props["excludeIds"]; if ($hit -and $rx -and ($rx -contains $p.id)) { $hit = $false }
            if ($hit) { $m += $r.realm }
        }
        if ($Mode -eq "summary") { $k="$($p.admin) => $($m -join ' / ')"; $sum[$k]=1+[int]$sum[$k]; continue }
        if ($Mode -eq "assign") { if ($p.admin -eq $Admin) { "$($p.id) | $($p.geonunit) => $($m -join ' / ')" }; continue }
        if ($m.Count -gt 1) { "OVERLAP $($p.id): $($m -join ' / ')" }
        if ($m.Count -eq 0) { $none += $p.id }
    }
    if ($Mode -eq "summary") { $sum.GetEnumerator() | Sort-Object Name | ForEach-Object { "$($_.Name) [$($_.Value)]" } }
    if ($Mode -eq "check") { "unassigned: $($none.Count)"
    $none -join ", " }
}



if ($Mode -eq "dump") {
    foreach ($r in $realms) {
        $rf = $r.props["regionFilters"]
        "== $($r.realm) | provinces: " + ($r.provinces -join ',')
        if ($rf) { $rf | ConvertTo-Json -Depth 6 -Compress }
    }
}


if ($Mode -eq "props") {
    foreach ($r in $realms) {
        $ra = $r.props["regionAdmins"]
        "{0} | fill={1} | border={2} | label={3} | admins={4} | leader={5}" -f $r.realm, $r.props["fillColor"], $r.props["borderColor"], $r.props["label"], ($ra -join ","), $r.props["leader"]
    }
}
