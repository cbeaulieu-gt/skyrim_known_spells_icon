param(
    [ValidateSet(
        "build-ae-debug",
        "build-ae-release",
        "build-se-debug",
        "build-se-release",
        "build-ae-debug-global",
        "build-ae-release-global",
        "build-se-debug-global",
        "build-se-release-global"
    )]
    [string]$Preset = "build-ae-release",
    [switch]$UseGlobalVcpkg
)

$ErrorActionPreference = "Stop"

$vswhere = "C:/Program Files (x86)/Microsoft Visual Studio/Installer/vswhere.exe"
if (-not (Test-Path $vswhere)) {
    throw "vswhere.exe not found. Install Visual Studio Build Tools."
}

$vsPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $vsPath) {
    throw "MSVC build tools were not found by vswhere."
}

$devCmd = Join-Path $vsPath "Common7/Tools/VsDevCmd.bat"
if (-not (Test-Path $devCmd)) {
    throw "VsDevCmd.bat not found at $devCmd"
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$escapedDevCmd = $devCmd.Replace('/', '\\')

if ($UseGlobalVcpkg) {
    if (-not $env:VCPKG_ROOT) {
        throw "UseGlobalVcpkg was specified, but VCPKG_ROOT is not set in this shell."
    }

    if ($Preset -notlike "*-global") {
        $globalPreset = "$Preset-global"
        $availablePresets = & cmake --list-presets=build 2>$null
        $quotedPreset = '"' + $globalPreset + '"'
        if ($availablePresets -match [regex]::Escape($quotedPreset)) {
            Write-Host "Using global vcpkg build preset: $globalPreset"
            $Preset = $globalPreset
        }
    }
}

$cmd = '"{0}" -arch=x64 && cd /d "{1}" && cmake --build --preset {2}' -f $escapedDevCmd, $repoRoot, $Preset
cmd /c $cmd
if ($LASTEXITCODE -ne 0) {
    throw "CMake build failed with exit code $LASTEXITCODE"
}

Write-Host "Build completed for preset: $Preset"
