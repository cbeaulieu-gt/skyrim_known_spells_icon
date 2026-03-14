param(
    [ValidateSet(
        "build-ae-debug",
        "build-ae-release",
        "build-se-debug",
        "build-se-release"
    )]
    [string]$Preset = "build-se-release",
    [string]$TargetDir,
    [string[]]$TargetDirs,
    [string]$BinaryName = "inventory_injector_known_spells_skse",
    [switch]$SkipPdb,
    [switch]$CreateZip,
    [switch]$AllowDebug,
    [switch]$SkipDependencyCheck
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$dotenvPath = Join-Path $repoRoot ".env"
$presetsPath = Join-Path $repoRoot "CMakePresets.json"
$diiiJsonSourceDir = Join-Path $repoRoot "config"
$assetsSourceDir = Join-Path $repoRoot "assets"
$interfaceAssetsSourceDir = Join-Path $assetsSourceDir "Interface"
$zipDeployTargetsKey = "DEPLOY_ZIP_TARGET_DIRS"
$deployTargetsKey = "DEPLOY_TARGET_DIRS"
$deployedFiles = @()

function Get-VisualStudioDevCmd {
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

    return $devCmd.Replace('/', '\\')
}

function Get-DllDependencies {
    param(
        [string]$DllPath
    )

    $escapedDevCmd = Get-VisualStudioDevCmd
    $cmd = '"{0}" -arch=x64 && dumpbin /nologo /dependents "{1}"' -f $escapedDevCmd, $DllPath
    $output = cmd /c $cmd 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "dumpbin failed while checking dependencies for $DllPath`n$output"
    }

    $dependencies = @()
    foreach ($line in $output) {
        $match = [regex]::Match([string]$line, '^\s+([A-Za-z0-9_.-]+\.dll)\s*$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ($match.Success) {
            $dependencies += $match.Groups[1].Value.ToLowerInvariant()
        }
    }

    return $dependencies | Select-Object -Unique
}

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

function Get-DotEnvPathList {
    param(
        [string]$Path,
        [string]$Key
    )

    $rawValue = Get-DotEnvValue -Path $Path -Key $Key
    if (-not $rawValue) {
        return @()
    }

    $items = $rawValue -split "[;,]"
    $results = @()
    foreach ($item in $items) {
        $trimmed = $item.Trim()
        if ($trimmed) {
            $results += $trimmed
        }
    }

    return $results
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

function Resolve-DeployDataRoot {
    param(
        [string]$TargetDirPath
    )

    $normalizedTarget = $TargetDirPath.TrimEnd('\', '/')
    if ($normalizedTarget -match '(?i)[\\/]SKSE[\\/]Plugins$') {
        return Split-Path -Parent (Split-Path -Parent $normalizedTarget)
    }

    return $normalizedTarget
}

function Resolve-PluginDeployDir {
    param(
        [string]$TargetDirPath
    )

    $normalizedTarget = $TargetDirPath.TrimEnd('\', '/')
    if ($normalizedTarget -match '(?i)[\\/]SKSE[\\/]Plugins$') {
        return $normalizedTarget
    }

    if ($normalizedTarget -match '(?i)[\\/]SKSE$') {
        return Join-Path $normalizedTarget "Plugins"
    }

    return Join-Path (Join-Path $normalizedTarget "SKSE") "Plugins"
}

$resolvedTargetDirs = @()
if ($TargetDirs -and $TargetDirs.Count -gt 0) {
    $resolvedTargetDirs = $TargetDirs | Where-Object { $_ -and $_.Trim() } | ForEach-Object { $_.Trim() }
}
elseif ($TargetDir) {
    $resolvedTargetDirs = @($TargetDir.Trim())
}
else {
    $resolvedTargetDirs = Get-DotEnvPathList -Path $dotenvPath -Key $deployTargetsKey
    if ($resolvedTargetDirs.Count -eq 0) {
        $legacyTarget = Get-DotEnvValue -Path $dotenvPath -Key "DEPLOY_TARGET_DIR"
        if ($legacyTarget) {
            $resolvedTargetDirs = @($legacyTarget)
        }
    }
}

$resolvedTargetDirs = $resolvedTargetDirs | Select-Object -Unique
if ($resolvedTargetDirs.Count -eq 0) {
    throw "No deployment target was provided. Pass -TargetDir/-TargetDirs or set DEPLOY_TARGET_DIRS in .env at $dotenvPath"
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

if ($configuration -ieq "Debug" -and -not $AllowDebug) {
    throw "Refusing to deploy Debug artifact '$sourceDll'. Build a release preset for distribution, or pass -AllowDebug to override."
}

if (-not $SkipDependencyCheck) {
    $dependencies = Get-DllDependencies -DllPath $sourceDll

    $forbiddenDependencies = @(
        "msvcp140d.dll",
        "vcruntime140d.dll",
        "vcruntime140_1d.dll",
        "ucrtbased.dll",
        "spdlogd.dll",
        "fmtd.dll",
        "spdlog.dll",
        "fmt.dll",
        "jsoncpp.dll"
    )

    $badDependencies = $dependencies | Where-Object { $forbiddenDependencies -contains $_ }
    if ($badDependencies.Count -gt 0) {
        $badList = ($badDependencies | Sort-Object -Unique) -join ", "
        throw "Blocked deployment: plugin imports disallowed runtime dependencies: $badList. Reconfigure and rebuild with x64-windows-static-md release presets."
    }
}

$shouldDeployPdb = (-not $SkipPdb) -and ($configuration -ieq "Debug")

$zipSourceDeployRoot = $null
foreach ($resolvedTargetDir in $resolvedTargetDirs) {
    $pluginDeployDir = Resolve-PluginDeployDir -TargetDirPath $resolvedTargetDir
    New-Item -ItemType Directory -Path $pluginDeployDir -Force | Out-Null

    if (-not $zipSourceDeployRoot) {
        $zipSourceDeployRoot = Resolve-DeployDataRoot -TargetDirPath $resolvedTargetDir
    }

    $destDll = Join-Path $pluginDeployDir ([IO.Path]::GetFileName($sourceDll))
    Copy-Item -Path $sourceDll -Destination $destDll -Force
    $deployedFiles += $destDll
    Write-Host "Deployed DLL: $destDll"

    if ($shouldDeployPdb) {
        $sourcePdb = [IO.Path]::ChangeExtension($sourceDll, ".pdb")
        if (Test-Path $sourcePdb) {
            $destPdb = Join-Path $pluginDeployDir ([IO.Path]::GetFileName($sourcePdb))
            Copy-Item -Path $sourcePdb -Destination $destPdb -Force
            $deployedFiles += $destPdb
            Write-Host "Deployed PDB: $destPdb"
        }
    }

    # With the x64-windows-static-md vcpkg triplet, all dependencies (fmt, spdlog,
    # jsoncpp) are statically linked into the plugin DLL. If the triplet is changed to
    # x64-windows this block will copy the resulting dependency DLLs automatically.
    $sourceDir = Split-Path -Parent $sourceDll
    $pluginFileName = [IO.Path]::GetFileName($sourceDll)
    $depDlls = Get-ChildItem -Path $sourceDir -Filter "*.dll" |
    Where-Object { $_.Name -ne $pluginFileName }
    foreach ($dep in $depDlls) {
        $dest = Join-Path $pluginDeployDir $dep.Name
        Copy-Item -Path $dep.FullName -Destination $dest -Force
        $deployedFiles += $dest
        Write-Host "Deployed dependency: $dest"
    }

    if (Test-Path $diiiJsonSourceDir) {
        $diiiTargetDir = Join-Path $pluginDeployDir "DIII"
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
            $deployedFiles += $destJsonPath
            Write-Host "Deployed DIII JSON: $destJsonPath"
        }
    }

    if (Test-Path $interfaceAssetsSourceDir) {
        $deployRoot = Resolve-DeployDataRoot -TargetDirPath $resolvedTargetDir
        $assetsTargetRoot = $deployRoot

        $interfaceFiles = Get-ChildItem -Path $interfaceAssetsSourceDir -File -Recurse
        foreach ($interfaceFile in $interfaceFiles) {
            # Preserve the full assets/Interface subtree under the game Data root.
            $relativePath = Get-RelativePath -BasePath $assetsSourceDir -FullPath $interfaceFile.FullName
            $destAssetPath = Join-Path $assetsTargetRoot $relativePath
            $destAssetDir = Split-Path -Parent $destAssetPath
            if ($destAssetDir) {
                New-Item -ItemType Directory -Path $destAssetDir -Force | Out-Null
            }

            Copy-Item -Path $interfaceFile.FullName -Destination $destAssetPath -Force
            $deployedFiles += $destAssetPath
            Write-Host "Deployed Interface asset: $destAssetPath"
        }
    }
}

if ($CreateZip) {
    $zipTargetDirs = Get-DotEnvPathList -Path $dotenvPath -Key $zipDeployTargetsKey
    if ($zipTargetDirs.Count -eq 0) {
        throw "-CreateZip was specified, but $zipDeployTargetsKey is missing or empty in .env at $dotenvPath"
    }

    $deployRoot = $zipSourceDeployRoot
    if (-not $deployRoot) {
        throw "Could not determine deployment root for ZIP creation."
    }

    $resolvedDeployRoot = (Resolve-Path -Path $deployRoot).Path.TrimEnd('\\')
    $deployRootPrefix = $resolvedDeployRoot + '\'
    $stagingRoot = Join-Path ([IO.Path]::GetTempPath()) ([IO.Path]::GetRandomFileName())
    $zipFileName = "{0}-{1}.zip" -f $BinaryName, $Preset
    $zipTempPath = Join-Path ([IO.Path]::GetTempPath()) $zipFileName

    New-Item -ItemType Directory -Path $stagingRoot -Force | Out-Null
    try {
        $uniqueFiles = $deployedFiles | Select-Object -Unique
        foreach ($filePath in $uniqueFiles) {
            if (-not (Test-Path $filePath)) {
                continue
            }

            $resolvedFilePath = (Resolve-Path -Path $filePath).Path
            if (-not $resolvedFilePath.StartsWith($deployRootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
                # Skip files from other deployment roots to avoid duplicate root-level entries.
                continue
            }

            $relativePath = Get-RelativePath -BasePath $deployRoot -FullPath $filePath
            $stagedPath = Join-Path $stagingRoot $relativePath
            $stagedDir = Split-Path -Parent $stagedPath
            if ($stagedDir) {
                New-Item -ItemType Directory -Path $stagedDir -Force | Out-Null
            }

            Copy-Item -Path $filePath -Destination $stagedPath -Force
        }

        if (Test-Path $zipTempPath) {
            Remove-Item -Path $zipTempPath -Force
        }

        $stagedFiles = Get-ChildItem -Path $stagingRoot -Recurse -File
        if ($stagedFiles.Count -eq 0) {
            throw "No files were staged for ZIP creation under $stagingRoot."
        }

        Push-Location $stagingRoot
        try {
            Compress-Archive -Path "*" -DestinationPath $zipTempPath -Force
        }
        finally {
            Pop-Location
        }

        if (-not (Test-Path $zipTempPath)) {
            throw "ZIP creation failed: expected archive not found at $zipTempPath"
        }

        foreach ($zipTargetDir in $zipTargetDirs) {
            New-Item -ItemType Directory -Path $zipTargetDir -Force | Out-Null
            $zipDestPath = Join-Path $zipTargetDir $zipFileName
            Copy-Item -Path $zipTempPath -Destination $zipDestPath -Force
            Write-Host "Deployed ZIP: $zipDestPath"
        }
    }
    finally {
        if (Test-Path $stagingRoot) {
            Remove-Item -Path $stagingRoot -Recurse -Force
        }

        if (Test-Path $zipTempPath) {
            Remove-Item -Path $zipTempPath -Force
        }
    }
}
