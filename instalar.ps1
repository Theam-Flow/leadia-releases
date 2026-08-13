# LeadIA — instalación de una línea en Windows.
#
#   irm https://raw.githubusercontent.com/Theam-Flow/leadia-releases/main/instalar.ps1 | iex
#
# QUÉ HACE Y QUÉ NO. Esto NO es el instalador: es el que va a buscar las piezas.
# Lee el manifiesto público (`latest.json`, el mismo que consulta la app para
# avisar de que hay versión nueva), se baja el .exe de esa versión y el juego de
# instaladores, COMPRUEBA LAS DOS HUELLAS SHA-256 y solo entonces le pasa el
# trabajo a `instalar-windows.ps1`, que es quien sabe cerrar la app y su daemon,
# ejecutar el NSIS y barrer las instalaciones de otros modos y nombres que NSIS
# no toca. Los datos del cliente (%APPDATA%) no se tocan jamás.
#
# POR QUÉ SE VERIFICA LA HUELLA Y NO SE CONFÍA EN HTTPS. HTTPS dice que viene de
# GitHub; la huella dice que es EXACTAMENTE el fichero que se publicó junto al
# manifiesto. Una descarga cortada también llega por HTTPS y un instalador a
# medias arranca lo justo para dejar el equipo peor que antes.
#
# Variables de entorno (pruebas / pinchar una versión):
#   LEADIA_MANIFIESTO       — URL o ruta del latest.json.
#   LEADIA_SOLO_DESCARGAR=1 — descarga y verifica, pero NO instala.

[CmdletBinding()]
param(
  [string] $Manifiesto = $(if ($env:LEADIA_MANIFIESTO) { $env:LEADIA_MANIFIESTO } else { 'https://raw.githubusercontent.com/Theam-Flow/leadia-releases/main/latest.json' })
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
# TLS 1.2 explícito: Windows Server y equipos sin actualizar negocian TLS 1.0
# por defecto y GitHub lo rechaza, con un error de red que no dice por qué.
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Escribir-Paso { param([string] $Texto) Write-Host "`n==> $Texto" }
function Morir { param([string] $Texto) Write-Error $Texto; exit 1 }

function Traer {
  param([string] $Url, [string] $Destino)
  if ($Url -like 'http://*') { Morir "la descarga va por http sin cifrar: $Url" }
  try {
    if ($Url -like 'file://*' -or (Test-Path -LiteralPath $Url -ErrorAction SilentlyContinue)) {
      Copy-Item -LiteralPath ($Url -replace '^file://', '') -Destination $Destino -Force
    } else {
      Invoke-WebRequest -Uri $Url -OutFile $Destino -UseBasicParsing
    }
  } catch {
    Morir "no se pudo descargar $Url — $($_.Exception.Message)"
  }
}

function Verificar {
  param([string] $Fichero, [string] $Esperado)
  if ([string]::IsNullOrWhiteSpace($Esperado)) {
    Morir "el manifiesto no trae huella para $(Split-Path $Fichero -Leaf); no se instala a ciegas"
  }
  $real = (Get-FileHash -LiteralPath $Fichero -Algorithm SHA256).Hash.ToLowerInvariant()
  if ($real -ne $Esperado.ToLowerInvariant()) {
    Morir "la huella de $(Split-Path $Fichero -Leaf) no cuadra`n  esperada: $Esperado`n  obtenida: $real`nNo se instala nada."
  }
  Write-Host "    huella verificada: $Esperado"
}

# Un campo que falta devuelve $null y quien llama decide si eso es fatal: nunca
# se sigue adelante con una URL a medio construir.
function Campo {
  param($Objeto, [string] $Ruta)
  foreach ($parte in $Ruta.Split('.')) {
    if ($null -eq $Objeto) { return $null }
    $prop = $Objeto.PSObject.Properties[$parte]
    if ($null -eq $prop) { return $null }
    $Objeto = $prop.Value
  }
  return $Objeto
}

$trabajo = Join-Path ([IO.Path]::GetTempPath()) ("leadia-instalar-" + [Guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $trabajo -Force | Out-Null
try {
  Escribir-Paso 'Buscando la última versión publicada'
  $rutaManifiesto = Join-Path $trabajo 'latest.json'
  Traer -Url $Manifiesto -Destino $rutaManifiesto
  $datos = Get-Content -LiteralPath $rutaManifiesto -Raw | ConvertFrom-Json

  $version = Campo $datos 'version'
  if (-not $version) { Morir 'el manifiesto no dice qué versión es' }
  $exeUrl = Campo $datos 'plataformas.windows.url'
  if (-not $exeUrl) { Morir 'esta versión no publicó instalador de Windows' }
  $exeSha = Campo $datos 'plataformas.windows.sha256'
  $exeNombre = Campo $datos 'plataformas.windows.nombre'
  if (-not $exeNombre) { $exeNombre = 'LeadIA-setup.exe' }
  $kitUrl = Campo $datos 'herramientas.instaladores.url'
  if (-not $kitUrl) { Morir 'esta versión no publicó el juego de instaladores' }
  $kitSha = Campo $datos 'herramientas.instaladores.sha256'
  Write-Host "    LeadIA $version"

  Escribir-Paso "Descargando LeadIA $version"
  $rutaExe = Join-Path $trabajo $exeNombre
  Traer -Url $exeUrl -Destino $rutaExe
  Verificar -Fichero $rutaExe -Esperado $exeSha

  Escribir-Paso 'Descargando los instaladores'
  $rutaKit = Join-Path $trabajo 'instaladores.zip'
  Traer -Url $kitUrl -Destino $rutaKit
  Verificar -Fichero $rutaKit -Esperado $kitSha
  Expand-Archive -LiteralPath $rutaKit -DestinationPath (Join-Path $trabajo 'kit') -Force
  $instalador = Join-Path $trabajo 'kit\installers\instalar-windows.ps1'
  if (-not (Test-Path -LiteralPath $instalador)) { Morir 'el juego descargado no trae instalar-windows.ps1' }

  if ($env:LEADIA_SOLO_DESCARGAR -eq '1') {
    Escribir-Paso 'Descargado y verificado; no se instala (LEADIA_SOLO_DESCARGAR=1)'
    Write-Output $rutaExe
    exit 0
  }

  Escribir-Paso 'Instalando (sustituye la versión anterior; tus datos no se tocan)'
  & $instalador -Instalador $rutaExe

  Escribir-Paso "Listo: LeadIA $version instalada"
} finally {
  # El .exe descargado vive dentro de la carpeta de trabajo: se borra DESPUÉS de
  # que el NSIS haya terminado, no antes.
  Remove-Item -LiteralPath $trabajo -Recurse -Force -ErrorAction SilentlyContinue
}
