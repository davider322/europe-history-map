param([string]$Out = "frag1815.json", [switch]$Report)
Add-Type -AssemblyName System.Web.Extensions
$ser = New-Object System.Web.Script.Serialization.JavaScriptSerializer
$ser.MaxJsonLength = [int]::MaxValue
$ser.RecursionLimit = 200
$root = "c:\Users\David\Documents\World Map\"
$db = $ser.DeserializeObject([IO.File]::ReadAllText($root + "data\years.json", [Text.Encoding]::UTF8))
$nd = [string][char]0x2013

function New-R($name, $provs, $props) { @{ realm = $name; provinces = @($provs); props = $props } }
function Get-Realms($y) {
    $cfg = $db[$y]
    if ($cfg["countries"]) {
        $list = @()
        foreach ($c in $cfg["countries"]) {
            $f = $ser.DeserializeObject([IO.File]::ReadAllText($root + $c["file"], [Text.Encoding]::UTF8))
            $props = @{}; foreach ($k in $f["properties"].Keys) { $props[$k] = $f["properties"][$k] }
            $list += (New-R $f["properties"]["realm"] $f["provinces"] $props)
        }
        return $list
    }
    $base = Get-Realms ([string]$cfg["baseYear"])
    $map = New-Object System.Collections.Specialized.OrderedDictionary
    foreach ($r in $base) { $map[$r.realm] = $r }
    if ($cfg["overrides"]) {
        foreach ($on in @($cfg["overrides"].Keys)) {
            if (-not $map.Contains($on)) { Write-Host "UNKNOWN OVERRIDE $on"; continue }
            $o = $cfg["overrides"][$on]; $r = $map[$on]
            if ($null -ne $o["provinces"]) { $r.provinces = @($o["provinces"]) }
            if ($o["properties"]) { foreach ($k in $o["properties"].Keys) { $r.props[$k] = $o["properties"][$k] } }
            $nn = $r.props["realm"]
            if ($nn -and $nn -ne $on) {
                $r.realm = $nn
                $new = New-Object System.Collections.Specialized.OrderedDictionary
                foreach ($k in @($map.Keys)) { if ($k -eq $on) { $new[$nn] = $r } else { $new[$k] = $map[$k] } }
                $map = $new
            }
        }
    }
    $res = @($map.Values)
    foreach ($a in $cfg["additions"]) {
        $props = @{}; foreach ($k in $a["properties"].Keys) { $props[$k] = $a["properties"][$k] }
        $res += (New-R $a["properties"]["realm"] $a["provinces"] $props)
    }
    return $res
}

$feats = @()
foreach ($f in "europe-provinces","europe-kosovo","europe-small-islands","middle-east-caucasus-provinces","europe-microstates","europe-historical-regions") {
    $g = $ser.DeserializeObject([IO.File]::ReadAllText($root + "data\$f.geojson", [Text.Encoding]::UTF8))
    foreach ($ft in $g["features"]) { $feats += , $ft["properties"] }
}
$realms = Get-Realms "1800"

$provSets = @{}
foreach ($r in $realms) { $h = New-Object 'System.Collections.Generic.HashSet[string]'; foreach ($i in $r.provinces) { [void]$h.Add([string]$i) }; $provSets[$r.realm] = $h }
$assign = @{}
$multi = 0
for ($i = 0; $i -lt $feats.Count; $i++) {
    $p = $feats[$i]; $m = @()
    foreach ($r in $realms) {
        $hit = $false; $pr = $r.props
        if ($provSets[$r.realm].Contains([string]$p["id"])) { $ra = $pr["regionAdmins"]; if (-not $ra -or ($ra -contains $p["admin"])) { $hit = $true } }
        if (-not $hit -and $pr["regionFilters"]) {
            foreach ($f in $pr["regionFilters"]) {
                $ok = $true
                if ($f["admin"] -and $f["admin"] -ne $p["admin"]) { $ok = $false }
                if ($ok -and $f["geonunit"] -and $f["geonunit"] -ne $p["geonunit"]) { $ok = $false }
                if ($ok -and $f["ids"] -and ($f["ids"] -notcontains $p["id"])) { $ok = $false }
                if ($ok -and $f["excludeIds"] -and ($f["excludeIds"] -contains $p["id"])) { $ok = $false }
                if ($ok) { $hit = $true; break }
            }
        }
        $rx = $pr["excludeIds"]; if ($hit -and $rx -and ($rx -contains $p["id"])) { $hit = $false }
        if ($hit) { $m += $r.realm }
    }
    if ($m.Count -gt 1) { $multi++ }
    if ($m.Count -ge 1) { $assign[$i] = $m[0] }
}
Write-Host "feats $($feats.Count) assigned $($assign.Count) multi $multi"

$S = @{}
function Spec($k, $realm, $label, $fill, $border, $leader, $info) { $script:S[$k] = @{ realm = $realm; label = $label; fill = $fill; border = $border; leader = $leader; info = $info } }
Spec 'GE' 'German Empire' 'German Empire' '#8b8f9e' '#4c4f5c' 'Wilhelm II' 'Germany was unified under Prussian leadership in 1871 and by 1900 was Europe''s leading industrial power; it included Alsace-Lorraine, taken from France.'
Spec 'AH' 'Austria-Hungary' 'Austria-Hungary' '#ffffff' '#8a8576' 'Franz Joseph I' 'The Dual Monarchy of Austria and Hungary (1867) ruled Bohemia, Galicia, Croatia, Transylvania and the Slovene lands; Bosnia was occupied from 1878.'
Spec 'IT' 'Kingdom of Italy' 'Kingdom of Italy' '#5fa07e' '#2f5e46' 'Umberto I' 'Italy was unified between 1859 and 1870 under the House of Savoy, with Rome as capital from 1871.'
Spec 'CH' 'Switzerland' 'Switzerland' '#c9726b' '#7a403c' 'Federal Council' 'The Swiss Confederation became a federal state in 1848.'
Spec 'BE' 'Belgium' 'Belgium' '#c2b04a' '#6b6125' 'Leopold II' 'Belgium became independent in 1830; Leopold II also ruled the Congo Free State as a personal possession.'
Spec 'NL' 'Netherlands' 'Netherlands' '#d98a3d' '#7a4a1d' 'Wilhelmina' 'The Kingdom of the Netherlands; Queen Wilhelmina succeeded in 1890.'
Spec 'LU' 'Luxembourg' 'Luxembourg' '#8fb0c9' '#4b6478' 'Adolphe' 'Luxembourg was a separate grand duchy, in personal union with the Netherlands until 1890, then under Adolphe of Nassau.'
Spec 'FR' 'France' 'France' '#4169a1' '#203b61' 'Emile Loubet' 'The Third Republic was proclaimed in 1870 after the defeat by Prussia; France lost Alsace-Lorraine but built a large colonial empire.'
Spec 'FRA' 'France (Africa)' 'French Africa' '#4169a1' '#203b61' 'Emile Loubet' 'France conquered Algeria from 1830 and treated it as part of France; Tunisia became a French protectorate in 1881 under the Bey of Tunis.'
Spec 'RU' 'Russian Empire' 'Russian Empire' '#1c3a22' '#0b1a10' 'Nicholas II' 'Russia ruled from Finland to the Pacific; Poland, the Baltic provinces, Ukraine, Bessarabia and the Caucasus were all incorporated.'
Spec 'RUF' 'Russian Empire (Finland)' '' '#1c3a22' '#0b1a10' 'Nicholas II (Grand Duke)' 'Finland was a grand duchy under the Russian tsar since 1809, with its own parliament and laws.'
Spec 'OT' 'Ottoman Empire' '' '#d1a52e' '#7a5f12' 'Abdulhamid II' 'The Ottoman Empire had lost most of the Balkans but still held Anatolia, Macedonia, Albania, the Levant, Iraq and the Hejaz.'
$S['OT'].fill = '#d1a52e'
Spec 'SR' 'Kingdom of Serbia' 'Serbia' '#8e6aa8' '#4f3a63' 'Alexander I' 'Serbia won full independence in 1878 and became a kingdom in 1882.'
Spec 'RO' 'Kingdom of Romania' 'Romania' '#cc8f6a' '#7a4a32' 'Carol I' 'Wallachia and Moldavia united in 1859; Romania became independent in 1878 and a kingdom in 1881, gaining Dobruja.'
Spec 'BG' 'Principality of Bulgaria' 'Bulgaria' '#5f9ea0' '#2f5e60' 'Ferdinand I' 'Bulgaria became an autonomous principality in 1878 and united with Eastern Rumelia in 1885, still nominally under the Sultan.'
Spec 'GR' 'Kingdom of Greece' 'Greece' '#6fa8d8' '#35607f' 'George I' 'Independent since the 1820s; Greece received the Ionian Islands in 1864 and Thessaly in 1881.'
Spec 'ME' 'Principality of Montenegro' 'Montenegro' '#b0607a' '#63303f' 'Nicholas I' 'Montenegro was recognised as independent in 1878.'
Spec 'SE' ('Sweden' + $nd + 'Norway') ('Sweden' + $nd + 'Norway') '#102548' '#06142b' 'Oscar II' 'Sweden and Norway were in a personal union under one king from 1814 to 1905; Norway kept its own constitution and parliament, and Sweden had held Scania, Halland and Blekinge since 1658.'
Spec 'ES' 'Kingdom of Spain' 'Spain' '#a37d45' '#654d2b' 'Alfonso XIII' 'Spain lost Cuba, Puerto Rico and the Philippines to the United States in 1898; Alfonso XIII was a minor under his mother''s regency until 1902.'
Spec 'DK' 'Kingdom of Denmark' 'Denmark' '#8b1e2d' '#4b0d16' 'Christian IX' 'Denmark had lost Norway (1814) and Schleswig-Holstein (1864) but kept Iceland and the Faroe Islands.'
Spec 'UK' 'United Kingdom' 'United Kingdom' '#c0504d' '#6e2927' 'Victoria' 'The United Kingdom of Great Britain and Ireland, centre of the largest empire in history; Queen Victoria reigned until 1901.'
Spec 'EG' 'Egypt (British occupation)' 'Egypt' '#d08a86' '#7a4a48' 'Abbas II (Khedive)' 'Egypt was formally Ottoman but under British occupation since 1882.'
Spec 'QI' 'Qajar Iran' 'Qajar Iran' '#9a4a6a' '#5a2640' 'Mozaffar ad-Din Shah' 'Persia was ruled by the Qajar dynasty and squeezed between Russian and British influence.'
$S['OT'].fill = '#d1a52e'; $S['OT'].border = '#7a5f12'

$GEpl = 'pomeranianvoivodeship','kuyavian-pomeranianvoivodeship','greaterpolandvoivodeship','lubuszvoivodeship','silesianvoivodeship','lowersilesianvoivodeship','opolevoivodeship','westpomeranianvoivodeship','warmian-masurianvoivodeship'
$AHpl = 'lesserpolandvoivodeship','podkarpackievoivodeship'
$AHit = 'trentino-southtyrol','trentino','trieste','gorizia'
$AHold = 'Principality of Transylvania','Royal Hungary (Reconquered)','Habsburg Monarchy (Banat)','Royal Hungary (Habsburg)','Habsburg Monarchy (Galicia)'

function NewKey($p, $old) {
    $a = $p["admin"]; $id = $p["id"]
    switch ($a) {
        'Germany' { return 'GE' }
        'Poland' { if ($GEpl -contains $id) { return 'GE' }; if ($AHpl -contains $id) { return 'AH' }; return 'RU' }
        'Russia' { if ($id -eq 'kaliningrad') { return 'GE' }; return 'RU' }
        'France' { if (@('bas-rhin','haut-rhin','moselle') -contains $id) { return 'GE' }; return 'FR' }
        { @('Austria','Czech Republic','Slovakia','Hungary','Slovenia','Croatia','Bosnia and Herzegovina') -contains $_ } { return 'AH' }
        'Italy' { if ($AHit -contains $id) { return 'AH' }; return 'IT' }
        'Switzerland' { return 'CH' }
        'Belgium' { return 'BE' }
        'Netherlands' { return 'NL' }
        'Luxembourg' { return 'LU' }
        'Republic of Serbia' { if ($AHold -contains $old) { return 'AH' }; return 'SR' }
        'Romania' { if ($AHold -contains $old) { return 'AH' }; return 'RO' }
        'Ukraine' { if (($AHold -contains $old) -or $old -eq 'Principality of Moldavia') { return 'AH' }; return 'RU' }
        { @('Moldova','Belarus','Lithuania','Latvia','Estonia','Georgia','Armenia','Azerbaijan') -contains $_ } { return 'RU' }
        'Finland' { return 'RU' }
        'Supplemental Islands' { if ($id -eq 'aland') { return 'RU' }; if ($id -eq 'faroe-islands') { return 'DK' }; return 'UK' }
        'Norway' { return 'SE' }
        'Spain' { if ($old -eq 'Alaouite Sultanate') { return $null }; return 'ES' }
        'Spain' { return 'ES' }
        'Sweden' { return 'SE' }
        { @('Denmark','Iceland') -contains $_ } { return 'DK' }
        { @('United Kingdom','Ireland','Malta','Cyprus') -contains $_ } { return 'UK' }
        'Egypt' { return 'EG' }
        'Iran' { return 'QI' }
        'Bulgaria' { return 'BG' }
        'Montenegro' { return 'ME' }
        'Algeria' { return 'FRA' }
        'Tunisia' { return 'FRA' }
        'Greece' {
            if (@('Ottoman Empire (Athens)','Ottoman Empire (Thessaly)','Kingdom of Naples') -contains $old) { return 'GR' }
            if ($old -eq 'Republic of Venice (Aegean)') { if ($id -eq 'crete') { return 'OT' }; return 'GR' }
            if (@('westgreece','peloponnese') -contains $id) { return 'GR' }
            return $null
        }
        'Albania' { if ($old -eq 'Kingdom of Naples') { return 'OT' }; return $null }
        'Turkey' {
            if ($old -eq 'Kingdom of Georgia') { return 'RU' }
            if ($old -eq 'Safavid Iran (Armenia)') { if ($id -eq 'kars' -or $id -like 'i?dir') { return 'RU' }; return 'OT' }
            return $null
        }
    }
    return $null
}

$S = @{}
Spec 'ES' 'Kingdom of Spain' 'Spain' '#a37d45' '#654d2b' 'Ferdinand VII' 'Spain was restored under Ferdinand VII after the Peninsular War (1808-14); its American colonies were in revolt.'
Spec 'AU' 'Austrian Empire' 'Austrian Empire' '#ffffff' '#8a8576' 'Francis I' 'The Austrian Empire (proclaimed 1804; Austria-Hungary only came in 1867) included Bohemia, Hungary, Croatia, Transylvania and Galicia, and regained Lombardy-Venetia, Tyrol, Illyria and Galicia at the Congress of Vienna, but gave up the Holy Roman crown in 1806 and the Austrian Netherlands. Bohemia, Hungary, Croatia and Transylvania were ruled in personal union.'
Spec 'PR' 'Kingdom of Prussia' 'Prussia' '#8b8f9e' '#4c4f5c' 'Frederick William III' 'Prussia was restored in 1815 and gained the Rhineland, Westphalia, Posen, northern Saxony and Swedish Pomerania; it was now the leading power in the German Confederation.'
Spec 'PL' 'Congress Poland' 'Congress Poland' '#f08080' '#a84646' 'Alexander I (King of Poland)' 'The Kingdom of Poland, created in 1815 from the Duchy of Warsaw, had its own constitution but was ruled by the Russian tsar as king.'
Spec 'BV' 'Kingdom of Bavaria' 'Bavaria' '#5aa5c8' '#2e6279' 'Maximilian I Joseph' 'Bavaria became a kingdom in 1806 under Napoleon and in 1815 joined the German Confederation, gaining the Palatinate in 1816.'
Spec 'SX' 'Kingdom of Saxony' 'Saxony' '#8fbf6f' '#4d7339' 'Frederick Augustus I' 'Saxony, a loyal ally of Napoleon, lost about half its territory to Prussia in 1815.'
Spec 'HN' 'Kingdom of Hanover' 'Hanover' '#d98c7a' '#7d463a' 'George III (Prince Regent George)' 'Hanover became a kingdom in 1814 and was in personal union with the British crown, gaining East Frisia and Hildesheim.'
Spec 'WB' ('Wü' + 'rttemberg and Baden') ('Wü' + 'rttemberg and Baden') '#c9a0dc' '#6f4a82' ('Frederick I of Wü' + 'rttemberg') ('Napoleon''s allies Wü' + 'rttemberg (kingdom) and Baden (grand duchy) kept their enlarged territories and joined the German Confederation in 1815.')
Spec 'HE' 'Hesse' 'Hesse' '#e0c36a' '#7d6a2c' 'William I (Hesse-Kassel)' 'Hesse was divided between the Electorate of Hesse-Kassel and the Grand Duchy of Hesse-Darmstadt, both members of the German Confederation.'
Spec 'TH' 'Thuringian states' 'Thuringian states' '#7fbfb0' '#3f7569' 'Charles Augustus (Saxe-Weimar)' 'Thuringia was split into many small Saxon duchies and principalities, which joined the German Confederation in 1815.'
Spec 'MK' 'Mecklenburg' 'Mecklenburg' '#b0845a' '#664a2c' 'Frederick Francis I' 'The Mecklenburg duchies became grand duchies in 1815; Swedish Pomerania passed to Denmark and then Prussia.'
Spec 'HC' 'Free Cities of Hamburg and Bremen' 'Hamburg and Bremen' '#b58fb0' '#684a63' 'City senates' 'Hamburg and Bremen regained their independence as free cities in 1814-15 after French occupation.'
Spec 'DK' 'Kingdom of Denmark' 'Denmark' '#8b1e2d' '#4b0d16' 'Frederick VI' 'Denmark lost Norway to Sweden in 1814 but kept Schleswig, Holstein, Iceland and the Faroe Islands.'
Spec 'SE' ('Sweden' + $nd + 'Norway') ('Sweden' + $nd + 'Norway') '#102548' '#06142b' 'Charles XIII' 'Sweden lost Finland to Russia (1809) and Swedish Pomerania, but gained Norway in 1814 in a personal union under one king.'
Spec 'RUF' 'Grand Duchy of Finland' 'Finland' '#1c3a22' '#0b1a10' 'Alexander I (Grand Duke)' 'Finland was conquered from Sweden in 1809 and became an autonomous grand duchy under the Russian tsar.'
Spec 'RU' 'Russian Empire' 'Russian Empire' '#1c3a22' '#0b1a10' 'Alexander I' 'Alexander I''s Russia emerged from the Napoleonic Wars as the dominant land power in Europe; it had annexed Finland (1809), Bessarabia (1812), Georgia (1801), northern Azerbaijan (1813) and most of Poland (1815).'
Spec 'NL' 'United Kingdom of the Netherlands' 'Netherlands' '#d98a3d' '#7a4a1d' 'William I' 'The Congress of Vienna created a united kingdom of the Netherlands, Belgium and Luxembourg under the House of Orange.'
Spec 'FR' 'Kingdom of France' 'France' '#4169a1' '#203b61' 'Louis XVIII' 'The Bourbons were restored in 1814-15 after Napoleon''s fall, and France was reduced to roughly its 1790 borders.'
Spec 'SA' 'Kingdom of Sardinia' 'Sardinia' '#6b8fb5' '#3a5470' 'Victor Emmanuel I' 'Restored in 1814, Sardinia regained Savoy and Nice and gained Genoa and Liguria at the Congress of Vienna.'
Spec 'PM' 'Duchy of Parma' 'Parma' '#d98fa0' '#7a4a56' 'Marie Louise' 'Parma was granted to Napoleon''s wife Marie Louise for life.'
Spec 'MO' 'Duchy of Modena' 'Modena' '#8f9fc9' '#4a566e' 'Francis IV' 'The Austrian Archduke Francis IV ruled Modena, Reggio and Massa-Carrara.'
Spec 'LU' 'Duchy of Lucca' 'Lucca' '#c9c27a' '#6f6a3c' 'Marie Louise of Bourbon' 'Lucca was a small Bourbon duchy under Marie Louise until 1824, when it was absorbed into Tuscany.'
Spec 'TU' 'Grand Duchy of Tuscany' 'Tuscany' '#b0455a' '#68232f' 'Ferdinand III' 'Habsburg-Lorraine Tuscany was restored in 1814.'
Spec 'PA' 'Papal States' 'Papal States' '#d7c7a1' '#796b50' 'Pius VII' 'The Papal States were restored in 1814-15 under Pius VII, including the Legations of Bologna and Ferrara.'
Spec 'NA' 'Kingdom of Naples (Molise)' '' '#a09060' '#655738' 'Ferdinand IV' 'Naples was restored under Ferdinand IV after Murat''s fall; the two kingdoms were merged as the Two Sicilies in 1816.'
Spec 'CH' 'Switzerland' 'Switzerland' '#c9726b' '#7a403c' 'Federal Diet' 'The Swiss Confederation was restored in 1815 with 22 cantons and declared permanently neutral.'
Spec 'IO' 'United States of the Ionian Islands' 'Ionian Islands' '#7fb2d8' '#3a6482' 'British Lord High Commissioner' 'The Ionian Islands became a British protectorate in 1815.'
Spec 'UK' 'United Kingdom (Malta)' '' '#c0504d' '#7a3330' 'George III (Prince Regent George)' 'Malta was taken from the French in 1800 and confirmed as British in 1814.'
Spec 'OT' 'Ottoman Empire (annexed lands)' '' '#d1a52e' '#7a5f12' 'Mahmud II' 'These lands remained Ottoman.'
Spec 'QA' 'Qajar Iran (Armenia)' '' '#9a4a6a' '#5a2640' 'Fath-Ali Shah' 'Armenia and Nakhchivan were still Persian until 1828.'

$PRpl = 'pomeranianvoivodeship','kuyavian-pomeranianvoivodeship','greaterpolandvoivodeship','lubuszvoivodeship','silesianvoivodeship','lowersilesianvoivodeship','opolevoivodeship','westpomeranianvoivodeship','warmian-masurianvoivodeship'
$KEEPpl = 'lesserpolandvoivodeship','podkarpackievoivodeship'
$habs = @('Kingdom of Bohemia','Royal Hungary (Habsburg)','Royal Hungary (Reconquered)','Habsburg Monarchy (Banat)','Habsburg Monarchy (Galicia)','Croatia (Hungarian crown)','Principality of Transylvania')
$ITmap = @{}
foreach ($x in 'asti','vercelli','alessandria','novara','biella','verbano-cusio-ossola','aosta','cuneo','turin','imperia','laspezia','liguria','savona') { $ITmap[$x] = 'SA' }
foreach ($x in 'varese','como','bergamo','brescia','cremona','milan','lecco','monzaandbrianza','lodi','pavia','vicenza','verona','mantua','venice','treviso','padua','rovigo','sondrio','trentino-southtyrol','trentino','belluno','udine','gorizia','trieste','pordenone') { $ITmap[$x] = 'AU' }
foreach ($x in 'parma','piacenza') { $ITmap[$x] = 'PM' }
foreach ($x in 'reggioemilia','modena','massa-carrara') { $ITmap[$x] = 'MO' }
$ITmap['lucca'] = 'LU'
foreach ($x in 'arezzo','florence','pistoia','prato','pisa','livorno','siena','grosseto') { $ITmap[$x] = 'TU' }
foreach ($x in 'bologna','ferrara',('forl'+[char]0xEC+'-cesena')) { $ITmap[$x] = 'PA' }
foreach ($x in 'campobasso','isernia') { $ITmap[$x] = 'NA' }
$DEmap = @{ 'bavaria'='BV'; 'saxony'='SX'; 'lowersaxony'='HN'; 'hesse'='HE'; 'thuringia'='TH'; 'mecklenburg-westernpomerania'='MK'; 'hamburg'='HC'; 'freehanseaticbremen'='HC'; 'schleswig-holstein'='DK'; 'brandenburg'='PR'; 'berlin'='PR'; 'saxony-anhalt'='PR'; 'northrhine-westphalia'='PR'; 'rhineland-palatinate'='PR'; 'saarland'='PR' }
$DEmap['baden-w' + [char]0xFC + 'rttemberg'] = 'WB'

function NewKey($p, $old) {
    $a = $p["admin"]; $id = $p["id"]
    switch ($a) {
        'Germany' { if ($DEmap.ContainsKey($id)) { return $DEmap[$id] }; return $null }
        'Poland' { if ($PRpl -contains $id) { return 'PR' }; if ($KEEPpl -contains $id) { return 'AU' }; return 'PL' }
        'Russia' { if ($id -eq 'kaliningrad') { return 'PR' }; return 'RU' }
        'France' { if (@('alpes-maritimes','savoie','haute-savoie') -contains $id) { return 'SA' }; return 'FR' }
        { @('Austria','Slovenia') -contains $_ } { return 'AU' }
        'Croatia' { return 'AU' }
        'Italy' { if ($ITmap.ContainsKey($id)) { return $ITmap[$id] }; if ($old -eq 'Kingdom of Sardinia') { return 'SA' }; if ($old -eq 'Papal States') { return 'PA' }; if ($old -eq 'Grand Duchy of Tuscany') { return 'TU' }; return $null }
        'Switzerland' { return 'CH' }
        { @('Belgium','Netherlands','Luxembourg') -contains $_ } { return 'NL' }
        'Ukraine' { if ($old -eq 'Principality of Moldavia') { return 'AU' }; if ($habs -contains $old) { return 'AU' }; return 'RU' }
        { @('Moldova','Georgia','Belarus','Lithuania','Latvia','Estonia') -contains $_ } { return 'RU' }
        'Armenia' { return 'QA' }
        { @('Czech Republic','Slovakia','Hungary','Croatia') -contains $_ } { return 'AU' }
        'Azerbaijan' { if ($old -like '*Arran*') { return 'RU' }; return 'QA' }
        'Finland' { return 'RU' }
        'Supplemental Islands' { if ($id -eq 'aland') { return 'RU' }; if ($id -eq 'faroe-islands') { return 'DK' }; return $null }
        'Norway' { return 'SE' }
        'Spain' { if ($old -eq 'Alaouite Sultanate') { return $null }; return 'ES' }
        'Sweden' { return 'SE' }
        { @('Denmark','Iceland') -contains $_ } { return 'DK' }
        'Malta' { return 'UK' }
        'Greece' {
            if ($old -eq 'Republic of Venice (Aegean)') { if ($id -eq 'crete') { return 'OT' }; return 'IO' }
            if ($old -eq 'Kingdom of Naples') { return 'IO' }
            return $null
        }
        'Albania' { if ($old -eq 'Kingdom of Naples') { return 'OT' }; return $null }
        'Turkey' {
            if ($old -eq 'Kingdom of Georgia') { return 'OT' }
            if ($old -eq 'Safavid Iran (Armenia)') { return 'OT' }
            return $null
        }
    }
    if ($habs -contains $old) { return 'AU' }
    return $null
}

$piecesByOld = @{}
foreach ($i in $assign.Keys) {
    $old = $assign[$i]; $p = $feats[$i]
    $k = NewKey $p $old
    if (-not $k) { $k = 'KEEP' }
    if (-not $piecesByOld[$old]) { $piecesByOld[$old] = @{} }
    if (-not $piecesByOld[$old][$k]) { $piecesByOld[$old][$k] = New-Object System.Collections.ArrayList }
    [void]$piecesByOld[$old][$k].Add($i)
}

$byAdmin = @{}
for ($i = 0; $i -lt $feats.Count; $i++) { $a = $feats[$i]["admin"]; $byAdmin[$a] = 1 + [int]$byAdmin[$a] }

function Make-Filters($idxs) {
    $groups = @{}
    foreach ($i in $idxs) { $a = $feats[$i]["admin"]; if (-not $groups[$a]) { $groups[$a] = New-Object System.Collections.ArrayList }; [void]$groups[$a].Add($feats[$i]["id"]) }
    $res = @()
    foreach ($a in ($groups.Keys | Sort-Object)) {
        if ($groups[$a].Count -eq $byAdmin[$a]) { $res += , ([ordered]@{ admin = $a }) }
        else { $res += , ([ordered]@{ admin = $a; ids = @($groups[$a] | Select-Object -Unique) }) }
    }
    return , $res
}
function Largest-Admin($idxs) {
    $c = @{}; foreach ($i in $idxs) { $a = $feats[$i]["admin"]; $c[$a] = 1 + [int]$c[$a] }
    return ($c.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 1).Name
}

$inst = @()
foreach ($old in ($piecesByOld.Keys | Sort-Object)) {
    $pc = $piecesByOld[$old]
    $keys = @($pc.Keys)
    if ($keys.Count -eq 1 -and $keys[0] -eq 'KEEP') { continue }
    if ($keys.Count -eq 1) { $inst += @{ key = $keys[0]; old = $old; idxs = $pc[$keys[0]]; kind = 'rename' }; continue }
    $inst += @{ key = $null; old = $old; idxs = $null; kind = 'empty' }
    foreach ($k in $keys) {
        if ($k -eq 'KEEP') { $inst += @{ key = 'KEEP'; old = $old; idxs = $pc[$k]; kind = 'residual' } }
        else { $inst += @{ key = $k; old = $old; idxs = $pc[$k]; kind = 'add' } }
    }
}

$mainOld = @{ SE = 'Sweden'; NL = 'Batavian Republic'; FR = 'French Republic'; AU = 'Holy Roman Empire'; ES = 'Kingdom of Spain'; SA = 'Kingdom of Sardinia'; PR = 'Kingdom of Prussia'; TU = 'Grand Duchy of Tuscany'; PA = 'Papal States'; DK = ('Denmark' + [char]0x2013 + 'Norway'); RU = 'Russian Empire'; OT = 'Kingdom of Naples'; QA = 'Safavid Iran (Armenia)'; IO = 'Republic of Venice (Aegean)'; CH = 'Duchy of Swabia'; PL = 'Kingdom of Prussia (Polish partition)' }
foreach ($k in $mainOld.Keys) {
    $pcs = @($inst | Where-Object { $_.key -eq $k })
    $main = $pcs | Where-Object { $_.old -eq $mainOld[$k] } | Select-Object -First 1
    $all = New-Object System.Collections.ArrayList
    foreach ($p in $pcs) { foreach ($x in $p.idxs) { [void]$all.Add($x) } }
    foreach ($p in $pcs) {
        if ($p -eq $main) { continue }
        if ($p.kind -eq 'rename') { $p.kind = 'empty'; $p.key = $null; $p.idxs = $null }
        else { $p.kind = 'skip'; $p.key = $null }
    }
    $main.idxs = $all
    $main.merged = $true
}
$used = @{}
$changed = @{}; foreach ($m in $inst) { $changed[$m.old] = 1 }
foreach ($m in $inst) { if ($m.kind -eq 'residual') { $used[$m.old] = 1 } }
foreach ($r in $realms) { if (-not $changed.ContainsKey($r.realm)) { $used[$r.realm] = 1 } }
$overrides = [ordered]@{}
$additions = @()
$pref = @{ RU = 'Russian Empire'; ES = 'Kingdom of Spain'; AU = 'Holy Roman Empire' }
$sfx = @{}
foreach ($k in ($S.Keys | Sort-Object)) {
    $mine = @($inst | Where-Object { $_.key -eq $k } | Sort-Object { - $_.idxs.Count })
    $pk = $pref[$k]
    if ($pk) { $pm = @($mine | Where-Object { $_.old.Replace($nd, '-') -eq $pk }); if ($pm.Count) { $mine = @($pm[0]) + @($mine | Where-Object { $_ -ne $pm[0] }) } }
    $n = 0
    foreach ($m in $mine) {
        $sp = $S[$k]
        if ($n -eq 0) { $name = $sp.realm; $label = $sp.label }
        else {
            $suf = $null
            foreach ($sk in $sfx.Keys) { $parts = $sk.Split('|'); if ($parts[0] -eq $k -and $m.old -like "*$($parts[1])*") { $suf = $sfx[$sk] } }
            if (-not $suf) { if ($m.old -match '\(([^)]+)\)\s*$') { $suf = $Matches[1] } else { $suf = $m.old } }
            if ($sp.realm -match '\(') { $name = $sp.realm + ' ' + $nd + ' ' + $suf } else { $name = $sp.realm + ' (' + $suf + ')' }
            $label = ''
        }
        $base = $name; $c = 2
        while ($used.ContainsKey($name)) { $name = "$base $c"; $c++ }
        $used[$name] = 1
        $m.name = $name; $m.label = $label
        $n++
    }
}
foreach ($m in ($inst | Where-Object { $_.kind -eq 'residual' })) { $m.name = $m.old; $m.label = '' }

foreach ($m in $inst) {
    if ($m.kind -eq 'empty') {
        $overrides[$m.old] = [ordered]@{ provinces = @(); properties = [ordered]@{ regionFilters = @() } }
        continue
    }
    if ($m.kind -eq 'rename') {
        $sp = $S[$m.key]
        $props = [ordered]@{ realm = $m.name; label = $m.label; leader = $sp.leader; fillColor = $sp.fill; borderColor = $sp.border; info = $sp.info }
        if ($m.merged) { $props['regionFilters'] = (Make-Filters $m.idxs); $props['excludeIds'] = @() }
        $overrides[$m.old] = [ordered]@{ properties = $props }
        continue
    }
    if ($m.kind -eq 'add') {
        $sp = $S[$m.key]
        $props = [ordered]@{ realm = $m.name; label = $m.label; leader = $sp.leader; regionFilters = (Make-Filters $m.idxs); fillColor = $sp.fill; borderColor = $sp.border; info = $sp.info }
        $additions += , ([ordered]@{ provinces = @(); properties = $props })
        continue
    }
    if ($m.kind -eq 'residual') {
        $overrides[$m.old] = [ordered]@{ provinces = @(); properties = [ordered]@{ regionFilters = (Make-Filters $m.idxs) } }
    }
}

foreach ($r in $realms) {
    if ($r.props['fillColor'] -ne '#6f8a2e') { continue }
    if (-not $overrides.Contains($r.realm)) { $overrides[$r.realm] = [ordered]@{ properties = [ordered]@{} } }
    $op = $overrides[$r.realm]['properties']
    if (-not $op.Contains('fillColor')) { $op['fillColor'] = $S['OT'].fill; $op['borderColor'] = $S['OT'].border }
    if ($r.realm -eq 'Ottoman Empire (Cyrenaica)') { $op['label'] = 'Ottoman Empire'; $op['labelOwn'] = $true }
}

$habs = @('Kingdom of Bohemia','Royal Hungary (Habsburg)','Royal Hungary (Reconquered)','Habsburg Monarchy (Banat)','Habsburg Monarchy (Galicia)','Croatia (Hungarian crown)','Principality of Transylvania')
$textFix = [ordered]@{
    'Kingdom of Spain' = @('Ferdinand VII', 'Spain was restored under Ferdinand VII after the Peninsular War (1808-14) and the Cortes of Cadiz; its American colonies were in revolt.')
    'Ottoman Empire' = @('Mahmud II', 'The Ottoman Empire still ruled the Balkans, Anatolia, the Levant and North Africa; Serbia rose in revolt in 1815 and Egypt was largely independent under Muhammad Ali.')
    'Russian Empire' = @('Alexander I', 'Alexander I''s Russia emerged from the Napoleonic Wars as the dominant land power in Europe, with Finland, Bessarabia and Poland added to the empire.')
    'Wallachia' = @('Ioan Caragea', 'Wallachia was an Ottoman vassal principality ruled by Phanariot Greek hospodars.')
    'Principality of Moldavia' = @('Scarlat Callimachi', 'Moldavia, reduced after Russia annexed Bessarabia in 1812, was an Ottoman vassal under a Phanariot hospodar.')
    'Kingdom of Portugal' = @('John VI (Prince Regent)', 'The Portuguese court ruled from Brazil after 1807; Portugal became part of a united kingdom with Brazil in 1815.')
    'United Kingdom of Great Britain' = @('George III (Prince Regent George)', 'The United Kingdom of Great Britain and Ireland (1801) emerged from the Napoleonic Wars as the leading naval and colonial power.')
    'Kingdom of Naples' = @('Ferdinand IV', 'Naples was restored under Ferdinand IV after Murat''s fall; the two kingdoms were merged as the Two Sicilies in 1816.')
    'Kingdom of Sicily' = @('Ferdinand III', 'Sicily remained under Bourbon rule through the Napoleonic era, protected by the British; merged with Naples in 1816.')
}
foreach ($r in $realms) {
    if ($habs -contains $r.realm) { $textFix[$r.realm] = @('Francis I', 'A Habsburg crown land: Francis I ruled it as king or archduke, in personal union with the Austrian Empire.') }
    elseif ($r.realm -like 'Ottoman Empire*' -and -not $textFix.Contains($r.realm)) { $textFix[$r.realm] = @('Mahmud II', 'An Ottoman province.') }
    elseif ($r.realm -like 'Russian Empire*' -and -not $textFix.Contains($r.realm)) { $textFix[$r.realm] = @('Alexander I', 'A province of the Russian Empire.') }
    elseif ($r.realm -like 'Spanish Monarchy*') { $textFix[$r.realm] = @('Ferdinand VII', 'A province of the Spanish monarchy.') }
}
foreach ($k in $textFix.Keys) {
    if (-not $overrides.Contains($k)) { $overrides[$k] = [ordered]@{ properties = [ordered]@{} } }
    $op = $overrides[$k]['properties']
    if (-not $op.Contains('leader')) { $op['leader'] = $textFix[$k][0]; $op['info'] = $textFix[$k][1] }
}
if ($overrides.Contains('United Kingdom of Great Britain')) { $uk = $overrides['United Kingdom of Great Britain']['properties']; $uk['realm'] = 'United Kingdom of Great Britain and Ireland'; $uk['label'] = 'United Kingdom' }
foreach ($r in $realms) {
    if ($r.realm -notmatch '^(Finnic Tribal Lands|Karelian Frontierlands|Northern Finnic Frontierlands|Nogai Horde)' -and $r.realm -notlike ('S' + [char]0xE1 + 'mi and Northern*')) { continue }
    if (-not $overrides.Contains($r.realm)) { $overrides[$r.realm] = [ordered]@{ properties = [ordered]@{} } }
    $op = $overrides[$r.realm]['properties']
    $op['fillColor'] = '#1c3a22'; $op['borderColor'] = '#0b1a10'; $op['label'] = ''
    if (-not $op.Contains('leader')) { $op['leader'] = 'Alexander I'; $op['info'] = 'Part of the Russian Empire.' }
}

$block = [ordered]@{
    baseYear = '1800'
    note = 'Europe 1815 after the Congress of Vienna: Austrian Empire, enlarged Prussia, German Confederation states, Congress Poland, United Netherlands, Sweden-Norway.'
    overrides = $overrides
    additions = $additions
}
$json = ConvertTo-Json $block -Depth 12
$json = $json -replace '\\u0027', "'"
[IO.File]::WriteAllText((Join-Path (Get-Location) $Out), $json, (New-Object Text.UTF8Encoding($false)))
Write-Host "overrides $($overrides.Count) additions $($additions.Count)"
if ($Report) { foreach ($m in $inst) { "{0} | {1} | {2} | {3}" -f $m.kind, $m.old, $m.name, $(if ($m.idxs) { $m.idxs.Count } else { 0 }) } }
