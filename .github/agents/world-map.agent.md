---
description: "Bygger och finjusterar den historiska Leaflet-kartan över Europa (data/years.json, index.html). Använd för att lägga till år, ändra riken, färger, etiketter och gränser."
---
Du arbetar på en datadriven historisk Leaflet-karta i detta projekt. Användaren skriver svenska och vill ha korta svar, helst på svenska.

## Struktur
- `index.html`: renderar kartan och en tidsslider. År kommer från nycklarna i `data/years.json`.
- `data/years.json`: platt objekt med år (1000, 1066, 1100 … 1900). 1000 har `countries`. Senare år har `baseYear`, `note`, `overrides` och `additions`, och samma provinspolygoner återanvänds.
- Override-nycklar är rikets namn i basåret (efter ev. namnbyte). Egenskaper: `realm` (nytt namn), `label` (`""` döljer), `leader`, `info`, `fillColor`, `borderColor`, `regionFilters` (`{admin, geo, ids[], excludeIds[]}`), `excludeIds`, `provinces`.
- `excludeIds` i en override ERSÄTTER basens lista, så upprepa tidigare exkluderingar (t.ex. HRE).
- Riken med samma namnstam före " (" och samma färger delas i en gränsgrupp (inga inre streck). Olika färg eller namn ger synlig gräns.

## Konventioner
- Nytt år: lägg ett block efter det senaste, med `baseYear` = föregående år. Ändra bara det som förändrats.
- Behåll provinser och grund; justera bara ägande, namn, färger, ledare och info.
- Färger: HRE/Habsburg/Österrike-Ungern VIT `#ffffff`/`#8a8576` (alla år); Danmark och Danmark–Norge mörkrött `#8b1e2d`/`#4b0d16`, Kalmarunionen klart gult `#ffeb00`/`#8a7600`, Polen–Litauen och Kongresspolen ljusrött `#f08080`/`#a84646` (håll konsekvent genom åren och skilt från Englands röd `#c0504d`/`#6e2927`); 1900: Ryssland mörkgrön `#1c3a22`/`#0b1a10`, Osmanska guld `#d1a52e`/`#7a5f12` (extra etikett över Libyen via `labelOwn`), Sverige–Norge mörkblå `#102548`/`#06142b`, etiketter spänner över hela rikesgruppen (samma namnstam+färg), Osmanska `#6f8a2e`/`#44561a`, Spanien `#a37d45`/`#654d2b`, Frankrike `#4169a1`/`#203b61`, Ryssland `#557b9b`/`#314b61`, Sverige `#46709a`/`#1f3d5e`, Brandenburg/Preussen grå `#8b8f9e`/`#4c4f5c` (som Tyska riket).
- Användaren föredrar samma färger framför sammanslagning när riken är i personalunion (Böhmen, Ungern, Kroatien = HRE-färg, egna etiketter).
- Kartetiketter använder Barlow Semi Condensed (Google Fonts) i vikt 600, versaler och bokstavsavstånd 0,04 em. Samma typsnitt används i hela gränssnittet: tidslinjen (årtalet utan versaler), popup-rutan och sidopanelen. Texten är svart (`#111111`) med en ljus gräddfärgad kontur (`paint-order: stroke`, bredd ≈ 0,14 × fontstorleken). Användaren provade text i landets egen färg men föredrog svart med ljus kontur.
- Brödtext (tidslinjens beskrivning, panelens ledare/info, popupens provinsnamn) använder Inter via `--body-font`; användaren ville inte ha serif. Rubriker/etiketter förblir Barlow.
- UI-kontroller (zoomknappar, källraden nere till höger) följer pergamentstilen `#f1e2c6`/`#b18a5d`/`#4a3520`. Källraden börjar med "© 2026 David Ericson" och ska behålla Esri, OpenStreetMap, geoBoundaries och Eurostat GISCO.
- Startintro: suddig förhandsbild av färgade 867-kartan (`data/intro-preview.jpg` i `#intro::before`, blur 12px; inte svart/vit). Ta om bilden om 867 eller startvyn ändras med pergamentrulle högt upp (14vh) som bara säger "Loading" + pulserande prickar; när första året visats tonas den bort och kartan går från avmättad till full färg (`#map.is-intro` → `finishIntro()`). Startfel visas i rullen via `showIntroError`.
- Prestanda: alla år förbyggs i bakgrunden och cachas (`YEAR_CACHE_LIMIT = Infinity`, ca 6,5 MB/år, ca 360 MB totalt; användaren godkände). Crossfaden är JS-styrd så att sammanlagd täckning hålls vid `FILL_OPACITY` (0,85).

## Skriva filer (Windows/PowerShell)
- Skriv UTF-8 utan BOM, t.ex. `[IO.File]::WriteAllText($p,$t,(New-Object Text.UTF8Encoding $false))`. Konsolutskrift av icke-ASCII är förvrängd; kopiera aldrig id:n från konsolen.
- Kör skript med `powershell -ExecutionPolicy Bypass -File ...`.
- Validera efter ändring: JSON ska parsa, och inga överlapp ("unassigned" ≈ 260 är känd baslinje).

## Verifiering i webbläsaren
- Ladda `file:///C:/Users/David/Documents/World%20Map/index.html?v=<tidsstämpel>` (cache-bust), vänta ~25 s, fokusera `input[type=range]`, tryck `End`, vänta ~16 s.
- Skärmdumpar är ofta inaktuella; flytta kartan lite med `map.panBy` och ta ny. Pålitligast: `map.eachLayer(l => l.feature.properties.id, l.options.fillColor)`.

## Kända öppna punkter
- Kosovo ska kontrolleras för 1000–1400 (hål/streckade gränser).
- Spanska Italien kan få ljusare nyans.
- Förenklingar: Nederländska Nordbrabant som Republiken, Jura ej spanskt 1600. Svenska Pommern 1700/1800 använder de moderna distrikten Vorpommern-Rügen och Vorpommern-Greifswald; Mecklenburg får de återstående sex distrikten. År 1815 återgår kartan till den sammanslagna Mecklenburg–Vorpommern-polygonen under Mecklenburg. Ingermanland 1700 representeras approximativt av moderna Leningradregionen och Sankt Petersburg; området återgår till Ryssland 1800.
- 1800 förenklar gränserna i Polens delningar till moderna administrativa provinser; vänstra Rhenstranden, Belgien och Luxemburg är franska.
- 1900 är byggt (baseYear 1800): Tyska riket, Österrike-Ungern, Italien, Schweiz, Belgien, Nederländerna, självständiga Balkanstater, franska Algeriet/Tunisien, Sverige–Norge i union. Genererat med `tools\gen1900.ps1` (mappar varje 1800-rike till nya riken och skriver `frag1900.json`, som sedan sätts in sist i years.json). Fungerar som mall för nästa år.
- 867 är byggt på 900 och uppdaterar hela Europa: karolingiska riken, Lotharingen, Provence, Stora Mähren, Magyarernas läge före inflyttningen i Karpaterbäckenet, Bulgarien/Byzans, Iberien och Britannien samt osäkerheten kring nordiska riken och Island.
- 900 är ett brett utkast byggt på 1000 med omfördelningar i hela Europa: Wessex/Mercia/Danelaw, Väst- och Östfrankerriket, Lotharingen, Italien, Övre/Nedre Burgund, Stora Mähren, magyarerna, Bulgarien/Serbien, Asturien och Córdoba. Små områden och flera gränser är fortfarande förenklade; moderna provinser används som approximationer.
- 962 är byggt på 900: Otto I:s kejsarkröning, det heliga romerska riket inklusive Lotharingen, Italien i personalunion, kungariket Arles, Normandie och enat England. Egypten och delar av Levanten visas under Ikhshididerna (Fatimidernas erövring av Egypten skedde 969); Ifriqiya ligger under Fatimidisk auktoritet. Även centraleuropeiska, iberiska, balkanska, nordiska, irländska och kaukasiska ledare/riken har uppdaterats för perioden; moderna provinser är ungefärliga kartgränser.
- Verktyg: `tools\resolve.ps1 -Year <år> -Mode list|check|assign|summary [-Admin X]` (kör med `powershell -ExecutionPolicy Bypass -File`). Mål: 0 OVERLAP, 0 UNKNOWN OVERRIDE. År 1000 har 350 otilldelade provinser; Bačka-överlappen är lösta.
- Bačka i år 1000: Ungern äger `northbačka`, `southbačka` och `westbačka` enligt kartans uttalade gränsantagande. Bulgariens `data\first-bulgarian-empire\1000.geojson` hade felaktigt UTF-8-korrupta exkluderings-ID:n (`baÄka`); de är rättade till korrekta ID:n. Alla 23 år validerar nu utan överlapp eller okända overrides.
- 1100 års fyra överlapp mellan armeniska riken och östra emiraten är lösta: `excludeIds` på Armenian Kingdoms and Principalities lämnar `ardahan`, `kars`, `van` och `bitlis` till Eastern Anatolian and Jazira Emirates. År 1200 återställs `excludeIds: []` för Armenian Kingdoms and Principalities, så de tre senare armeniska områdena inte förblir otilldelade efter att emiraten upplösts.
- Norra Cyperns saknade Kyrenia-distrikt är tillagt som `id: kyrenia` i `data\europe-provinces.geojson`, med geometri från GeoBoundaries (OpenStreetMap/Wambacher, ODbL 1.0) och käll/licensmetadata. År 2000 har `kyrenia` lagts till i Cyperns explicit-ID-filter. Resolvern tilldelar Kyrenia under alla 23 år; de ursprungliga fem cypriotiska ID:na är oförändrade.
- Området norr om Moldavien kontrollerades visuellt för 1600 och 1700; det är tilldelat Polen–Litauen och ingen vit lucka syns. Den tidigare noteringen om ett hål var inaktuell.
- Ett rest-rike (delvis kvar) ska göras som override med `provinces: []` + `regionFilters`, aldrig som addition med samma namn (webbläsaren avvisar dubbla namn).
- Skåne/Halland/Blekinge/Gotland är svenska från 1700 (addition "Sweden (Scania)" + excludeIds på Denmark–Norway). Tidigare fel är rättat.
- Sverige har färgen #102548/#06142b i alla år från 1500; Ryssland/Moskva #1c3a22/#0b1a10; Preussen/Brandenburg grått #8b8f9e/#4c4f5c (Pommern behåller sin färg).
- Ledare/info: när ett rike finns kvar i ett nytt år MÅSTE leader och info överskrivas (annars ärvs fel ledare från äldre år). Kontrollera med resolveYearConfigs(år) att inga gamla ledare finns kvar. Ledare/info för 1600–1900 är granskade. 1900 styrs via textFix i tools\gen1900.ps1.
- 1871 är byggt på 1900 (baseYear 1900) via tools\gen1871.ps1 (läser names1900.txt = realmnamn i 1900). Block-ordning i years.json: 1871 ligger före 1900. När 1900 splitsas om (gen1900) behåll 1871-blocket (klipp bara från ,"1900").
- 1815 (Wienkongressen) är byggt på 1800 via tools\gen1815.ps1 (kopia av gen1900-ramverket med egen NewKey/Spec/mainOld). Eget rike per tyskt delstat (Bayern, Sachsen, Hannover, Württemberg och Baden, Hessen, Thüringen, Mecklenburg, Hamburg/Bremen), Kongresspolen, Österrikiska kejsardömet (Lombardiet–Venetien), Nederländerna (förenade), Sverige–Norge. Block-ordning: 1800, 1815, 1871, 1900. Validering: resolve.ps1 -Year 1815 -Mode check ger 260 otilldelade.
- Nästa år att bygga: 2000 (modern tid).
- Försök med bitmapp/canvas-etiketter (för snabbare zoom) avvisades: suddiga och fel lagerordning. Behåll levande SVG-etiketter.
