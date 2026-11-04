# Cómo funciona

*(English: [HOW-IT-WORKS.md](HOW-IT-WORKS.md))*

Qué hubo que cambiar, y por qué. Si solo quieres construirlo, ve a
[INSTALL.es.md](INSTALL.es.md).

## La forma del problema

Smash4PC es una **recompilación estática**: `cafe-recomp` lee el `.rpx` del juego y emite una
función C++ por cada función PowerPC, y `runtime/` reimplementa Cafe OS —hilos, sistema de
archivos, `snd_core`, `vpad`— y convierte GX2 en PM4, registros Latte, GLSL, SPIR-V y Vulkan.
No se interpreta nada.

Eso significa que un port a Xbox no es «que el emulador corra allí». Son tres problemas
distintos:

1. el ejecutable tiene que vivir en un **App Container** (sin `user32`, sin APIs de escritorio,
   sin línea de órdenes, con la carpeta de instalación de solo lectura);
2. en una Xbox **no hay Vulkan**, así que Vulkan tiene que volverse Direct3D 12: eso es
   **Dozen**, el driver `microsoft-experimental` de Mesa;
3. el renderizador le pide a Vulkan cosas que **este** Direct3D 12 no tiene.

La tercera es la interesante, y la que pidió una reescritura y no un parche.

## Lo que la consola contesta de verdad

Medido allí, con un programa UWP mínimo, antes de escribir nada de esto. La GPU es
`Microsoft Direct3D12 (SraKmd_arden)`, Vulkan **1.2.354**:

| | |
|---|---|
| swapchain, `dynamic_rendering`, `synchronization2`, `timelineSemaphore`, formatos BC | ✅ |
| los cuatro formatos de profundidad | ✅ (pero ver abajo: «soportado» no es «creable») |
| **`VK_KHR_buffer_device_address`** | ❌ y el renderizador la exigía |
| **`VK_EXT_external_memory_host`** | ❌ (Dozen pide `ID3D12Device13` para ella) |
| `descriptor_indexing` | ❌ |
| `maxStorageBufferRange` | **128 MiB** |
| `maxMemoryAllocationSize` | **1024 MiB**, y MEM2 son 1024 MiB exactos |

Una Xbox en modo desarrollador reporta **Feature Level 11_0** pese a ser RDNA2, y Dozen
condiciona `buffer_device_address` y `descriptor_indexing` al **Shader Model 6.6**. El
dispositivo WARP por software sí las tiene, y así se sabe que el límite es el driver de la GPU
y no Dozen.

## 1. La vida sin `bufferDeviceAddress`

Toda lectura o escritura de memoria del invitado desde un shader pasa por tres funciones GLSL
que emite el traductor —`gload`, `gstore`, `kc`— y el descriptor del ABI ya viajaba como un
`uvec4`.

Así que el arreglo no cuesta nada en los puntos de llamada: `abi::Buffer` conserva el tamaño y
cambia de significado, de `(addr_lo, addr_hi, size, stride)` a **`(offset, region, size,
stride)`**, donde `region` indexa un array de storage buffers enlazados en
`abi::kGuestMemoryBinding`.

**No** hace falta `descriptor_indexing`: el índice sale de un uniform, y eso lo vuelve
*dinámicamente uniforme*, que es lo único que Vulkan 1.0 pide para indexar un array de
descriptores.

## 2. La vida sin `VK_EXT_external_memory_host`

Sin ella, la RAM del invitado no se le puede entregar a la GPU tal cual. Hay que copiarla, y la
pregunta es cuánto.

Lo que lo hizo viable es que **todo lo que la GPU lee pasa por una sola función**,
`Renderer::buffer_descriptor`. Ese es el único sitio que tiene que volcar. Alrededor:

* `GuestMemory::written()`, la invalidación del propio juego;
* `gpu_wrote()`, el destino del stream-out, que **no** hay que refrescar;
* `flush()`, antes de cada draw, con un **mapa de páginas de 256 bytes** para que solo viaje lo
  sucio.

Dos hallazgos decidieron si esto servía o no:

* **Creerse las invalidaciones de toda la caché costaba 148 veces el tráfico.** El juego hace
  **1,7 `GX2Invalidate` por frame con tamaño `0xFFFFFFFF`**, que no dicen qué cambió. Tomarlas al
  pie de la letra obliga a recopiar todo lo que el frame lee, todos los frames: **1.759 MB/s**.
  Creyendo solo las que traen rango: **11,9 MB/s**, con 59,9 FPS y 444 draws. Es la misma
  apuesta que ya hacía la caché de texturas.
* **Un agujero real del renderizador:** el hilo de retiro desteje los write-backs de los render
  targets **escribiendo memoria del invitado con la CPU**, y no avisaba a nadie. Con memoria
  compartida daba igual; con copias, esos bytes no llegaban nunca. Ahora avisa por la misma cola
  que ordena el aviso respecto a los draws.

Red de seguridad: `TTT2_GUEST_COPY=frame` marca todo atrasado una vez por frame (170 MB/s) si
sospechas de una invalidación que falta.

## 3. El que no estaba en la lista: 128 MiB por storage buffer

Direct3D 12 deja que un shader vea `1 << D3D12_REQ_BUFFER_RESOURCE_TEXEL_COUNT_2_TO_EXP` =
**128 MiB** de un buffer. MEM2 es **1 GiB**. Esto rompía también el cambio 1, que ya se había
dado por bueno: una RTX 4080 tiene un tope de 4 GiB y no lo delata nunca.

La salida no cuesta nada en el shader, porque el ABI ya indexa un array: cada región se parte en
**ventanas solapadas a la mitad**, un `VkBuffer` por ventana, **todas sobre la misma asignación**
a distinto desplazamiento (`vkBindBufferMemory` con offset; Dozen lo implementa con
`CreatePlacedResource`). Cualquier objeto que quepa en media ventana está entero dentro de
alguna. MEM2 sale en 16 ventanas de 128 MiB.

> ⚠ `maxMemoryAllocationSize` son 1024 MiB y MEM2 son 1024 MiB exactos: entra sin un byte de
> margen. Si la región creciera habría que partir también la **asignación**, no solo las
> ventanas.

Los tres límites se pueden probar en una GPU de escritorio antes de tocar la consola:
`TTT2_NO_EXTERNAL_MEMORY_HOST=1` y `TTT2_STORAGE_BUFFER_RANGE=0x8000000`.

## 4. Formatos que Direct3D 12 no tiene

«Soportado» y «creable» son preguntas distintas, y Dozen contesta la primera.
`vkGetPhysicalDeviceFormatProperties` puede devolver un juego de capacidades utilizable para un
formato cuya imagen Direct3D 12 se niega después a reservar; la negativa llega como
`VkMemoryRequirements::size == UINT64_MAX`, o como `0`.

Así que el port lo comprueba **creando una imagen de prueba** y mirando el tamaño, y al arrancar
escribe la lista de formatos que este driver no tiene. En la consola esa lista es:

```
R8_SRGB, R4G4_UNORM_PACK8, R8G8_SRGB, B5G6R5_UNORM_PACK16
```

* **`R8_SRGB`, `R8G8_SRGB`**: no hay equivalente DXGI. Caen a UNORM: se pierde la curva de gamma,
  no la imagen.
* **`R4G4_UNORM_PACK8`**: dos canales de 4 bits en un byte. Pasa a `R8G8_UNORM`, desempaquetado
  al subir: cada nibble a su byte, ×17 para que `0xF` llegue a `0xFF`.
* **`B5G6R5_UNORM_PACK16`**: lo usa un render target de pantalla completa. Pasa a
  `R8G8B8A8_UNORM`, desempaquetado igual. Más precisión que la del invitado, no menos. Un target
  desempaquetado no se escribe de vuelta a la memoria del invitado, que es la regla que ya había
  para los formatos ensanchados.

## 5. Dentro del App Container

| Problema | Qué hace el parche |
|---|---|
| No hay línea de órdenes | Las carpetas del volcado salen de `LocalState\Smash4\rutas.txt`, un argumento por línea. `LocalState\Smash4\entorno.txt` fija variables de entorno igual |
| La carpeta de instalación es de **solo lectura** | Las partidas, la caché de shaders y el registro se fuerzan a `LocalState` con `_putenv_s` antes de que arranque el runtime. ⚠ `SDL_setenv_unsafe` no basta: escribe en la tabla de SDL y `std::getenv` no la ve |
| Un `freopen` que falla **cierra stderr** | y entonces el proceso muere sin rastro. `_dup`/`_dup2` guardan una copia de rescate |
| `GetClientRect` tiene que contestar | El WSI de Mesa mide la ventana con ella y da la superficie por perdida si falla. El sustituto se lo pregunta al ejecutable, que exporta `uwp_get_width` / `uwp_get_height` |
| La CoreWindow tiene afinidad de hilo | La superficie Vulkan se crea **en el propio hilo de la CoreWindow**, por una petición y una variable de condición |
| El Device Portal se rinde cerca de los 256 MB | `partir-volcado.ps1` parte los dos archivos grandes, y el VFS sirve `x.000` + `x.parteN` como un solo archivo |
| `/APPCONTAINER` | Sin ese bit el paquete no se instala. `empaquetar.ps1` comprueba la cabecera antes de montar nada |

## 6. Por qué esto se depura en el PC

Dozen sobre una GPU de escritorio es el mismo driver, y el runtime de Direct3D 12 que rechaza un
command list mal grabado es el mismo código. Una vuelta a la consola —empaquetar, instalar,
lanzar, bajar el registro— son ocho minutos; en el PC es uno.

Dos de los tres fallos de Mesa salieron así en minutos. El tercero solo ocurre en hardware de
AMD, así que el parche hace que el **InfoQueue** de D3D12 se vuelque a stderr cuando `Close()`
falla, y eso funciona también en la consola. Con `DZN_DEBUG=d3d12`, la consola imprimió en una
línea lo que nadie habría adivinado:

```
D3D12 #1095: ID3D12CommandList::SetViewInstanceMask: Device does not support view instancing.
Hardware tier is D3D12_VIEW_INSTANCING_TIER_NOT_SUPPORTED.
```
