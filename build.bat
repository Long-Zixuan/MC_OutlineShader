@echo off
rem Build every material folder (ColorPostProcessing, RenderChunk, ...) and
rem package all of them into OutlineShader.mcpack.
rem   ColorPostProcessing -> colour-edge post-process outline
rem   RenderChunk         -> texture outline (forward mode only)
rem Requires: Python 3.10 + lazurite (pip install lazurite==0.10.0) + env\shaderc.exe + dxc.exe
cd /d "%~dp0"
if not exist build mkdir build

set "DXC=C:\Program Files (x86)\Windows Kits\10\bin\10.0.22621.0\x64\dxc.exe"
py -3.10 -m lazurite build "%~dp0." --shaderc "%~dp0env\shaderc.exe" --dxc "%DXC%" -o "%~dp0build"
if errorlevel 1 goto :fail

powershell -ExecutionPolicy Bypass -File "%~dp0package.ps1"
if errorlevel 1 goto :fail

echo.
echo Done. Install OutlineShader.mcpack as a resource pack.
goto :eof

:fail
echo.
echo BUILD FAILED
exit /b 1
