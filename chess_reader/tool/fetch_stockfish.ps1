# Downloads the official Stockfish Windows binary into assets/engines/.
# The binary is not committed (110 MB, > GitHub's file limit); run this once
# after cloning. The Windows build bundles it via windows/CMakeLists.txt.
$ErrorActionPreference = "Stop"
$dest = Join-Path $PSScriptRoot "..\assets\engines"
New-Item -ItemType Directory -Force $dest | Out-Null
$exe = Join-Path $dest "stockfish-windows-x86-64-avx2.exe"
if (Test-Path $exe) {
    Write-Host "Already present: $exe"
    exit 0
}
$rel = Invoke-RestMethod "https://api.github.com/repos/official-stockfish/Stockfish/releases/latest"
$asset = $rel.assets | Where-Object { $_.name -eq "stockfish-windows-x86-64-avx2.zip" }
Write-Host "Downloading Stockfish $($rel.tag_name)..."
$zip = Join-Path $env:TEMP "stockfish.zip"
Invoke-WebRequest $asset.browser_download_url -OutFile $zip
$extract = Join-Path $env:TEMP "stockfish-extract"
Expand-Archive $zip -DestinationPath $extract -Force
$found = Get-ChildItem $extract -Recurse -Filter "*.exe" | Select-Object -First 1
Copy-Item $found.FullName $exe
Remove-Item $zip -Force
Remove-Item $extract -Recurse -Force
Write-Host "Installed: $exe"
