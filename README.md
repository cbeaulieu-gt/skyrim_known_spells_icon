# Description

This project is an SKSE plugin for Skyrim that marks spell tomes as known or unknown by integrating with Dynamic Inventory Icon Injector (DIII), then applies the icon state in game through an SKSE plugin DLL.

## Requirements

- Skyrim Special Edition 1.5.x or Anniversary Edition 1.6.x
- SKSE matching your game version
- Address Library for SKSE Plugins
- Visual Studio 2022 with Desktop development with C++
- CMake 3.23+
- Git
- vcpkg (local bootstrap or global installation)

## How to Build

1. Install dependencies:

```powershell
./scripts/install-deps.ps1
```

2. Configure the build:

```powershell
./scripts/configure.ps1 -Preset vs2022-ae-debug
```

3. Build the plugin:

```powershell
./scripts/build.ps1 -Preset build-ae-debug
```

Use SE presets instead for Skyrim SE 1.5.x:

```powershell
./scripts/configure.ps1 -Preset vs2022-se-debug
./scripts/build.ps1 -Preset build-se-debug
```