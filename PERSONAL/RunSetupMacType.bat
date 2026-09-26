@echo off
setlocal enabledelayedexpansion

title MacType Registry Setup

:: ============================================================================
:: MacType Registry Setup Script (Combined BAT + PowerShell)
:: ============================================================================
:: This batch file embeds a PowerShell script at the end, after the
:: :PS_SCRIPT_START label. It checks for administrator privileges, relaunches
:: itself elevated if necessary, then extracts and executes the embedded
:: PowerShell script to configure MacType's AppInit_DLLs registry entries.
::
:: Reference:
::   https://github.com/snowie2000/mactype/wiki/Enable-registry-mode-manually
::
:: NOTE:
::   This script uses full DLL paths for AppInit_DLLs. It does NOT rely on
::   the PATH environment variable. If your MacType installation path contains
::   spaces (e.g., C:\Program Files\MacType), AppInit_DLLs may not parse the
::   path correctly. In that case, consider installing MacType to a path
::   without spaces, or use the short (8.3) path name.
:: ============================================================================

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting administrator privileges...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

cd /d "%~dp0"

echo Administrator rights granted.
echo Launching embedded PowerShell script (bypass execution policy)...
echo.

set "SCRIPT_PATH=%~f0"

set "PS_EXTRACT=$lines = Get-Content -LiteralPath $env:SCRIPT_PATH; $start = [Array]::IndexOf($lines, ':PS_SCRIPT_START'); if ($start -lt 0) { Write-Error 'PS_SCRIPT_START marker not found.'; exit 1 }; $ps = $lines[($start + 1)..($lines.Length - 1)] -join [Environment]::NewLine; Invoke-Expression $ps"

powershell -NoProfile -ExecutionPolicy Bypass -Command "%PS_EXTRACT%"

exit /b

:PS_SCRIPT_START
<#
.SYNOPSIS
    Configure MacType registry entries for registry loading mode.
.DESCRIPTION
    This script requires administrator privileges.
    It writes MacType64.dll and MacType.dll paths to AppInit_DLLs,
    sets LoadAppInit_DLLs = 1 and RequireSignedAppInit_DLLs = 0.

    Before writing, it checks whether the existing AppInit_DLLs value
    already contains the MacType DLL (matching either the full path or the
    file name, case-insensitively). If the DLL is already present and the
    companion values are also correct, the entry is skipped and reported
    as "already configured".

    Reference:
    https://github.com/snowie2000/mactype/wiki/Enable-registry-mode-manually
#>

# ============================================================================
# Configuration
# ============================================================================

$MacTypePath = "C:\Program Files\MacType"

$RegPaths = @(
    @{
        Path        = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows"
        DllName     = "MacType64.dll"
        Description = "64-bit registry hive"
    },
    @{
        Path        = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows NT\CurrentVersion\Windows"
        DllName     = "MacType.dll"
        Description = "32-bit registry hive (WOW6432Node)"
    }
)

# ============================================================================
# Helper Functions
# ============================================================================

<#
.SYNOPSIS
    Checks whether an AppInit_DLLs value already contains the specified DLL.
.DESCRIPTION
    AppInit_DLLs is a comma- or space-delimited list of DLL names or paths.
    This function splits the value and compares each entry against both the
    file name (e.g., MacType64.dll) and the full path, case-insensitively.
#>
function Test-AppInitContainsDll {
    param(
        [string]$AppInitValue,
        [string]$DllName,
        [string]$FullPath
    )

    if ([string]::IsNullOrWhiteSpace($AppInitValue)) {
        return $false
    }

    # Split on comma or whitespace, discard empty entries
    $items = $AppInitValue -split '[, \t]+' | Where-Object { $_.Trim() -ne '' }

    foreach ($item in $items) {
        $trimmed = $item.Trim()
        if ($trimmed -ieq $DllName -or $trimmed -ieq $FullPath) {
            return $true
        }
    }

    return $false
}

# ============================================================================
# Administrator Privilege Check
# ============================================================================

if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "Error: This script must be run as administrator." -ForegroundColor Red
    Read-Host -Prompt "Press Enter to exit"
    exit 1
}

Write-Host "=== MacType Registry Setup ===" -ForegroundColor Cyan
Write-Host "MacType Path: $MacTypePath" -ForegroundColor Yellow
Write-Host ""

# ============================================================================
# Installation Directory Check
# ============================================================================

if (-NOT (Test-Path $MacTypePath)) {
    Write-Host "ERROR: MacType directory not found: $MacTypePath" -ForegroundColor Red
    Write-Host ""
    Write-Host "Please install MacType to the default location:" -ForegroundColor Yellow
    Write-Host "  C:\Program Files\MacType\" -ForegroundColor White
    Write-Host ""
    Write-Host "If you have installed MacType elsewhere, edit the `$MacTypePath" -ForegroundColor Yellow
    Write-Host "variable at the top of the PowerShell section in this file." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Reference:" -ForegroundColor Gray
    Write-Host "  https://github.com/snowie2000/mactype/wiki/Enable-registry-mode-manually" -ForegroundColor Cyan
    Write-Host ""
    Read-Host -Prompt "Press Enter to exit"
    exit 1
}

# ============================================================================
# Step 1: Inspect Existing Values
# ============================================================================

Write-Host "[1/3] Inspecting existing AppInit_DLLs values..." -ForegroundColor Green

$entries = @()

foreach ($reg in $RegPaths) {
    $path        = $reg.Path
    $dllName     = $reg.DllName
    $description = $reg.Description
    $fullDllPath = Join-Path $MacTypePath $dllName

    $currentValue = $null
    $loadValue    = $null
    $requireValue = $null

    try {
        $currentValue = Get-ItemProperty -Path $path -Name "AppInit_DLLs" -ErrorAction SilentlyContinue |
                        Select-Object -ExpandProperty "AppInit_DLLs"
    } catch { }

    try {
        $loadValue = Get-ItemProperty -Path $path -Name "LoadAppInit_DLLs" -ErrorAction SilentlyContinue |
                     Select-Object -ExpandProperty "LoadAppInit_DLLs"
    } catch { }

    try {
        $requireValue = Get-ItemProperty -Path $path -Name "RequireSignedAppInit_DLLs" -ErrorAction SilentlyContinue |
                        Select-Object -ExpandProperty "RequireSignedAppInit_DLLs"
    } catch { }

    $dllPresent = Test-AppInitContainsDll -AppInitValue $currentValue -DllName $dllName -FullPath $fullDllPath
    $loadOk     = ($loadValue -eq 1)
    $requireOk  = ($requireValue -eq 0)

    $entries += @{
        Path          = $path
        DllName       = $dllName
        Description   = $description
        FullDllPath   = $fullDllPath
        CurrentValue  = $currentValue
        LoadValue     = $loadValue
        RequireValue  = $requireValue
        DllPresent    = $dllPresent
        LoadOk        = $loadOk
        RequireOk     = $requireOk
        FullyDone     = ($dllPresent -and $loadOk -and $requireOk)
    }

    Write-Host "  $path ($description)" -ForegroundColor Gray
    Write-Host "    AppInit_DLLs        = $(if ($null -eq $currentValue) { '<not set>' } else { $currentValue })" -ForegroundColor Yellow
    Write-Host "    LoadAppInit_DLLs    = $(if ($null -eq $loadValue) { '<not set>' } else { $loadValue })" -ForegroundColor Yellow
    Write-Host "    RequireSigned...    = $(if ($null -eq $requireValue) { '<not set>' } else { $requireValue })" -ForegroundColor Yellow

    if ($dllPresent) {
        Write-Host "    -> DLL already present in AppInit_DLLs" -ForegroundColor Green
    }
    if ($loadOk) {
        Write-Host "    -> LoadAppInit_DLLs is already 1" -ForegroundColor Green
    }
    if ($requireOk) {
        Write-Host "    -> RequireSignedAppInit_DLLs is already 0" -ForegroundColor Green
    }
    if ($entries[-1].FullyDone) {
        Write-Host "    => Already fully configured, will skip." -ForegroundColor Cyan
    }
    Write-Host ""
}

# ============================================================================
# Step 2: Write Registry Entries (only where needed)
# ============================================================================

Write-Host "[2/3] Writing registry entries..." -ForegroundColor Green
$success = $true
$anyWritten = $false

foreach ($entry in $entries) {
    $path        = $entry.Path
    $dllName     = $entry.DllName
    $fullDllPath = $entry.FullDllPath

    if ($entry.FullyDone) {
        Write-Host "  [SKIP] $($entry.Description) - already configured." -ForegroundColor Cyan
        continue
    }

    if (-NOT (Test-Path $fullDllPath)) {
        Write-Host "  [ERROR] DLL not found: $fullDllPath" -ForegroundColor Red
        $success = $false
        continue
    }

    try {
        # --- Determine new AppInit_DLLs value ---
        $newValue = $null

        if ([string]::IsNullOrWhiteSpace($entry.CurrentValue)) {
            $newValue = $fullDllPath
        } else {
            if ($entry.DllPresent) {
                # DLL already listed; keep existing value
                $newValue = $entry.CurrentValue
            } else {
                # Append with comma separator
                $trimmed = $entry.CurrentValue.TrimEnd(' ', ',')
                $newValue = "$trimmed,$fullDllPath"
            }
        }

        # --- Write AppInit_DLLs ---
        Set-ItemProperty -Path $path -Name "AppInit_DLLs" -Value $newValue -Type String -Force
        Write-Host "  [OK] AppInit_DLLs = $newValue" -ForegroundColor Green

        # --- Write LoadAppInit_DLLs ---
        Set-ItemProperty -Path $path -Name "LoadAppInit_DLLs" -Value 1 -Type DWord -Force
        Write-Host "  [OK] LoadAppInit_DLLs = 1" -ForegroundColor Green

        # --- Write RequireSignedAppInit_DLLs ---
        Set-ItemProperty -Path $path -Name "RequireSignedAppInit_DLLs" -Value 0 -Type DWord -Force
        Write-Host "  [OK] RequireSignedAppInit_DLLs = 0" -ForegroundColor Green

        $anyWritten = $true
    } catch {
        Write-Host "  [ERROR] Failed to write to $path : $_" -ForegroundColor Red
        $success = $false
    }
}

# ============================================================================
# Step 3: Verify
# ============================================================================

Write-Host "`n[3/3] Verifying registry entries..." -ForegroundColor Green

if ($success) {
    foreach ($entry in $entries) {
        $path        = $entry.Path
        $description = $entry.Description
        try {
            $appInit  = Get-ItemProperty -Path $path -Name "AppInit_DLLs" -ErrorAction SilentlyContinue |
                        Select-Object -ExpandProperty "AppInit_DLLs"
            $load     = Get-ItemProperty -Path $path -Name "LoadAppInit_DLLs" -ErrorAction SilentlyContinue |
                        Select-Object -ExpandProperty "LoadAppInit_DLLs"
            $require  = Get-ItemProperty -Path $path -Name "RequireSignedAppInit_DLLs" -ErrorAction SilentlyContinue |
                        Select-Object -ExpandProperty "RequireSignedAppInit_DLLs"

            Write-Host "  $path ($description)" -ForegroundColor Gray
            Write-Host "    AppInit_DLLs        = $appInit" -ForegroundColor Cyan
            Write-Host "    LoadAppInit_DLLs    = $load" -ForegroundColor Cyan
            Write-Host "    RequireSigned...    = $require" -ForegroundColor Cyan
        } catch {
            Write-Host "  [WARN] Could not read $path" -ForegroundColor Yellow
        }
    }

    if ($anyWritten) {
        Write-Host "`nConfiguration completed. Please restart your computer to apply changes." -ForegroundColor Magenta
    } else {
        Write-Host "`nAll entries were already configured. No changes were made." -ForegroundColor Magenta
    }
} else {
    Write-Host "`nSome operations failed. Please check the error messages and retry." -ForegroundColor Red
}

Read-Host -Prompt "`nPress Enter to exit"