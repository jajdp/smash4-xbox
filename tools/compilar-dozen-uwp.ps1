# Compila el driver Dozen de Mesa para UWP (el de la Xbox), con la correccion de
# dzn_BindBufferMemory2 que ya lleva $arbol.
#
# rpcs3-xbox lo hace desde Linux con Zig como compilador cruzado; aqui se hace en Windows con
# clang-cl dentro del entorno «store» de Visual Studio, que es el que pone en LIB las bibliotecas
# de la familia APP. Lo que se toma de su receta:
#   - mesa_sysstubs.c, que define los `__imp_` de las funciones de GDI, shell y version que Dozen
#     importa y no usa, para que esas DLL no entren en la tabla de importaciones del paquete.
#   - El enfoque: NO marcar el codigo como familia APP, sino dejar que los stubs quiten las
#     importaciones que no se pueden llevar al paquete. Lo que vale es la tabla final.
param([switch]$SoloNinja)
$arbol     = if ($env:SMASH4_MESA)      { $env:SMASH4_MESA }      else { 'D:\mesa' }
$toolchain = if ($env:SMASH4_TOOLCHAIN) { $env:SMASH4_TOOLCHAIN } else { 'D:\smash4\toolchain' }

$ErrorActionPreference = 'Continue'

$sp = $PSScriptRoot
$vcvarsall = 'C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvarsall.bat'

# «x64 store», no «x64»: es lo que hace que /MD enlace el CRT del contenedor
# (VCRUNTIME140_APP.dll). Con el de escritorio el DLL se construye igual pero en la consola no
# carga: LoadPackagedLibrary devuelve el error 126, que dice «no se encuentra el modulo»
# refiriendose a la dependencia, no al archivo.
& cmd.exe /c "`"$vcvarsall`" x64 store >nul 2>&1 && set" | ForEach-Object {
    if ($_ -match '^([^=]+)=(.*)$') { Set-Item -Path "Env:$($Matches[1])" -Value $Matches[2] -EA SilentlyContinue }
}
# ⚠ El entorno «store» deja fuera de LIB el um\x64 del SDK, y ahi vive d3d12.lib: sin esto,
# meson se planta en find_library('d3d12'). Es la razon por la que antes se usaba el entorno
# de escritorio, y el motivo de que el CRT saliera mal.
$umx64 = Get-ChildItem 'C:\Program Files (x86)\Windows Kits\10\Lib\*\um\x64\d3d12.lib' -EA SilentlyContinue |
         Sort-Object FullName | Select-Object -Last 1
if ($umx64) {
    $env:LIB = "$($umx64.Directory.FullName);$env:LIB"
    Write-Output "d3d12.lib: $($umx64.FullName)"
} else {
    Write-Output 'OJO: no encuentro d3d12.lib en el SDK'
}
$limpio = ($env:PATH -split ';' | Where-Object { $_ -and $_ -notmatch 'retcomm' }) -join ';'
# ⚠ El venv de meson vive con el ARBOL de Mesa, no junto a este guion: si no, basta con
# copiar el guion a otro sitio para que «meson» deje de existir.
$env:PATH = "$(Join-Path $arbol 'uwp\venv-meson\Scripts');$(Join-Path $toolchain 'Ninja');$limpio"
$env:CC = 'clang-cl'
$env:CXX = 'clang-cl'

# Los stubs, a objeto, para enlazarlos en el driver.
$stubs = "$arbol\uwp\mesa_sysstubs.obj"
if (-not $SoloNinja) {
    # /MD obligatorio: sin el, el objeto lleva dentro la directiva /DEFAULTLIB:libcmt.lib y
    # arrastra al enlazado el CRT estatico, que en UWP no existe («LNK1104: libcmt.lib»).
    & clang-cl /c /O2 /MD /nologo "/Fo$stubs" "$arbol\uwp\mesa_sysstubs.c" 2>&1 |
        Select-Object -First 5
    if (-not (Test-Path -LiteralPath $stubs)) { Write-Output 'no pude compilar mesa_sysstubs.c'; exit 1 }
    Write-Output "stubs: $stubs"

    # Tiene que ser un CROSS file, no un native file: un ejecutable de UWP corre en AppContainer y
    # no se puede lanzar desde el escritorio, asi que con --native-file meson falla al probarlo
    # («Executables created by c compiler clang-cl are not runnable»). Declarado como cruzado, no
    # intenta ejecutar nada. Es la misma razon por la que rpcs3-xbox usa un cross file.
    $cross = "$arbol\uwp\cross-uwp.ini"
    # Meson lee el .ini como texto: la ruta de la cabecera forzada va con barras normales.
    $compat = ($arbol -replace '\\', '/') + '/uwp/mesa_uwp_compat.h'
    @"
# Generado por mesa_uwp.ps1. Compila Dozen con el ABI de MSVC y la familia APP.
[binaries]
c = 'clang-cl'
cpp = 'clang-cl'
ar = 'llvm-lib'
windres = 'rc'
pkg-config = 'false'

[built-in options]
# NO se define WINAPI_FAMILY_APP, igual que en el cross file de rpcs3-xbox: Mesa se compila
# como codigo normal de Windows y lo que mantiene fuera del paquete las APIs prohibidas son
# los sysstubs, que es justo para lo que existen. Definirlo hacia fallar disk_cache_os.c
# (CreateFileW no esta en la familia APP) sin ganar nada.
# mesa_uwp_compat.h, incluida a la fuerza con /FI: Mesa usa los intrinsecos _Interlocked* en
# minuscula (que MSVC declara y clang-cl no) y _InterlockedAdd/_InterlockedAdd64, que en x64
# no existen en ninguno de los dos porque son de ARM. («call to undeclared function '_interlockedexchange64'»).
c_args = ['-DNOMINMAX', '-Wno-error', '/FI$compat']
cpp_args = ['-DNOMINMAX', '-Wno-error', '/FI$compat']
# WindowsApp.lib: en UWP es la que trae las APIs del sistema. Sin ella no se resuelve ni
# GetProcAddress ni lo que el propio CRT necesita (QueryPerformanceCounter, RoInitialize...),
# y meson lo cuenta como «no encuentro d3d12», que es lo ultimo que intentaba enlazar.
c_link_args = [$($stubs -replace '\\', '/'), 'WindowsApp.lib']
cpp_link_args = [$($stubs -replace '\\', '/'), 'WindowsApp.lib']
b_vscrt = 'md'

[host_machine]
system = 'windows'
cpu_family = 'x86_64'
cpu = 'x86_64'
endian = 'little'
"@ | Set-Content -LiteralPath $cross -Encoding ascii

    Push-Location $arbol
    $opciones = @(
        '--buildtype=release', "--cross-file=$cross",
        '-Dvulkan-drivers=microsoft-experimental', '-Dgallium-drivers=', '-Dopengl=false',
        '-Dgles1=disabled', '-Dgles2=disabled', '-Degl=disabled', '-Dglx=disabled',
        '-Dplatforms=windows', '-Dllvm=disabled', '-Dzlib=disabled', '-Dzstd=disabled',
        '-Dexpat=disabled', '-Dbuild-tests=false', '-Dmicrosoft-clc=disabled',
        '-Dspirv-to-dxil=false', '-Dvideo-codecs=',
        # La cache de shaders en disco usa CreateFileW, que no esta en la familia APP, y arrastra
        # blake3 con un ensamblador del ABI de GNU. RPCS3 la neutraliza con un stub que devuelve
        # «sin directorio de cache»; aqui se quita de raiz. Dozen guarda sus PSO por otra via.
        '-Dshader-cache=disabled'
    )
    if (Test-Path -LiteralPath "$arbol\build-uwp") { $opciones = @('--wipe') + $opciones }
    & meson setup build-uwp @opciones *>&1 | Out-File -FilePath "$sp\mesa_uwp_setup.log" -Encoding utf8
    if ($LASTEXITCODE -ne 0) {
        Write-Output '=== meson setup fallo ==='
        Get-Content -LiteralPath "$sp\mesa_uwp_setup.log" -Tail 15
        Pop-Location; exit 1
    }
    Write-Output 'setup OK'
    Pop-Location
}

Push-Location $arbol
& ninja -C build-uwp *>&1 | Out-File -FilePath "$sp\mesa_uwp_build.log" -Encoding utf8
Write-Output "ninja exit=$LASTEXITCODE"
Pop-Location
$dll = "$arbol\build-uwp\src\microsoft\vulkan\vulkan_dzn.dll"
if (Test-Path -LiteralPath $dll) {
    Write-Output ("DLL: $dll  {0} MB" -f [math]::Round((Get-Item $dll).Length / 1MB, 1))
}
