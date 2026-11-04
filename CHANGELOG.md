# Changelog

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
