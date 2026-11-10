#!/bin/zsh
# Construit Pilote (app + outil), installe l'app dans ~/Applications et l'outil à la racine du projet.
set -e
cd "$(dirname "$0")/.."
APP=~/Applications/Pilote.app
ID=io.github.pjksens.pilote   # Identite.app (Shared/Identite.swift), PRODUCT_BUNDLE_IDENTIFIER de project.yml
# Une autre app nommée Pilote (autre identifiant) dans ~/Applications : on ne la ferme pas et on ne la remplace pas.
AUTRE=""
# Premier install : pas d'app, donc pas de plist (PlistBuddy écrirait « File Doesn't Exist » sur la sortie standard).
[[ -f "$APP/Contents/Info.plist" ]] && AUTRE=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$APP/Contents/Info.plist" 2>/dev/null || true)
if [[ "$1" != "--outil" && -n "$AUTRE" && "$AUTRE" != "$ID" ]]; then
  echo "~/Applications/Pilote.app est une autre app ($AUTRE) : rien n'est remplacé. Déplacez-la d'abord."
  exit 1
fi
xcodegen generate --quiet
# --outil : seulement l'outil en ligne de commande (l'app Pilote qui tourne n'est ni fermée ni remplacée).
[[ "$1" == "--outil" ]] || xcodebuild -project Pilote.xcodeproj -scheme Pilote -configuration Release -derivedDataPath build/derived build -quiet
xcodebuild -project Pilote.xcodeproj -scheme pilote -configuration Release -derivedDataPath build/derived build -quiet
if [[ "$1" == "--outil" ]]; then
  cp build/derived/Build/Products/Release/pilote ./pilote.nouveau && mv -f ./pilote.nouveau ./pilote
  echo "Outil installé : $(pwd)/pilote (app inchangée)"
  exit 0
fi
mkdir -p ~/Applications
# Seulement l'app installée à cet endroit (vérifiée plus haut), jamais une autre app Pilote ouverte.
pkill -f "$APP/Contents/MacOS/Pilote" 2>/dev/null && sleep 1 || true
rm -rf "$APP"
cp -R build/derived/Build/Products/Release/Pilote.app ~/Applications/
# Remplacement par renommage : une session Claude qui utilise déjà l'outil (connecteur MCP) n'est pas coupée.
cp build/derived/Build/Products/Release/pilote ./pilote.nouveau && mv -f ./pilote.nouveau ./pilote
echo "Pilote installé : ~/Applications/Pilote.app · outil : $(pwd)/pilote"
