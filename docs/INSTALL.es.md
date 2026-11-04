# Construirlo e instalarlo

*(English: [INSTALL.md](INSTALL.md))*

Todas las rutas de aquí son ejemplos. Los scripts las sacan de variables de entorno: las fijas
una vez y te olvidas.

```powershell
$env:SMASH4_UPSTREAM  = 'D:\smash4\upstream'
$env:SMASH4_TOOLCHAIN = 'D:\smash4\toolchain'
$env:SMASH4_UWP_DEP   = 'D:\uwp-dep\x64'
$env:SMASH4_MESA      = 'D:\mesa'
$env:SMASH4_GENERATED = 'D:\smash4\generated\smash'
$env:SMASH4_VKSHIM    = 'D:\smash4\vkshim'
$env:SMASH4_PKG       = 'D:\smash4_pkg'
```

## 0. Primero, que Smash4PC funcione en tu PC

No te lo saltes. Si no corre en tu PC no va a correr en una consola, y acabarás depurando dos
cosas a la vez.

* Clona [`josiahg2502-glitch/Smash4PC`](https://github.com/josiahg2502-glitch/Smash4PC) y sigue
  **sus** instrucciones para recompilar tu propio volcado.
* ⚠ **No compila tal cual.** Su CMake busca `stb_image.h` y `stb_truetype.h` en
  `third_party/stb`, y esa carpeta no está en el repositorio, ni en `dependencies.lock.json`, ni
  es un submódulo. Las dos cabeceras se traen de
  [`nothings/stb`](https://github.com/nothings/stb), fijadas a un commit.
* `TTT2_GPU=null` lo corre sin ventana, que es la forma rápida de ver si el código recompilado
  está vivo antes de preocuparse por los gráficos.

## 1. Aplicar los dos parches

```powershell
git -C $env:SMASH4_UPSTREAM apply --3way ..\patches\smash4pc-xbox.patch
git -C $env:SMASH4_MESA     apply --3way ..\patches\mesa-dozen-xbox.patch
mkdir $env:SMASH4_MESA\uwp -Force
copy src\mesa_sysstubs.c, src\mesa_uwp_compat.h $env:SMASH4_MESA\uwp\
```

Si el primero no entra limpio es que el árbol de arriba se movió. Lee los hunks: la reescritura
del renderizador está en `runtime/src/gpu/vulkan/`, la parte UWP en `runtime/src/host/`, y son
independientes entre sí.

## 2. Dozen para escritorio

Compílalo **primero**, aunque lo que quieras sea el de la consola. Es con lo que se depura todo
lo demás.

```powershell
tools\mesa-compilar.ps1
```

Tres cosas que costaron tiempo y que el script ya resuelve:

* **El árbol no puede estar en una ruta profunda.** Pasando de 260 caracteres MSVC no crea sus
  PDB: `C1083: Cannot open compiler generated file: ''`.
* **Cualquier `ccache` en el PATH rompe los PDB igual.** El script lo saca.
* Las herramientas de Python de Mesa necesitan `packaging` y `mako`, en un venv.

Prueba el juego contra él antes de acercarte a la consola:

```powershell
$env:VK_DRIVER_FILES = "$env:SMASH4_MESA\build\src\microsoft\vulkan\dzn_devenv_icd.x86_64.json"
$env:TTT2_PRESENT_BLIT = '1'
D:\smash4\Play\smash.exe --dlc <dlc> <actualizacion> <juego>
```

## 3. Dozen para UWP

```powershell
tools\compilar-dozen-uwp.ps1
```

Cuatro trampas, todas ya dentro del script:

1. **No definas `WINAPI_FAMILY_APP`**, por lógico que parezca. Mesa se compila como código
   normal de Windows y lo que mantiene las APIs prohibidas fuera del paquete es
   `mesa_sysstubs.c`. Definirlo rompe `disk_cache_os.c` y no gana nada.
2. **Un cross file, no un native file.** Un ejecutable de UWP no se puede lanzar desde el
   escritorio, así que meson falla al probar el compilador: *«Executables created by c compiler
   clang-cl are not runnable»*. Declarado como compilación cruzada, no lo intenta.
3. **`mesa_uwp_compat.h` incluida a la fuerza con `/FI`.** Mesa usa las grafías en minúscula
   `_interlocked*` (que MSVC declara y clang-cl no) y `_InterlockedAdd`/`_InterlockedAdd64`, que
   en x64 no existen en ninguno de los dos porque son intrínsecos de ARM. ⚠ Tiene que ir dentro
   de `#ifndef __ASSEMBLER__`: un force-include llega también a los `.S` de blake3.
4. **`-Dshader-cache=disabled`**: su caché en disco usa `CreateFileW`.

Y la que parece otra cosa: meson diciendo que falla `find_library('d3d12')`. La biblioteca que
falta es **`WindowsApp.lib`**, no d3d12.

Deja `DXIL.dll` donde el empaquetado la encuentre: `$env:SMASH4_MESA\uwp\dxil.dll` sirve, y
sobrevive a un `meson setup --wipe`, cosa que la carpeta de compilación no.

## 4. El juego, y el paquete

```powershell
tools\compilar-uwp.ps1
tools\empaquetar.ps1 -Version 0.1.0.0
```

`empaquetar.ps1` se niega a montar nada si el ejecutable no lleva el bit de AppContainer o si tu
certificado caducó: las dos cosas fallan, si no, mucho más tarde y mucho peor explicadas.

⚠ **Sube la versión en cada entrega que instales.** Windows no reemplaza un paquete con
contenido distinto bajo la misma versión, y el despliegue se queda tan ancho con el viejo.

## 5. La consola

```powershell
$h = '<la IP de tu consola>'
tools\xbox-portal.ps1 instalar -Host_ $h -Paquete $env:SMASH4_PKG\Smash4-Recomp-0.1.0.0.msix `
                               -Certificado <tu .cer>
```

Las credenciales del Device Portal van en `%LOCALAPPDATA%\xbox-devportal\credenciales.txt`, una
línea, `usuario:contraseña`. Nunca en este repositorio.

### El volcado

Unos 12 GB más 2,3 GB, en una partición de desarrollo de unos 30 GB. Dos archivos pesan varios
GB cada uno y el portal se rinde sobre los 256 MB por subida, así que:

```powershell
tools\partir-volcado.ps1 -Origen <tu volcado> -Destino D:\para-subir
```

Eso escribe `dt00.000`, `dt00.parte1`… y el VFS parcheado los sirve como un solo archivo. Sube
el resultado a `LocalState\Smash4\` y escribe `LocalState\Smash4\rutas.txt`:

```
<la carpeta del DLC>
<la carpeta de la actualización>
<la carpeta del juego>
```

⚠ El portal rechaza nombres de carpeta con corchetes o puntos en algunas operaciones: contesta
`-2147024773, «syntax is incorrect»` y le echa la culpa al archivo, no a la carpeta. Usa nombres
simples.

### Lanzar, y leer qué pasó

```powershell
tools\xbox-portal.ps1 lanzar -Host_ $h -Pfn <nombre completo del paquete> -AppId <PRID>
tools\xbox-portal.ps1 descargar -Host_ $h -Pfn <pfn> -Ruta '\LocalState\Smash4' `
                                -Nombre smash.log -Salida .\smash.log
```

Para encender una traza del driver sin recompilar nada, sube un `entorno.txt`:

```
DZN_DEBUG=d3d12
MESA_TRACE_ERRORS=1
SMASH_COUNTER=2
```

```powershell
tools\xbox-portal.ps1 subir -Host_ $h -Pfn <pfn> -Ruta '\LocalState\Smash4' -Archivo .\entorno.txt
```

## Cuando sale mal

| Lo que ves | Qué es |
|---|---|
| `vkCreateInstance` → `VK_ERROR_INITIALIZATION_FAILED` | Falta `DXIL.dll` en el paquete, o es una compilada para escritorio. Usa la 1.8.2502.8 o posterior |
| `vkEndCommandBuffer` → `-1` y no se dibuja nada | El fallo del view instancing. Comprueba que el parche de Mesa está aplicado |
| `vkCreateSwapchainKHR` → `-3` | El camino de DirectComposition. El mismo parche |
| `vkAllocateMemory` … `18446744073709551615 bytes` | Direct3D 12 rechazó una imagen. Con el parche aplicado, el registro dice qué formato |
| La aplicación no arranca y la consola muestra **«Sign in to start this app»** | La consola no tiene cuenta conectada: la pierde al reiniciar. Hay que iniciar sesión con el mando; el Device Portal no puede sin la contraseña de la cuenta |
| `Failed to terminate the application` | Un proceso cuyo paquete se desinstaló. Se mata por PID con `/api/taskmanager/process?pid=` |
| Un proceso viejo sigue vivo | Comparte `LocalState` con el nuevo y le pisa el `smash.log`. Mira `tools\xbox-portal.ps1 procesos` antes de fiarte de un registro |
