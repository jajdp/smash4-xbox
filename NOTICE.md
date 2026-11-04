# Notice

*(Español: [NOTICE.es.md](NOTICE.es.md))*

## Not affiliated

This is an unofficial, noncommercial fan project. It is **not affiliated with, endorsed by or
connected to Nintendo or Microsoft**, nor to the authors of Smash4PC, nor to the Mesa project.
*Super Smash Bros. for Wii U*, *Xbox* and all related names and marks are the property of their
respective owners, and are used here only to say what this works with.

Nothing here is for sale, and nothing here is monetized.

## What this repository does not distribute

No Wii U title, no update, no DLC, no extracted dump. No game data of any kind. No recompiled
C++ (Smash4PC turns the game's PowerPC code into source files: those files **are** the game and
are not here). No built executable, no `.msix`, no save data.

No package tiles either: `package/Assets/` is empty on purpose and
[`docs/ASSETS.md`](docs/ASSETS.md) says what to put in it.

**And none of the libraries**: SDL3, shaderc, SPIRV-Tools, zlib, ZArchive, `dxil.dll`,
`vulkan_dzn.dll`. Some are other people's binaries and the rest you build yourself; the guide
says where each one comes from.

**There are no screenshots of the game here.** A screenshot of this running would be mostly
Nintendo's artwork.

## What it does contain of other people's work, and under what permission

Measured file by file before publishing.

| Tree | What is here | Its license | Why that is allowed |
|---|---|---|---|
| [Smash4PC](https://github.com/josiahg2502-glitch/Smash4PC) | `patches/smash4pc-xbox.patch` — **2.281 added lines over 35 files** | **MIT**, © 2026 Petexy / Linexy (its `LICENSE`) | MIT permits modified versions as long as its notice travels with them. `LICENSE` here carries it |
| [Mesa](https://gitlab.freedesktop.org/mesa/mesa) | `patches/mesa-dozen-xbox.patch` — **199 added lines over 7 files** | **MIT** on every file it touches: © Microsoft Corporation (`src/microsoft/vulkan/*`), © Intel Corporation (`src/vulkan/*`) | Same reason. Mesa is a collection of components under different licenses; these are MIT |
| This port | `tools/`, `src/`, `docs/`, `package/` | **MIT**, © 2026 jajdp | New work |

`src/mesa_sysstubs.c` and `src/mesa_uwp_compat.h` are written here, not copied. The *idea* of
answering Mesa's desktop-only imports with stubs, so that `user32`, `gdi32` and `shell32` never
enter the import table, is taken from [`emelin2004/rpcs3-xbox`](https://github.com/emelin2004/rpcs3-xbox)
(GPL-2.0), which did it first for RPCS3 on Xbox. No line of that project is reproduced here;
what is reused is the approach, and the credit is theirs.

## Third-party pieces you will fetch yourself

| | Where from | License |
|---|---|---|
| **Smash4PC** | [`josiahg2502-glitch/Smash4PC`](https://github.com/josiahg2502-glitch/Smash4PC) | MIT |
| **Mesa** (the Dozen driver) | [mesa/mesa](https://gitlab.freedesktop.org/mesa/mesa), 26.2.x | MIT |
| **`DXIL.dll`** | Microsoft's DirectX Shader Compiler release | Microsoft's own terms |
| **SDL3 for UWP** | [`worleydl/uwp-dep`](https://github.com/worleydl/uwp-dep) | see that repository |
| **`stb_image.h`, `stb_truetype.h`** | [`nothings/stb`](https://github.com/nothings/stb) | MIT / public domain |

## Your dump is yours

Everything here starts from a dump **you** make of **your own** copy of the game. Nothing in
this repository will produce a playable build without it, and nothing here helps you obtain one.
