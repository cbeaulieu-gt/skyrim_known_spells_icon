$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot

function Resolve-VcpkgRoot {
    $candidates = @()

    if ($env:VCPKG_ROOT) {
        $candidates += $env:VCPKG_ROOT
    }

    $candidates += (Join-Path $repoRoot ".tools/vcpkg")

    foreach ($candidate in $candidates) {
        if (-not $candidate) {
            continue
        }

        $exePath = Join-Path $candidate "vcpkg.exe"
        if (Test-Path $exePath) {
            return $candidate
        }
    }

    throw "vcpkg.exe was not found. Set VCPKG_ROOT, or bootstrap local vcpkg at '$repoRoot/.tools/vcpkg'."
}

$vcpkgRoot = Resolve-VcpkgRoot
$vcpkgExe = Join-Path $vcpkgRoot "vcpkg.exe"
$env:VCPKG_ROOT = $vcpkgRoot

& $vcpkgExe install --triplet x64-windows-static-md --x-manifest-root=$repoRoot
if ($LASTEXITCODE -ne 0) {
    throw "Dependency installation failed with exit code $LASTEXITCODE"
}

Write-Host "Dependencies installed successfully using triplet x64-windows-static-md."
