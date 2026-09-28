$ErrorActionPreference = 'Stop'
$node = Get-Command node.exe -ErrorAction SilentlyContinue
if ($node) { $exe = $node.Source } else { $exe = 'C:\Program Files\nodejs\node.exe' }
& $exe (Join-Path $PSScriptRoot 'build.js')
if ($LASTEXITCODE -ne 0) { throw 'Build failed' }
