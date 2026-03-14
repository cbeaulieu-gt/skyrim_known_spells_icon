$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$vcpkgExe = Join-Path $vcpkgRoot "vcpkg.exe"
$env:VCPKG_ROOT = $vcpkgRoot

& $vcpkgExe install --triplet x64-windows --x-manifest-root=$repoRoot
if ($LASTEXITCODE -ne 0) {
    throw "Dependency installation failed with exit code $LASTEXITCODE"
}

Write-Host "Dependencies installed successfully."
