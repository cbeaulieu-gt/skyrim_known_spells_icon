$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$vcpkgRoot = Join-Path $repoRoot ".tools/vcpkg"
$vcpkgExe = Join-Path $vcpkgRoot "vcpkg.exe"

if (-not (Test-Path $vcpkgExe)) {
    throw "vcpkg executable not found at $vcpkgExe. Run scripts/bootstrap-vcpkg.ps1 first."
}

$env:VCPKG_ROOT = $vcpkgRoot

& $vcpkgExe install --triplet x64-windows --x-manifest-root=$repoRoot
if ($LASTEXITCODE -ne 0) {
    throw "Dependency installation failed with exit code $LASTEXITCODE"
}

Write-Host "Dependencies installed successfully."
