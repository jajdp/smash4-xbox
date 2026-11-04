# Aviso

*(English: [NOTICE.md](NOTICE.md))*

## Sin relación con nadie

Es un proyecto de aficionado, no comercial y no oficial. **No tiene relación con Nintendo ni con
Microsoft**, ni con los autores de Smash4PC, ni con el proyecto Mesa, ni cuenta con su respaldo.
*Super Smash Bros. for Wii U*, *Xbox* y los demás nombres y marcas son de sus dueños, y aquí se
nombran solo para decir con qué funciona esto.

No se vende nada ni se monetiza nada.

## Lo que este repositorio NO distribuye

Ni el juego, ni la actualización, ni el DLC, ni ningún volcado. Ningún dato del juego. Ni el C++
recompilado (Smash4PC convierte el código PowerPC del juego en archivos fuente: esos archivos
**son** el juego y no están aquí). Ni el ejecutable, ni el `.msix`, ni partidas guardadas.

Tampoco los mosaicos del paquete: `package/Assets/` está vacía a propósito y
[`docs/ASSETS.es.md`](docs/ASSETS.es.md) dice qué poner ahí.

**Ni ninguna biblioteca**: SDL3, shaderc, SPIRV-Tools, zlib, ZArchive, `dxil.dll`,
`vulkan_dzn.dll`. Unas son binarios de otros y las demás se construyen; la guía dice de dónde
sale cada una.

**No hay capturas del juego.** Una captura de esto funcionando sería, sobre todo, arte de
Nintendo.

## Lo que sí lleva de otros, y con qué permiso

Medido archivo por archivo antes de publicar.

| Árbol | Qué hay aquí | Su licencia | Por qué se puede |
|---|---|---|---|
| [Smash4PC](https://github.com/josiahg2502-glitch/Smash4PC) | `patches/smash4pc-xbox.patch` — **2.281 líneas añadidas en 35 archivos** | **MIT**, © 2026 Petexy / Linexy (su `LICENSE`) | La MIT permite versiones modificadas mientras su aviso viaje con ellas. El `LICENSE` de aquí lo lleva |
| [Mesa](https://gitlab.freedesktop.org/mesa/mesa) | `patches/mesa-dozen-xbox.patch` — **199 líneas añadidas en 7 archivos** | **MIT** en todos los archivos que toca: © Microsoft Corporation (`src/microsoft/vulkan/*`), © Intel Corporation (`src/vulkan/*`) | Lo mismo. Mesa es un conjunto de componentes con licencias distintas; estos son MIT |
| Este port | `tools/`, `src/`, `docs/`, `package/` | **MIT**, © 2026 jajdp | Obra nueva |

`src/mesa_sysstubs.c` y `src/mesa_uwp_compat.h` están escritos aquí, no copiados. La *idea* de
contestar con sustitutos a lo que Mesa importa del escritorio, para que `user32`, `gdi32` y
`shell32` no entren nunca en la tabla de importaciones, viene de
[`emelin2004/rpcs3-xbox`](https://github.com/emelin2004/rpcs3-xbox) (GPL-2.0), que lo hizo
primero para RPCS3 en Xbox. Aquí no se reproduce ni una línea de ese proyecto; lo que se reusa
es el planteamiento, y el mérito es suyo.

## Las piezas de terceros que tendrás que traer tú

| | De dónde | Licencia |
|---|---|---|
| **Smash4PC** | [`josiahg2502-glitch/Smash4PC`](https://github.com/josiahg2502-glitch/Smash4PC) | MIT |
| **Mesa** (el driver Dozen) | [mesa/mesa](https://gitlab.freedesktop.org/mesa/mesa), 26.2.x | MIT |
| **`DXIL.dll`** | La entrega del DirectX Shader Compiler de Microsoft | Términos de Microsoft |
| **SDL3 para UWP** | [`worleydl/uwp-dep`](https://github.com/worleydl/uwp-dep) | Ver ese repositorio |
| **`stb_image.h`, `stb_truetype.h`** | [`nothings/stb`](https://github.com/nothings/stb) | MIT / dominio público |

## Tu volcado es tuyo

Todo esto arranca de un volcado que haces **tú** de **tu** copia del juego. Nada de este
repositorio produce algo jugable sin él, y nada de aquí ayuda a conseguirlo.
