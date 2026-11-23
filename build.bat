@echo off
rem Build RenderChunk.material.bin, then package it into OutlineShader.mcpack.
rem Requires: Python 3.10 + lazurite (pip install lazurite==0.10.0) + env\shaderc.exe
cd /d "%~dp0"
if not exist build mkdir build

py -3.10 -m lazurite build "%~dp0." --shaderc "%~dp0env\shaderc.exe" -o "%~dp0build"
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
