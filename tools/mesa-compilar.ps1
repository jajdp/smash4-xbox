# Compila el driver Dozen de Mesa (vulkan_dzn.dll) con la correccion de dzn_BindBufferMemory2.
#   mesa.ps1             configura y compila
#   mesa.ps1 -SoloNinja  solo compila
#
# Tres cosas que costaron y conviene no repetir:
#  1. El arbol va en $arbol, NO en el scratchpad: las rutas de alli pasan de 260 caracteres y
#     MSVC no puede crear los PDB («C1083: Cannot open compiler generated file: ''»).
#  2. Hay que sacar del PATH el toolchain de retcomm, porque meson usa el ccache que trae y ese
#     ccache rompe los PDB de MSVC con el mismo error.
#  3. Las herramientas de Python de Mesa necesitan packaging y mako: estan en venv-meson.
param([switch]$SoloNinja)
$arbol     = if ($env:SMASH4_MESA)      { $env:SMASH4_MESA }      else { 'D:\mesa' }
$toolchain = if ($env:SMASH4_TOOLCHAIN) { $env:SMASH4_TOOLCHAIN } else { 'D:\smash4\toolchain' }

$ErrorActionPreference = 'Continue'

$sp = $PSScriptRoot
$vcvars = 'C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat'
if (-not (Test-Path -LiteralPath $vcvars)) { Write-Output "no encuentro $vcvars"; exit 1 }

# El entorno que deja vcvars64, traido a esta sesion.
& cmd.exe /c "`"$vcvars`" >nul 2>&1 && set" | ForEach-Object {
    if ($_ -match '^([^=]+)=(.*)$') { Set-Item -Path "Env:$($Matches[1])" -Value $Matches[2] -EA SilentlyContinue }
}
$limpio = ($env:PATH -split ';' | Where-Object { $_ -and $_ -notmatch 'retcomm' }) -join ';'
$env:PATH = "$sp\venv-meson\Scripts;$(Join-Path $toolchain 'Ninja');$limpio"
$env:CC = 'cl'
$env:CXX = 'cl'

Write-Output ("cl -> " + ((Get-Command cl -EA SilentlyContinue).Source))
Push-Location $arbol
if (-not $SoloNinja) {
    $opciones = @(
        '--buildtype=release', '-Dvulkan-drivers=microsoft-experimental', '-Dgallium-drivers=',
        '-Dopengl=false', '-Dgles1=disabled', '-Dgles2=disabled', '-Degl=disabled', '-Dglx=disabled',
        '-Dplatforms=windows', '-Dllvm=disabled', '-Dzlib=disabled', '-Dzstd=disabled',
        '-Dexpat=disabled', '-Dbuild-tests=false', '-Dmicrosoft-clc=disabled',
        '-Dspirv-to-dxil=false', '-Dvideo-codecs='
    )
    if (Test-Path -LiteralPath "$arbol\build") { $opciones = @('--wipe') + $opciones }
    & meson setup build @opciones *>&1 | Out-File -FilePath "$sp\mesa_setup.log" -Encoding utf8
    if ($LASTEXITCODE -ne 0) {
        Write-Output '=== meson setup fallo ==='
        Get-Content -LiteralPath "$sp\mesa_setup.log" -Tail 12
        Pop-Location; exit 1
    }
    $usa = (Select-String -LiteralPath "$arbol\build\build.ninja" -Pattern 'ccache' -EA SilentlyContinue |
            Measure-Object).Count
    Write-Output "referencias a ccache en build.ninja: $usa  (deben ser 0)"
}
& ninja -C build *>&1 | Out-File -FilePath "$sp\mesa_build.log" -Encoding utf8
Write-Output "ninja exit=$LASTEXITCODE"
Pop-Location
