# Changelog

## 0.3.0 — 2026-11-05

The console draws **everything**, and without a crutch: title screen, main menu, the attract
demo **with its stage** and the fight itself, at **23-32 FPS** and 16 submissions per frame.
The black stage and the four-times-repeated menu sprite were the same bug, and both are gone.

**Mesa (`patches/mesa-dozen-xbox.patch`)**

* **16-bit types were not lowered where the hardware has no native 16-bit ops.** The condition
  in `dzn_pipeline.c` only lowered them if the application had asked for `float16`/`int16`,
  assuming that otherwise they could only come from min-precision. They cannot: a SPIR-V may
  carry real 16-bit types anyway, `CreateVertexShader` then rejects the shader — *"Shader uses
  native 16bit ops, but the device does not support this"* —, **creating the variant's PSO
  fails**, `dzn_graphics_pipeline_get_state()` returns NULL, nobody calls `SetPipelineState()`
  and D3D12 runs the draw with a **default no-op pipeline state**: it paints nothing, with no
  error and no trace on the Vulkan side. Measured on the console: 23 of 40 traced draws had no
  PSO. A desktop GPU reports `Native16BitShaderOpsSupported`, which is why the same game with
  the same Dozen drew on a PC and not on the Xbox.
  Fix: `.lower_int16 = !pdev->options4.Native16BitShaderOpsSupported`.
* `dzn_cmd_buffer_update_pipeline()` called `dzn_graphics_pipeline_get_state()` **without using
  its return value** and then compared and bound `pipeline->state`, which is NULL as soon as the
  pipeline has variants. The PSO actually bound is now kept in `cmdbuf->state.pipeline_state`.
* `dzn_BeginCommandBuffer()` did not clear `cmdbuf->state`, although `Reset(…, NULL)` leaves the
  command list with no pipeline, no root signature and no descriptor heaps.
* `DZN_DUMP_MESSAGES=1` dumps the `ID3D12InfoQueue` at **every** command list close, not only
  when `Close()` fails. A draw can be accepted and still paint nothing; the debug layer's
  warnings are then the only thing that explains it. With one draw per batch, each warning lands
  next to the draw that caused it. This is what found all of the above.

**The game (`patches/smash4pc-xbox.patch`)** — regenerated: now **3,467 added lines over 45
files** (was 2,281 over 35).

* **The SPIR-V was compiled for Vulkan 1.3 even when the driver is 1.2.** In 1.3
  `shaderDemoteToHelperInvocation` is core, so glslang translated `discard` into
  `OpDemoteToHelperInvocation`, which the console's Dozen cannot compile: **191 shaders lost per
  run, now zero**. It compiles for `properties.apiVersion`.
* The translator emitted `demote` on every KILL and alpha test even though the runtime does not
  use it; it emits `discard` now.
* `TTT2_VS_FIJO` and `TTT2_PS_FIJO` never actually applied: the patch went in **after** the GLSL
  hash was computed, so the already-compiled module and the SPIR-V cache skipped it, and the
  patched shader was stored under the original's key, poisoning the cache. The patch now goes in
  before the hash, so forced GLSL gets a key of its own. Without this there was no way to cut
  the problem in half.
* The file, event, audio and input traces were read into statically initialised globals, before
  `uwp_entry` reads `entorno.txt`: they worked on the PC and never switched on at all on the
  console. Now evaluated lazily.
* The per-draw trace cost half the frame rate — one line per draw at ~4,500/s. It is behind
  `TTT2_TRACE_EVERY_DRAW` now.

New instruments, all of them written to chase a draw that is issued and paints nothing:
`TTT2_TRACE_VB_ORIGEN` (who writes a vertex-buffer descriptor with a negative size, on the
producer's side), `TTT2_TRACE_PAREJAS` (every distinct vertex/pixel shader pair that reaches a
draw, which is how you aim `TTT2_VS_FIJO` without guessing a hash), `TTT2_TRACE_ESTADO_PS` (the
full state that decides whether a draw covers pixels: viewport, scissor, masks, depth, target
and pipeline key, and which draw of the frame it is) and `TTT2_TRACE_EN_PASE` (trace the frame
that contains the pass, instead of timing it by hand with `TTT2_TRACE_AT`).

## 0.2.0 — 2026-11-04

The console draws. Title screen, main menu and the attract demo, on a television. It is held up
by `TTT2_SUBMIT_EVERY=1` — one submission per draw, ~15 FPS — and the menus ghost, but the chain
from dump to picture is closed.

**Mesa (`patches/mesa-dozen-xbox.patch`)**

* `dzn_cmd_buffer_update_viewports()` dereferenced a null pipeline. When Dozen emulates a
  triangle fan it dispatches a compute shader, clears `state.pipeline` and marks **only** the
  compute bindpoint dirty; the blit and resolve paths in the same file mark the graphics one too.
  Nothing drew on the console until this: the first thing the title draws is a triangle fan.
  Found from a crash dump — `vulkan_dzn.dll+0xC1E7`, reading `0x4CC` — resolved with
  `llvm-symbolizer` because the console has no debugger.
* `OpenExistingHeapFromAddress1` now says which `HRESULT` it failed with, and what Windows thinks
  of that memory. On an Xbox it answers `E_INVALIDARG` for memory that is committed,
  `PAGE_READWRITE` and contiguous — so `VK_EXT_external_memory_host` cannot work there and the
  guest memory has to be copied. That is 1 GiB that cannot be given back.

**The renderer**

* Triangle fans drawn as a list through generated indices, instead of Dozen's emulation: one
  dispatch and one barrier less per draw.
* `D16_UNORM` was the only depth format whose fallback was not checked. A console says it has it
  and then asks for zero bytes to hold an image of it; the game died at its first shadow map.
* A depth buffer read as a texture is now converted when the formats do not match: depth → buffer
  → `R32_SFLOAT` image → **blit**, which is the only Vulkan operation that converts between
  colour formats. 16-bit buffers prefer a float depth format for exactly this.
* `4_4_4_4` unpacked on upload to `R8G8B8A8_UNORM` when neither `A4B4G4R4` nor `R4G4B4A4` exists.
  A console has neither, and that is the format of the interface sprites with transparency.
* Emulated push descriptors: running out of pool space now **closes the batch**, which is the
  only thing that gives the sets back. It used to make another pool, and another, up to 1024,
  each with its own memory — on a console with ~2.6 GB for the app, the system takes the process
  away without a word. Pools also grew from 256 to 1024 sets.
* A new image's barrier covers both planes of a depth-stencil format, not just the view's aspect.

**Switches, all off by default**

| Variable | What it does |
|---|---|
| `TTT2_SUBMIT_EVERY=N` | Close the batch every N draws. The console needed `1` until 0.3.0; now it is only a way to pin down the draw that hangs a GPU |
| `DZN_DUMP_MESSAGES=1` | Dump the D3D12 debug layer's messages at every command list close, not only on failure (needs `DZN_DEBUG=d3d12`) |
| `TTT2_GPU_TIMEOUT=seconds` | How long to wait for the GPU before calling it dead. Tells apart a hang from something absurdly slow |
| `TTT2_NO_D16=1`, `TTT2_NO_4444=1` | Pretend the driver lacks those formats, to reproduce a console's behaviour on a PC |
| `TTT2_TRACE_GUEST_SPAN=1` | How much of a guest region the GPU ever reads. Measured: 369 MiB of MEM2's gigabyte |
| `TTT2_FATAL_CRASH=1` | Make a fatal error leave a crash dump, the only way to see the other threads on a console |

**Tools**

* `pc/probar-en-el-pc.ps1`: one run on a PC from end to end, capturing from the render and
  leaving nothing alive. With `TTT2_NO_D16` and company it reproduces a console's quirks with a
  one-minute cycle instead of ten.

## 0.1.0 — 2026-11-04

First public version. What it does and does not do is in the README's first table; the short
version is that it builds, installs and starts on an Xbox Series X, and has not been seen
drawing a frame there yet.

**The renderer, rewritten so it stops needing what the console does not have**

* Guest memory reached through an array of storage buffers instead of
  `VK_KHR_buffer_device_address`. `abi::Buffer` keeps its size and changes meaning.
* Guest memory copied, with a 256-byte page map, instead of imported with
  `VK_EXT_external_memory_host`. 11.9 MB/s by believing only ranged invalidations.
* Regions split into half-overlapping windows over one allocation, because
  `maxStorageBufferRange` is 128 MiB and MEM2 is 1 GiB.
* Depth and colour formats verified by creating a test image, not by asking. Startup prints the
  formats this driver does not have.
* `R4G4_UNORM_PACK8` → `R8G8_UNORM` and `B5G6R5_UNORM_PACK16` → `R8G8B8A8_UNORM`, unpacked on
  upload. Neither exists in DXGI.
* Emulated push descriptors: each slot now walks its own list of pools from the first one after
  a reset, instead of always using the last. The old way spent one pool per pass and grew the
  list forever — 44 pools in a slot that had served 108 sets — until `vkCreateDescriptorPool`
  ran out of host memory. A slot settles at five. `TTT2_TRACE_POOLS=1` shows it.
* On Dozen, present from the drawing queue: its swapchain cannot be written by a shader even
  though `supportedUsageFlags` says it can.

**UWP**

* Entry point, `LocalState` for saves, cache and log, and the arguments read from `rutas.txt`.
* `entorno.txt` sets environment variables on a console that has no command line.
* Vulkan surface created on the CoreWindow's own thread.
* VFS serving `x.000` + `x.parteN` as one file, for a dump the Device Portal will not take whole.
* The overlay — and with it the FPS counter — opens with **LB + RB + View**, because the Guide
  button never reaches an application on an Xbox. `SMASH_COUNTER=0|1|2` turns it on at startup.

**Mesa (`patches/mesa-dozen-xbox.patch`)**

* `SetViewInstanceMask` only where the hardware has view instancing. Without this nothing draws
  on any AMD GPU.
* `CreateSwapChainForCoreWindow` in the Win32 WSI, instead of DirectComposition over a desktop
  HWND that UWP does not have.
* `DXIL.dll` loaded with `LoadPackagedLibrary`, trying the three spellings, then from System32.
* The D3D12 InfoQueue dumped when `Close()` fails, and the rejected resource described when
  `GetResourceAllocationInfo` returns `UINT64_MAX`. `MESA_TRACE_ERRORS=1` turns on a file and
  line for every Mesa error.
