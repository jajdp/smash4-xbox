# Building and installing it

*(Español: [INSTALL.es.md](INSTALL.es.md))*

Every path here is an example. The scripts take them from environment variables, so set those
once and forget about them.

```powershell
$env:SMASH4_UPSTREAM  = 'D:\smash4\upstream'
$env:SMASH4_TOOLCHAIN = 'D:\smash4\toolchain'
$env:SMASH4_UWP_DEP   = 'D:\uwp-dep\x64'
$env:SMASH4_MESA      = 'D:\mesa'
$env:SMASH4_GENERATED = 'D:\smash4\generated\smash'
$env:SMASH4_VKSHIM    = 'D:\smash4\vkshim'
$env:SMASH4_PKG       = 'D:\smash4_pkg'
```

## 0. Get Smash4PC running on your PC first

Do not skip this. If it does not run on your PC it will not run on a console, and you will be
debugging two things at once.

* Clone [`josiahg2502-glitch/Smash4PC`](https://github.com/josiahg2502-glitch/Smash4PC) and
  follow **its** instructions to recompile your own dump.
* ⚠ **It does not build out of the box.** Its CMake looks for `stb_image.h` and
  `stb_truetype.h` in `third_party/stb`, and that folder is not in the repository, not in
  `dependencies.lock.json` and not a submodule. Fetch both headers from
  [`nothings/stb`](https://github.com/nothings/stb), pinned to a commit.
* `TTT2_GPU=null` runs it with no window, which is a quick way to see whether the recompiled
  code is alive before worrying about graphics.

## 1. Apply the two patches

```powershell
git -C $env:SMASH4_UPSTREAM apply --3way ..\patches\smash4pc-xbox.patch
git -C $env:SMASH4_MESA     apply --3way ..\patches\mesa-dozen-xbox.patch
mkdir $env:SMASH4_MESA\uwp -Force
copy src\mesa_sysstubs.c, src\mesa_uwp_compat.h $env:SMASH4_MESA\uwp\
```

Both were made against, and checked with `git apply --check` on, these commits:

| Tree | Commit |
|---|---|
| Smash4PC | `760bd35` — *Netplay: 1080p, encoded on the GPU; keep-alive; 3DS link fails gracefully* |
| Mesa | `a44c011` — *docs: add sha sum for 26.2.6* (26.2.x) |

If the first one does not apply cleanly, the upstream tree has moved on. Read the hunks: the
renderer rewrite is in `runtime/src/gpu/vulkan/`, the UWP side in `runtime/src/host/`, and they
are independent of each other.

## 2. Dozen for the desktop

Build this **first**, even though you want the console one. It is how you debug everything else.

```powershell
tools\mesa-compilar.ps1
```

Three things that cost time and are already handled in the script:

* **The tree cannot live under a deep path.** Over 260 characters and MSVC cannot create its
  PDBs: `C1083: Cannot open compiler generated file: ''`.
* **Any `ccache` on the PATH breaks the PDBs the same way.** The script strips it.
* Mesa's Python tooling needs `packaging` and `mako`, in a venv.

Test the game against it before going near the console:

```powershell
$env:VK_DRIVER_FILES = "$env:SMASH4_MESA\build\src\microsoft\vulkan\dzn_devenv_icd.x86_64.json"
$env:TTT2_PRESENT_BLIT = '1'
D:\smash4\Play\smash.exe --dlc <dlc> <update> <game>
```

## 3. Dozen for UWP

```powershell
tools\compilar-dozen-uwp.ps1
```

Four traps, all of them already in the script:

1. **Do not define `WINAPI_FAMILY_APP`**, however logical it looks. Mesa compiles as ordinary
   Windows code and what keeps the forbidden APIs out of the package is `mesa_sysstubs.c`.
   Defining it breaks `disk_cache_os.c` and buys nothing.
2. **A cross file, not a native file.** A UWP executable cannot be launched from the desktop, so
   meson fails while probing the compiler: *"Executables created by c compiler clang-cl are not
   runnable"*. Declared as a cross build, it does not try.
3. **`mesa_uwp_compat.h` force-included with `/FI`.** Mesa uses the lowercase `_interlocked*`
   spellings (MSVC declares them, clang-cl does not) and `_InterlockedAdd`/`_InterlockedAdd64`,
   which do not exist on x64 in either compiler because they are ARM intrinsics. ⚠ It has to be
   inside `#ifndef __ASSEMBLER__`: a force-include reaches blake3's `.S` files too.
4. **`-Dshader-cache=disabled`**: its on-disk cache uses `CreateFileW`.

And the one that looks like something else: meson reporting `find_library('d3d12')` failing. The
missing library is **`WindowsApp.lib`**, not d3d12.

Put `DXIL.dll` where the packager will find it — `$env:SMASH4_MESA\uwp\dxil.dll` works, and
survives a `meson setup --wipe`, which the build directory does not.

## 4. The game, and the package

```powershell
tools\compilar-uwp.ps1
tools\empaquetar.ps1 -Version 0.1.0.0
```

`empaquetar.ps1` refuses to build if the executable does not carry the AppContainer bit or if
your certificate has expired — both of which otherwise fail much later and much less clearly.

⚠ **Bump the version on every build you install.** Windows will not replace a package with
different content under the same version, and the deploy will quietly keep the old one.

## 5. The console

```powershell
$h = '<your console IP>'
tools\xbox-portal.ps1 instalar -Host_ $h -Paquete $env:SMASH4_PKG\Smash4-Recomp-0.1.0.0.msix `
                               -Certificado <your .cer>
```

The Device Portal credentials go in `%LOCALAPPDATA%\xbox-devportal\credenciales.txt`, one line,
`user:password`. They never go in this repository.

### The dump

About 12 GB plus 2.3 GB, on a developer partition of roughly 30 GB. Two archives are several GB
each and the portal gives up around 256 MB per upload, so:

```powershell
tools\partir-volcado.ps1 -Origen <your dump> -Destino D:\to-upload
```

That writes `dt00.000`, `dt00.parte1`… and the patched VFS serves them as one file. Upload the
result into `LocalState\Smash4\` and write `LocalState\Smash4\rutas.txt`:

```
<the DLC folder>
<the update folder>
<the game folder>
```

⚠ The portal rejects folder names with brackets or dots in some operations — it answers
`-2147024773, "syntax is incorrect"` and blames the file, not the folder. Use plain names.

### Launching, and reading what happened

```powershell
tools\xbox-portal.ps1 lanzar -Host_ $h -Pfn <package full name> -AppId <PRID>
tools\xbox-portal.ps1 descargar -Host_ $h -Pfn <pfn> -Ruta '\LocalState\Smash4' `
                                -Nombre smash.log -Salida .\smash.log
```

To turn on a driver trace without rebuilding anything, upload a one-line `entorno.txt`:

```
DZN_DEBUG=d3d12
MESA_TRACE_ERRORS=1
SMASH_COUNTER=2
```

```powershell
tools\xbox-portal.ps1 subir -Host_ $h -Pfn <pfn> -Ruta '\LocalState\Smash4' -Archivo .\entorno.txt
```

## When it goes wrong

| What you see | What it is |
|---|---|
| `vkCreateInstance` → `VK_ERROR_INITIALIZATION_FAILED` | `DXIL.dll` missing from the package, or a desktop build of it. Use 1.8.2502.8 or later |
| `vkEndCommandBuffer` → `-1`, nothing drawn | The view instancing bug. Make sure the Mesa patch is applied |
| `vkCreateSwapchainKHR` → `-3` | The DirectComposition path. Same patch |
| `vkAllocateMemory` ... `18446744073709551615 bytes` | Direct3D 12 rejected an image. With the patch applied, the log says which format |
| The app does not start, the console shows **"Sign in to start this app"** | The console has no signed-in account — it loses it on a restart. Sign in with the controller; the Device Portal cannot do it without the account password |
| `Failed to terminate the application` | A process whose package was uninstalled. Kill it by PID through `/api/taskmanager/process?pid=` |
| A stale process keeps running | It shares `LocalState` with the new one and will overwrite `smash.log`. Check `tools\xbox-portal.ps1 procesos` before trusting a log |
