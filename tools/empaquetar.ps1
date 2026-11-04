<#
.SYNOPSIS
  Arma y firma el .msix del port de Smash 4 para la Xbox Series X en modo desarrollador.

.DESCRIPTION
  Reune en una carpeta de montaje el ejecutable de UWP, las DLL que necesita, el manifiesto y
  los mosaicos; llama a makeappx y firma con el certificado CN=Decompilaciones del almacen
  personal, el mismo de los demas ports.

  ⚠ Lo que no puede faltar, y cada una costo un intento en otro port:
    - **DXIL.dll** junto a vulkan_dzn.dll: sin ella, en la consola `vkCreateInstance` devuelve
      VK_ERROR_INITIALIZATION_FAILED (visto en el port de Yakumo).
    - El ejecutable tiene que estar enlazado con /APPCONTAINER; se comprueba aqui antes de
      empaquetar, porque un .exe sin ese bit produce un paquete que no instala.
    - La version del manifiesto sube en cada entrega: Windows rechaza reinstalar la misma
      version con otro contenido, y el guion de despliegue no se entera.

.EXAMPLE
  pwsh -File empaquetar.ps1
  pwsh -File empaquetar.ps1 -Version 0.1.0.1
#>
[CmdletBinding()]
param(
    [string]$Version,
    [string]$Salida = $(if ($env:SMASH4_PKG) { $env:SMASH4_PKG } else { 'D:\smash4_pkg' }),
    # -Semilla arma el paquete con un ejecutable minimo en vez del juego: ver semilla.cpp. Hace
    # falta la PRIMERA vez que la familia entra en una consola, porque esa instalacion va a
    # D:\DevelopmentFiles (5 GB casi llenos) y falla con «There is not enough space on the disk»
    # aunque el espacio de desarrollo tenga sitio. El completo entra despues, como actualizacion.
    [switch]$Semilla
)
$upstream   = if ($env:SMASH4_UPSTREAM) { $env:SMASH4_UPSTREAM } else { 'D:\smash4\upstream' }
$uwpdepRaiz = if ($env:SMASH4_UWP_DEP)  { $env:SMASH4_UWP_DEP }  else { 'D:\uwp-dep\x64' }
$mesa       = if ($env:SMASH4_MESA)     { $env:SMASH4_MESA }     else { 'D:\mesa' }

$ErrorActionPreference = 'Stop'

$sub = Split-Path -Parent $PSScriptRoot
$paquete = Join-Path $PSScriptRoot 'package'
$exe = $(Join-Path $upstream 'build-uwp\smash.exe')
$depsUwp = $(Join-Path $upstream 'build-deps-uwp\prefix\bin')
$uwpdep = $(Join-Path $uwpdepRaiz 'bin')
$dozen = $(Join-Path $mesa 'build-uwp\src\microsoft\vulkan')

function Herramienta([string]$nombre) {
    $h = Get-ChildItem "C:\Program Files (x86)\Windows Kits\10\bin\*\x64\$nombre" -EA SilentlyContinue |
         Sort-Object FullName | Select-Object -Last 1
    if (-not $h) { throw "no encuentro $nombre en el Windows SDK" }
    return $h.FullName
}

# --- la semilla, si toca ------------------------------------------------------------------
if ($Semilla) {
    $vcvarsall = 'C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvarsall.bat'
    & cmd.exe /c "`"$vcvarsall`" x64 store >nul 2>&1 && set" | ForEach-Object {
        if ($_ -match '^([^=]+)=(.*)$') { Set-Item -Path "Env:$($Matches[1])" -Value $Matches[2] -EA SilentlyContinue }
    }
    $env:PATH = ($env:PATH -split ';' | Where-Object { $_ -and $_ -notmatch 'retcomm' }) -join ';'
    New-Item -ItemType Directory -Force $Salida | Out-Null
    $exe = Join-Path $Salida 'smash.exe'   # el mismo nombre que pide el manifiesto
    $obj = Join-Path $Salida 'semilla.obj'
    # Compilar y enlazar por separado, nombrando las bibliotecas de la Store: dejarselo a
    # clang-cl da «linker command failed» porque busca las del escritorio. Receta del port de Brawl.
    & clang-cl /c /O2 /MD /nologo /DWINAPI_FAMILY=WINAPI_FAMILY_APP "/Fo$obj" `
        (Join-Path $PSScriptRoot 'semilla.cpp')
    & lld-link /nologo /machine:x64 /subsystem:windows,10.0 /appcontainer /dynamicbase /nxcompat `
        "/out:$exe" $obj WindowsApp.lib msvcrt.lib vcruntime.lib ucrt.lib
    if (-not (Test-Path -LiteralPath $exe)) { throw 'no pude compilar la semilla' }
    Write-Host ("semilla: {0:N0} bytes" -f (Get-Item $exe).Length) -ForegroundColor Cyan
}

# --- comprobaciones antes de montar nada -------------------------------------------------
if (-not (Test-Path -LiteralPath $exe)) { throw "no esta el ejecutable: $exe  (xbox\compilar-uwp.ps1)" }

$dumpbin = Get-ChildItem 'C:\Program Files\Microsoft Visual Studio\2022\*\VC\Tools\MSVC\*\bin\Hostx64\x64\dumpbin.exe' -EA SilentlyContinue |
           Select-Object -First 1
if ($dumpbin) {
    $cabecera = & $dumpbin.FullName /HEADERS $exe
    if (-not ($cabecera | Select-String -Pattern 'App Container' -Quiet)) {
        throw 'el ejecutable no lleva el bit de AppContainer: falta /APPCONTAINER al enlazar'
    }
    Write-Host 'ejecutable: marcado como AppContainer' -ForegroundColor Green
}

$cert = Get-ChildItem Cert:\CurrentUser\My | Where-Object { $_.Subject -eq 'CN=Decompilaciones' -and $_.HasPrivateKey } |
        Select-Object -First 1
if (-not $cert) { throw 'no encuentro el certificado CN=Decompilaciones con clave privada' }
if ($cert.NotAfter -lt (Get-Date)) { throw "el certificado caduco el $($cert.NotAfter)" }

# --- la version --------------------------------------------------------------------------
[xml]$manifiesto = Get-Content -LiteralPath (Join-Path $paquete 'AppxManifest.xml')
if ($Version) { $manifiesto.Package.Identity.Version = $Version }
$Version = $manifiesto.Package.Identity.Version
Write-Host "version $Version" -ForegroundColor Cyan

# --- montaje ------------------------------------------------------------------------------
$montaje = Join-Path $Salida "stage-$Version"
if (Test-Path -LiteralPath $montaje) {
    Get-ChildItem -LiteralPath $montaje -Recurse -File | Remove-Item -Force -EA SilentlyContinue
} else {
    New-Item -ItemType Directory -Force $montaje | Out-Null
}
New-Item -ItemType Directory -Force (Join-Path $montaje 'Assets') | Out-Null

$manifiesto.Save((Join-Path $montaje 'AppxManifest.xml'))
Copy-Item (Join-Path $paquete 'Assets\*') (Join-Path $montaje 'Assets') -Force
Copy-Item $exe $montaje -Force

# Las DLL del paquete. Dozen y DXIL van juntas: ver el aviso de arriba.
$dlls = @(
    (Join-Path $uwpdep 'SDL3.dll'),
    (Join-Path $depsUwp 'shaderc_shared.dll'),
    (Join-Path $depsUwp 'SPIRV-Tools-shared.dll'),
    (Join-Path $dozen 'vulkan_dzn.dll'),
    # DXIL.dll no la construye Mesa: es la de Microsoft y vive tambien fuera del arbol de
    # compilacion, porque «meson setup --wipe» se lleva build-uwp con ella dentro.
    $(if (Test-Path -LiteralPath (Join-Path $dozen 'dxil.dll')) { Join-Path $dozen 'dxil.dll' }
      else { $(Join-Path $mesa 'uwp\dxil.dll') })
)
if ($Semilla) {
    # La semilla solo registra la familia: sin DLL pesa unos pocos KB y entra enseguida.
    Write-Host 'semilla: sin las DLL del juego'
} else {
    foreach ($dll in $dlls) {
        if (-not (Test-Path -LiteralPath $dll)) { throw "falta una DLL del paquete: $dll" }
        Copy-Item $dll $montaje -Force
    }
}

$total = (Get-ChildItem -LiteralPath $montaje -Recurse -File | Measure-Object Length -Sum).Sum
Write-Host ("montaje: {0} archivos, {1:N1} MB" -f
    (Get-ChildItem -LiteralPath $montaje -Recurse -File).Count, ($total / 1MB))

# --- empaquetar y firmar --------------------------------------------------------------------
$msix = Join-Path $Salida ("Smash4-Recomp-$Version" + $(if ($Semilla) { '-semilla' } else { '' }) + '.msix')
& (Herramienta 'makeappx.exe') pack /o /d $montaje /p $msix
if ($LASTEXITCODE) { throw 'makeappx fallo' }

& (Herramienta 'signtool.exe') sign /fd SHA256 /sha1 $cert.Thumbprint $msix
if ($LASTEXITCODE) { throw 'signtool fallo' }

Write-Host ("`nlisto: {0}  ({1:N1} MB)" -f $msix, ((Get-Item $msix).Length / 1MB)) -ForegroundColor Green
