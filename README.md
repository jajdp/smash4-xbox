# Super Smash Bros. for Wii U on Xbox — the UWP port

How to take what **Smash4PC** produces from your own *Super Smash Bros. for Wii U* dump — a
native executable, not an emulator — and build it **for an Xbox Series X in Developer Mode**, as
a UWP package you sign yourself, with its Vulkan renderer running on **Direct3D 12**.

*(Español: [README.es.md](README.es.md))*

## Read this first: what actually works

This is an honest status, not a trailer. Dates are when each line was measured.

| Where | State |
|---|---|
| **PC, Vulkan on an NVIDIA GPU** | **Plays, 59.9 FPS.** This is Smash4PC doing its job; the port changes nothing here |
| **PC, Vulkan on Direct3D 12** (Mesa's Dozen) | **Boots, draws, reaches the attract demo.** Slow — tens of FPS at best, and after a few minutes it runs out of descriptor pools and stops (2026-11-04) |
| **Xbox Series X, Developer Mode** | **Draws.** Title screen, main menu and the attract demo, on a television (2026-11-04). With `TTT2_SUBMIT_EVERY=1`, which costs one submission per draw and holds it at ~15 FPS; without it the process is killed for memory. Menus come out with the same sprite repeated four times |

So: it draws, it reaches the menu, and it plays its own demo — but it is held together by a
submission per draw, and the menus have ghosting. If you are here for a finished port, it is not
one yet. [Issues](../../issues) says what is left and what each thing would take.

## Which console this was tested on

**An Xbox Series X**, in Developer Mode. That is the only hardware any claim here covers.

**A Series S has never been tried — not once.** It is a different machine: less memory available
to a game, a weaker GPU, and this port already needs **1 GiB of mapped guest memory** plus a
~12 GB dump on a ~30 GB developer partition. It may work, it may be slower, or it may not start
at all; nothing here has been measured on it.

## What this repository is

**The whole UWP recipe**: the two patches, the Mesa stubs, and the scripts that compile, package
and deploy. Smash4PC builds a Windows desktop executable with MinGW; this is everything that has
to change so the result lives inside an Xbox App Container and talks to Direct3D 12.

| Piece | What it is |
|---|---|
| `patches/smash4pc-xbox.patch` | **2.281 added lines over 35 files.** The renderer rewrite (below), the UWP entry point, the split-file VFS, the gamepad shortcut for the on-screen FPS counter |
| `patches/mesa-dozen-xbox.patch` | **199 added lines over 7 files.** Three real Mesa bugs and one diagnostic, all of them found on the console (below) |
| `src/mesa_sysstubs.c` | Stand-ins for the desktop-only functions Dozen imports, so `user32`, `gdi32` and `shell32` never enter `vulkan_dzn.dll`'s import table |
| `src/mesa_uwp_compat.h` | A force-included header: the `_Interlocked*` spellings clang-cl does not declare, and the UWP marker the WSI reads |
| `tools/compilar-dozen-uwp.ps1` | Builds Dozen for UWP: cross file, `store` environment, `WindowsApp.lib` |
| `tools/mesa-compilar.ps1` | Builds Dozen for the desktop — which is how you debug any of this without an eight-minute round trip to the console |
| `tools/compilar-uwp.ps1` | Builds the game for UWP, inside Visual Studio's `store` environment |
| `tools/empaquetar.ps1` | Package layout, `makeappx` and `signtool`, with the AppContainer bit checked before it builds anything |
| `tools/partir-volcado.ps1` | Splits the two multi-GB archive files, because the Device Portal gives up around 256 MB per upload |
| `tools/xbox-portal.ps1` | A Device Portal client: install, upload, download, list, launch, screenshot, kill |
| `package/` | The manifest, with `CHANGE-ME` where your identity goes |

## What it is not

There is **no dump, no recompiled C++, no executable, no `.msix`, no tiles and no libraries**
here. `package/Assets/` is empty on purpose. See [NOTICE.md](NOTICE.md).

## What you need first

| | |
|---|---|
| **Smash4PC** | [`josiahg2502-glitch/Smash4PC`](https://github.com/josiahg2502-glitch/Smash4PC), already building and running **on your PC** first. ⚠ Its tree does not compile out of the box: it includes `stb_image.h` and `stb_truetype.h` from `third_party/stb`, and that folder is neither in the repository nor in its `dependencies.lock.json` ([issue #11](https://github.com/josiahg2502-glitch/Smash4PC/issues/11)). Fetch the two headers from [`nothings/stb`](https://github.com/nothings/stb) |
| **Your own dump** | *Super Smash Bros. for Wii U* `[AXFE01]`, **update v304** and the DLC, in Cemu's unpacked layout. About 12 GB plus 2.3 GB |
| **Mesa 26.2.x** | Source. You build the `microsoft-experimental` driver (Dozen) twice: once for the desktop and once for UWP |
| **Visual Studio 2022** | With the **C++ UWP component**: its `store` environment (`vcvarsall x64 store`), plus `makeappx` and `signtool` from the Windows SDK |
| **`DXIL.dll`** | Microsoft's, **1.8.2502.8 or later**. Without it `vkCreateInstance` fails on the console with `VK_ERROR_INITIALIZATION_FAILED`, and a desktop-built one will not load inside the container |
| **SDL3 for UWP** | [`worleydl/uwp-dep`](https://github.com/worleydl/uwp-dep) — prebuilt for UWP x64. The desktop SDL3 refuses: *"Windows RT/UWP is no longer supported in SDL"* |
| **Python 3, PowerShell 7, an Xbox in Developer Mode** | And a code-signing certificate of your own |

## How it goes

```powershell
# Paths live in environment variables, not in the scripts
$env:SMASH4_UPSTREAM  = 'D:\smash4\upstream'   # Smash4PC, already built for PC
$env:SMASH4_TOOLCHAIN = 'D:\smash4\toolchain'  # ninja, cmake
$env:SMASH4_UWP_DEP   = 'D:\uwp-dep\x64'       # worleydl/uwp-dep
$env:SMASH4_MESA      = 'D:\mesa'              # the Mesa tree
$env:SMASH4_GENERATED = 'D:\smash4\generated\smash'
$env:SMASH4_VKSHIM    = 'D:\smash4\vkshim'
$env:SMASH4_PKG       = 'D:\smash4_pkg'        # where the .msix lands

# 1. the two patches
git -C $env:SMASH4_UPSTREAM apply patches\smash4pc-xbox.patch
git -C $env:SMASH4_MESA     apply patches\mesa-dozen-xbox.patch
copy src\mesa_sysstubs.c, src\mesa_uwp_compat.h $env:SMASH4_MESA\uwp\

# 2. Dozen, for the desktop first — so you can debug there, not on the console
tools\mesa-compilar.ps1

# 3. Dozen for UWP, then the game, then the package
tools\compilar-dozen-uwp.ps1
tools\compilar-uwp.ps1
tools\empaquetar.ps1 -Version 0.1.0.0

# 4. the console
tools\xbox-portal.ps1 instalar -Host_ <your console> -Paquete ... -Certificado ...
tools\partir-volcado.ps1 -Origen <your dump> -Destino D:\to-upload
#   then upload D:\to-upload to LocalState and write LocalState\Smash4\rutas.txt
tools\xbox-portal.ps1 lanzar -Host_ <your console> -Pfn ... -AppId ...
```

[`docs/INSTALL.md`](docs/INSTALL.md) is the long version, step by step, with what goes wrong.

## The part that was actually hard

Smash4PC's renderer asks for three things an Xbox's Direct3D 12 does not give, and all three
were **measured on the console**, not guessed. None of them is patched around: the renderer was
rewritten so it no longer needs them. The full story is in
[`docs/HOW-IT-WORKS.md`](docs/HOW-IT-WORKS.md); the short version:

1. **No `bufferDeviceAddress`.** Every shader access to guest memory goes through three GLSL
   functions, and the ABI's `Buffer` already travelled as a `uvec4`. It did not change size —
   only what each component means: from `(addr_lo, addr_hi, size, stride)` to
   `(offset, region, size, stride)`, indexing an array of storage buffers. No
   `descriptor_indexing` needed either: the index comes from a uniform, which is what makes it
   dynamically uniform.
2. **No `VK_EXT_external_memory_host`.** The guest's RAM cannot be handed to the GPU as-is, so
   it is copied, tracked with a 256-byte page map. What made this affordable: the game issues
   1.7 whole-cache invalidations per frame with size `0xFFFFFFFF`, and believing them costs
   **1759 MB/s**; believing only the ranged ones costs **11.9 MB/s**.
3. **`maxStorageBufferRange` is 128 MiB** and MEM2 is 1 GiB. Direct3D 12 lets a shader see
   `1 << D3D12_REQ_BUFFER_RESOURCE_TEXEL_COUNT_2_TO_EXP` of a buffer, and no more. Each region is
   split into **half-overlapping windows** — one `VkBuffer` each, all bound to the same
   allocation at different offsets. MEM2 takes 16 windows.

## Three Mesa bugs, found on the console

All three are in `patches/mesa-dozen-xbox.patch` and all three are worth upstreaming.

| Bug | What happens | Where |
|---|---|---|
| **`SetViewInstanceMask` on hardware without view instancing** | Dozen calls it on every graphics pipeline change, mask or no mask. A mask of `1` is the default single view, so the call does nothing — except on any AMD GPU, where the tier is `NOT_SUPPORTED`, the runtime rejects it, the command list enters an error state and `Close()` fails. `vkEndCommandBuffer` then returns `VK_ERROR_OUT_OF_HOST_MEMORY` and **nothing is ever drawn**. `dzn_pipeline.c` already makes this check; the command buffer does not | `dzn_cmd_buffer.c` |
| **Win32 WSI needs a desktop window** | It presents through DirectComposition: `CreateSwapChainForComposition`, then `IDCompositionDevice::CreateTargetForHwnd`. In UWP there is no desktop HWND — what the surface holds is a CoreWindow — so `vkCreateSwapchainKHR` returns `VK_ERROR_INITIALIZATION_FAILED`. The fix is `CreateSwapChainForCoreWindow`, which presents on its own | `wsi_common_win32.cpp` |
| **`DXIL.dll` is loaded with `LoadLibrary`** | Inside an App Container that does not find a packaged DLL, and the spelling has to match the file exactly. Without the validator, `vkCreateInstance` fails with no explanation | `dxil_validator.cpp`, `dzn_dxgi.c` |

Plus one diagnostic that is not a bug but saved days: `GetResourceAllocationInfo` returns
`SizeInBytes = UINT64_MAX` when Direct3D 12 rejects a resource, and Dozen copies that straight
into `VkMemoryRequirements::size`, so the application tries to allocate 18 446 744 073 709 551 615
bytes and dies. The patch prints the rejected resource description instead of leaving you
guessing. That is how two missing texture formats turned up: **`R4G4_UNORM_PACK8`** and
**`B5G6R5_UNORM_PACK16`**, neither of which exists in DXGI. Both are now unpacked on upload into
a format that does.

## Debug on the PC, not on the console

The single most useful thing in this repository. Dozen on a desktop GPU is the same driver that
runs on the console, and the Direct3D 12 runtime that rejects a malformed command list is the
same code:

```powershell
$env:VK_DRIVER_FILES = "$env:SMASH4_MESA\build\src\microsoft\vulkan\dzn_devenv_icd.x86_64.json"
$env:TTT2_PRESENT_BLIT = '1'      # Dozen's swapchain cannot be written by a shader
$env:MESA_TRACE_ERRORS = '1'      # every Mesa error says which file and line raised it
$env:DZN_DEBUG = 'd3d12'          # the D3D12 debug layer; the patch dumps its InfoQueue
```

Two of the three bugs above were found this way in minutes. The third — view instancing — only
appears on AMD hardware, which is why the D3D12 InfoQueue dump had to work **on the console**;
it does.

On the console itself there is no command line, so `LocalState\Smash4\entorno.txt` sets
environment variables, one `KEY=value` per line, and it is uploaded in seconds with
`tools\xbox-portal.ps1 subir`.

## The on-screen FPS counter

Smash4PC already has one, in its overlay, with a detailed mode (game FPS, slowest frame, GPU
time, draws). Two problems on a console, both fixed in the patch:

* the overlay opens with Escape or the **Guide** button, and on an Xbox the system keeps Guide
  for itself — it never reaches the application. **LB + RB + View** now opens the same menu;
* `SMASH_COUNTER=0|1|2` turns the counter on from startup, which is what you want when there is
  no keyboard and you are measuring.

## Credits

* **Smash4PC** and the `cafe-recomp` engine behind it — [JosiahG](https://github.com/josiahg2502-glitch),
  with the engine and its runtime by **Petexy / Linexy**, who are the copyright holders named in
  its `LICENSE`. Everything this port does is their work running somewhere else.
* **Mesa** and its **Dozen** driver — Microsoft and the Mesa contributors. Vulkan on Direct3D 12
  is what makes an Xbox possible at all here.
* **[`emelin2004/rpcs3-xbox`](https://github.com/emelin2004/rpcs3-xbox)** — for showing that
  Dozen can be put inside an Xbox App Container, and for the idea of the system stubs. No code
  of theirs is here.
* **[`worleydl/uwp-dep`](https://github.com/worleydl/uwp-dep)** — SDL3 and friends, built for UWP.
* **Nintendo and HAL Laboratory**, who made the game. Bring your own copy.
