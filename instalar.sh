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
# Variables (para pruebas y para pinchar una versión concreta):
#   LEADIA_MANIFIESTO  — URL o ruta del latest.json (por defecto, el público).
#   LEADIA_SOLO_DESCARGAR=1 — descarga y verifica, pero NO instala.
#   LEADIA_DESTINO     — carpeta destino (por defecto /Applications).
set -euo pipefail

MANIFIESTO="${LEADIA_MANIFIESTO:-https://raw.githubusercontent.com/Theam-Flow/leadia-releases/main/latest.json}"
DESTINO="${LEADIA_DESTINO:-/Applications}"

morir() { echo "error: $*" >&2; exit 1; }
paso() { printf '\n==> %s\n' "$*"; }

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
  echo "    huella verificada: $esperado"
}

paso "Buscando la última versión publicada"
traer "$MANIFIESTO" "$TRABAJO/latest.json"
VERSION="$(campo version)" || morir "el manifiesto no dice qué versión es"
DMG_URL="$(campo plataformas.macos.url)" || morir "esta versión no publicó instalador de macOS"
DMG_SHA="$(campo plataformas.macos.sha256)" || DMG_SHA=""
DMG_NOMBRE="$(campo plataformas.macos.nombre)" || DMG_NOMBRE="LeadIA.dmg"
KIT_URL="$(campo herramientas.instaladores.url)" || morir "esta versión no publicó el juego de instaladores"
KIT_SHA="$(campo herramientas.instaladores.sha256)" || KIT_SHA=""
echo "    LeadIA $VERSION"

paso "Descargando LeadIA $VERSION"
traer "$DMG_URL" "$TRABAJO/$DMG_NOMBRE"
verificar "$TRABAJO/$DMG_NOMBRE" "$DMG_SHA"

paso "Descargando los instaladores"
traer "$KIT_URL" "$TRABAJO/instaladores.zip"
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

paso "Instalando (sustituye la versión anterior; tus datos no se tocan)"
"$INSTALADOR" --origen "$TRABAJO/$DMG_NOMBRE" --destino "$DESTINO"

paso "Listo: LeadIA $VERSION instalada en $DESTINO"
