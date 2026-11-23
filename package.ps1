# package.ps1 - build the .mcpack from build/*.material.bin
# Usage (from the BE folder):  powershell -ExecutionPolicy Bypass -File package.ps1
$ErrorActionPreference = 'Stop'
$be = $PSScriptRoot
$pack = Join-Path $be 'pack'
$materials = Join-Path $pack 'renderer\materials'

if (Test-Path $pack) { Remove-Item -Recurse -Force $pack }
New-Item -ItemType Directory -Force -Path $materials | Out-Null

$count = 0
Get-ChildItem -File (Join-Path $be 'build\*.material.bin') -ErrorAction SilentlyContinue | ForEach-Object {
    Copy-Item $_.FullName $materials
    $count++
    Write-Output ("packed: " + $_.Name)
}
if ($count -eq 0) {
    Write-Output 'ERROR: no .material.bin in build/. Run the lazurite build first.'
    exit 1
}

$manifest = [ordered]@{
    format_version = 2
    header = [ordered]@{
        name               = 'Outline Shader (BRD)'
        description        = 'NPR outline shader - Better RenderDragon port'
        uuid               = [guid]::NewGuid().ToString()
        version            = @(1, 0, 0)
        min_engine_version = @(1, 20, 15)
    }
    modules = @(
        [ordered]@{
            type    = 'resources'
            uuid    = [guid]::NewGuid().ToString()
            version = @(1, 0, 0)
        }
    )
}
$manifest | ConvertTo-Json -Depth 6 | Set-Content -Path (Join-Path $pack 'manifest.json') -Encoding UTF8

$zip = Join-Path $be 'OutlineShader.zip'
$mcpack = Join-Path $be 'OutlineShader.mcpack'
if (Test-Path $zip) { Remove-Item -Force $zip }
Compress-Archive -Path (Join-Path $pack '*') -DestinationPath $zip -Force
if (Test-Path $mcpack) { Remove-Item -Force $mcpack }
Move-Item -Path $zip -Destination $mcpack -Force
Write-Output ''
Write-Output ('OK: ' + $mcpack + ' (' + (Get-Item $mcpack).Length + ' bytes, ' + $count + ' material(s))')
