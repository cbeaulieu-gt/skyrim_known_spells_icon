# inventory_injector_known_spells_skse

SKSE plugin scaffold targeting Skyrim SE 1.5.x and AE 1.6.x, with a safe integration path through Dynamic Inventory Icon Injector (DIII) public API.

## What is implemented now

- CMake + CommonLibSSE NG project skeleton
- Plugin entry point with startup logging
- DIII conditions for spell tomes whose taught spell is known or unknown to the player
- Post-build deployment to SKSE plugin folder under your mod manager path

## Prerequisites

- Visual Studio 2022 with Desktop C++ workload
- CMake 3.23+
- Git
- SKSE for your game version
- Address Library for SKSE Plugins
- vcpkg (required)

## Install vcpkg and dependencies

```powershell
./scripts/bootstrap-vcpkg.ps1
./scripts/install-deps.ps1
```

This repository keeps a local vcpkg clone under .tools/vcpkg for deterministic setup.

## Use your existing vcpkg installation

If you already have vcpkg installed, you can skip local bootstrap and build with global-vcpkg presets.

1. Point this shell at your vcpkg root:
  - $env:VCPKG_ROOT = "C:/path/to/your/vcpkg"
2. Configure with a global preset:
  - ./scripts/configure.ps1 -Preset vs2022-ae-debug-global -Clean
3. Build with a matching global build preset:
  - ./scripts/build.ps1 -Preset build-ae-debug-global

Shortcut option:

- If you set VCPKG_ROOT, you can auto-map a normal preset to its global equivalent:
  - ./scripts/configure.ps1 -Preset vs2022-ae-debug -UseGlobalVcpkg -Clean
  - ./scripts/build.ps1 -Preset build-ae-debug -UseGlobalVcpkg

SE global presets are also available:

- vs2022-se-debug-global / build-se-debug-global
- vs2022-se-release-global / build-se-release-global

If bootstrap fails, use this recovery flow:

1. Close other terminals using this workspace.
2. Delete the local vcpkg folder: .tools/vcpkg
3. Re-run:
  - ./scripts/bootstrap-vcpkg.ps1
  - ./scripts/install-deps.ps1

If you see a warning about mismatched VCPKG_ROOT, clear your global variable so this repo's local toolchain is used:

1. Current shell only: Remove-Item Env:VCPKG_ROOT
2. Persisted user variable (optional): [Environment]::SetEnvironmentVariable("VCPKG_ROOT", $null, "User")

## DIII API header placement

Copy the public header from the upstream project into:

external/diii/DIII_API.h

Pinned source commit for the current header copy:

https://github.com/JerryYOJ/Dynamic-Inventory-Icon-Injector-SKSE/commit/783444cbed8ff02ba4fa59e4c74d57d3d3f90daf

Until this file exists, the plugin still builds but skips DIII listener registration.

## DIII condition keys

The plugin currently registers two equivalent condition keys for DIII JSON:

- knownSpellTome
- teachesKnownSpell

Both expect a boolean value and only match books that teach a spell.

- true: spell tomes where the player already knows the taught spell
- false: spell tomes where the player does not know the taught spell yet

A reusable JSON fragment for the main mod is included at:

config/diii-observation-clauses.json

That file is intended as source material to merge into the main mod's DIII rule set.

Example DIII-style usage:

```json
{
  "match": {
    "teachesKnownSpell": true
  }
}
```

```json
{
  "match": {
    "knownSpellTome": false
  }
}
```

## Build from terminal

```powershell
./scripts/configure.ps1 -Preset vs2022-ae-debug
./scripts/build.ps1 -Preset build-ae-debug
```

SE presets are also available:

```powershell
./scripts/configure.ps1 -Preset vs2022-se-debug
./scripts/build.ps1 -Preset build-se-debug
```

## Visual Studio workflow

- Open this folder in VS Code CMake Tools
- Select configure preset such as vs2022-ae-debug
- Build preset build-ae-debug

Note: this repository uses Ninja presets. If you build from a plain terminal, use scripts/configure.ps1 and scripts/build.ps1 so MSVC environment variables are initialized via VsDevCmd.

## Deployment behavior

If SKYRIM_MODS_FOLDER is set, output deploys to:

SKYRIM_MODS_FOLDER/inventory_injector_known_spells_skse/SKSE/Plugins

Fallback: if SKYRIM_FOLDER is set, output deploys to SKYRIM_FOLDER/Data/SKSE/Plugins.

## Manual deployment to a custom folder

You can push the built DLL (and PDB) to any folder with:

```powershell
./scripts/deploy.ps1 -Preset build-se-debug -TargetDir "I:/path/to/SKSE/Plugins"
```

To avoid passing the folder each time, create a local .env file from .env.example and set:

```text
DEPLOY_TARGET_DIR=I:/path/to/SKSE/Plugins
```

Then deploy using the .env default:

```powershell
./scripts/deploy.ps1 -Preset build-se-debug
```

VS Code tasks are included for both modes:

- Deploy Built DLL (.env default)
- Deploy Built DLL (Prompt target)
- Build SE Debug + Deploy (.env default)

## First run verification

- Start Skyrim via SKSE
- Check SKSE log and plugin log in Documents/My Games/.../SKSE
- Confirm log lines:
  - init start
  - SKSE initialized
  - ready
