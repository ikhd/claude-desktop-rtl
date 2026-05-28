@echo off
title Claude Desktop RTL - Installer
REM Runs the in-place patcher. It will ask for Administrator (UAC) - click Yes,
REM then watch the elevated PowerShell window it opens.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install-windows.ps1"
