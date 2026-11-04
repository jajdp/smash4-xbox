# Los mosaicos del paquete

*(English: [ASSETS.md](ASSETS.md))*

`package/Assets/` está vacía a propósito, y el empaquetado se para hasta que la llenes. Un
mosaico de esto sería arte del propio juego, que es de Nintendo; quien empaqueta pone el suyo.

## Lo que pide el manifiesto

| Archivo | Tamaño | Dónde sale |
|---|---|---|
| `Square44x44Logo.png` | 44×44 | El icono pequeño |
| `Square44x44Logo.scale-200.png` | 88×88 | El mismo, en un panel 4K |
| `Square44x44Logo.targetsize-24_altform-unplated.png` | 24×24 | En listas, sin placa detrás |
| `Square150x150Logo.png` | 150×150 | El mosaico mediano |
| `Square150x150Logo.scale-200.png` | 300×300 | El mismo, escalado |
| `Wide310x150Logo.png` | 310×150 | El mosaico ancho: este es el que se ve en la consola |
| `SplashScreen.png` | 620×300 | Mientras carga |
| `SplashScreen.scale-200.png` | 1240×600 | El mismo, escalado |
| `StoreLogo.png` | 50×50 | En listados |
| `LockScreenLogo.png` | 24×24 | Monocromo, con transparencia |

Todos PNG de 32 bits con canal alfa. El manifiesto pone `BackgroundColor="transparent"`, así que
un mosaico con fondo transparente toma el color del panel.

## Dos cosas que muerden

* **Un mosaico de más de 200 KB hace que el paso de recursos de MSBuild se arrastre**, y con un
  juego grande parece que la compilación se colgó. Mantenlos pequeños: son iconos.
* **Quítales los metadatos.** Un PNG exportado de un editor puede llevar trozos `tEXt`, `iTXt` o
  `eXIf` con tu nombre de usuario, tu máquina o la ruta completa del original. Viajan dentro del
  paquete.

## Si solo quieres algo con lo que compilar

Cualquier provisional vale: un color plano con una letra basta para pasar el empaquetado y ver
que la cosa arranca. Cámbialo antes de enseñárselo a nadie.
