#!/usr/bin/env bash
# LeadIA — instalación de una línea en macOS.
#
#   curl -fsSL https://raw.githubusercontent.com/Theam-Flow/leadia-releases/main/instalar.sh | bash
#
# QUÉ HACE Y QUÉ NO. Esto NO es un instalador: es el que va a buscar las piezas.
# Lee el manifiesto público (`latest.json`, el mismo que consulta la app para
# avisar de que hay versión nueva), se baja el .dmg de esa versión y el juego de
# instaladores, COMPRUEBA LAS DOS HUELLAS SHA-256 y solo entonces le pasa el
# trabajo a `instalar-mac.sh`, que es quien de verdad sabe sustituir una
# instalación sin dejar copias sueltas y sin tocar los datos del cliente.
#
# POR QUÉ SE VERIFICA LA HUELLA Y NO SE CONFÍA EN HTTPS. HTTPS dice que el
# fichero viene de GitHub; la huella dice que es EXACTAMENTE el que se publicó
# junto al manifiesto. Un instalador a medio descargar también llega por HTTPS y
# arranca lo justo para dejar el equipo peor que antes. Si la huella no cuadra,
# aquí se para: no se ejecuta nada.
#
# POR QUÉ SE BAJA UN ZIP DE INSTALADORES EN LUGAR DE LLEVAR LA LÓGICA DENTRO.
# `instalar-mac.sh` y sus reglas de limpieza tienen pruebas y una historia de
# cicatrices detrás (un cliente acabó con dos apps distintas conviviendo). Si
# este guion las reimplementara, habría dos verdades y la de aquí sería la que
# nadie prueba. Se baja el juego que se publicó CON esa versión y se le llama.
#
# SOBRE LA PANTALLA. Lo que ve el cliente es la primera impresión del producto,
# así que se cuida: paleta azure de la app, pasos numerados y una barra de
# descarga con el PORCENTAJE REAL (bytes en disco contra el tamaño anunciado).
# Nunca un porcentaje inventado: para lo que no se puede medir hay un girador,
# que dice «esto sigue vivo» sin prometer cuánto falta.
#
# Variables (para pruebas y para pinchar una versión concreta):
#   LEADIA_MANIFIESTO  — URL o ruta del latest.json (por defecto, el público).
#   LEADIA_SOLO_DESCARGAR=1 — descarga y verifica, pero NO instala.
#   LEADIA_DESTINO     — carpeta destino (por defecto /Applications).
#   NO_COLOR=1         — sin color (también se apaga solo si la salida no es una terminal).
set -euo pipefail

MANIFIESTO="${LEADIA_MANIFIESTO:-https://raw.githubusercontent.com/Theam-Flow/leadia-releases/main/latest.json}"
DESTINO="${LEADIA_DESTINO:-/Applications}"

# ── Paleta: los mismos azules del tema de la app (design/tokens.css) ──────────
ESC=$'\033'
RESET="${ESC}[0m"; BOLD="${ESC}[1m"
AZURE="${ESC}[38;2;44;160;255m"        # --brand
AZURE_SOFT="${ESC}[38;2;79;176;255m"   # --brand-soft
AZURE_INK="${ESC}[38;2;127;197;255m"   # --brand-ink
AZURE_PALE="${ESC}[38;2;166;214;255m"  # --brand-2
NAVY="${ESC}[38;2;31;52;82m"           # --ink-600, para las líneas
VERDE="${ESC}[38;2;22;195;145m"        # --esmeralda
AMBAR="${ESC}[38;2;224;102;46m"        # --ember
GRIS="${ESC}[38;2;159;176;196m"        # --ink-2
GRIS_TENUE="${ESC}[38;2;94;113;134m"   # --ink-3
BLANCO="${ESC}[38;2;234;242;251m"      # --ink-1
GRAD=(
  "${ESC}[38;2;31;52;82m" "${ESC}[38;2;44;160;255m" "${ESC}[38;2;79;176;255m"
  "${ESC}[38;2;127;197;255m" "${ESC}[38;2;166;214;255m"
)
if [ ! -t 1 ] || [ -n "${NO_COLOR:-}" ]; then
  RESET=""; BOLD=""; AZURE=""; AZURE_SOFT=""; AZURE_INK=""; AZURE_PALE=""
  NAVY=""; VERDE=""; AMBAR=""; GRIS=""; GRIS_TENUE=""; BLANCO=""
  GRAD=("" "" "" "" "")
fi

ANCHO=68
PASO_ACTUAL=0
PASOS_TOTAL=4

repetir() { [ "$2" -gt 0 ] && printf "$1%.0s" $(seq 1 "$2") || true; }

morir() {
  printf "\n  %s✗  %s%s\n\n" "$AMBAR" "$1" "$RESET" >&2
  exit 1
}

paso() {
  PASO_ACTUAL=$((PASO_ACTUAL + 1))
  local titulo="[$PASO_ACTUAL/$PASOS_TOTAL] $1"
  local relleno=$((ANCHO - ${#titulo} - 4))
  printf "\n  %s%s%s %s%s\n" "$AZURE" "$titulo" "$RESET" "$NAVY" "$(repetir '─' "$relleno")$RESET"
}

detalle() { printf "     %s%s%s\n" "$GRIS_TENUE" "$1" "$RESET"; }
bien()    { printf "     %s✓%s %s%s%s\n" "$VERDE" "$RESET" "$GRIS" "$1" "$RESET"; }

# El logo, en degradado por columnas. Solo caracteres de bloque, que se ven
# igual en Terminal, iTerm y en una sesión por SSH.
portada() {
  local L1='██╗     ███████╗ █████╗ ██████╗ ██╗ █████╗ '
  local L2='██║     ██╔════╝██╔══██╗██╔══██╗██║██╔══██╗'
  local L3='██║     █████╗  ███████║██║  ██║██║███████║'
  local L4='██║     ██╔══╝  ██╔══██║██║  ██║██║██╔══██║'
  local L5='███████╗███████╗██║  ██║██████╔╝██║██║  ██║'
  local L6='╚══════╝╚══════╝╚═╝  ╚═╝╚═════╝ ╚═╝╚═╝  ╚═╝'
  printf "\n"
  local i=0
  for linea in "$L1" "$L2" "$L3" "$L4" "$L5" "$L6"; do
    printf "  %s%s%s\n" "${GRAD[$((i % 5))]}" "$linea" "$RESET"
    i=$((i + 1))
  done
  printf "\n  %s%sSu copiloto comercial%s  %s·%s  %sinstalación asistida%s\n\n" \
    "$BOLD" "$AZURE_PALE" "$RESET" "$NAVY" "$RESET" "$GRIS" "$RESET"
}

# Un instalador de 129 MB y un juego de instaladores de 60 KB se miden con la
# misma barra: en megas enteros, el segundo decía «0 de 0 MB» y parecía roto.
tamano_humano() {
  local bytes="${1:-0}"
  if [ "$bytes" -ge 1048576 ] 2>/dev/null; then
    awk -v b="$bytes" 'BEGIN { printf "%.1f MB", b / 1048576 }'
  else
    awk -v b="$bytes" 'BEGIN { printf "%d KB", (b + 1023) / 1024 }'
  fi
}

# Girador para lo que no se puede medir. Se dibuja solo si hay terminal.
girar_hasta() {
  local pid="$1" etiqueta="$2"
  if [ ! -t 1 ]; then return 0; fi
  local marcos=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
  local i=0
  while kill -0 "$pid" 2>/dev/null; do
    printf "\r     %s%s%s %s%s%s   " "$AZURE_SOFT" "${marcos[$((i % 10))]}" "$RESET" "$GRIS" "$etiqueta" "$RESET"
    sleep 0.1
    i=$((i + 1))
  done
  printf "\r%-${ANCHO}s\r" ""
}

# Barra con el porcentaje REAL: los bytes que hay en disco contra el tamaño que
# anunció el servidor. Si el servidor no dice el tamaño, se cae al girador en
# vez de inventarse un número — una barra que miente es peor que no tenerla.
barra_descarga() {
  local pid="$1" destino="$2" total="$3" etiqueta="$4"
  if [ ! -t 1 ] || [ -z "$total" ] || [ "$total" -le 0 ] 2>/dev/null; then
    girar_hasta "$pid" "$etiqueta"
    return 0
  fi
  local ancho=32
  while kill -0 "$pid" 2>/dev/null; do
    local hechos=0
    [ -f "$destino" ] && hechos=$(stat -f%z "$destino" 2>/dev/null || echo 0)
    local pct=$((hechos * 100 / total))
    [ "$pct" -gt 100 ] && pct=100
    local llenos=$((pct * ancho / 100))
    printf "\r     %s%s%s%s%s %s%3d%%%s  %s%s de %s%s   " \
      "$AZURE" "$(repetir '━' "$llenos")" "$RESET" \
      "$NAVY" "$(repetir '━' $((ancho - llenos)))$RESET" \
      "$AZURE_INK" "$pct" "$RESET" \
      "$GRIS_TENUE" "$(tamano_humano "$hechos")" "$(tamano_humano "$total")" "$RESET"
    sleep 0.2
  done
  printf "\r%-${ANCHO}s\r" ""
}

[ "$(uname -s)" = "Darwin" ] || morir "este arranque es para macOS; en Windows se usa instalar.ps1"

for req in curl shasum unzip; do
  command -v "$req" >/dev/null 2>&1 || morir "falta '$req' en el sistema"
done

TRABAJO="$(mktemp -d "${TMPDIR:-/tmp}/leadia-instalar.XXXXXX")"
trap 'rm -rf "$TRABAJO"' EXIT

# `curl` también sabe leer file://, y así las pruebas usan el camino de verdad
# en lugar de uno paralelo que podría divergir del que corre en casa del cliente.
traer() {
  local url="$1" destino="$2"
  case "$url" in
    http://*) morir "el manifiesto o la descarga van por http sin cifrar: $url" ;;
  esac
  curl -fsSL --retry 3 --retry-connrefused "$url" -o "$destino" \
    || morir "no se pudo descargar $url"
}

# Igual que `traer`, pero enseñando el avance. El tamaño se pregunta antes con
# una cabecera; si no viene, `barra_descarga` se pasa sola al girador.
traer_con_barra() {
  local url="$1" destino="$2" etiqueta="$3"
  case "$url" in
    http://*) morir "la descarga va por http sin cifrar: $url" ;;
  esac
  local total=""
  case "$url" in
    file://*) total="$(stat -f%z "${url#file://}" 2>/dev/null || echo '')" ;;
    *) total="$(curl -fsSLI "$url" 2>/dev/null | awk 'tolower($1) ~ /^content-length:/ {print $2}' | tr -d '\r' | tail -1)" ;;
  esac
  curl -fsSL --retry 3 --retry-connrefused "$url" -o "$destino" &
  local pid=$!
  barra_descarga "$pid" "$destino" "${total:-0}" "$etiqueta"
  wait "$pid" || morir "no se pudo descargar $url"
}

# Se lee con el JSON parser del sistema (python3 viene en macOS) y no con grep:
# un campo que cambie de sitio no puede acabar en una URL a medias.
campo() {
  local ruta="$1"
  python3 -c '
import json, sys
datos = json.load(open(sys.argv[1]))
for parte in sys.argv[2].split("."):
    datos = datos.get(parte) if isinstance(datos, dict) else None
    if datos is None:
        sys.exit(3)
print(datos)
' "$TRABAJO/latest.json" "$ruta" 2>/dev/null || return 1
}

verificar() {
  local fichero="$1" esperado="$2"
  [ -n "$esperado" ] || morir "el manifiesto no trae huella para $(basename "$fichero"); no se instala a ciegas"
  local real
  real="$(shasum -a 256 "$fichero" | awk '{print $1}')"
  [ "$real" = "$esperado" ] || morir "la huella de $(basename "$fichero") no cuadra
     esperada: $esperado
     obtenida: $real
  No se instala nada. Vuelve a intentarlo; si sigue igual, avisa."
  bien "huella verificada"
  detalle "$esperado"
}

portada

paso "Buscando la última versión publicada"
traer "$MANIFIESTO" "$TRABAJO/latest.json"
VERSION="$(campo version)" || morir "el manifiesto no dice qué versión es"
DMG_URL="$(campo plataformas.macos.url)" || morir "esta versión no publicó instalador de macOS"
DMG_SHA="$(campo plataformas.macos.sha256)" || DMG_SHA=""
DMG_NOMBRE="$(campo plataformas.macos.nombre)" || DMG_NOMBRE="LeadIA.dmg"
KIT_URL="$(campo herramientas.instaladores.url)" || morir "esta versión no publicó el juego de instaladores"
KIT_SHA="$(campo herramientas.instaladores.sha256)" || KIT_SHA=""
bien "LeadIA $VERSION"
detalle "$DMG_NOMBRE"

paso "Descargando LeadIA $VERSION"
traer_con_barra "$DMG_URL" "$TRABAJO/$DMG_NOMBRE" "bajando la aplicación…"
verificar "$TRABAJO/$DMG_NOMBRE" "$DMG_SHA"

paso "Descargando los instaladores"
traer_con_barra "$KIT_URL" "$TRABAJO/instaladores.zip" "bajando el instalador…"
verificar "$TRABAJO/instaladores.zip" "$KIT_SHA"
unzip -q "$TRABAJO/instaladores.zip" -d "$TRABAJO/kit"
INSTALADOR="$TRABAJO/kit/installers/instalar-mac.sh"
[ -f "$INSTALADOR" ] || morir "el juego descargado no trae instalar-mac.sh"
chmod +x "$INSTALADOR" "$TRABAJO/kit/installers/firmar-app-mac.sh" 2>/dev/null || true

if [ "${LEADIA_SOLO_DESCARGAR:-0}" = "1" ]; then
  paso "Descargado y verificado; no se instala (LEADIA_SOLO_DESCARGAR=1)"
  echo "$TRABAJO/$DMG_NOMBRE"
  exit 0
fi

paso "Instalando en $DESTINO"
detalle "sustituye la versión anterior · sus datos no se tocan"
printf "\n"
# La salida del instalador se enseña ENTERA y sangrada: el cliente ve cerrar la
# app, firmar, verificar el motor y sustituir. Es lo que convierte «se quedó
# pensando dos minutos» en «está haciendo estas cosas». `PIPESTATUS` porque a
# través de la tubería el `$?` sería el del `sed`, y un fallo pasaría por bueno.
set +e
"$INSTALADOR" --origen "$TRABAJO/$DMG_NOMBRE" --destino "$DESTINO" 2>&1 \
  | sed -e "s/^==> /$(printf '%s' "     ${AZURE_SOFT}▸${RESET} ")/" -e "s/^\( *\)\([^ ]\)/     \1\2/"
ESTADO=${PIPESTATUS[0]}
set -e
[ "$ESTADO" -eq 0 ] || morir "la instalación no se completó (código $ESTADO). No se ha tocado la versión anterior."

# ── Tarjeta final ────────────────────────────────────────────────────────────
printf "\n  %s%s%s\n" "$NAVY" "$(repetir '─' "$ANCHO")" "$RESET"
printf "  %s%s✓  LeadIA %s instalada%s\n" "$BOLD" "$VERDE" "$VERSION" "$RESET"
printf "  %s%s%s\n\n" "$NAVY" "$(repetir '─' "$ANCHO")" "$RESET"
printf "     %sDónde:%s        %s%s/LeadIA.app%s\n" "$GRIS_TENUE" "$RESET" "$AZURE_INK" "$DESTINO" "$RESET"
printf "     %sSus datos:%s    %s~/Library/Application Support/tech.leadia.desktop%s\n" "$GRIS_TENUE" "$RESET" "$GRIS" "$RESET"
printf "     %sActualiza:%s    %ssola — la app le avisa cuando haya versión nueva%s\n" "$GRIS_TENUE" "$RESET" "$GRIS" "$RESET"
printf "\n  %s%sÁbrala desde Aplicaciones o desde el acceso del Escritorio.%s\n\n" "$BOLD" "$AZURE_PALE" "$RESET"
