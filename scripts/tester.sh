#!/bin/zsh
# Lance les tests unitaires de Pilote (Swift), puis ceux du Facteur (Python). Ne touche ni à l'app ni à la base réelle.
set -e
cd "$(dirname "$0")/.."
xcodegen generate --quiet
xcodebuild test -project Pilote.xcodeproj -scheme PiloteTests -destination 'platform=macOS' -derivedDataPath build/derived-tests 2>&1 \
  | grep -E "error: |Executed [0-9]+ tests|TEST (SUCCEEDED|FAILED)" || true
python3 -I scripts/test_facteur.py
