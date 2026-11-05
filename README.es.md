# Super Smash Bros. for Wii U en Xbox — el port UWP

Cómo coger lo que **Smash4PC** produce a partir de tu volcado de *Super Smash Bros. for Wii U*
—un ejecutable nativo, no un emulador— y construirlo **para una Xbox Series X en modo
desarrollador**, como un paquete UWP que firmas tú, con su renderizador de Vulkan corriendo
sobre **Direct3D 12**.

*(English: [README.md](README.md))*

## Lo primero: qué funciona de verdad

Esto es un estado honesto, no un tráiler. Las fechas son de cuando se midió cada línea.

| Dónde | Estado |
|---|---|
| **PC, Vulkan sobre una GPU NVIDIA** | **Se juega, 59,9 FPS.** Eso es Smash4PC haciendo su trabajo; el port no cambia nada aquí |
| **PC, Vulkan sobre Direct3D 12** (Dozen, de Mesa) | **Arranca, dibuja y llega a la demo de atracción.** Lento —decenas de FPS como mucho— y a los pocos minutos se queda sin pools de descriptores y para (2026-11-04) |
| **Xbox Series X, modo desarrollador** | **Dibuja, y dibuja todo** (2026-11-05): pantalla de título, menú principal, la demo de atracción **con su escenario** y el combate, en una televisión, a **23-32 FPS**. Ya no hace falta ninguna muleta: 16 envíos por fotograma, los menús salen limpios y el escenario ya no sale negro |

O sea: en la consola la cadena entera está en pie, el juego dibuja su demo completa en un
televisor y lo hace sin muletas. Si vienes buscando un port terminado, todavía no lo es: queda
el rendimiento —23-32 FPS, no 60— y lo que nadie ha probado aún, empezando por una partida larga
con mando. En [Issues](../../issues) está lo que falta y lo que costaría cada cosa.

## En qué consola se probó

**Una Xbox Series X**, en modo desarrollador. Es el único hardware del que habla nada de aquí.

**Una Series S no se ha probado nunca, ni una vez.** Es otra máquina: menos memoria para el
juego y una GPU más floja, y este port ya necesita **1 GiB de memoria del invitado mapeada** más
un volcado de ~12 GB en una partición de desarrollo de ~30 GB. Puede que funcione, puede que vaya
más lento o puede que ni arranque; aquí no se ha medido nada de eso.

## Qué es este repositorio

**La receta UWP entera**: los dos parches, los sustitutos para Mesa y los scripts que compilan,
empaquetan y despliegan. Smash4PC construye un ejecutable de escritorio con MinGW; esto es todo
lo que hay que cambiar para que el resultado viva dentro de un App Container de Xbox y hable con
Direct3D 12.

| Pieza | Qué es |
|---|---|
| `patches/smash4pc-xbox.patch` | **2.281 líneas añadidas en 35 archivos.** La reescritura del renderizador (abajo), el arranque UWP, el VFS de archivos partidos y el atajo de mando para el contador de FPS |
| `patches/mesa-dozen-xbox.patch` | **199 líneas añadidas en 7 archivos.** Tres fallos reales de Mesa y un diagnóstico, los cuatro encontrados en la consola (abajo) |
| `src/mesa_sysstubs.c` | Sustitutos de las funciones de escritorio que Dozen importa, para que `user32`, `gdi32` y `shell32` no entren nunca en la tabla de importaciones de `vulkan_dzn.dll` |
| `src/mesa_uwp_compat.h` | Cabecera incluida a la fuerza: las grafías de `_Interlocked*` que clang-cl no declara, y la marca de UWP que lee el WSI |
| `tools/compilar-dozen-uwp.ps1` | Compila Dozen para UWP: cross file, entorno `store` y `WindowsApp.lib` |
| `tools/mesa-compilar.ps1` | Compila Dozen para el escritorio, que es como se depura todo esto sin ocho minutos de ida y vuelta a la consola |
| `tools/compilar-uwp.ps1` | Compila el juego para UWP, dentro del entorno `store` de Visual Studio |
| `tools/empaquetar.ps1` | Montaje del paquete, `makeappx` y `signtool`, comprobando el bit de AppContainer antes de construir nada |
| `tools/partir-volcado.ps1` | Parte los dos archivos de varios GB, porque el Device Portal se rinde sobre los 256 MB por subida |
| `tools/xbox-portal.ps1` | Un cliente del Device Portal: instalar, subir, bajar, listar, lanzar, capturar, matar |
| `package/` | El manifiesto, con `CHANGE-ME` donde va tu identidad |

## Lo que no es

Aquí **no hay volcado, ni C++ recompilado, ni ejecutable, ni `.msix`, ni mosaicos, ni
bibliotecas**. `package/Assets/` está vacía a propósito. Ver [NOTICE.es.md](NOTICE.es.md).

## Lo que necesitas antes

| | |
|---|---|
| **Smash4PC** | [`josiahg2502-glitch/Smash4PC`](https://github.com/josiahg2502-glitch/Smash4PC), compilando y funcionando **en tu PC** primero. ⚠ Su árbol no compila tal cual: incluye `stb_image.h` y `stb_truetype.h` desde `third_party/stb`, y esa carpeta ni está en el repositorio ni en su `dependencies.lock.json` ([issue #11](https://github.com/josiahg2502-glitch/Smash4PC/issues/11)). Las dos cabeceras se traen de [`nothings/stb`](https://github.com/nothings/stb) |
| **Tu propio volcado** | *Super Smash Bros. for Wii U* `[AXFE01]`, **actualización v304** y el DLC, en el formato desempaquetado de Cemu. Unos 12 GB más 2,3 GB |
| **Mesa 26.2.x** | El código. Compilas el driver `microsoft-experimental` (Dozen) dos veces: una para escritorio y otra para UWP |
| **Visual Studio 2022** | Con el **componente C++ de UWP**: su entorno `store` (`vcvarsall x64 store`), más `makeappx` y `signtool` del SDK de Windows |
| **`DXIL.dll`** | La de Microsoft, **1.8.2502.8 o posterior**. Sin ella `vkCreateInstance` falla en la consola con `VK_ERROR_INITIALIZATION_FAILED`, y una compilada para escritorio no carga dentro del contenedor |
| **SDL3 para UWP** | [`worleydl/uwp-dep`](https://github.com/worleydl/uwp-dep), ya compilado para UWP x64. El SDL3 de escritorio se niega: *«Windows RT/UWP is no longer supported in SDL»* |
| **Python 3, PowerShell 7 y una Xbox en modo desarrollador** | Y un certificado de firma tuyo |

## Cómo va

```powershell
# Las rutas viven en variables de entorno, no escritas en los scripts
$env:SMASH4_UPSTREAM  = 'D:\smash4\upstream'   # Smash4PC, ya compilado para PC
$env:SMASH4_TOOLCHAIN = 'D:\smash4\toolchain'  # ninja, cmake
$env:SMASH4_UWP_DEP   = 'D:\uwp-dep\x64'       # worleydl/uwp-dep
$env:SMASH4_MESA      = 'D:\mesa'              # el árbol de Mesa
$env:SMASH4_GENERATED = 'D:\smash4\generated\smash'
$env:SMASH4_VKSHIM    = 'D:\smash4\vkshim'
$env:SMASH4_PKG       = 'D:\smash4_pkg'        # donde cae el .msix

# 1. los dos parches
git -C $env:SMASH4_UPSTREAM apply patches\smash4pc-xbox.patch
git -C $env:SMASH4_MESA     apply patches\mesa-dozen-xbox.patch
copy src\mesa_sysstubs.c, src\mesa_uwp_compat.h $env:SMASH4_MESA\uwp\

# 2. Dozen, primero para escritorio: ahí se depura, no en la consola
tools\mesa-compilar.ps1

# 3. Dozen para UWP, luego el juego, luego el paquete
tools\compilar-dozen-uwp.ps1
tools\compilar-uwp.ps1
tools\empaquetar.ps1 -Version 0.1.0.0

# 4. la consola
tools\xbox-portal.ps1 instalar -Host_ <tu consola> -Paquete ... -Certificado ...
tools\partir-volcado.ps1 -Origen <tu volcado> -Destino D:\para-subir
#   luego subes D:\para-subir a LocalState y escribes LocalState\Smash4\rutas.txt
tools\xbox-portal.ps1 lanzar -Host_ <tu consola> -Pfn ... -AppId ...
```

[`docs/INSTALL.es.md`](docs/INSTALL.es.md) es la versión larga, paso a paso, con lo que sale mal.

## La parte que de verdad costó

El renderizador de Smash4PC pide tres cosas que el Direct3D 12 de una Xbox no da, y las tres se
**midieron en la consola**, no se supusieron. Ninguna se rodeó con un parche: el renderizador se
reescribió para no necesitarlas. La historia completa está en
[`docs/HOW-IT-WORKS.es.md`](docs/HOW-IT-WORKS.es.md); en corto:

1. **Sin `bufferDeviceAddress`.** Todo acceso de un shader a la memoria del invitado pasa por
   tres funciones GLSL, y el `Buffer` del ABI ya viajaba como un `uvec4`. No cambió de tamaño,
   solo qué significa cada componente: de `(addr_lo, addr_hi, size, stride)` a
   `(offset, region, size, stride)`, indexando un array de storage buffers. Tampoco hace falta
   `descriptor_indexing`: el índice sale de un uniform, y eso es lo que lo vuelve dinámicamente
   uniforme.
2. **Sin `VK_EXT_external_memory_host`.** La RAM del invitado no se le puede entregar a la GPU
   tal cual, así que se copia, con un mapa de páginas de 256 bytes. Lo que hizo esto viable: el
   juego lanza 1,7 invalidaciones de toda la caché por frame con tamaño `0xFFFFFFFF`, y creerlas
   cuesta **1.759 MB/s**; creer solo las que traen rango cuesta **11,9 MB/s**.
3. **`maxStorageBufferRange` son 128 MiB** y MEM2 es 1 GiB. Direct3D 12 deja que un shader vea
   `1 << D3D12_REQ_BUFFER_RESOURCE_TEXEL_COUNT_2_TO_EXP` de un buffer, y ni un byte más. Cada
   región se parte en **ventanas solapadas a la mitad** —un `VkBuffer` por ventana, todas sobre
   la misma asignación a distinto desplazamiento—. MEM2 sale en 16 ventanas.

## Tres fallos de Mesa, encontrados en la consola

Los tres están en `patches/mesa-dozen-xbox.patch` y los tres merecen ir aguas arriba.

| Fallo | Qué pasa | Dónde |
|---|---|---|
| **`SetViewInstanceMask` donde no hay view instancing** | Dozen la llama en cada cambio de pipeline gráfico, haya máscara o no. Una máscara de `1` es la vista única por omisión, así que la llamada no hace nada —salvo en cualquier GPU de AMD, donde el tier es `NOT_SUPPORTED`: el runtime la rechaza, el command list queda en estado de error y `Close()` falla. `vkEndCommandBuffer` devuelve entonces `VK_ERROR_OUT_OF_HOST_MEMORY` y **no se dibuja nada**. `dzn_pipeline.c` ya hace esa comprobación; el command buffer no | `dzn_cmd_buffer.c` |
| **El WSI de Win32 necesita una ventana de escritorio** | Presenta por DirectComposition: `CreateSwapChainForComposition` y después `IDCompositionDevice::CreateTargetForHwnd`. En UWP no hay HWND de escritorio —lo que la superficie guarda es una CoreWindow— y `vkCreateSwapchainKHR` devuelve `VK_ERROR_INITIALIZATION_FAILED`. La salida es `CreateSwapChainForCoreWindow`, que presenta por sí misma | `wsi_common_win32.cpp` |
| **`DXIL.dll` se carga con `LoadLibrary`** | Dentro de un App Container eso no encuentra una DLL del paquete, y además la grafía tiene que coincidir exactamente con el archivo. Sin el validador, `vkCreateInstance` falla sin explicar nada | `dxil_validator.cpp`, `dzn_dxgi.c` |

Y un diagnóstico que no es un fallo pero ahorró días: `GetResourceAllocationInfo` devuelve
`SizeInBytes = UINT64_MAX` cuando Direct3D 12 rechaza un recurso, y Dozen lo copia tal cual a
`VkMemoryRequirements::size`, así que la aplicación intenta reservar
18.446.744.073.709.551.615 bytes y se cae. El parche imprime la descripción del recurso
rechazado en vez de dejarte adivinando. Así salieron dos formatos de textura que faltan:
**`R4G4_UNORM_PACK8`** y **`B5G6R5_UNORM_PACK16`**, que no existen en DXGI. Los dos se
desempaquetan ahora al subirlos, a un formato que sí existe.

## Depurar en el PC, no en la consola

Lo más útil de todo este repositorio. Dozen sobre una GPU de escritorio es el mismo driver que
corre en la consola, y el runtime de Direct3D 12 que rechaza un command list mal grabado es el
mismo código:

```powershell
$env:VK_DRIVER_FILES = "$env:SMASH4_MESA\build\src\microsoft\vulkan\dzn_devenv_icd.x86_64.json"
$env:TTT2_PRESENT_BLIT = '1'      # la cadena de Dozen no se puede escribir desde un shader
$env:MESA_TRACE_ERRORS = '1'      # cada error de Mesa dice en qué archivo y línea nació
$env:DZN_DEBUG = 'd3d12'          # la capa de depuración de D3D12; el parche vuelca su InfoQueue
```

Dos de los tres fallos de arriba salieron así en minutos. El tercero —el view instancing— solo
aparece en hardware de AMD, y por eso el volcado del InfoQueue de D3D12 tenía que funcionar **en
la consola**; funciona.

En la consola no hay línea de órdenes, así que `LocalState\Smash4\entorno.txt` fija variables de
entorno, una `CLAVE=valor` por línea, y se sube en segundos con `tools\xbox-portal.ps1 subir`.

## El contador de FPS en pantalla

Smash4PC ya trae uno, en su overlay, con modo detallado (FPS del juego, fotograma más lento,
tiempo de GPU, draws). Dos problemas en una consola, los dos resueltos en el parche:

* el overlay se abre con Escape o con el botón **Guide**, y en una Xbox el sistema se queda el
  Guide para él: no llega nunca a la aplicación. Ahora **LB + RB + View** abre el mismo menú;
* `SMASH_COUNTER=0|1|2` enciende el contador desde el arranque, que es lo que hace falta cuando
  no hay teclado y estás midiendo.

## Créditos

* **Smash4PC** y el motor `cafe-recomp` que lleva dentro — [JosiahG](https://github.com/josiahg2502-glitch),
  con el motor y su runtime de **Petexy / Linexy**, que son los titulares del copyright que
  nombra su `LICENSE`. Todo lo que este port hace es su trabajo corriendo en otro sitio.
* **Mesa** y su driver **Dozen** — Microsoft y quienes contribuyen a Mesa. Vulkan sobre
  Direct3D 12 es lo que hace posible una Xbox aquí.
* **[`emelin2004/rpcs3-xbox`](https://github.com/emelin2004/rpcs3-xbox)** — por demostrar que
  Dozen se puede meter en un App Container de Xbox, y por la idea de los sustitutos del sistema.
  Aquí no hay código suyo.
* **[`worleydl/uwp-dep`](https://github.com/worleydl/uwp-dep)** — SDL3 y compañía, compilados
  para UWP.
* **Nintendo y HAL Laboratory**, que hicieron el juego. Trae tu copia.
