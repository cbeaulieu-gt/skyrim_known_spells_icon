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
    [string]$Preset = "build-se-debug",
    [string]$TargetDir,
    [string]$BinaryName = "inventory_injector_known_spells_skse",
    [switch]$SkipPdb
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$dotenvPath = Join-Path $repoRoot ".env"
$presetsPath = Join-Path $repoRoot "CMakePresets.json"
$diiiJsonSourceDir = Join-Path $repoRoot "config"
$assetsSourceDir = Join-Path $repoRoot "assets"
$interfaceSwfSourceDir = Join-Path $assetsSourceDir "Interface"

function Get-DotEnvValue {
    param(
        [string]$Path,
        [string]$Key
    )

    if (-not (Test-Path $Path)) {
        return $null
    }

    foreach ($line in Get-Content -Path $Path) {
        $trimmed = $line.Trim()
        if (-not $trimmed -or $trimmed.StartsWith("#")) {
            continue
        }

        $parts = $trimmed -split "=", 2
        if ($parts.Count -ne 2) {
            continue
        }

        $currentKey = $parts[0].Trim()
        if ($currentKey -ne $Key) {
            continue
        }

        $value = $parts[1].Trim()
        if (($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'"))) {
            $value = $value.Substring(1, $value.Length - 2)
        }
        return $value
    }

    return $null
}

function Get-RelativePath {
    param(
        [string]$BasePath,
        [string]$FullPath
    )

    $resolvedBase = (Resolve-Path -Path $BasePath).Path.TrimEnd('\\')
    $resolvedFull = (Resolve-Path -Path $FullPath).Path

    $basePrefix = $resolvedBase + '\'
    if ($resolvedFull.StartsWith($basePrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $resolvedFull.Substring($basePrefix.Length)
    }

    # Safety fallback; keeps deployment in target tree even if path normalization differs.
    return [IO.Path]::GetFileName($resolvedFull)
}

if (-not $TargetDir) {
    $TargetDir = Get-DotEnvValue -Path $dotenvPath -Key "DEPLOY_TARGET_DIR"
}

if (-not $TargetDir) {
    throw "No deployment target was provided. Pass -TargetDir or set DEPLOY_TARGET_DIR in .env at $dotenvPath"
}

if (-not (Test-Path $presetsPath)) {
    throw "CMakePresets.json was not found at $presetsPath"
}

$presets = Get-Content -Raw $presetsPath | ConvertFrom-Json
$buildPreset = $presets.buildPresets | Where-Object { $_.name -eq $Preset } | Select-Object -First 1
if (-not $buildPreset) {
    throw "Build preset '$Preset' was not found in CMakePresets.json"
}

$configurePreset = [string]$buildPreset.configurePreset
$configuration = [string]$buildPreset.configuration
if (-not $configurePreset -or -not $configuration) {
    throw "Build preset '$Preset' is missing configurePreset or configuration."
}

$expectedDll = Join-Path $repoRoot ("build/{0}/{1}/{2}.dll" -f $configurePreset, $configuration, $BinaryName)
$sourceDll = $expectedDll
if (-not (Test-Path $sourceDll)) {
    $searchRoot = Join-Path $repoRoot ("build/{0}" -f $configurePreset)
    if (Test-Path $searchRoot) {
        $fallbackDll = Get-ChildItem -Path $searchRoot -Filter ("{0}.dll" -f $BinaryName) -File -Recurse |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
        if ($fallbackDll) {
            $sourceDll = $fallbackDll.FullName
        }
    }
}

if (-not (Test-Path $sourceDll)) {
    throw "Built DLL not found for preset '$Preset'. Build first, then deploy. Expected: $expectedDll"
}

New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null
$destDll = Join-Path $TargetDir ([IO.Path]::GetFileName($sourceDll))
Copy-Item -Path $sourceDll -Destination $destDll -Force
Write-Host "Deployed DLL: $destDll"

if (-not $SkipPdb) {
    $sourcePdb = [IO.Path]::ChangeExtension($sourceDll, ".pdb")
    if (Test-Path $sourcePdb) {
        $destPdb = Join-Path $TargetDir ([IO.Path]::GetFileName($sourcePdb))
        Copy-Item -Path $sourcePdb -Destination $destPdb -Force
        Write-Host "Deployed PDB: $destPdb"
    }
}

# With the x64-windows-static-md vcpkg triplet, all dependencies (fmt, spdlog,
# jsoncpp) are statically linked into the plugin DLL — no sibling DLLs are
# produced and none need to be deployed. If the triplet is ever changed back to
# x64-windows this block will copy the resulting dependency DLLs automatically.
$sourceDir = Split-Path -Parent $sourceDll
$pluginFileName = [IO.Path]::GetFileName($sourceDll)
$depDlls = Get-ChildItem -Path $sourceDir -Filter "*.dll" |
Where-Object { $_.Name -ne $pluginFileName }
foreach ($dep in $depDlls) {
    $dest = Join-Path $TargetDir $dep.Name
    Copy-Item -Path $dep.FullName -Destination $dest -Force
    Write-Host "Deployed dependency: $dest"
}

if (Test-Path $diiiJsonSourceDir) {
    $diiiTargetDir = Join-Path $TargetDir "DIII"
    New-Item -ItemType Directory -Path $diiiTargetDir -Force | Out-Null

    $jsonFiles = Get-ChildItem -Path $diiiJsonSourceDir -Filter "*.json" -File -Recurse
    foreach ($jsonFile in $jsonFiles) {
        $relativePath = Get-RelativePath -BasePath $diiiJsonSourceDir -FullPath $jsonFile.FullName
        $destJsonPath = Join-Path $diiiTargetDir $relativePath
        $destJsonDir = Split-Path -Parent $destJsonPath
        if ($destJsonDir) {
            New-Item -ItemType Directory -Path $destJsonDir -Force | Out-Null
        }

        Copy-Item -Path $jsonFile.FullName -Destination $destJsonPath -Force
        Write-Host "Deployed DIII JSON: $destJsonPath"
    }
}

if (Test-Path $interfaceSwfSourceDir) {
    $deployRoot = Split-Path -Parent (Split-Path -Parent $TargetDir)
    $assetsTargetRoot = $deployRoot

    $swfFiles = Get-ChildItem -Path $interfaceSwfSourceDir -Filter "*.swf" -File -Recurse
    foreach ($swfFile in $swfFiles) {
        # Preserve the full assets/Interface subtree under the game Data root.
        $relativePath = Get-RelativePath -BasePath $assetsSourceDir -FullPath $swfFile.FullName
        $destSwfPath = Join-Path $assetsTargetRoot $relativePath
        $destSwfDir = Split-Path -Parent $destSwfPath
        if ($destSwfDir) {
            New-Item -ItemType Directory -Path $destSwfDir -Force | Out-Null
        }

        Copy-Item -Path $swfFile.FullName -Destination $destSwfPath -Force
        Write-Host "Deployed Interface SWF: $destSwfPath"
    }
}
