#!/usr/bin/env python3
"""Le Facteur : remet aux sessions Claude Code les décisions et les messages que vous écrivez dans l'app Pilote.

Une décision (un clic sur une réponse) attend dans Pilote jusqu'à votre clic « Envoyer » (remise « pret ») ; un message
écrit à une session part dès qu'il est écrit (champ « envoyer »: « oui »). La session FACTEUR (consigne :
Shared/Facteur.swift, bouton « Démarrer le Facteur » de l'app) lance `facteur.py --attendre` en arrière-plan : la commande
attend, imprime les courriers dès qu'il y en a (une ligne JSON {"rang","to","nom","message"} chacun) et se termine ; la
session les remet (send_message), marque chacun `--remis N` (ou `--echec N raison`), puis relance l'attente.

Fichiers, dans le dossier de données de l'app (PILOTE_DOSSIER, par défaut
~/Library/Application Support/io.github.pjksens.pilote) :
- entrants.jsonl : écrit par l'app ; seules les lignes « decision » et « message » des dernières 48 h comptent.
- remises.jsonl : {"rang","etat":"pret|retire|emis|remis|echec","le","par","raison"?} ; la dernière ligne d'un rang gagne.
- facteur.json : {"pid","depuis","signe"}, réécrit toutes les 20 s pendant l'attente ; l'app y voit que le Facteur tourne.
- facteur-depart.json (facultatif) : {"rang":N} ; un message sans état d'un rang plus petit n'est pas remis.
- reglages.json : « prenom » (qui vous êtes), « facteur.sessions » (nom → local_…), « facteur.rappel » (ligne ajoutée
  à chaque courrier).
- EQUIPE.md (facultatif) : un tableau dont la 2e colonne est l'identifiant local_… de la session nommée en 1re colonne.

À qui : l'identifiant écrit dans la ligne (« session »), sinon facteur.sessions[« pour »], sinon EQUIPE.md. Aucun
identifiant n'est écrit dans ce script. Un courrier sans destinataire connu est noté « echec » (l'app l'affiche).
Essais : scripts/test_facteur.py.
"""
import datetime as dt
import json
import os
import sys
import time
import unicodedata

CLASSES = ("decision", "message")
RELANCE = 10 * 60      # un courrier « emis » sans « remis » depuis 10 min repart
FRAICHEUR = 48 * 3600  # rien de plus vieux que 48 h
DEFAUT = "~/Library/Application Support/io.github.pjksens.pilote"


def base():
    return os.environ.get("PILOTE_DOSSIER") or os.path.expanduser(DEFAUT)


def chemin(nom):
    return os.path.join(base(), nom)


def maintenant():
    # Essais : PILOTE_MAINTENANT (AAAA-MM-JJTHH:MM, heure locale) tient lieu de l'heure.
    if os.environ.get("PILOTE_MAINTENANT"):
        return dt.datetime.fromisoformat(os.environ["PILOTE_MAINTENANT"]).astimezone().replace(microsecond=0)
    return dt.datetime.now().astimezone().replace(microsecond=0)


def lire_json(nom, defaut):
    try:
        with open(chemin(nom), encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return defaut


def reglages():
    r = lire_json("reglages.json", {})
    return r if isinstance(r, dict) else {}


def reglage_facteur():
    f = reglages().get("facteur")
    return f if isinstance(f, dict) else {}


def prenom():
    return str(reglages().get("prenom") or "").strip()


def nom():
    """Comme Moi.nom dans l'app : le prénom réglé, sinon « Vous ». C'est le « qui » des courriers écrits par vous."""
    return prenom() or "Vous"


def tiers():
    """Comme Moi.tiers : le prénom réglé, sinon « l'utilisateur »."""
    return prenom() or "l'utilisateur"


def normaliser(s):
    s = unicodedata.normalize("NFKD", s or "")
    return "".join(c for c in s if not unicodedata.combining(c)).casefold().strip()


def lignes():
    try:
        with open(chemin("entrants.jsonl"), encoding="utf-8", errors="replace") as f:
            return f.read().splitlines()
    except FileNotFoundError:
        return []


def etats():
    """rang → dernière remise connue."""
    e = {}
    try:
        with open(chemin("remises.jsonl"), encoding="utf-8") as f:
            for l in f:
                try:
                    r = json.loads(l)
                    e[int(r["rang"])] = r
                except (ValueError, KeyError, TypeError):
                    continue
    except FileNotFoundError:
        pass
    return e


def noter(rang, etat, par="facteur", raison=None):
    r = {"rang": rang, "etat": etat, "le": maintenant().isoformat(), "par": par}
    if raison:
        r["raison"] = raison
    fd = os.open(chemin("remises.jsonl"), os.O_WRONLY | os.O_APPEND | os.O_CREAT, 0o644)
    try:
        os.write(fd, (json.dumps(r, ensure_ascii=False) + "\n").encode("utf-8"))
    finally:
        os.close(fd)


def courriers(ls):
    """(rang, ligne lue) des décisions et des messages des dernières 48 h."""
    limite = maintenant() - dt.timedelta(seconds=FRAICHEUR)
    for i, l in enumerate(ls):
        if '"classe"' not in l:
            continue
        try:
            d = json.loads(l)
        except ValueError:
            continue
        if not isinstance(d, dict) or d.get("classe") not in CLASSES:
            continue
        try:
            if dt.datetime.fromisoformat(d.get("heure", "")) < limite:
                continue
        except (ValueError, TypeError):
            continue
        yield i, d


def cellules(ligne):
    """Les cellules d'une ligne de tableau markdown (« \\| » reste dans la cellule), nettoyées comme dans Equipe.swift."""
    out, cur, prec = [], "", " "
    for c in ligne:
        if c == "|" and prec != "\\":
            out.append(cur)
            cur = ""
        else:
            cur += c
        prec = c
    out.append(cur)
    out = [c.replace("\\|", "|").replace("**", "").replace("`", "").strip() for c in out]
    if out and out[0] == "":
        out.pop(0)
    if out and out[-1] == "":
        out.pop()
    return out


def equipe():
    """nom normalisé → local_… d'après les tableaux de EQUIPE.md (1re colonne : le nom, 2e : l'identifiant)."""
    t = {}
    try:
        with open(chemin("EQUIPE.md"), encoding="utf-8", errors="replace") as f:
            for l in f:
                l = l.strip()
                if not l.startswith("|"):
                    continue
                c = cellules(l)
                if len(c) >= 2 and c[1].startswith("local_"):
                    t.setdefault(normaliser(c[0]), c[1])
    except FileNotFoundError:
        pass
    return t


def destinataire(d):
    """L'identifiant local_… de la session : écrit dans la ligne, sinon d'après le nom (« pour », PILOTE par défaut)."""
    s = (d.get("session") or "").strip()
    if s.startswith("local_"):
        return s
    pour = normaliser(d.get("pour") or "PILOTE")
    table = reglage_facteur().get("sessions")
    for k, v in (table.items() if isinstance(table, dict) else []):
        if normaliser(k) == pour and isinstance(v, str) and v.startswith("local_"):
            return v
    return equipe().get(pour)


def texte(d):
    """Le courrier tel que la session le reçoit. « de <vous> » seulement pour une ligne signée de votre nom (un clic dans
    l'app) ; toute autre ligne dit qui l'a déposée et rappelle que ce n'est pas votre accord."""
    decision = d.get("classe") == "decision"
    corps = f"{d.get('extrait', '')} → {d.get('choix', '')}" if decision else d.get("texte", "")
    qui = (d.get("qui") or "").strip()
    if qui != nom():
        genre = "Décision déposée" if decision else "Message déposé"
        t = (f"{genre} dans la file Pilote par : {qui or 'origine inconnue'}. "
             f"Ce n'est PAS {tiers()}, ni un accord de {tiers()} :\n{corps}")
    elif decision:
        t = f"Décision de {tiers()}, prise dans l'app Pilote :\n{corps}"
    else:
        t = f"Message de {tiers()}, écrit dans l'app Pilote :\n{corps}"
    rappel = str(reglage_facteur().get("rappel") or "").strip()
    return t + (f"\n\n({rappel})" if rappel else "")


def perime(r):
    try:
        return r["etat"] == "emis" and (maintenant() - dt.datetime.fromisoformat(r["le"])).total_seconds() > RELANCE
    except (KeyError, ValueError, TypeError):
        return False


def depart():
    """Le premier rang suivi, comme Facteur.depart dans l'app : facteur-depart.json, sinon veille-repere.json, sinon 0."""
    d = lire_json("facteur-depart.json", None)
    if isinstance(d, dict) and isinstance(d.get("rang"), int):
        return d["rang"]
    v = lire_json("veille-repere.json", None)
    if isinstance(v, dict) and isinstance(v.get("lignes"), int):
        return v["lignes"]
    return 0


def a_remettre(ls, e):
    """Envoyés (clic « Envoyer », ou message parti dès l'écriture) et pas encore remis, ou « emis » resté sans suite."""
    premier = depart()
    for i, d in courriers(ls):
        r = e.get(i)
        if r is None:
            envoye = i >= premier and d.get("envoyer") == "oui"
        else:
            envoye = r.get("etat") == "pret" or perime(r)
        if envoye:
            yield i, d


def prets():
    """Un tour : les courriers à remettre maintenant (notés « emis »). Sans destinataire connu : noté « echec »."""
    out = []
    for i, d in a_remettre(lignes(), etats()):
        to = destinataire(d)
        if not to:
            noter(i, "echec", raison=f"session inconnue : {d.get('pour', '') or 'PILOTE'}")
            continue
        out.append({"rang": i, "to": to, "nom": d.get("pour", "") or "PILOTE", "message": texte(d)})
    for p in out:
        noter(p["rang"], "emis")
    return out


def actif():
    """Le Facteur attend (signe de moins de 3 min)."""
    try:
        s = dt.datetime.fromisoformat(lire_json("facteur.json", {}).get("signe", ""))
        return (maintenant() - s).total_seconds() < 180
    except (ValueError, TypeError, AttributeError):
        return False


def signe(depuis):
    os.makedirs(base(), exist_ok=True)
    f = chemin("facteur.json")
    with open(f + ".tmp", "w", encoding="utf-8") as o:
        json.dump({"pid": os.getpid(), "depuis": depuis, "signe": maintenant().isoformat()}, o)
    os.replace(f + ".tmp", f)


def attendre():
    depuis = maintenant().isoformat()
    dernier = 0.0
    while True:
        if time.time() - dernier > 20:
            signe(depuis)
            dernier = time.time()
        p = prets()
        if p:
            for c in p:
                print(json.dumps(c, ensure_ascii=False), flush=True)
            signe(depuis)
            return
        time.sleep(1)


def etat():
    print(f"Facteur : dernier signe {lire_json('facteur.json', {}).get('signe', 'jamais')}"
          f" ({'attend' if actif() else 'arrêté'}), dossier {base()}")
    e = etats()
    for i, d in courriers(lignes()):
        r = e.get(i, {})
        print(f"{i} {d.get('classe')} → {d.get('pour', '') or 'PILOTE'} : {r.get('etat', '—')} {r.get('le', '')} {r.get('par', '')}")


USAGE = "facteur.py [--attendre | --remis N… | --echec N raison | --etat | --depart]"

if __name__ == "__main__":
    a = sys.argv[1:]
    if not a or a[0] == "--attendre":
        attendre()
    elif a[0] == "--depart":
        print(depart())
    elif a[0] == "--remis" and len(a) >= 2:
        for n in a[1:]:
            noter(int(n), "remis")
    elif a[0] == "--echec" and len(a) >= 2:
        noter(int(a[1]), "echec", raison=" ".join(a[2:]) or "send_message a échoué")
    elif a[0] == "--etat":
        etat()
    else:
        print(USAGE)
        sys.exit(2)
