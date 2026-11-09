<p align="center">
  <img src="docs/media/hero.de.png" alt="Pilote: deine Kunden, deine Projekte und dein Claude-Code-Team auf einem Bildschirm">
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-15%2B-black?logo=apple" alt="macOS 15+">
  <img src="https://img.shields.io/badge/Swift-SwiftUI-F05138?logo=swift&logoColor=white" alt="Swift und SwiftUI">
  <img src="https://img.shields.io/badge/Claude%20Code-MCP%20server-C2502C" alt="Funktioniert mit Claude Code (MCP-Server)">
  <img src="https://img.shields.io/badge/data-stays%20on%20your%20Mac-0A84FF" alt="Deine Daten bleiben auf deinem Mac">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="MIT">
  <a href="../../stargazers"><img src="https://img.shields.io/github/stars/pjksens/pilote?style=flat&color=FFD60A&label=%E2%98%85%20stars" alt="Sterne"></a>
</p>

<p align="center">
  <a href="README.md">English</a> · <a href="README.fr.md">Français</a> · <a href="README.es.md">Español</a> · <a href="README.pt-BR.md">Português (Brasil)</a> · <b>Deutsch</b> · <a href="README.it.md">Italiano</a> · <a href="README.zh-CN.md">简体中文</a> · <a href="README.ja.md">日本語</a> · <a href="README.ko.md">한국어</a>
</p>

<p align="center">
  Entwickelt von <b>pjk</b> (Sacha Praljak) ·
  <a href="https://sachapraljak.com/?utm_source=github&utm_medium=readme&utm_campaign=pilote">sachapraljak.com</a> ·
  <a href="https://www.instagram.com/sachaprljk/">Instagram</a> ·
  <a href="https://www.tiktok.com/@sachaprljk">TikTok</a>
</p>

<p align="center">
  <b>Wenn dir Pilote hilft, hilft ein ⭐ anderen dabei, es zu finden.</b>
</p>

**Pilote ist das Logbuch eines Freelancers, der mit einem Team aus Claude-Code-Agenten arbeitet.**
Eine native Mac-App für alles, was dich braucht: deine Kunden und jeden Austausch mit ihnen, die nächste Aktion für jeden Einzelnen, deine
Erinnerungen und deinen Kalender und das, was deine Claude-Code-Sitzungen gerade tun. Die Sitzungen lesen und schreiben
Pilote über einen MCP-Server und halten es so auf dem neuesten Stand; du siehst nur, was dich braucht. Alles bleibt auf
deinem Mac: eine lokale SQLite-Datenbank, kein Server, kein Konto.

<p align="center">
  <img src="docs/media/suivi.gif" width="720" alt="Das Prospects-Board von Pilote: Ein Klick auf einen Kontakt öffnet seine Karte mit jedem Austausch und der nächsten Aktion">
  <br><sub>Demo-Modus (<code>./scripts/demo.sh</code>): erfundene Daten, keine echten Personen.</sub>
</p>

> Die Oberfläche der App und ihre Code-Kommentare sind auf Französisch. Dieses README gibt es in neun Sprachen; die App (noch) nicht.

## Was Pilote kann

- **Ein Bildschirm für den Tag.** Termine (Kalender), heutige und überfällige Erinnerungen (Erinnerungen, du hakst sie
  ab), von Claude vorbereitete Nachrichten, die auf deine Freigabe warten, fällige Nachfassaktionen, erhaltene Antworten.
- **Kunden mit ihrem Kontext.** Ein Adressbuch pro Arbeitsbereich, mit Phase, nächster Aktion und dem vollständigen
  Verlauf jedes Austauschs (E-Mail, SMS, Anruf, Besuch). Vor einem Anruf siehst du alles, was gesagt wurde.
- **Claude Code angebunden.** Ein MCP-Server gibt deinen Claude-Sitzungen Werkzeuge, um Pilote zu lesen und zu
  beschreiben (`jour`, `cherche`, `fiche`, `enregistre_contact`, `ajoute_au_fil`, `marque`, `carte`, `ou_est`, `agents`,
  `journal`, `note_au_journal`, `publications`…). Die Anweisungen des Servers sagen ihnen, dass sie suchen sollen, bevor
  sie etwas anlegen, nichts erfinden und nichts von sich aus senden dürfen.
- **Agenten.** Die auf deinem Mac geöffneten Claude-Code-Sitzungen, ihr Zustand und ihre letzte Aktion sowie ein
  Journal dessen, was sie geliefert haben (gefüllt durch einen `Stop`-Hook von Claude Code).
- **Eine Karte deiner Arbeit.** Jedes Projekt, sein Ordner, seine `ETAT.md` (Statusdatei), seine wichtigen Dokumente;
  durchsuche alles (⌘K) über Projekte, Kontakte, Journal und Dateien (Spotlight).
- **E-Mail unter Kontrolle.** Eine vorbereitete E-Mail geht erst raus, wenn du klickst, von deinem Gmail aus (SMTP,
  App-Passwort im macOS-Schlüsselbund, von Claude nie gelesen). Reiner Text, Antworten bleiben im richtigen Thread.
- **Veröffentlichen.** Plane Videos auf YouTube, Instagram und TikTok, mit einer ausdrücklichen Freigabe vor jeder
  Veröffentlichung (Tokens im Schlüsselbund).
- **Radar.** Beobachte Social-Media-Konten (Aufrufe, Veröffentlichungsrhythmus, Ideen), von Hand eingetragen oder über
  eine kostenpflichtige Quelle, die niemals ohne deine Bestätigung läuft.

## Mit Claude Code

Deine Sitzungen erledigen die Arbeit; in Pilote siehst du sie und antwortest ihnen.

<p align="center">
  <img src="docs/media/claude.gif" width="720" alt="Die Seite Agenten: welche Sitzungen arbeiten, das Journal dessen, was sie geliefert haben; dann eine Nachricht an die Sitzung eines Arbeitsbereichs">
  <br><sub>Was deine Sitzungen gerade tun, und eine Nachricht an eine von ihnen, ohne Pilote zu verlassen.</sub>
</p>

Braucht eine Sitzung eine Entscheidung, erscheint ihre Frage mit den passenden Schaltflächen auf dem Startbildschirm.
Deine Antwort wartet unter **„Vos réponses, prêtes à partir“** (deine Antworten, versandbereit), bis du auf **Envoyer**
(senden) klickst: Nichts erreicht eine Sitzung versehentlich.

<p align="center">
  <img src="docs/media/facteur.gif" width="720" alt="Die Frage einer Sitzung auf dem Startbildschirm: ein Klick auf eine Antwort, dann Senden">
  <br><sub>Eine Sitzung fragt, du antwortest mit einem Klick und bestimmst selbst, wann es rausgeht.</sub>
</p>

> **Wie deine Antworten zu den Sitzungen kommen:** [`scripts/facteur.py`](scripts/facteur.py), der „Facteur“ (der Briefträger).
> Der Button **Démarrer le Facteur** auf dem Startbildschirm öffnet eine Claude-Code-Sitzung mit seinen Anweisungen: Sie
> wartet im Hintergrund und stellt jede Antwort innerhalb von Sekunden der richtigen Sitzung zu. Das ist die Sitzung, die
> gefragt hat oder der du geschrieben hast; sonst die in `facteur.sessions` in `reglages.json` genannte; sonst die aus der
> Tabelle in `EQUIPE.md`. Im Code steht keine Sitzungs-ID.

## Ein Warnhinweis

Dies ist **mein persönliches System, so veröffentlicht, wie es ist**, aber konfigurierbar gemacht: Deine Schlüssel,
deine Ordner und dein Vorname stehen in einer einzigen Einstellungsdatei (siehe „Einstellungen“), und alles, was ein
Konto oder einen Online-Dienst berührt, bleibt ausgeschaltet, bis du es einschaltest. Spuren meiner eigenen Nutzung
sind geblieben: meine Arbeitsbereiche (interner Schlüssel `kryva`, Anzeigename konfigurierbar), mein Team aus
Claude-Sitzungen, französische Beschriftungen. Alle echten Daten (Kontakte, Nachrichten, Konten, Zugangsdaten) wurden
entfernt oder durch erfundene Werte ersetzt.

Nicht enthalten: meine eigenen Organisationsskripte (Zustellung von Antworten, Beobachtung, Importe), meine Notizen und
meine Datenbank.

## Ausprobieren, ohne etwas zu verbinden: Demo-Modus

```bash
./scripts/demo.sh             # baut die App (ohne sie zu installieren) und öffnet sie mit erfundenen Daten
./scripts/demo.sh --captures  # erstellt die Screenshots unten neu (docs/captures)
./scripts/demo.sh --gif       # spielt die drei Demos ab und baut die GIFs neu (docs/media, benötigt ffmpeg)
```

Im Demo-Modus (`PILOTE_DEMO=1`) sieht Pilote statt deines Home-Ordners einen fiktiven, der bei jedem Start neu ist:
Datenbank, Claude-Sitzungen, Dateien. Es liest weder Erinnerungen, Kalender, Mail noch Spotlight, und nichts verlässt
den Rechner (E-Mail, Nachricht an eine Sitzung, Benachrichtigung, Beitrag). Screenshots und GIFs nimmt die App selbst
von ihrem eigenen Fenster auf: keine Berechtigung zur Bildschirmaufnahme nötig.

| | |
|---|---|
| ![Agenten: die Claude-Code-Sitzungen und ihr Journal](docs/captures/10-claude.png) | ![Kontakte: das Adressbuch, die Phase und die nächste Aktion](docs/captures/04-contacts.png) |
| ![Prospects: das Board nach Phasen](docs/captures/03-prospects.png) | ![Videos: die Woche, zwei Konten](docs/captures/05-semaine.png) |
| ![Aufgaben: eine Karte ziehen, um ihren Tag zu ändern](docs/captures/08-taches.png) | ![Startbildschirm im Dunkelmodus](docs/captures/01-aujourdhui-sombre.png) |

Alle Daten in den Screenshots sind erfunden (Namen, Firmen, Telefonnummern im französischen Fiktionsbereich
06 39 98 00 0x, Adressen auf `.example`).

## Installation

Du brauchst macOS 15 oder neuer, Xcode und [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
git clone https://github.com/pjksens/pilote.git && cd pilote
./scripts/tester.sh        # Unit-Tests (sie berühren weder die App noch deine Datenbank)
./scripts/construire.sh    # baut die App, installiert sie in ~/Applications und legt das Werkzeug ./pilote an
```

`construire.sh` beendet Pilote, falls es läuft, und ersetzt dann `~/Applications/Pilote.app`. Liegt dort schon eine andere App namens Pilote (mit anderer Kennung), bricht es ab und ersetzt nichts. Diese Kopie hat ihre eigene Kennung (`io.github.pjksens.pilote`) und ihren eigenen Datenordner: Sie liest und schreibt nie die Datenbank eines anderen Pilote auf demselben Mac.

**Signierung.** Das Projekt signiert lokal (`CODE_SIGN_IDENTITY: "-"`), daher fragt macOS bei jedem neuen Build erneut
nach Berechtigungen. Um sie zu behalten, trage dein Apple-Team in `project.yml` ein (`DEVELOPMENT_TEAM`,
`CODE_SIGN_IDENTITY: "Apple Development"`).

**Berechtigungen.** Ohne Einstellungen bittet Pilote macOS um nichts. Erinnerungen und Kalender werden nur angefragt,
wenn du `rappels_calendrier` einschaltest, „Mail steuern“ (Lesen und Entwürfe, nie Senden) nur, wenn du `mail`
einschaltest. Die App läuft nicht in der Sandbox: Sie liest `~/.claude`, um deinen Claude-Code-Sitzungen zu folgen.

## Einstellungen: deine Konten verbinden

Alles läuft über eine JSON-Datei: `~/Library/Application Support/io.github.pjksens.pilote/reglages.json`. Vorlage:
[`docs/reglages.exemple.json`](docs/reglages.exemple.json). Pilote liest sie neu ein, sobald sie sich ändert.
`./pilote reglages` zeigt dir, was an ist, was aus ist und was fehlt.

**Ohne diese Datei** arbeitet Pilote allein auf deinem Mac (lokale Datenbank, Kontakte, Karte, Planung,
Claude-Code-Sitzungen) und **alles andere ist aus**: kein Lesen von Erinnerungen, Kalender, Mail, Kontakten oder
Anrufen, kein Netzwerkaufruf an eine Datenbank, an Stripe oder an ein soziales Netzwerk.

Diese Datei enthält deine Schlüssel: Halte sie aus jedem Git-Repository heraus und nur für dich lesbar (`chmod 600`).
Pilote schreibt einen Schlüssel nie an eine andere Stelle.

| Einstellung | Was sie einschaltet |
|---|---|
| `prenom` | Dein Vorname in der App („Camille : rappeler…“). Standard: „Vous“ (du). |
| `espaces` | Die Anzeigenamen deiner Arbeitsbereiche (interne Schlüssel `kryva`, `freelance`, `autre`). |
| `dossiers_sessions`, `routines` | Die Ordner, die beim Öffnen einer Claude-Code-Sitzung angeboten werden, und deine Anweisungen per Klick. |
| `facteur` | Wohin der Facteur zustellt: `sessions` (Name → ID `local_…`) und `rappel` (eine Zeile, die jeder Nachricht angehängt wird). |
| `depot_suivi` | Ein Git-Repository, dessen neueste Commits Pilote anzeigt (nur lesend, kein `fetch`). |
| `rappels_calendrier: true` | Erinnerungen und Kalender (EventKit). |
| `mail: true` | Mail.app: empfangene Nachrichten, Entwürfe. |
| `entrants: true` | Der Collector `pilote entrants`: Anrufe, SMS, iMessage, WhatsApp, empfangene E-Mails. |
| `publication: true` + `dossier_secrets` | Veröffentlichen auf YouTube, Instagram, TikTok. OAuth-Clients in diesem Ordner: `pilote-google-oauth.json`, `pilote-tiktok-client.json`. Tokens im Schlüsselbund. |
| `radar: true` + `dossier_secrets` | Radar über ScrapeCreators (kostenpflichtig pro Credit): `cle-scrapecreators.env` (`SCRAPECREATORS_API_KEY=…`). |
| `domaines_interdits` | Domains, von denen Pilote keine E-Mail sendet und die es meldet, wenn es eine rausgehen sieht. |
| `comptes` | Die Anmeldungen deines Produkts und ihr Abonnement, nur lesend (unten). |
| `synchro` | Die Kontakte eines Arbeitsbereichs, ausgetauscht mit zwei entfernten Tabellen (unten). |

Das Senden von E-Mail über Gmail nutzt diese Datei nicht: Es bleibt aus, bis du ein Gmail-App-Passwort in der App
einfügst (im Schlüsselbund gespeichert).

### `comptes`: deine Anmeldungen, nur lesend

Pilote liest **eine View** über eine PostgREST-kompatible REST-API (zum Beispiel Supabase). Es kennt keine deiner
Tabellen: Die View übersetzt dein Schema. Erwartete Spalten:

| Spalte | Inhalt |
|---|---|
| `id` | Konto-ID (Text) |
| `entreprise`, `nom`, `email`, `telephone` | Text (Firma, Name, E-Mail, Telefon) |
| `inscrit_le` | Anmeldedatum (timestamptz) |
| `devis` | eine Zahl (Integer), die du neben jeder Anmeldung sehen willst |
| `abonnement_stripe` | die Stripe-ID `sub_…` oder null |
| `store_expire_le` | Ende des Apple- oder Google-Abonnements oder null |
| `actif` | Boolean oder null |

```sql
-- Beispiel, an dein Schema anzupassen.
create view pilote_comptes with (security_invoker = true) as
select o.id::text as id, o.nom as entreprise, u.nom_complet as nom, u.email, u.telephone,
       o.cree_le as inscrit_le, 0 as devis, o.abonnement_stripe, o.store_expire_le, o.actif
from organisations o left join utilisateurs u on u.organisation_id = o.id;
```

**Der Schlüssel.** Gib Pilote so wenige Rechte wie möglich: ein Token, das nur **diese View lesen** kann, zum Beispiel
eine eigene Postgres-Rolle mit nichts als `select` darauf (siehe die Dokumentation deiner Datenbank, um ein an diese
Rolle gebundenes Token zu erhalten). **Niemals den Supabase-Schlüssel `service_role` (oder „secret“)**: Er öffnet die
gesamte Datenbank, lesend und schreibend, und umgeht die Row-Level-Security. Mach die View auch nicht für die Rolle
`anon` lesbar: Der „anon“-Schlüssel ist in deinen Apps öffentlich.

**Stripe** (`stripe_cle`, optional): ein **eingeschränkter Schlüssel** (`rk_…`) mit der einzigen Berechtigung
„Subscriptions: Read“. Er unterscheidet Testphasen von zahlenden Konten; ohne ihn erscheint ein Konto mit Abonnement
als „À vérifier“ (zu prüfen).

**Zähler** (`compteur`, optional): ein eigener Befehl von dir, ausgeführt in `dossier`, der eine Zeile `ACTIFS 7 / 10`
ausgibt, dann Abschnittstitel, gefolgt von Zeilen, die mit zwei Leerzeichen eingerückt sind.

### `synchro`: deine Kontakte auf einem Telefon

Tauscht die Kontakte und den Verlauf eines Arbeitsbereichs (`espace`, Standard: der erste) mit zwei Tabellen aus
(`table_contacts`, `table_evenements`; Standard `pilote_contacts`, `pilote_evenements`), deren Spalten die von
`Synchro.colonnesContact` und `Synchro.colonnesEvenement` (`Shared/Synchro.swift`) sind. Pilote **schreibt** dort: Gib
ihm ein Token, das auf diese beiden Tabellen beschränkt ist (`select`, `insert`, `update`), niemals `service_role`.

## Claude Code verbinden

```bash
claude mcp add --scope user pilote -- "$(pwd)/pilote" mcp
```

Nach diesem Befehl geöffnete Sitzungen sehen die Pilote-Werkzeuge. Für das Journal der Agenten füge in
`~/.claude/settings.json` einen `Stop`-Hook hinzu, der `pilote journal-crochet` ausführt.

## Daten

- Datenbank: `~/Library/Application Support/io.github.pjksens.pilote/pilote.sqlite` (SQLite, WAL). Die App aktualisiert sich, sobald eine
  andere Verbindung (das Werkzeug, eine Claude-Sitzung) hineinschreibt.
- Eine andere Datenbank ausprobieren: `PILOTE_BASE=/path/test.sqlite ./pilote jour`.
- Absendername für E-Mails: `PILOTE_NOM`, sonst der vollständige Name deines macOS-Kontos.
- Einstellungen und Schlüssel: `~/Library/Application Support/io.github.pjksens.pilote/reglages.json` (siehe „Einstellungen“).
- Tägliche Sicherung: eine JSON-Kopie in iCloud Drive, Ordner `Pilote open source` (die letzten 14 bleiben), wenn iCloud Drive aktiv ist.
- Hilfe zum Werkzeug: `./pilote aide`.

## Wie es gebaut ist

Swift 5, SwiftUI, AppKit, EventKit, das SQLite3 des Systems, Security (Schlüsselbund), CryptoKit. Keine externen
Abhängigkeiten. Etwa 28.000 Zeilen Swift (ohne Tests), 425 Unit-Tests.

- `App/`: die Mac-App (Bildschirme, Integrationen für Kalender, Erinnerungen, Mail und Claude).
- `Shared/`: das Modell, die Datenbank, die Regeln (gemeinsam genutzt von App, Werkzeug und Tests).
- `CLI/`: das Werkzeug `pilote` und der MCP-Server (`pilote mcp`).
- `Tests/`: Unit-Tests auf temporären Datenbanken.

## Entwickelt von

**pjk** (Sacha Praljak). Ich baue KI-Werkzeuge und zeige sie in kurzen Videos. Pilote ist mit Claude Code gebaut.

- Website: [sachapraljak.com](https://sachapraljak.com/?utm_source=github&utm_medium=readme&utm_campaign=pilote)
- Instagram: [@sachaprljk](https://www.instagram.com/sachaprljk/)
- TikTok: [@sachaprljk](https://www.tiktok.com/@sachaprljk)

Wenn dir Pilote hilft, helfen ein ⭐ auf dem Repo und ein Follow sehr.

## Lizenz

MIT, siehe [LICENSE](LICENSE).
