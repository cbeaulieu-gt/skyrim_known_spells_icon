$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot

function Resolve-VcpkgRoot {
    if (-not $env:VCPKG_ROOT) {
        throw "VCPKG_ROOT is not set. Point it to your vcpkg install root (folder containing vcpkg.exe)."
    }

    $exePath = Join-Path $env:VCPKG_ROOT "vcpkg.exe"
    if (-not (Test-Path $exePath)) {
        throw "vcpkg.exe was not found at '$exePath'. Fix VCPKG_ROOT and try again."
    }

    return $env:VCPKG_ROOT
}

$vcpkgRoot = Resolve-VcpkgRoot
$vcpkgExe = Join-Path $vcpkgRoot "vcpkg.exe"
$env:VCPKG_ROOT = $vcpkgRoot

& $vcpkgExe install --triplet x64-windows-static-md --x-manifest-root=$repoRoot
if ($LASTEXITCODE -ne 0) {
    throw "Dependency installation failed with exit code $LASTEXITCODE"
}

Write-Host "Dependencies installed successfully using triplet x64-windows-static-md."
