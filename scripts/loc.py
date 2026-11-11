#!/usr/bin/env python3
"""Le catalogue des textes de Pilote (App/Localizable.xcstrings) : français = clés, anglais et espagnol = traductions.

  scripts/loc.py extraire [dossier-derived]   ajoute au catalogue les textes que le compilateur a relevés dans le code
                                              (build/derived-loc par défaut) ; --purger retire ceux qui n'y sont plus
  scripts/loc.py fusionner fichier.json…      verse des traductions : { "clé": {"en": …, "es": …} }
                                              (un pluriel = {"one": …, "other": …} ; le français pluriel se donne aussi)
  scripts/loc.py verifier                     rend 1 s'il manque une traduction ou si les %@ / %lld ne correspondent pas
  scripts/loc.py manque [en|es] [--source f…] liste les clés sans traduction (--source : seulement celles de ces fichiers)

La construction relève les textes (SWIFT_EMIT_LOC_STRINGS) dans des fichiers .stringsdata ; ce script les lit : xcodebuild,
lui, ne réécrit pas le catalogue. Une clé = la phrase française telle que le code l'écrit (un nombre y devient %lld, un texte %@)."""
import glob
import json
import os
import re
import sys

RACINE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATALOGUE = os.path.join(RACINE, "App", "Localizable.xcstrings")
LANGUES = ("en", "es")
PLACEHOLDER = re.compile(r"%(?:\d+\$)?(?:l{0,2}[dfu]|@)")


def charger():
    with open(CATALOGUE, encoding="utf-8") as f:
        return json.load(f)


def ecrire(cat):
    # Le français (langue source) est écrit en toutes lettres : sans lui le compilateur ne produit pas fr.lproj, et un Mac
    # en français retomberait sur l'anglais.
    for cle, entree in cat["strings"].items():
        loc = entree.get("localizations")
        if loc and "fr" not in loc:
            loc["fr"] = unite(cle)
    # Même mise en page que Xcode (« clé » : valeur, 2 espaces), clés triées : un diff ne montre que le vrai changement.
    texte = json.dumps(cat, ensure_ascii=False, indent=2, sort_keys=True, separators=(",", " : "))
    with open(CATALOGUE, "w", encoding="utf-8") as f:
        f.write(texte + "\n")


def unite(valeur):
    return {"stringUnit": {"state": "translated", "value": valeur}}


def localisation(valeur):
    """Une chaîne simple, ou un pluriel {"one": …, "other": …} (+ zero, few, many si la langue en a besoin)."""
    if isinstance(valeur, str):
        return unite(valeur)
    return {"variations": {"plural": {cat: unite(v) for cat, v in valeur.items()}}}


def formes(loc):
    """Toutes les chaînes d'une localisation (une ou plusieurs formes de pluriel)."""
    if not loc:
        return []
    if "stringUnit" in loc:
        return [loc["stringUnit"]["value"]]
    return [u["stringUnit"]["value"] for u in loc.get("variations", {}).get("plural", {}).values()]


def utile(cle):
    """Une clé sans une seule lettre (« · », « —», « %@ · %@ », « ×%@ ») n'a rien à traduire."""
    return re.search(r"[A-Za-zÀ-ÿ]", PLACEHOLDER.sub("", cle)) is not None


def marques(t):
    return sorted(re.sub(r"%\d+\$", "%", m) for m in PLACEHOLDER.findall(t.replace("%%", "")))


def extraire(dossier, purger):
    cat = charger()
    vus, sources = {}, {}
    for chemin in glob.glob(os.path.join(dossier, "**", "*.stringsdata"), recursive=True):
        with open(chemin, encoding="utf-8") as f:
            d = json.load(f)
        source = d.get("source", "")
        if "/App/" not in source and "/Shared/" not in source:
            continue
        for table, lignes in d.get("tables", {}).items():
            if table != "Localizable":
                print(f"table « {table} » ignorée ({source})")
                continue
            for l in lignes:
                vus.setdefault(l["key"], os.path.relpath(source, RACINE))
                sources.setdefault(l["key"], set()).add(os.path.relpath(source, RACINE))
    vus = {k: v for k, v in vus.items() if utile(k)}
    ajoutes = [k for k in vus if k not in cat["strings"]]
    for k in ajoutes:
        cat["strings"][k] = {}
    orphelins = [k for k in cat["strings"] if k not in vus]
    if purger:
        for k in orphelins:
            del cat["strings"][k]
    ecrire(cat)
    # Qui écrit quoi : le fichier (ignoré par git, dans build/) sert à « manque --source ».
    os.makedirs(os.path.join(RACINE, "build"), exist_ok=True)
    with open(os.path.join(RACINE, "build", "loc-sources.json"), "w", encoding="utf-8") as f:
        json.dump({k: sorted(v) for k, v in sources.items()}, f, ensure_ascii=False)
    print(f"{len(vus)} textes dans le code · {len(ajoutes)} ajoutés au catalogue · "
          f"{len(orphelins)} dans le catalogue sans le code" + (" (retirés)" if purger else ""))
    for k in orphelins[:15]:
        print("  orphelin :", k)


def fusionner(fichiers):
    cat = charger()
    inconnus, ecrits = [], 0
    for chemin in fichiers:
        with open(chemin, encoding="utf-8") as f:
            traductions = json.load(f)
        for cle, langues in traductions.items():
            entree = cat["strings"].get(cle)
            if entree is None:
                inconnus.append(cle)
                continue
            loc = entree.setdefault("localizations", {})
            for langue, valeur in langues.items():
                loc[langue] = localisation(valeur)
                ecrits += 1
            # Un pluriel dans une langue demande le pluriel français aussi (la clé sert de forme « other » si seule).
            if any(isinstance(v, dict) for v in langues.values()) and "fr" not in loc:
                print("pluriel sans forme française :", cle)
    ecrire(cat)
    print(f"{ecrits} traductions versées")
    for k in inconnus:
        print("  clé absente du catalogue (faute de frappe, ou à extraire d'abord) :", k)


def problemes():
    cat = charger()
    manque, marques_ko = [], []
    for cle, entree in cat["strings"].items():
        if not utile(cle):
            continue
        loc = entree.get("localizations", {})
        for langue in LANGUES:
            f = formes(loc.get(langue))
            if not f:
                manque.append((cle, langue))
                continue
            for v in f:
                if marques(v) != marques(cle):
                    marques_ko.append((cle, langue, v))
    return cat, manque, marques_ko


def verifier():
    cat, manque, marques_ko = problemes()
    print(f"{len(cat['strings'])} textes · {len(manque)} traductions manquantes · {len(marques_ko)} marques %@/%lld différentes")
    for cle, langue in manque[:20]:
        print(f"  manque {langue} : {cle}")
    for cle, langue, v in marques_ko[:20]:
        print(f"  marques {langue} : {cle}  →  {v}")
    return 1 if manque or marques_ko else 0


def liste_manque(langue, fichiers):
    cat, manque, _ = problemes()
    sources = {}
    if fichiers:
        with open(os.path.join(RACINE, "build", "loc-sources.json"), encoding="utf-8") as f:
            sources = json.load(f)
    for cle, l in manque:
        if langue not in (None, l):
            continue
        if fichiers and not any(x in fichiers for x in sources.get(cle, [])):
            continue
        print(json.dumps(cle, ensure_ascii=False), "\t", ",".join(sources.get(cle, [])) if not fichiers else "")


if __name__ == "__main__":
    a = sys.argv[1:]
    if not a or a[0] not in ("extraire", "fusionner", "verifier", "manque"):
        print(__doc__)
        sys.exit(2)
    if a[0] == "extraire":
        purger = "--purger" in a
        reste = [x for x in a[1:] if x != "--purger"]
        extraire(reste[0] if reste else os.path.join(RACINE, "build", "derived-loc"), purger)
    elif a[0] == "fusionner":
        fusionner(a[1:])
    elif a[0] == "verifier":
        sys.exit(verifier())
    else:
        reste = a[1:]
        langue = reste[0] if reste and reste[0] in LANGUES else None
        fichiers = reste[reste.index("--source") + 1:] if "--source" in reste else []
        liste_manque(langue, fichiers)
