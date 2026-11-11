#!/bin/bash
# Pilote en mode démo : données fictives, rien de réel n'est lu ni envoyé (voir Shared/Demo.swift).
#   ./scripts/demo.sh              construit l'app (sans l'installer) et l'ouvre en démo
#   ./scripts/demo.sh --captures   refait les captures du README dans docs/captures, puis se ferme
#   ./scripts/demo.sh --gif [noms] refait les GIF du README dans docs/media (suivi facteur claude ; ffmpeg requis)
set -euo pipefail
cd "$(dirname "$0")/.."
DD="${PILOTE_DERIVED:-build/demo}"
xcodegen generate --quiet
xcodebuild -project Pilote.xcodeproj -scheme Pilote -configuration Release -derivedDataPath "$DD" build -quiet
APP="$DD/Build/Products/Release/Pilote.app"
DEMO="$(mktemp -d -t pilote-demo)"   # base et fichiers fictifs, neufs à chaque lancement
# Lancé par LaunchServices (open) : l'app est alors son propre processus responsable et peut photographier sa fenêtre
# sans la permission d'enregistrer l'écran.
lancer() { open -n -W --env PILOTE_DEMO=1 --env PILOTE_DEMO_DOSSIER="$DEMO" "$@"; }
if [ "${1:-}" = "--captures" ]; then
  mkdir -p docs/captures
  # Stats vidéos lit une base de relevés qui n'existe pas en démo : pas de capture.
  lancer --env PILOTE_CAPTURES="$PWD/docs/captures" \
         --env PILOTE_CAPTURES_PAGES=aujourdhui,journee,prospects,contacts,semaine,planning,taches,projets,claude \
         "$APP" --args -apparence clair
  lancer --env PILOTE_CAPTURES="$PWD/docs/captures" --env PILOTE_CAPTURES_PAGES=aujourdhui,claude \
         --env PILOTE_CAPTURES_SUFFIXE=-sombre "$APP" --args -apparence sombre
  echo "Captures : docs/captures"
elif [ "${1:-}" = "--gif" ]; then
  command -v ffmpeg >/dev/null || { echo "ffmpeg manque : brew install ffmpeg"; exit 1; }
  IMAGES="$(mktemp -d -t pilote-gif)"; SORTIE="$PWD/docs/media"; mkdir -p "$SORTIE"
  shift; NOMS="suivi facteur claude"; [ $# -gt 0 ] && NOMS="$*"
  for s in $NOMS; do
    DEMO="$(mktemp -d -t pilote-demo)"   # chaque scénario repart des données de démo neuves
    DEPLIER=""; [ "$s" = "claude" ] && DEPLIER="app"
    lancer --env PILOTE_CAPTURES="$IMAGES" --env PILOTE_SCENARIO="$s" --env PILOTE_DEPLIER="$DEPLIER" "$APP" --args -apparence clair
    (cd "$IMAGES/$s" && ffmpeg -loglevel error -y -f concat -safe 0 -i images.txt \
      -vf "fps=12,scale=960:-1:flags=lanczos,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle" \
      -loop 0 "$SORTIE/$s.gif")
    echo "GIF : docs/media/$s.gif ($(du -h "$SORTIE/$s.gif" | cut -f1))"
    if [ -s "$IMAGES/$s/manques.txt" ]; then
      echo "  Cibles introuvables ($s) :"; sed 's/^/    /' "$IMAGES/$s/manques.txt"
    fi
  done
  echo "Images : $IMAGES"
else
  lancer "$APP"
fi
