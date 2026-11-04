# Configura y compila el juego para UWP (la Xbox), en upstream\build-uwp.
# Es la variante de tools\windows\build-smash.ps1, que lo hace para el escritorio con mingw.
#
#   build_uwp.ps1               configura y compila
#   build_uwp.ps1 -SoloNinja    solo compila
#   build_uwp.ps1 -SoloConfig   solo configura (para ver si CMake pasa)
param([switch]$SoloNinja, [switch]$SoloConfig, [string]$Objetivo = 'smash')
# Rutas: todas salen de variables de entorno, ninguna esta escrita aqui. Ver el README.
$upstream  = if ($env:SMASH4_UPSTREAM)  { $env:SMASH4_UPSTREAM }  else { 'D:\smash4\upstream' }
$toolchain = if ($env:SMASH4_TOOLCHAIN) { $env:SMASH4_TOOLCHAIN } else { 'D:\smash4\toolchain' }
$uwpdepRaiz = if ($env:SMASH4_UWP_DEP)  { $env:SMASH4_UWP_DEP }   else { 'D:\uwp-dep\x64' }

$ErrorActionPreference = 'Continue'

$sp = $PSScriptRoot
$dir = Join-Path $upstream 'build-uwp'
$uwpdep = $uwpdepRaiz

$vcvarsall = 'C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvarsall.bat'
& cmd.exe /c "`"$vcvarsall`" x64 store >nul 2>&1 && set" | ForEach-Object {
    if ($_ -match '^([^=]+)=(.*)$') { Set-Item -Path "Env:$($Matches[1])" -Value $Matches[2] -EA SilentlyContinue }
}
$limpio = ($env:PATH -split ';' | Where-Object { $_ -and $_ -notmatch 'retcomm' }) -join ';'
$env:PATH = "$toolchain\Ninja;$toolchain\CMake\bin;$limpio"

if (-not $SoloNinja) {
    $opciones = @(
        '-S', $upstream, '-B', $dir, '-G', 'Ninja',
        '-DCMAKE_SYSTEM_NAME=WindowsStore', '-DCMAKE_SYSTEM_VERSION=10.0',
        '-DCMAKE_BUILD_TYPE=Release',
        '-DCMAKE_C_COMPILER=clang-cl', '-DCMAKE_CXX_COMPILER=clang-cl',
        '-DCMAKE_POLICY_DEFAULT_CMP0091=NEW', '-DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreadedDLL',
        # NOMINMAX: sin el, las macros min/max de minwindef.h rompen cualquier std::min.
        # /EHsc: clang-cl trae las excepciones apagadas por defecto («cannot use 'throw' with
        # exceptions disabled»), al reves que el clang de mingw.
        # WINAPI_FAMILY_APP: CMAKE_SYSTEM_NAME=WindowsStore no lo define con clang-cl y Ninja, y
        # sin el las cabeceras dan por buenas las APIs de escritorio. El codigo se compilaba como
        # tal y el enlazado moria pidiendo MessageBoxA, que en el SDK de la Store no esta.
        '-DCMAKE_C_FLAGS=-DNOMINMAX -DWINAPI_FAMILY=WINAPI_FAMILY_APP',
        '-DCMAKE_CXX_FLAGS=-DNOMINMAX -DWINAPI_FAMILY=WINAPI_FAMILY_APP /EHsc',
        # /APPCONTAINER: pone en la cabecera el bit 0x1000 que marca el ejecutable como de
        # AppContainer. Sin el, el .exe parece de escritorio y el paquete no se instala.
        '-DCMAKE_EXE_LINKER_FLAGS=/APPCONTAINER',
        # Las dependencias hechas para UWP, y el SDL3 y libuwp del uwp-dep de Daniel Worley.
        "-DCAFE_DEPS_PREFIX=$upstream/build-deps-uwp/prefix",
        "-DCMAKE_PREFIX_PATH=$upstream/build-deps-uwp/prefix;$uwpdep",
        "-DCMAKE_INCLUDE_PATH=$uwpdep/include",
        "-DCMAKE_LIBRARY_PATH=$uwpdep/lib",
        # Al SDL3 de UWP por su ruta: sin esto find_package coge el de escritorio, que ademas
        # mete build-deps\prefix\include en el include path y con el un zconf.h con <unistd.h>.
        "-DSDL3_DIR=$uwpdep/lib/cmake/SDL3",
        # Vulkan: en UWP no hay loader. La implib del driver solo exporta el punto de entrada del
        # ICD, no la API, asi que se enlaza el vkshim: 770 saltos que reenvian a Dozen, cargado del
        # propio paquete con LoadPackagedLibrary.
        "-DVulkan_INCLUDE_DIR=$upstream/build-deps-uwp/prefix/include",
        "-DVulkan_LIBRARY=$(($env:SMASH4_VKSHIM ?? 'D:/smash4/vkshim') + '/vkshim.lib')",
        "-DSMASH_GENERATED_DIR=$($env:SMASH4_GENERATED ?? 'D:/smash4/generated/smash')",
        # Las herramientas del build no pueden ejecutarse aqui (un .exe de UWP corre en
        # AppContainer), asi que se toma la del build de escritorio.
        "-DSPIRV_EMBED_HOST=$upstream/build/runtime/spirv_embed.exe"
    )
    & cmake @opciones *>&1 | Out-File -FilePath "$sp\build_uwp_config.log" -Encoding utf8
    if ($LASTEXITCODE -ne 0) {
        Write-Output '=== configure FALLO ==='
        Get-Content -LiteralPath "$sp\build_uwp_config.log" -Tail 20
        exit 1
    }
    Write-Output 'configure OK'
    if ($SoloConfig) { exit 0 }
}

& ninja -C $dir $Objetivo *>&1 | Out-File -FilePath "$sp\build_uwp_build.log" -Encoding utf8
Write-Output "ninja exit=$LASTEXITCODE"
