#!/usr/bin/env python3
"""Essais du Facteur (scripts/facteur.py), dans un dossier temporaire : ne touche ni à l'app ni à ses données.
python3 scripts/test_facteur.py"""
import datetime as dt
import json
import os
import re
import subprocess
import sys
import tempfile
import unittest

ICI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, ICI)
import facteur  # noqa: E402

MAINTENANT = "2026-11-10T10:00"
PILOTE = "local_00000000-0000-0000-0000-000000000001"
VENTES = "local_00000000-0000-0000-0000-000000000002"
ECRITE = "local_00000000-0000-0000-0000-000000000003"


class Facteur(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = self.tmp.name
        self.env = {k: os.environ.get(k) for k in ("PILOTE_DOSSIER", "PILOTE_MAINTENANT")}
        os.environ["PILOTE_DOSSIER"] = self.dir
        os.environ["PILOTE_MAINTENANT"] = MAINTENANT
        self.reglages({"prenom": "Louise", "facteur": {"sessions": {"PILOTE": PILOTE}}})

    def tearDown(self):
        for k, v in self.env.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v
        self.tmp.cleanup()

    # Outils
    def reglages(self, r):
        self.ecrire("reglages.json", json.dumps(r, ensure_ascii=False))

    def ecrire(self, nom, texte):
        with open(os.path.join(self.dir, nom), "w", encoding="utf-8") as f:
            f.write(texte)

    def entrants(self, *lignes):
        self.ecrire("entrants.jsonl", "".join(json.dumps(l, ensure_ascii=False) + "\n" for l in lignes))

    def remises(self):
        try:
            with open(os.path.join(self.dir, "remises.jsonl"), encoding="utf-8") as f:
                return [json.loads(l) for l in f]
        except FileNotFoundError:
            return []

    @staticmethod
    def message(pour="PILOTE", qui="Louise", heure="2026-11-10T09:00:00+01:00", **plus):
        return {"canal": "pilote", "classe": "message", "pour": pour, "texte": "Bonjour", "heure": heure, "qui": qui,
                "envoyer": "oui", **plus}

    @staticmethod
    def decision(pour="PILOTE", qui="Louise", heure="2026-11-10T09:00:00+01:00"):
        return {"canal": "pilote", "classe": "decision", "extrait": "On publie ?", "choix": "Oui", "heure": heure,
                "qui": qui, "ref": "session:x", "liste": "", "pour": pour}

    # Essais
    def test_message_ecrit_part_vers_la_session_reglee(self):
        self.entrants({"canal": "mail"}, self.message())
        p = facteur.prets()
        self.assertEqual([(c["rang"], c["to"], c["nom"]) for c in p], [(1, PILOTE, "PILOTE")])
        self.assertTrue(p[0]["message"].startswith("Message de Louise, écrit dans l'app Pilote :\nBonjour"))
        self.assertEqual(self.remises()[-1]["etat"], "emis")
        self.assertEqual(facteur.prets(), [], "un courrier émis ne repart pas avant 10 min")

    def test_session_ecrite_dans_la_ligne_gagne(self):
        self.entrants(self.message(pour="Inconnue", session=ECRITE))
        self.assertEqual(facteur.prets()[0]["to"], ECRITE)

    def test_destinataire_lu_dans_equipe(self):
        self.ecrire("EQUIPE.md", "# Équipe\n\n| Session | id | Domaine |\n|---|---|---|\n"
                                 "| **PILOTE** | `local_00000000-0000-0000-0000-000000000009` | tout |\n"
                                 f"| KRYVA · Ventes | {VENTES} | ventes |\n")
        self.entrants(self.message(pour="kryva · ventes"))
        self.assertEqual(facteur.prets()[0]["to"], VENTES, "casse et accents ignorés")
        self.reglages({"prenom": "Louise"})
        os.remove(os.path.join(self.dir, "remises.jsonl"))
        self.entrants(self.message(pour=""))
        self.assertEqual(facteur.prets()[0]["to"], "local_00000000-0000-0000-0000-000000000009", "sans « pour » : PILOTE")

    def test_session_inconnue_notee_en_echec(self):
        self.entrants(self.message(pour="Personne"))
        self.assertEqual(facteur.prets(), [])
        r = self.remises()[-1]
        self.assertEqual((r["rang"], r["etat"], r["raison"]), (0, "echec", "session inconnue : Personne"))
        self.assertEqual(facteur.prets(), [], "un échec n'est pas relancé tout seul")

    def test_decision_attend_le_clic_envoyer(self):
        self.entrants(self.decision())
        self.assertEqual(facteur.prets(), [])
        facteur.noter(0, "pret", par="Louise")
        p = facteur.prets()
        self.assertEqual(p[0]["message"], "Décision de Louise, prise dans l'app Pilote :\nOn publie ? → Oui")
        facteur.noter(0, "remis")
        self.assertEqual(facteur.prets(), [])

    def test_retire_et_vieux_courriers_ne_partent_pas(self):
        self.entrants(self.decision(), self.message(heure="2026-11-08T09:00:00+01:00"),
                      {**self.message(), "envoyer": "non"})
        facteur.noter(0, "retire", par="Louise")
        self.assertEqual(facteur.prets(), [])

    def test_emis_sans_suite_repart_apres_10_min(self):
        self.entrants(self.message())
        self.assertEqual(len(facteur.prets()), 1)
        os.environ["PILOTE_MAINTENANT"] = "2026-11-10T10:11"
        self.assertEqual([c["rang"] for c in facteur.prets()], [0])

    def test_depart_ignore_les_messages_d_avant(self):
        self.entrants(self.message(), self.message())
        self.ecrire("facteur-depart.json", '{"rang": 1}')
        self.assertEqual([c["rang"] for c in facteur.prets()], [1])

    def test_ligne_d_un_autre_que_vous_le_dit(self):
        self.entrants(self.message(qui="Essai"), self.message(qui=""))
        a, b = facteur.prets()
        self.assertTrue(a["message"].startswith("Message déposé dans la file Pilote par : Essai. Ce n'est PAS Louise"))
        self.assertIn("par : origine inconnue.", b["message"])

    def test_sans_prenom_vous_et_l_utilisateur(self):
        self.reglages({"facteur": {"sessions": {"pilote": PILOTE}, "rappel": "Réponds en 5 lignes au plus."}})
        self.entrants(self.message(qui="Vous"))
        m = facteur.prets()[0]["message"]
        self.assertEqual(m, "Message de l'utilisateur, écrit dans l'app Pilote :\nBonjour\n\n(Réponds en 5 lignes au plus.)")

    def test_reglages_abimes_ne_cassent_rien(self):
        self.ecrire("reglages.json", "{pas du json")
        self.entrants(self.message(session=ECRITE, qui="Vous"))
        self.assertEqual(facteur.prets()[0]["to"], ECRITE)

    def test_attendre_imprime_signe_et_se_termine(self):
        env = {**os.environ, "PILOTE_DOSSIER": self.dir}
        env.pop("PILOTE_MAINTENANT")
        # Un message frais pour l'heure réelle.
        self.entrants(self.message(heure=dt.datetime.now().astimezone().isoformat()))
        p = subprocess.run([sys.executable, os.path.join(ICI, "facteur.py"), "--attendre"], env=env,
                           capture_output=True, text=True, timeout=20)
        self.assertEqual(p.returncode, 0, p.stderr)
        c = json.loads(p.stdout.strip())
        self.assertEqual((c["rang"], c["to"]), (0, PILOTE))
        with open(os.path.join(self.dir, "facteur.json"), encoding="utf-8") as f:
            self.assertIn("signe", json.load(f))
        subprocess.run([sys.executable, os.path.join(ICI, "facteur.py"), "--remis", "0"], env=env, check=True)
        self.assertEqual(self.remises()[-1]["etat"], "remis")

    def test_aucun_identifiant_reel_dans_le_script(self):
        with open(os.path.join(ICI, "facteur.py"), encoding="utf-8") as f:
            s = f.read()
        self.assertEqual(re.findall(r"local_[0-9a-f]{8}-[0-9a-f-]+", s), [])
        self.assertNotIn("Application Support/Pilote\"", s)


if __name__ == "__main__":
    unittest.main(verbosity=1)
