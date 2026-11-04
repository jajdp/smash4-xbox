# Una tanda en el PC, de principio a fin y sin dejar nada vivo: lanza el juego con las variables
# que se le digan, deja que llegue donde tenga que llegar, guarda unas cuantas imagenes del
# render (no de la ventana: estas salen iguales se mire o no la pantalla) y mata el proceso.
#
# Es la herramienta para perseguir en el PC lo que pasa en la consola, con TTT2_NO_D16=1 y
# compania: el ciclo baja de diez minutos a uno.
#
#   .\probar-en-el-pc.ps1 -Nombre con-d16
#   .\probar-en-el-pc.ps1 -Nombre sin-d16 -Variables @{ TTT2_NO_D16 = '1' }
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Nombre,
    # Variables de entorno extra para la tanda: CLAVE=valor separadas por punto y coma, como
    # 'TTT2_NO_D16=1;TTT2_SUBMIT_EVERY=1'. Una cadena y no una tabla porque asi se puede llamar
    # igual desde PowerShell que desde un shell de Unix, donde una tabla llega hecha pedazos.
    [string]$Variables = '',
    # Botones, en segundos desde el arranque. Dos pulsaciones bastan para llegar al menu: una
    # pasa el dialogo del album y otra la pantalla de titulo. Mas de eso se mete en modos.
    [string]$Botones = '12:a,30:a',
    [int]$Segundos = 55,
    [double]$Escala = 1,
    [string]$Salida = $(if ($env:SMASH4_MEDICIONES) { $env:SMASH4_MEDICIONES }
                       else { 'D:\smash4\mediciones\comparar' })
)
$ErrorActionPreference = 'Continue'

$play = if ($env:SMASH4_PLAY) { $env:SMASH4_PLAY } else { 'D:\smash4\Play' }
$exe = Join-Path $play 'smash.exe'
$nuevo = Join-Path $(if ($env:SMASH4_UPSTREAM) { $env:SMASH4_UPSTREAM }
                     else { 'D:\smash4\upstream' }) 'build\smash.exe'

# El ejecutable recien compilado, si no esta en uso (si lo esta, es que quedo una tanda viva).
Get-Process smash -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 1
if (Test-Path -LiteralPath $nuevo) {
    try { Copy-Item -LiteralPath $nuevo -Destination $exe -Force } catch {
        Write-Output "no pude copiar el ejecutable nuevo: $($_.Exception.Message)"
    }
}

$carpeta = Join-Path $Salida $Nombre
if (Test-Path -LiteralPath $carpeta) {
    Get-ChildItem -LiteralPath $carpeta -File | ForEach-Object { $_.Delete() }
} else {
    New-Item -ItemType Directory -Force -Path $carpeta | Out-Null
}

# La carpeta que contiene las tres del volcado, como en rutas.txt.
$wiiu = if ($env:SMASH4_WIIU) { $env:SMASH4_WIIU } else { 'D:\WiiU' }
$env:SMASH_SAVE_DIR = Join-Path $play 'save'
$env:SMASH_LOG = Join-Path $carpeta 'smash.log'
$env:TTT2_SCALE = "$Escala"
$env:TTT2_INPUT_SCRIPT = $Botones
$env:TTT2_CAPTURE = $carpeta
$env:TTT2_CAPTURE_INTERVAL = '2'
$env:TTT2_CAPTURE_START = "$([math]::Max(1, $Segundos - 20))"
$env:TTT2_CAPTURE_TV_ONLY = '1'
$puestas = @()
foreach ($par in ($Variables -split ';')) {
    if ($par -notmatch '=') { continue }
    $clave, $valor = $par -split '=', 2
    Set-Item -Path "env:$($clave.Trim())" -Value $valor
    $puestas += $clave.Trim()
}

# Un .cmd escrito al vuelo: las rutas del volcado llevan parentesis y puntos, y cualquier otra
# forma de pasarlas (Start-Process con -ArgumentList, el operador de llamada) las parte por el
# camino. Un archivo de ordenes las entrega enteras.
$guion = Join-Path $carpeta 'lanzar.cmd'
$lineas = @('@echo off')
$lineas += '"{0}" --dlc "{1}" "{2}" "{3}"' -f $exe,
    "$wiiu\Super Smash Bros. for Wii U (DLC) (9.273 MB) (USA) (unpacked)",
    "$wiiu\Super Smash Bros. for Wii U (UPDATE DATA) (v304) (2.449 GB) (USA) (unpacked)",
    "$wiiu\Super Smash Bros. for Wii U [AXFE01]"
Set-Content -LiteralPath $guion -Value $lineas -Encoding ascii
$p = Start-Process -FilePath $guion -PassThru -WindowStyle Minimized

$fin = (Get-Date).AddSeconds($Segundos)
while ((Get-Date) -lt $fin -and -not $p.HasExited) { Start-Sleep -Milliseconds 500 }
Get-Process smash -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 1
foreach ($k in $puestas) { Set-Item -Path "env:$k" -Value $null }

$imagenes = @(Get-ChildItem -LiteralPath $carpeta -Filter '*.png' -ErrorAction SilentlyContinue)
$fps = (Get-Content -LiteralPath $env:SMASH_LOG -ErrorAction SilentlyContinue |
        Select-String -Pattern 'frames/s,' | Select-Object -Last 1)
Write-Output ("{0}: {1} imagenes en {2}" -f $Nombre, $imagenes.Count, $carpeta)
if ($fps) { Write-Output ('   ' + $fps.Line.Trim()) }
if ((Get-Process smash -ErrorAction SilentlyContinue | Measure-Object).Count -ne 0) {
    Write-Output '   ⚠ quedo un smash.exe vivo'
}
