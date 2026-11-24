# package.ps1 - package build/*.material.bin into OutlineShader.mcpack
#
# The manifest is read from pack\manifest.json (NOT regenerated), so you can
# edit it freely; this script only refreshes the compiled materials and zips
# the pack folder. If pack\manifest.json is missing, a default one is created.
#
# Usage (from the BE folder):  powershell -ExecutionPolicy Bypass -File package.ps1

$ErrorActionPreference = 'Stop'
$be = $PSScriptRoot
$pack = Join-Path $be 'pack'
$materials = Join-Path $pack 'renderer\materials'

New-Item -ItemType Directory -Force -Path $materials | Out-Null

# remove stale compiled materials so the pack matches build/ exactly
Remove-Item (Join-Path $materials '*.material.bin') -Force -ErrorAction SilentlyContinue

# --- refresh compiled materials from build/ --------------------------------
$count = 0
Get-ChildItem -File (Join-Path $be 'build\*.material.bin') -ErrorAction SilentlyContinue | ForEach-Object {
    Copy-Item $_.FullName $materials -Force
    $count++
    Write-Output ("packed: " + $_.Name)
}
if ($count -eq 0) {
    Write-Output 'ERROR: no .material.bin in build/. Run the lazurite build first.'
    exit 1
}

# --- manifest: use pack\manifest.json as-is, create default only if missing -
$manifestPath = Join-Path $pack 'manifest.json'
if (-not (Test-Path $manifestPath)) {
    $manifest = [ordered]@{
        format_version = 2
        header = [ordered]@{
            name               = 'Outline Shader (BRD)'
            description        = 'NPR outline shader - Better RenderDragon port'
            uuid               = '4f9c2a1e-7b3d-4e6a-9c8f-1a2b3c4d5e6f'
            version            = @(1, 0, 0)
            min_engine_version = @(1, 20, 15)
        }
        modules = @(
            [ordered]@{
                type    = 'resources'
                uuid    = '8a2b4c6d-1e3f-4a5b-9c0d-2e4f6a8b0c1d'
                version = @(1, 0, 0)
            }
        )
    }
    $manifest | ConvertTo-Json -Depth 6 | Set-Content -Path $manifestPath -Encoding UTF8
    Write-Output 'created default pack\manifest.json'
} else {
    Write-Output 'using existing pack\manifest.json'
}

# --- zip pack/ into .mcpack ------------------------------------------------
$zip = Join-Path $be 'OutlineShader.zip'
$mcpack = Join-Path $be 'OutlineShader.mcpack'
if (Test-Path $zip) { Remove-Item -Force $zip }
Compress-Archive -Path (Join-Path $pack '*') -DestinationPath $zip -Force
if (Test-Path $mcpack) { Remove-Item -Force $mcpack }
Move-Item -Path $zip -Destination $mcpack -Force

Write-Output ''
Write-Output ('OK: ' + $mcpack + ' (' + (Get-Item $mcpack).Length + ' bytes, ' + $count + ' material(s))')
