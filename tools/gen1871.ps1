param([string]$Names = "names1900.txt", [string]$Out = "frag1871.json")
# 1871 is built on top of 1900: only ownership, names, leaders and info that differ are overridden.
$raw = [IO.File]::ReadAllText((Join-Path $PSScriptRoot $Names), [Text.Encoding]::UTF8)
$yearsText = [IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\data\years.json'), [Text.Encoding]::UTF8)
$allNames = @($raw -split "`n" | ForEach-Object { ($_ -split ' \| ')[0].Trim() } | Where-Object { $_ })

function Tok($rx) { $m = [regex]::Match($yearsText, $rx); if (-not $m.Success) { throw "token $rx not found" }; return $m.Groups[1].Value }
$constanta = Tok '"(constan.a)"'
$nisava = Tok '"(ni.ava)"'
$pcinja = Tok '"(p.inja)"'

$OTfill = '#d1a52e'; $OTborder = '#7a5f12'
$overrides = [ordered]@{}
function Ov($name, $props) {
    if ($allNames -notcontains $name) { throw "unknown 1900 realm: $name" }
    if (-not $script:overrides.Contains($name)) { $script:overrides[$name] = [ordered]@{ properties = [ordered]@{} } }
    foreach ($k in $props.Keys) { $script:overrides[$name]['properties'][$k] = $props[$k] }
}

# Leaders for every piece, by owner.
$leaders = @(
    @('^Russian Empire', 'Alexander II'),
    @('^German Empire', 'Wilhelm I'),
    @('^France', 'Adolphe Thiers (President)'),
    @('^Kingdom of Italy', 'Victor Emmanuel II'),
    @('^Ottoman Empire', 'Abdulaziz'),
    @('^Alaouite Sultanate', 'Muhammad IV'),
    @('^Qajar Iran', 'Naser al-Din Shah'),
    @('^Kingdom of Spain', 'Amadeo I (of Savoy)'),
    @('^Kingdom of Portugal', ('Lu' + [char]0xED + 's I')),
    @('^Netherlands', 'William III'),
    @('^Luxembourg', 'William III (Grand Duke)'),
    @('^Sweden.Norway', 'Charles XV')
)
foreach ($n in $allNames) {
    foreach ($l in $leaders) { if ($n -match $l[0]) { Ov $n ([ordered]@{ leader = $l[1] }); break } }
}

function Main($rx, $props) {
    $hit = @($allNames | Where-Object { $_ -match $rx })
    if ($hit.Count -ne 1) { throw "main realm $rx matched $($hit.Count)" }
    Ov $hit[0] $props
}
Main '^German Empire$' ([ordered]@{ info = 'The German Empire was proclaimed at Versailles on 18 January 1871 under Wilhelm I of Prussia, uniting the North German Confederation with the southern states; Alsace was annexed from France.' })
Main '^Austria-Hungary$' ([ordered]@{ info = 'The Dual Monarchy of Austria and Hungary was created by the Compromise of 1867 under Franz Joseph I; Bosnia was still Ottoman.' })
Main '^Kingdom of Italy$' ([ordered]@{ info = 'Italy was almost unified: Venetia was gained in 1866 and Rome was taken from the Pope in 1870 (capital from 1871); Trento and Trieste were still Austrian.' })
Main '^France$' ([ordered]@{ info = 'The Third Republic was proclaimed in September 1870 after Napoleon III fell at Sedan; France lost Alsace and part of Lorraine and put down the Paris Commune in 1871.' })
Main '^France \(Africa\)$' ([ordered]@{ info = 'France had ruled Algeria since 1830; Tunisia was still a nominally Ottoman beylik until the protectorate of 1881.' })
Main '^Russian Empire$' ([ordered]@{ info = 'Russia under Alexander II had freed the serfs in 1861 and was expanding in Central Asia and the Caucasus; Poland, the Baltic provinces and Finland were under the tsar.' })
Main '^Russian Empire \(Finland\)$' ([ordered]@{ leader = 'Alexander II (Grand Duke)'; info = 'Finland was a grand duchy under the Russian tsar since 1809, with its own diet.' })
Main '^Ottoman Empire$' ([ordered]@{ info = 'The Ottoman Empire still held the whole Balkans from Bosnia and Bulgaria to Thessaly and Macedonia, plus Anatolia, the Levant, Iraq, the Hejaz, Cyprus and Libya; Serbia and Romania were autonomous vassals.' })
Main '^Kingdom of Greece$' ([ordered]@{ info = 'Greece received the Ionian Islands from Britain in 1864; Thessaly, Epirus, Macedonia and Crete were still Ottoman.' })
Main '^Principality of Montenegro$' ([ordered]@{ info = 'Montenegro was a small mountain principality under Nicholas I; it was recognised as independent only in 1878 and doubled in size then.' })
Main '^Sweden.Norway$' ([ordered]@{ info = 'Sweden and Norway were in a personal union under Charles XV (d. 1872, succeeded by Oscar II); Norway kept its own constitution and parliament.' })
Main '^Kingdom of Spain$' ([ordered]@{ info = 'After the Revolution of 1868 ousted Isabella II, Spain was ruled by Amadeo of Savoy (1870-73), followed by the First Republic.' })
Main '^Kingdom of Portugal$' ([ordered]@{ info = 'Portugal under Lu' + [char]0xED + 's I (1861-89) was a constitutional monarchy with African colonies.' })
Main '^Netherlands$' ([ordered]@{ info = 'The Kingdom of the Netherlands under William III (1849-90).' })
Main '^Luxembourg$' ([ordered]@{ info = 'Luxembourg was a neutral grand duchy (since 1867) in personal union with the Netherlands.' })
Main '^Belgium$' ([ordered]@{ info = 'Belgium became independent in 1830; Leopold II reigned from 1865.' })
Main '^Denmark 2$' ([ordered]@{ info = 'Denmark lost Schleswig-Holstein to Prussia and Austria in 1864 but kept Iceland and the Faroe Islands.' })
Main '^United Kingdom$' ([ordered]@{ info = 'The United Kingdom was the leading industrial and naval power, with Gladstone as prime minister; Queen Victoria reigned until 1901.' })
Main '^Alaouite Sultanate$' ([ordered]@{ info = 'Morocco was an independent sultanate under Muhammad IV (1859-73), under growing European pressure.' })
Main '^Qajar Iran$' ([ordered]@{ info = 'Persia was ruled by Naser al-Din Shah of the Qajar dynasty, balancing between Russia and Britain.' })

# Ownership that changed between 1871 and 1900.
$bg = 'Principality of Bulgaria'
$otProps = { param($real, $info) [ordered]@{ realm = $real; label = ''; leader = 'Abdulaziz'; fillColor = $OTfill; borderColor = $OTborder; info = $info } }
Ov 'Principality of Bulgaria' (& $otProps 'Ottoman Empire (Bulgaria)' 'Bulgaria was still a set of Ottoman provinces; the autonomous principality came only in 1878.')
Ov 'Principality of Bulgaria' ([ordered]@{ label = 'Ottoman Empire'; labelOwn = $true })
Ov 'Ottoman Empire (Anatolia)' ([ordered]@{ label = 'Ottoman Empire'; labelOwn = $true })
Ov 'Ottoman Empire' ([ordered]@{ label = '' })
Ov 'Austria-Hungary (Bosnia)' (& $otProps 'Ottoman Empire (Bosnia)' 'Bosnia and Herzegovina were Ottoman until Austria-Hungary occupied them in 1878.')
Ov 'United Kingdom (Cyprus)' (& $otProps 'Ottoman Empire (Cyprus)' 'Cyprus was Ottoman until Britain took over its administration in 1878.')
Ov 'Kingdom of Greece (Thessaly)' (& $otProps 'Ottoman Empire (Thessaly)' 'Thessaly was Ottoman until it was ceded to Greece in 1881.')

Ov 'Egypt (British occupation)' ([ordered]@{ realm = 'Khedivate of Egypt'; leader = 'Isma' + [char]0x2019 + 'il Pasha (Khedive)'; info = 'Egypt was a semi-autonomous Ottoman khedivate; Isma' + [char]0x2019 + 'il opened the Suez Canal in 1869 and ran up huge debts.' })
Ov 'Kingdom of Serbia' ([ordered]@{ realm = 'Principality of Serbia'; leader = 'Milan IV Obrenovi' + [char]0x107 + ' (under regency until 1872)'; excludeIds = @($nisava, 'pirot', 'toplica', 'jablanica', $pcinja); info = 'Serbia was an autonomous principality under Ottoman suzerainty; it gained independence and the Ni' + [char]0x161 + ' region only in 1878, and became a kingdom in 1882.' })
Ov 'Kingdom of Romania' ([ordered]@{ realm = 'Principality of Romania'; leader = 'Carol I (Prince)'; excludeIds = @($constanta, 'tulcea'); info = 'Wallachia and Moldavia united in 1859 and Carol I of Hohenzollern became prince in 1866; Romania was still under Ottoman suzerainty and Dobruja was Ottoman.' })
Ov 'Kingdom of Romania (Principality of Moldavia)' ([ordered]@{ realm = 'Principality of Romania (Moldavia)'; leader = 'Carol I (Prince)' })

Main '^Principality of Montenegro$' ([ordered]@{ leader = 'Nicholas I'; regionFilters = @([ordered]@{ admin = 'Montenegro'; ids = @('cetinje', 'danilovgrad') }); info = 'Montenegro was a small mountain principality around Cetinje under Nicholas I; it was recognised as independent only in 1878, when it roughly doubled in size.' })
Main '^France \(Africa\)$' ([ordered]@{ regionFilters = @([ordered]@{ admin = 'Algeria' }) })
function U($s) { [regex]::Replace($s, '\\u([0-9a-f]{4})', { param($m) [string][char][Convert]::ToInt32($m.Groups[1].Value, 16) }) }
$mneOtt = @('podgorica', (U 'nik\u0161i\u0107'), 'bar', 'ulcinj', 'pljevlja', 'bijelopolje', (U '\u017eabljak'), (U 'plu\u017eine'), (U '\u0161avnik'), (U 'kola\u0161in'), 'mojkovac', 'andrijevica', 'plav', 'berane', (U 'ro\u017eaje'))
$rashka = U 'ra\u0161ka'
$serbiaOv = $overrides['Kingdom of Serbia']['properties']
$serbiaOv['excludeIds'] = @($serbiaOv['excludeIds']) + $rashka

$additions = @(
    [ordered]@{ provinces = @(); properties = [ordered]@{ realm = 'Ottoman Empire (Montenegrin lands)'; label = ''; leader = 'Abdulaziz'; regionFilters = @([ordered]@{ admin = 'Montenegro'; ids = $mneOtt }); fillColor = $OTfill; borderColor = $OTborder; info = 'These districts were Ottoman until Montenegro took them in 1878.' } },
    [ordered]@{ provinces = @(); properties = [ordered]@{ realm = 'Austria-Hungary (Bay of Kotor)'; label = ''; leader = 'Franz Joseph I'; regionFilters = @([ordered]@{ admin = 'Montenegro'; ids = @('kotor', 'hercegnovi', 'budva', 'tivat') }); fillColor = '#ffffff'; borderColor = '#8a8576'; info = 'The Bay of Kotor belonged to the Austrian Kingdom of Dalmatia.' } },
    [ordered]@{ provinces = @(); properties = [ordered]@{ realm = 'Beylik of Tunis'; label = 'Tunis'; leader = 'Muhammad III as-Sadiq (Bey)'; regionFilters = @([ordered]@{ admin = 'Tunisia' }); fillColor = '#c9b36a'; borderColor = '#7a6a30'; info = 'Tunisia was a nominally Ottoman beylik, effectively autonomous and deep in debt; France made it a protectorate in 1881.' } },
    [ordered]@{ provinces = @(); properties = [ordered]@{ realm = 'Ottoman Empire (Nis and Vranje)'; label = ''; leader = 'Abdulaziz'; regionFilters = @([ordered]@{ admin = 'Republic of Serbia'; ids = @($nisava, 'pirot', 'toplica', 'jablanica', $pcinja, $rashka) }); fillColor = $OTfill; borderColor = $OTborder; info = 'These districts (including the Sanjak of Novi Pazar) were Ottoman until Serbia took them in 1878 (Novi Pazar until 1912).' } },
    [ordered]@{ provinces = @(); properties = [ordered]@{ realm = 'Ottoman Empire (Dobruja)'; label = ''; leader = 'Abdulaziz'; regionFilters = @([ordered]@{ admin = 'Romania'; ids = @($constanta, 'tulcea') }); fillColor = $OTfill; borderColor = $OTborder; info = 'Dobruja was Ottoman until it passed to Romania in 1878.' } }
)

$block = [ordered]@{
    baseYear = '1900'
    note = 'Europe in 1871: the German Empire is proclaimed, Italy has just taken Rome, Austria-Hungary is a dual monarchy, France is a republic, and the Balkans, Bosnia and Cyprus are still Ottoman.'
    overrides = $overrides
    additions = $additions
}
$json = (ConvertTo-Json $block -Depth 12) -replace '\\u0027', "'"
[IO.File]::WriteAllText((Join-Path (Get-Location) $Out), $json, (New-Object Text.UTF8Encoding($false)))
Write-Host "overrides $($overrides.Count) additions $($additions.Count)"
