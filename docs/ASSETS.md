# The package tiles

*(Español: [ASSETS.es.md](ASSETS.es.md))*

`package/Assets/` is empty on purpose, and the build will stop until you fill it. A tile for
this would be the game's own artwork, which is Nintendo's; whoever packages it supplies their
own.

## What the manifest asks for

| File | Size | Where it shows |
|---|---|---|
| `Square44x44Logo.png` | 44×44 | The small icon |
| `Square44x44Logo.scale-200.png` | 88×88 | The same, on a 4K dashboard |
| `Square44x44Logo.targetsize-24_altform-unplated.png` | 24×24 | Lists, with no plate behind it |
| `Square150x150Logo.png` | 150×150 | The medium tile |
| `Square150x150Logo.scale-200.png` | 300×300 | The same, scaled |
| `Wide310x150Logo.png` | 310×150 | The wide tile — this is the one you see on the console |
| `SplashScreen.png` | 620×300 | While it loads |
| `SplashScreen.scale-200.png` | 1240×600 | The same, scaled |
| `StoreLogo.png` | 50×50 | Listings |
| `LockScreenLogo.png` | 24×24 | Monochrome, with transparency |

All PNG, 32-bit with an alpha channel. The manifest sets `BackgroundColor="transparent"`, so a
tile with a transparent background takes the dashboard's colour.

## Two things that will bite you

* **A tile over 200 KB makes MSBuild's resource step crawl**, and on a large set it can look
  like the build hung. Keep them small; they are icons.
* **Strip the metadata.** A PNG exported from an editor can carry `tEXt`, `iTXt` or `eXIf`
  chunks with your user name, your machine or the full path of the source file. They travel
  inside the package.

## If you just want something to build with

Any placeholder works — a flat colour with a letter on it is enough to get through packaging and
see the thing boot. Replace it before you show it to anyone.
