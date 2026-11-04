# How it works

*(Español: [HOW-IT-WORKS.es.md](HOW-IT-WORKS.es.md))*

What had to change, and why. If you only want to build it, read
[INSTALL.md](INSTALL.md) instead.

## The shape of the problem

Smash4PC is a **static recompilation**: `cafe-recomp` reads the game's `.rpx` and emits one C++
function per PowerPC function, and `runtime/` reimplements Cafe OS — threads, filesystem,
`snd_core`, `vpad` — and turns GX2 into PM4, Latte registers, GLSL, SPIR-V and Vulkan. Nothing
is interpreted.

That means an Xbox port is not "make the emulator run there". It is three separate problems:

1. the executable has to live in an **App Container** (no `user32`, no desktop APIs, no command
   line, a read-only install folder);
2. there is **no Vulkan** on an Xbox, so Vulkan has to become Direct3D 12 — that is **Dozen**,
   Mesa's `microsoft-experimental` driver;
3. the renderer asks Vulkan for things **this particular** Direct3D 12 does not have.

The third one is the interesting part, and the one that took a rewrite rather than a patch.

## What the console actually reports

Measured there, with a tiny UWP program before any of this was written. The GPU is
`Microsoft Direct3D12 (SraKmd_arden)`, Vulkan **1.2.354**:

| | |
|---|---|
| swapchain, `dynamic_rendering`, `synchronization2`, `timelineSemaphore`, BC formats | ✅ |
| all four depth formats | ✅ (but see below — "supported" is not "creatable") |
| **`VK_KHR_buffer_device_address`** | ❌ and the renderer required it |
| **`VK_EXT_external_memory_host`** | ❌ (Dozen wants `ID3D12Device13` for it) |
| `descriptor_indexing` | ❌ |
| `maxStorageBufferRange` | **128 MiB** |
| `maxMemoryAllocationSize` | **1024 MiB** — and MEM2 is 1024 MiB exactly |

An Xbox in Developer Mode reports **Feature Level 11_0** even though it is RDNA2, and Dozen gates
`buffer_device_address` and `descriptor_indexing` on **Shader Model 6.6**. The WARP software
device does have them, which is how you can tell the limit is the GPU driver and not Dozen.

## 1. Life without `bufferDeviceAddress`

Every shader read or write of guest memory goes through three GLSL functions the translator
emits — `gload`, `gstore`, `kc` — and the ABI's descriptor already travelled as a `uvec4`.

So the fix costs nothing at the call sites: `abi::Buffer` keeps its size and changes meaning,
from `(addr_lo, addr_hi, size, stride)` to **`(offset, region, size, stride)`**, where `region`
indexes an array of storage buffers bound at `abi::kGuestMemoryBinding`.

It does **not** need `descriptor_indexing`: the index comes from a uniform, and that makes it
*dynamically uniform*, which is all Vulkan 1.0 asks for when indexing an array of descriptors.

## 2. Life without `VK_EXT_external_memory_host`

Without it the guest's RAM cannot be handed to the GPU as-is. It has to be copied, and the
question is how much.

What made it affordable is that **everything the GPU reads passes through one function**,
`Renderer::buffer_descriptor`. That is the only place that has to flush. Around it:

* `GuestMemory::written()` — the game's own invalidation;
* `gpu_wrote()` — the stream-out destination, which must **not** be refreshed;
* `flush()` — before each draw, with a **256-byte page map** so only dirty pages travel.

Two findings decided whether this was viable at all:

* **Believing the whole-cache invalidations costs 148× the traffic.** The game issues **1.7
  `GX2Invalidate` calls per frame with size `0xFFFFFFFF`**, which say nothing about what
  changed. Taking them literally means re-copying everything the frame reads, every frame:
  **1759 MB/s**. Believing only the ranged ones: **11.9 MB/s**, with 59.9 FPS at 444 draws. It is
  the same bet the texture cache already made.
* **A real hole in the renderer:** the retirement thread un-tiles render-target write-backs by
  writing guest memory **with the CPU**, and told nobody. With shared memory that was harmless;
  with copies, those bytes never arrived. It now reports through the same queue that orders the
  notice against the draws.

Safety net: `TTT2_GUEST_COPY=frame` marks everything stale once per frame (170 MB/s) if you
suspect a missing invalidation.

## 3. The one that was not on the list: 128 MiB per storage buffer

Direct3D 12 lets a shader see `1 << D3D12_REQ_BUFFER_RESOURCE_TEXEL_COUNT_2_TO_EXP` = **128 MiB**
of a buffer. MEM2 is **1 GiB**. This also broke change 1, which had already been declared done —
an RTX 4080 has a 4 GiB limit and never tells you.

The way out costs nothing in the shader, because the ABI already indexes an array: each region is
split into **half-overlapping windows**, one `VkBuffer` per window, **all bound to the same
allocation** at different offsets (`vkBindBufferMemory` with an offset; Dozen implements that
with `CreatePlacedResource`). Any object that fits in half a window is wholly inside some window.
MEM2 comes out as 16 windows of 128 MiB.

> ⚠ `maxMemoryAllocationSize` is 1024 MiB and MEM2 is 1024 MiB exactly: it fits with no margin.
> A larger region would have to split the **allocation** too, not only the windows.

You can try all three limits on a desktop GPU before touching the console:
`TTT2_NO_EXTERNAL_MEMORY_HOST=1` and `TTT2_STORAGE_BUFFER_RANGE=0x8000000`.

## 4. Formats Direct3D 12 does not have

"Supported" and "creatable" are different questions, and Dozen answers the first one.
`vkGetPhysicalDeviceFormatProperties` can return a usable set of features for a format whose
image Direct3D 12 then refuses to allocate — the refusal arrives as
`VkMemoryRequirements::size == UINT64_MAX`, or as `0`.

So the port checks by **creating a test image** and looking at the size, and at startup it prints
the list of formats this driver does not have. On the console that list is:

```
R8_SRGB, R4G4_UNORM_PACK8, R8G8_SRGB, B5G6R5_UNORM_PACK16
```

* **`R8_SRGB`, `R8G8_SRGB`** — no DXGI equivalent. They fall back to UNORM: the gamma curve is
  lost, the image is not.
* **`R4G4_UNORM_PACK8`** — two 4-bit channels in a byte. Becomes `R8G8_UNORM`, unpacked on
  upload: each nibble to its own byte, ×17 so `0xF` reaches `0xFF`.
* **`B5G6R5_UNORM_PACK16`** — used for a full-screen render target. Becomes `R8G8B8A8_UNORM`,
  unpacked the same way. More precision than the guest had, not less. A target that is unpacked
  is never written back to guest memory, which is the existing rule for widened formats.

## 5. Inside the App Container

| Problem | What the patch does |
|---|---|
| No command line | The dump's folders come from `LocalState\Smash4\rutas.txt`, one argument per line. `LocalState\Smash4\entorno.txt` sets environment variables the same way |
| The install folder is **read only** | Saves, shader cache and the log are forced to `LocalState` with `_putenv_s` before the runtime starts. ⚠ `SDL_setenv_unsafe` is not enough: it writes SDL's own table and `std::getenv` never sees it |
| A failed `freopen` **closes stderr** | and then the process dies with no trace. `_dup`/`_dup2` keep a rescue copy |
| `GetClientRect` has to answer | Mesa's WSI measures the window with it and declares the surface lost if it fails. The stub asks the executable, which exports `uwp_get_width` / `uwp_get_height` |
| The CoreWindow has thread affinity | The Vulkan surface is created **on the CoreWindow's own thread**, through a request and a condition variable |
| The Device Portal gives up near 256 MB | `partir-volcado.ps1` splits the two big archives, and the VFS serves `x.000` + `x.parteN` as one file |
| `/APPCONTAINER` | Without that bit the package will not install. `empaquetar.ps1` checks the header before building anything |

## 6. Why you debug this on the PC

Dozen on a desktop GPU is the same driver, and the Direct3D 12 runtime that rejects a malformed
command list is the same code. A round trip to the console — package, install, launch, download
the log — is eight minutes; on the PC it is one.

Two of the three Mesa bugs were found that way in minutes. The third only happens on AMD
hardware, so the patch makes the D3D12 **InfoQueue** dump to stderr when `Close()` fails, and
that works on the console too. With `DZN_DEBUG=d3d12` the console printed, in one line, the
thing nobody would have guessed:

```
D3D12 #1095: ID3D12CommandList::SetViewInstanceMask: Device does not support view instancing.
Hardware tier is D3D12_VIEW_INSTANCING_TIER_NOT_SUPPORTED.
```
