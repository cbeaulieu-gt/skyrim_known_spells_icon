# Description

This project is an SKSE plugin for Skyrim that marks spell tomes as known or unknown by integrating with Dynamic Inventory Icon Injector (DIII), then applies the icon state in game through an SKSE plugin DLL.

## Requirements

- Skyrim Special Edition 1.5.x or Anniversary Edition 1.6.x
- SKSE matching your game version
- Address Library for SKSE Plugins
- Visual Studio 2022 with Desktop development with C++
- CMake 3.23+
- Git
- vcpkg (set VCPKG_ROOT)

## Runtime Compatibility

- Plugin metadata uses SKSE Address Library version independence.
- One release artifact supports both SE 1.5.x and AE 1.6.x, as long as users install:
	- matching SKSE build for their game runtime
	- Address Library package compatible with their runtime
- Do not distribute Debug builds. Debug artifacts depend on debug runtime DLLs that are not present on player systems.

## How to Build

1. Ensure `VCPKG_ROOT` is set. Dependencies are resolved automatically when you run the configure step (CMake + vcpkg manifest mode).

Optional preinstall command:

```powershell
vcpkg install --triplet x64-windows-static-md --x-manifest-root=.
```

2. Configure and build a Release artifact (recommended for distribution):

```powershell
./scripts/configure.ps1 -Preset vs2022-release
./scripts/build.ps1 -Preset build-release
```

3. Optional Debug build for local testing only:

```powershell
./scripts/configure.ps1 -Preset vs2022-debug
./scripts/build.ps1 -Preset build-debug
```

Unified presets are version-independent for SE/AE runtime support, so there are no separate AE/SE build commands.

## Deployment Notes

- The deployment script defaults to a release preset and rejects debug artifacts unless `-AllowDebug` is explicitly provided.
- The deployment script validates imported DLLs and blocks packages that depend on debug runtimes or dynamic fmt/spdlog/jsoncpp DLLs.