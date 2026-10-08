@echo off
chcp 65001 >nul
title Servidor local do app

REM ============================================================
REM  SERVIR.bat - abre o app do jeito certo
REM
REM  Duplo clique no index.html NAO funciona: em file:// o
REM  navegador bloqueia o login do Firebase, a camera do leitor
REM  de codigo de barras e o modo offline. Este arquivo serve a
REM  pasta por http, que e o que o app precisa.
REM
REM  Deixe esta janela aberta enquanto estiver usando o app.
REM ============================================================

cd /d "%~dp0"

set "PY="
where py >nul 2>&1 && set "PY=py -3"
if not defined PY ( where python >nul 2>&1 && set "PY=python" )
if not defined PY (
  echo  Python nao encontrado. Instale de python.org marcando
  echo  "Add python.exe to PATH" e rode este arquivo de novo.
  pause & exit /b 1
)

set "PORTA=8000"

echo.
echo  ============================================================
echo   Neste computador:   http://localhost:%PORTA%
echo.
echo   Em outro aparelho da mesma rede (celular do balcao),
echo   use um dos enderecos abaixo com :%PORTA% no fim:
for /f "tokens=2 delims=:" %%i in ('ipconfig ^| findstr /c:"IPv4"') do echo      http://%%i:%PORTA%
echo.
echo   Para o celular funcionar, cadastre esse IP no Firebase:
echo   Authentication ^> Settings ^> Dominios autorizados.
echo  ============================================================
echo.
echo  Encerrar: feche esta janela ou pressione Ctrl+C.
echo.

start "" "http://localhost:%PORTA%"
%PY% -m http.server %PORTA%
