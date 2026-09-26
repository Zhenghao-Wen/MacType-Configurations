@echo off
chcp 65001 >nul
title WPS MacType Block Remover

:: ============================================================================
:: WPS MacType Block Remover (Combined BAT + PowerShell)
:: ============================================================================
:: This batch file embeds a PowerShell script at the end, after the
:: :PS_SCRIPT_START label. It extracts and executes the embedded script
:: to remove the "MacType.Core" line from WPS Office's krpt.ini file.
::
:: NOTE:
::   Recent WPS Office versions (approximately build 20000 and later),
::   when freshly installed, no longer create the krpt.ini protection list
::   file. In that case, this script will find nothing to remove and will
::   exit gracefully. The script is retained for older installations or
::   systems upgraded from older WPS versions.
:: ============================================================================

echo Running embedded PowerShell script...

:: Store the full path to this batch file in an environment variable.
set "SCRIPT_PATH=%~f0"

:: Define the PowerShell extraction command as a single-line variable.
set "PS_EXTRACT=$lines = Get-Content -LiteralPath $env:SCRIPT_PATH; $start = [Array]::IndexOf($lines, ':PS_SCRIPT_START'); if ($start -lt 0) { Write-Error 'PS_SCRIPT_START marker not found.'; exit 1 }; $ps = $lines[($start + 1)..($lines.Length - 1)] -join [Environment]::NewLine; Invoke-Expression $ps"

:: Execute the embedded PowerShell script.
powershell -NoProfile -ExecutionPolicy Bypass -Command "%PS_EXTRACT%"

pause
exit /b

:PS_SCRIPT_START
<#
.SYNOPSIS
    Safely removes the line containing "MacType.Core" from WPS Office's krpt.ini file.
.DESCRIPTION
    This script locates the active krpt configuration folder for WPS Office,
    backs up the original krpt.ini, and deletes the line that blocks MacType.
    It uses line-by-line filtering to avoid corrupting the file structure.
    Reference at "https://github.com/snowie2000/mactype/wiki/WPS".

.NOTES
    Recent WPS Office versions (approximately build 20000 and later),
    when freshly installed, no longer create the krpt.ini protection list
    file. Therefore, if the paths or files below are not found, it is likely
    a normal situation for a modern WPS installation, and no action is
    required. The script will report this and exit without error.
#>

$ErrorActionPreference = "Stop"

# ============================================================================
# Locate WPS Addons Directory
# ============================================================================

# Path to WPS addons. WPS stores its addons in the user's AppData folder.
$addonsBasePath = "$env:APPDATA\kingsoft\wps\addons\pool\win-i386"

# Check if the addons directory exists. If not, WPS may not be installed,
# may not have been run yet, or may be a modern version that no longer
# creates the krpt protection list.
if (-not (Test-Path $addonsBasePath)) {
    Write-Host "INFO: WPS addons path not found: $addonsBasePath" -ForegroundColor Yellow
    Write-Host "This is normal for fresh WPS installations around build 20000 or later," -ForegroundColor Yellow
    Write-Host "which no longer generate the krpt.ini protection list file." -ForegroundColor Yellow
    Write-Host "No action is required." -ForegroundColor Green
    exit 0
}

# ============================================================================
# Find the Latest krpt* Folder
# ============================================================================

# WPS anti-malware module (krpt) creates versioned folders. We need the
# most recently modified one, which corresponds to the active configuration.
$krptFolders = Get-ChildItem -Path $addonsBasePath -Directory | Where-Object { $_.Name -like "krpt*" } | Sort-Object LastWriteTime -Descending
if ($krptFolders.Count -eq 0) {
    Write-Host "INFO: No folder starting with 'krpt' found in $addonsBasePath" -ForegroundColor Yellow
    Write-Host "This is normal for fresh WPS installations around build 20000 or later," -ForegroundColor Yellow
    Write-Host "which no longer generate the krpt.ini protection list file." -ForegroundColor Yellow
    Write-Host "No action is required." -ForegroundColor Green
    exit 0
}

$latestKrptFolder = $krptFolders[0]
$krptIniPath = Join-Path -Path $latestKrptFolder.FullName -ChildPath "krpt.ini"

if (-not (Test-Path $krptIniPath)) {
    Write-Host "INFO: krpt.ini not found at $krptIniPath" -ForegroundColor Yellow
    Write-Host "This is normal for fresh WPS installations around build 20000 or later," -ForegroundColor Yellow
    Write-Host "which no longer generate the krpt.ini protection list file." -ForegroundColor Yellow
    Write-Host "No action is required." -ForegroundColor Green
    exit 0
}

Write-Host "Found configuration file: $krptIniPath" -ForegroundColor Green

# ============================================================================
# Backup krpt.ini
# ============================================================================

# Create a backup of the original file before making any changes.
$backupPath = "$krptIniPath.backup"
Copy-Item -Path $krptIniPath -Destination $backupPath -Force
Write-Host "Backup saved to: $backupPath" -ForegroundColor Cyan

# ============================================================================
# Remove MacType.Core Line
# ============================================================================

# Read all lines from krpt.ini. WPS typically saves this file as UTF-8.
$lines = [System.IO.File]::ReadAllLines($krptIniPath, [System.Text.Encoding]::UTF8)

# Filter out any line that contains "MacType.Core". This is the line that
# WPS uses to block MacType from injecting into its processes.
$newLines = $lines | Where-Object { $_ -notmatch "MacType\.Core" }

# Check if any line was actually removed.
if ($newLines.Count -eq $lines.Count) {
    Write-Host "No line containing 'MacType.Core' was found. No changes made." -ForegroundColor Yellow
    Remove-Item $backupPath -Force
} else {
    # Write the filtered lines back to krpt.ini using UTF-8 without BOM.
    # Using UTF8Encoding($false) ensures no byte order mark is added,
    # which could corrupt the INI file for WPS.
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllLines($krptIniPath, $newLines, $utf8NoBom)
    Write-Host "Successfully removed the line containing 'MacType.Core'." -ForegroundColor Green
}

Write-Host "Operation completed. Please restart WPS Office for changes to take effect." -ForegroundColor Yellow