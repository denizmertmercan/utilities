@echo off
rem Drop a Claude Code session .jsonl onto this file to export it to markdown.
rem Runs extract-claude-transcript.ps1 (same folder) with the dropped path; any extra
rem arguments are passed through. pause keeps the window open so the result or error is readable.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0extract-claude-transcript.ps1" %*
pause
