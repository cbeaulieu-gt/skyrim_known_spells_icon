$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$vcpkgRoot = Join-Path $repoRoot ".tools/vcpkg"
$vcpkgExe = Join-Path $vcpkgRoot "vcpkg.exe"

if (-not (Test-Path $vcpkgRoot)) {
    git clone https://github.com/microsoft/vcpkg $vcpkgRoot
}

# If the folder exists but does not look like a valid vcpkg git checkout,
# remove and reclone to recover from interrupted bootstrap attempts.
if ((Test-Path $vcpkgRoot) -and -not (Test-Path (Join-Path $vcpkgRoot ".git"))) {
    Remove-Item -Recurse -Force $vcpkgRoot
    git clone https://github.com/microsoft/vcpkg $vcpkgRoot
}

if (Test-Path $vcpkgExe) {
    Write-Host "vcpkg already bootstrapped at $vcpkgRoot"
    $env:VCPKG_ROOT = $vcpkgRoot
    return
}

& (Join-Path $vcpkgRoot "bootstrap-vcpkg.bat")
if ($LASTEXITCODE -ne 0) {
    throw "vcpkg bootstrap failed with exit code $LASTEXITCODE"
}

$env:VCPKG_ROOT = $vcpkgRoot

Write-Host "Local vcpkg is ready at $vcpkgRoot"
