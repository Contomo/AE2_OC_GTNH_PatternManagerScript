param([string]$Name = 'preview')
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$data = Get-Content -LiteralPath (Join-Path $PSScriptRoot "assline_app.lua-$Name.actual.json") -Raw | ConvertFrom-Json
$bitmap = New-Object System.Drawing.Bitmap(1600, 900)
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$graphics.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit
$font = New-Object System.Drawing.Font('Consolas', 12, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
$format = [System.Drawing.StringFormat]::GenericTypographic
$brushes = @{}
function Brush([int]$Color) {
  if (-not $brushes.ContainsKey($Color)) {
    $brushes[$Color] = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, ($Color -shr 16) -band 255, ($Color -shr 8) -band 255, $Color -band 255))
  }
  return $brushes[$Color]
}
for ($y = 0; $y -lt 50; $y++) {
  for ($x = 0; $x -lt 160; $x++) {
    $graphics.FillRectangle((Brush $data.background[$y][$x]), $x * 10, $y * 18, 10, 18)
    $char = $data.rows[$y].Substring($x, 1)
    if ($char -ne ' ') { $graphics.DrawString($char, $font, (Brush $data.foreground[$y][$x]), [single]($x * 10), [single]($y * 18 + 2), $format) }
  }
}
$bitmap.Save((Join-Path $PSScriptRoot "$Name.png"), [System.Drawing.Imaging.ImageFormat]::Png)
$graphics.Dispose(); $bitmap.Dispose(); $font.Dispose()
foreach ($brush in $brushes.Values) { $brush.Dispose() }
