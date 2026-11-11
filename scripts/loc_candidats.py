#!/usr/bin/env python3
"""Les littéraux de texte qu'un fichier Swift contient et que le compilateur n'a PAS relevés pour le catalogue : à convertir
en L("…") si ce sont des textes d'écran, à laisser si ce sont des données, valeurs stockées, motifs ou commandes
(voir docs/LOCALISATION.md). Lit les relevés de la dernière construction (build/derived-loc).

  python3 -I scripts/loc_candidats.py App/Vues/FicheVue.swift Shared/Suivi.swift …"""
import glob
import json
import os
import re
import sys

RACINE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
relevees = {}
for p in glob.glob(os.path.join(RACINE, "build", "derived-loc", "**", "*.stringsdata"), recursive=True):
    with open(p, encoding="utf-8") as f:
        d = json.load(f)
    rel = os.path.relpath(d["source"], RACINE)
    for lignes in d.get("tables", {}).values():
        for l in lignes:
            relevees.setdefault(rel, set()).add(l["location"]["startingLine"])

LITTERAL = re.compile(r'"((?:[^"\\\n]|\\.)*)"')
total = 0
for f in sys.argv[1:]:
    rel = os.path.relpath(os.path.abspath(f), RACINE)
    n = 0
    with open(os.path.join(RACINE, rel), encoding="utf-8") as fh:
        for i, ligne in enumerate(fh, 1):
            if ligne.lstrip().startswith("//") or i in relevees.get(rel, ()):
                continue
            code = ligne.split(" // ")[0]
            for m in LITTERAL.finditer(code):
                t = m.group(1)
                brut = re.sub(r"\\\([^)]*\)", "", t)
                if not re.search(r"[A-Za-zÀ-ÿ]{2}", brut):
                    continue
                if re.match(r"^[A-Za-z0-9_.:/\-]+$", brut):      # identifiant, clé, valeur stockée, chemin
                    continue
                if brut.startswith(("http", "/", "~", "\\", "(?", "^", "[")) or "systemImage" in code[max(0, m.start() - 14):m.start()]:
                    continue
                print(f"{rel}:{i}: {t}")
                n += 1
    total += n
print(f"-- {total} littéraux à décider", file=sys.stderr)
