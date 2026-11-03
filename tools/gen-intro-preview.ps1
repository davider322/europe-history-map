$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$source = Get-Content -Raw -Encoding UTF8 (Join-Path $root 'data\europe-provinces.geojson') | ConvertFrom-Json

Add-Type -TypeDefinition @'
using System;
using System.Globalization;
using System.Text;

public static class IntroCoastline {
    private static double Mercator(double latitude) {
        double radians = Math.Max(-85, Math.Min(85, latitude)) * Math.PI / 180;
        return Math.Log(Math.Tan(Math.PI / 4 + radians / 2));
    }

    public static string Ring(object[] coordinates) {
        var path = new StringBuilder();
        double lastX = double.NaN, lastY = double.NaN;
        double minX = double.PositiveInfinity, minY = double.PositiveInfinity;
        double maxX = double.NegativeInfinity, maxY = double.NegativeInfinity;
        int kept = 0;
        foreach (object coordinate in coordinates) {
            var point = (object[])coordinate;
            double x = 640 + (Convert.ToDouble(point[0]) - 10) * 4096 / 360;
            double y = 450 + (Mercator(54.43668) - Mercator(Convert.ToDouble(point[1]))) * 4096 / (2 * Math.PI);
            minX = Math.Min(minX, x); maxX = Math.Max(maxX, x);
            minY = Math.Min(minY, y); maxY = Math.Max(maxY, y);
            if (kept > 0 && Math.Pow(x - lastX, 2) + Math.Pow(y - lastY, 2) < 1) continue;
            path.Append(kept == 0 ? "M" : "L");
            path.Append(x.ToString("0.0", CultureInfo.InvariantCulture));
            path.Append(" ");
            path.Append(y.ToString("0.0", CultureInfo.InvariantCulture));
            lastX = x; lastY = y; kept++;
        }
        if (kept < 3 || maxX < -20 || minX > 1300 || maxY < -20 || minY > 920) return "";
        return path.Append("Z").ToString();
    }
}
'@

$paths = New-Object Text.StringBuilder
foreach ($feature in $source.features) {
    if ($feature.geometry.type -eq 'Polygon') {
        $polygons = ,$feature.geometry.coordinates
    } elseif ($feature.geometry.type -eq 'MultiPolygon') {
        $polygons = $feature.geometry.coordinates
    } else {
        throw "Unsupported geometry: $($feature.geometry.type)"
    }
    foreach ($polygon in $polygons) {
        $rings = @(foreach ($ring in $polygon) { [IntroCoastline]::Ring($ring) })
        if ($rings[0]) {
            [void]$paths.AppendLine(('      <path d="{0}"/>' -f ($rings -join '')))
        }
    }
}

$svg = @"
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1280 900">
  <title>Europe - year-independent loading preview</title>
  <desc>Coastlines derived from europe-provinces.geojson. Abstract colours do not represent countries or historical borders. Source attribution and licences are retained in the source GeoJSON and map credits.</desc>
  <defs>
    <filter id="colour-soften" x="-20%" y="-20%" width="140%" height="140%">
      <feGaussianBlur stdDeviation="18"/>
    </filter>
    <mask id="land" maskUnits="userSpaceOnUse" x="0" y="0" width="1280" height="900">
      <rect width="1280" height="900" fill="black"/>
      <g fill="white" stroke="white" stroke-width="0.6" fill-rule="evenodd">
$paths      </g>
    </mask>
  </defs>
  <rect width="1280" height="900" fill="#9ebcd8"/>
  <g mask="url(#land)">
    <rect width="1280" height="900" fill="#d2b178"/>
    <g filter="url(#colour-soften)">
      <ellipse cx="300" cy="285" rx="130" ry="90" fill="#82964f"/>
      <ellipse cx="505" cy="415" rx="90" ry="150" fill="#587fa0"/>
      <ellipse cx="420" cy="505" rx="55" ry="85" fill="#a96c54"/>
      <ellipse cx="470" cy="700" rx="130" ry="95" fill="#ad8050"/>
      <ellipse cx="565" cy="580" rx="90" ry="85" fill="#4169a1"/>
      <ellipse cx="665" cy="465" rx="75" ry="90" fill="#c6a253"/>
      <ellipse cx="720" cy="230" rx="75" ry="180" fill="#46709a"/>
      <ellipse cx="810" cy="150" rx="80" ry="170" fill="#bba165"/>
      <ellipse cx="870" cy="320" rx="90" ry="100" fill="#6a8b55"/>
      <ellipse cx="800" cy="510" rx="85" ry="80" fill="#bc7874"/>
      <ellipse cx="700" cy="655" rx="65" ry="100" fill="#6f8a2e"/>
      <ellipse cx="815" cy="650" rx="90" ry="75" fill="#98719a"/>
      <ellipse cx="1020" cy="455" rx="155" ry="160" fill="#557b9b"/>
      <ellipse cx="1050" cy="730" rx="175" ry="85" fill="#d1a52e"/>
      <ellipse cx="490" cy="890" rx="175" ry="85" fill="#598b8a"/>
      <ellipse cx="795" cy="900" rx="130" ry="70" fill="#bd8a58"/>
    </g>
  </g>
</svg>
"@

$target = Join-Path $root 'data\intro-preview.svg'
[IO.File]::WriteAllText($target, $svg, (New-Object Text.UTF8Encoding $false))
Write-Output ("Generated {0} ({1:N0} bytes)" -f $target, (Get-Item $target).Length)
