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
# SOBRE LA PANTALLA. Es la primera impresión del producto, así que se cuida:
# los mismos azules del tema de la app, pasos numerados y una barra con el
# PORCENTAJE REAL de la descarga. Nunca un porcentaje inventado.
#
# COLOR EN LA CONSOLA DE VERDAD. PowerShell 5.1 sobre la consola clásica no
# entiende los colores de 24 bits, así que se detecta y se cae a los 16 colores
# de siempre. Un equipo recién instalado es justo el que tiene la consola vieja.
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
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }

# ── Paleta: los mismos azules del tema de la app (design/tokens.css) ──────────
$script:Ansi = ($PSVersionTable.PSVersion.Major -ge 7) -or [bool]$env:WT_SESSION
$script:Ancho = 68
$script:Paso = 0
$script:PasosTotal = 4

function Pintar {
  # $Truecolor: "r;g;b" para terminales modernos. $Basico: color de los 16 de
  # toda la vida, que es lo que hay en una consola de Windows sin estrenar.
  param([string] $Texto, [string] $Truecolor, [string] $Basico = 'Gray', [switch] $SinSalto)
  if ($script:Ansi) {
    $s = "$([char]27)[38;2;$Truecolor" + "m$Texto$([char]27)[0m"
    if ($SinSalto) { Write-Host $s -NoNewline } else { Write-Host $s }
  } else {
    if ($SinSalto) { Write-Host $Texto -ForegroundColor $Basico -NoNewline }
    else { Write-Host $Texto -ForegroundColor $Basico }
  }
}

$AZURE = '44;160;255'; $AZURE_SOFT = '79;176;255'; $AZURE_INK = '127;197;255'
$AZURE_PALE = '166;214;255'; $NAVY = '31;52;82'; $VERDE = '22;195;145'
$AMBAR = '224;102;46'; $GRIS = '159;176;196'; $GRIS_TENUE = '94;113;134'

function Morir {
  param([string] $Texto)
  Write-Host ''
  Pintar "  X  $Texto" $AMBAR 'Red'
  Write-Host ''
  exit 1
}

function Escribir-Paso {
  param([string] $Titulo)
  $script:Paso++
  $etiqueta = "[$script:Paso/$script:PasosTotal] $Titulo"
  $relleno = $script:Ancho - $etiqueta.Length - 4
  Write-Host ''
  Pintar "  $etiqueta " $AZURE 'Cyan' -SinSalto
  if ($relleno -gt 0) { Pintar ('─' * $relleno) $NAVY 'DarkGray' } else { Write-Host '' }
}

function Detalle { param([string] $T) Pintar "     $T" $GRIS_TENUE 'DarkGray' }
function Bien {
  param([string] $T)
  Pintar '     v ' $VERDE 'Green' -SinSalto
  Pintar $T $GRIS 'Gray'
}

# El logo, en degradado por columnas. Solo caracteres de bloque CP437, que se
# ven igual en la consola clásica y en Windows Terminal.
function Escribir-Portada {
  $lineas = @(
    '##      ######  #####  ####   ##  #####  ',
    '##      ##     ##   ## ##  ## ## ##   ## ',
    '##      #####  ####### ##  ## ## ####### ',
    '##      ##     ##   ## ##  ## ## ##   ## ',
    '####### ###### ##   ## #####  ## ##   ## '
  )
  $grad = @($NAVY, $AZURE, $AZURE_SOFT, $AZURE_INK, $AZURE_PALE)
  Write-Host ''
  for ($i = 0; $i -lt $lineas.Count; $i++) {
    Pintar ("  " + $lineas[$i]) $grad[$i % $grad.Count] 'Cyan'
  }
  Write-Host ''
  Pintar '  Su copiloto comercial' $AZURE_PALE 'Cyan' -SinSalto
  Pintar '  ·  instalación asistida' $GRIS 'Gray'
  Write-Host ''
}

function Tamano-Humano {
  param([long] $Bytes)
  if ($Bytes -ge 1048576) { return ('{0:N1} MB' -f ($Bytes / 1048576)) }
  return ('{0:N0} KB' -f [math]::Ceiling($Bytes / 1024))
}

# Descarga enseñando el porcentaje REAL: los bytes escritos contra el tamaño
# que anunció el servidor. Si el servidor no lo dice, no se dibuja barra —
# antes que un número inventado, ninguno.
function Traer {
  param([string] $Url, [string] $Destino, [string] $Etiqueta = '')
  if ($Url -like 'http://*') { Morir "la descarga va por http sin cifrar: $Url" }
  try {
    if ($Url -like 'file://*' -or (Test-Path -LiteralPath $Url -ErrorAction SilentlyContinue)) {
      Copy-Item -LiteralPath ($Url -replace '^file://', '') -Destination $Destino -Force
      return
    }
    $total = 0
    try {
      $cab = Invoke-WebRequest -Uri $Url -Method Head -UseBasicParsing
      $total = [long]($cab.Headers['Content-Length'] | Select-Object -First 1)
    } catch { $total = 0 }

    $tarea = Start-Job -ScriptBlock {
      param($u, $d)
      [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
      (New-Object Net.WebClient).DownloadFile($u, $d)
    } -ArgumentList $Url, $Destino

    $ancho = 32
    while ($tarea.State -eq 'Running') {
      if ($total -gt 0 -and $Etiqueta) {
        $hechos = 0
        if (Test-Path -LiteralPath $Destino) { $hechos = (Get-Item -LiteralPath $Destino).Length }
        $pct = [math]::Min(100, [int](100 * $hechos / $total))
        $llenos = [int]($pct * $ancho / 100)
        Write-Host "`r     " -NoNewline
        Pintar ('=' * $llenos) $AZURE 'Cyan' -SinSalto
        Pintar ('-' * ($ancho - $llenos)) $NAVY 'DarkGray' -SinSalto
        Pintar ("{0,4}%" -f $pct) $AZURE_INK 'White' -SinSalto
        Pintar ("  $(Tamano-Humano $hechos) de $(Tamano-Humano $total)   ") $GRIS_TENUE 'DarkGray' -SinSalto
      }
      Start-Sleep -Milliseconds 200
    }
    Write-Host ("`r" + (' ' * ($script:Ancho + 12)) + "`r") -NoNewline
    Receive-Job $tarea -ErrorAction Stop | Out-Null
    Remove-Job $tarea -Force
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
    Morir "la huella de $(Split-Path $Fichero -Leaf) no cuadra`n     esperada: $Esperado`n     obtenida: $real`n  No se instala nada."
  }
  Bien 'huella verificada'
  Detalle $Esperado
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
  Escribir-Portada

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
  Bien "LeadIA $version"
  Detalle $exeNombre

  Escribir-Paso "Descargando LeadIA $version"
  $rutaExe = Join-Path $trabajo $exeNombre
  Traer -Url $exeUrl -Destino $rutaExe -Etiqueta 'bajando la aplicación'
  Verificar -Fichero $rutaExe -Esperado $exeSha

  Escribir-Paso 'Descargando los instaladores'
  $rutaKit = Join-Path $trabajo 'instaladores.zip'
  Traer -Url $kitUrl -Destino $rutaKit -Etiqueta 'bajando el instalador'
  Verificar -Fichero $rutaKit -Esperado $kitSha
  Expand-Archive -LiteralPath $rutaKit -DestinationPath (Join-Path $trabajo 'kit') -Force
  $instalador = Join-Path $trabajo 'kit\installers\instalar-windows.ps1'
  if (-not (Test-Path -LiteralPath $instalador)) { Morir 'el juego descargado no trae instalar-windows.ps1' }

  if ($env:LEADIA_SOLO_DESCARGAR -eq '1') {
    Escribir-Paso 'Descargado y verificado; no se instala (LEADIA_SOLO_DESCARGAR=1)'
    Write-Output $rutaExe
    exit 0
  }

  Escribir-Paso 'Instalando'
  Detalle 'sustituye la versión anterior · sus datos no se tocan'
  Write-Host ''
  # La salida del instalador se enseña ENTERA: el cliente ve cerrar la app,
  # ejecutar el instalador y barrer lo viejo. Es lo que convierte «se quedó
  # pensando dos minutos» en «está haciendo estas cosas».
  try {
    & $instalador -Instalador $rutaExe
  } catch {
    Morir "la instalación no se completó — $($_.Exception.Message). No se ha tocado la versión anterior."
  }
  # `$LASTEXITCODE` solo existe si algo NATIVO llegó a ejecutarse. Bajo
  # `Set-StrictMode`, leerlo sin más aborta el guion en el último paso, con la
  # app ya instalada y un mensaje que no habla de instalar nada.
  $codigo = if (Test-Path variable:LASTEXITCODE) { $LASTEXITCODE } else { 0 }
  if ($codigo -ne 0) {
    Morir "la instalación no se completó (código $codigo). No se ha tocado la versión anterior."
  }

  # ── Tarjeta final ──────────────────────────────────────────────────────────
  Write-Host ''
  Pintar ("  " + ('─' * $script:Ancho)) $NAVY 'DarkGray'
  Pintar "  v  LeadIA $version instalada" $VERDE 'Green'
  Pintar ("  " + ('─' * $script:Ancho)) $NAVY 'DarkGray'
  Write-Host ''
  Pintar '     Sus datos:    ' $GRIS_TENUE 'DarkGray' -SinSalto
  Pintar "$env:APPDATA\tech.leadia.desktop" $GRIS 'Gray'
  Pintar '     Actualiza:    ' $GRIS_TENUE 'DarkGray' -SinSalto
  Pintar 'sola — la app le avisa cuando haya versión nueva' $GRIS 'Gray'
  Write-Host ''
  Pintar '  Ábrala desde el menú de inicio o desde el acceso del Escritorio.' $AZURE_PALE 'Cyan'
  Write-Host ''
} finally {
  # El .exe descargado vive dentro de la carpeta de trabajo: se borra DESPUÉS de
  # que el NSIS haya terminado, no antes.
  Remove-Item -LiteralPath $trabajo -Recurse -Force -ErrorAction SilentlyContinue
}
