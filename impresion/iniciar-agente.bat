@echo off
REM Pinchos la 17 ? Agente de impresion de comandas (Windows)
REM Doble clic para iniciarlo. Si se cierra por un error, vuelve a arrancar solo a los 5 segundos.
title Comandas Pinchos la 17 - NO CERRAR
cd /d "%~dp0.."
:inicio
node impresion\agente.mjs
echo El agente se detuvo. Reiniciando en 5 segundos... (cierra esta ventana para apagarlo)
timeout /t 5 /nobreak >nul
goto inicio
