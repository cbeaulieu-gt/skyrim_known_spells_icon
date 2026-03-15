param(
    [string]$Preset = "vs2022-debug",
    [switch]$Clean
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

function Get-ConfigurePresetByName {
    param(
        [object[]]$ConfigurePresets,
        [string]$Name
    )

    return $ConfigurePresets | Where-Object { $_.name -eq $Name } | Select-Object -First 1
}

function Resolve-ConfigureCacheVariables {
    param(
        [object[]]$ConfigurePresets,
        [string]$PresetName
    )

    $preset = Get-ConfigurePresetByName -ConfigurePresets $ConfigurePresets -Name $PresetName
    if (-not $preset) {
        return @{}
    }

    $resolved = @{}
    $parents = @()
    if ($preset.PSObject.Properties.Name -contains "inherits") {
        if ($preset.inherits -is [System.Array]) {
            $parents = $preset.inherits
        }
        elseif ($preset.inherits) {
            $parents = @([string]$preset.inherits)
        }
    }

    foreach ($parent in $parents) {
        $parentVars = Resolve-ConfigureCacheVariables -ConfigurePresets $ConfigurePresets -PresetName $parent
        foreach ($key in $parentVars.Keys) {
            $resolved[$key] = $parentVars[$key]
        }
    }

    if ($preset.PSObject.Properties.Name -contains "cacheVariables") {
        $cacheVars = $preset.cacheVariables
        if ($cacheVars) {
            foreach ($property in $cacheVars.PSObject.Properties) {
                $resolved[$property.Name] = [string]$property.Value
            }
        }
    }

    return $resolved
}

function Get-CachedCMakeValue {
    param(
        [string]$CachePath,
        [string]$VariableName
    )

    if (-not (Test-Path $CachePath)) {
        return $null
    }

    $line = Select-String -Path $CachePath -Pattern ("^" + [regex]::Escape($VariableName) + ":[^=]+=") | Select-Object -First 1
    if (-not $line) {
        return $null
    }

    $rawLine = [string]$line.Line
    $parts = $rawLine -split "=", 2
    if ($parts.Count -ne 2) {
        return $null
    }

    return $parts[1].Trim()
}

$presetBuildDir = Join-Path $repoRoot ("build/" + $Preset)

$presetsPath = Join-Path $repoRoot "CMakePresets.json"
if (-not (Test-Path $presetsPath)) {
    throw "CMakePresets.json not found at $presetsPath"
}

$presets = Get-Content -Raw $presetsPath | ConvertFrom-Json
$resolvedCacheVars = Resolve-ConfigureCacheVariables -ConfigurePresets $presets.configurePresets -PresetName $Preset
$expectedTriplet = $null
if ($resolvedCacheVars.ContainsKey("VCPKG_TARGET_TRIPLET")) {
    $expectedTriplet = $resolvedCacheVars["VCPKG_TARGET_TRIPLET"]
}

$cachePath = Join-Path $presetBuildDir "CMakeCache.txt"
if (-not $Clean -and $expectedTriplet -and (Test-Path $cachePath)) {
    $cachedTriplet = Get-CachedCMakeValue -CachePath $cachePath -VariableName "VCPKG_TARGET_TRIPLET"
    if ($cachedTriplet -and $cachedTriplet -ne $expectedTriplet) {
        Write-Warning "Preset '$Preset' expects triplet '$expectedTriplet' but cache has '$cachedTriplet'. Removing stale build directory."
        Remove-Item -Recurse -Force $presetBuildDir
    }
}

if ($Clean -and (Test-Path $presetBuildDir)) {
    Remove-Item -Recurse -Force $presetBuildDir
}

$cmd = '"{0}" -arch=x64 && cd /d "{1}" && cmake --preset {2}' -f $escapedDevCmd, $repoRoot, $Preset
cmd /c $cmd
if ($LASTEXITCODE -ne 0) {
    throw "CMake configure failed with exit code $LASTEXITCODE"
}

Write-Host "Configure completed for preset: $Preset"
