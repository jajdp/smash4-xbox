# Arma el arbol que se subira a la Xbox: igual que el volcado pero con dt00 y dt01 en
# trozos de 150 MB, que es lo que el Device Portal admite (corta en ~256 MB). Sin movie ni
# sound. No toca el volcado original.
param(
  # Tu volcado, y donde dejar la copia partida. Ninguno de los dos esta en el repositorio.
  [Parameter(Mandatory = $true)][string]$Origen,
  [Parameter(Mandatory = $true)][string]$Destino,
  [int]$TrozoMB = 150,
  [string[]]$Fuera = @('movie', 'sound')
)
$ErrorActionPreference = 'Stop'
$trozo = $TrozoMB * 1MB

New-Item -ItemType Directory -Path $Destino -Force | Out-Null
foreach ($d in @('code', 'meta')) {
  $src = Join-Path $Origen $d
  $dst = Join-Path $Destino $d
  if ((Test-Path -LiteralPath $src) -and -not (Test-Path -LiteralPath $dst)) {
    Copy-Item -LiteralPath $src -Destination $dst -Recurse
    $m = Get-ChildItem -LiteralPath $dst -Recurse -File | Measure-Object Length -Sum
    "copiada  {0,-6} {1,7:N1} MB  {2} archivos" -f $d, ($m.Sum / 1MB), $m.Count
  } else { "ya estaba  $d" }
}

$contOrig = Join-Path $Origen 'content'
$contDest = Join-Path $Destino 'content'
New-Item -ItemType Directory -Path $contDest -Force | Out-Null

foreach ($it in (Get-ChildItem -LiteralPath $contOrig)) {
  if ($Fuera -contains $it.Name) { "fuera    $($it.Name)"; continue }
  if ($it.PSIsContainer) { "fuera    $($it.Name) (carpeta, no prevista)"; continue }
  if ($it.Length -le $trozo) {
    $dst = Join-Path $contDest $it.Name
    if (-not (Test-Path -LiteralPath $dst)) { Copy-Item -LiteralPath $it.FullName -Destination $dst }
    "entero   {0,-8} {1,7:N1} MB" -f $it.Name, ($it.Length / 1MB)
    continue
  }
  # a trozos: nombre.000, nombre.001, ...
  $ya = Get-ChildItem -LiteralPath $contDest -Filter "$($it.Name).*" -ErrorAction SilentlyContinue
  if ($ya) { "ya estaba {0} en {1} trozos" -f $it.Name, $ya.Count; continue }
  $t0 = Get-Date
  $entrada = [System.IO.File]::OpenRead($it.FullName)
  try {
    $buffer = New-Object byte[] (8MB)
    $indice = 0
    while ($entrada.Position -lt $entrada.Length) {
      $nombre = '{0}.{1:d3}' -f $it.Name, $indice
      $salida = [System.IO.File]::Create((Join-Path $contDest $nombre))
      try {
        $restan = $trozo
        while ($restan -gt 0) {
          $pedir = [Math]::Min($buffer.Length, $restan)
          $leido = $entrada.Read($buffer, 0, $pedir)
          if ($leido -le 0) { break }
          $salida.Write($buffer, 0, $leido)
          $restan -= $leido
        }
      } finally { $salida.Dispose() }
      $indice++
    }
    "partido  {0,-8} {1,7:N1} MB en {2} trozos ({3:N0} s)" -f $it.Name, ($it.Length / 1MB), $indice, ((Get-Date) - $t0).TotalSeconds
  } finally { $entrada.Dispose() }
}

''
# comprobacion: los trozos suman exactamente lo que medía el original
foreach ($it in (Get-ChildItem -LiteralPath $contOrig -File)) {
  if ($Fuera -contains $it.Name) { continue }
  $piezas = Get-ChildItem -LiteralPath $contDest -Filter "$($it.Name).[0-9][0-9][0-9]" -ErrorAction SilentlyContinue
  if (-not $piezas) { continue }
  $suma = ($piezas | Measure-Object Length -Sum).Sum
  "{0,-8} original {1,14:N0} B   trozos {2,14:N0} B   {3}" -f $it.Name, $it.Length, $suma,
    $(if ($suma -eq $it.Length) { 'CUADRA' } else { 'NO CUADRA' })
}
$m = Get-ChildItem -LiteralPath $Destino -Recurse -File | Measure-Object Length -Sum
"total a subir: {0:N2} GiB en {1} archivos  ->  {2}" -f ($m.Sum / 1GB), $m.Count, $Destino
