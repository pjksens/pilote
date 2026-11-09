<p align="center">
  <img src="docs/media/hero.png" alt="Pilote: your clients, your projects and your Claude Code team, on one screen">
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-15%2B-black?logo=apple" alt="macOS 15+">
  <img src="https://img.shields.io/badge/Swift-SwiftUI-F05138?logo=swift&logoColor=white" alt="Swift and SwiftUI">
  <img src="https://img.shields.io/badge/Claude%20Code-MCP%20server-C2502C" alt="Works with Claude Code (MCP server)">
  <img src="https://img.shields.io/badge/data-stays%20on%20your%20Mac-0A84FF" alt="Your data stays on your Mac">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="MIT">
  <a href="../../stargazers"><img src="https://img.shields.io/github/stars/pjksens/pilote?style=flat&color=FFD60A&label=%E2%98%85%20stars" alt="Stars"></a>
</p>

<p align="center">
  <b>English</b> · <a href="README.fr.md">Français</a> · <a href="README.es.md">Español</a> · <a href="README.pt-BR.md">Português (Brasil)</a> · <a href="README.de.md">Deutsch</a> · <a href="README.it.md">Italiano</a> · <a href="README.zh-CN.md">简体中文</a> · <a href="README.ja.md">日本語</a> · <a href="README.ko.md">한국어</a>
</p>

<p align="center">
  Made by <b>pjk</b> (Sacha Praljak) ·
  <a href="https://sachapraljak.com/?utm_source=github&utm_medium=readme&utm_campaign=pilote">sachapraljak.com</a> ·
  <a href="https://www.instagram.com/sachaprljk/">Instagram</a> ·
  <a href="https://www.tiktok.com/@sachaprljk">TikTok</a>
</p>

<p align="center">
  <b>If Pilote helps you, a ⭐ helps other people find it.</b>
</p>

**Pilote is the logbook of a freelancer who works with a team of Claude Code agents.** One native Mac app for
everything that needs you: your clients and every exchange with them, the next action for each one, your reminders and
your calendar, and what your Claude Code sessions are doing right now. The sessions read and write Pilote through an
MCP server, so they keep it up to date; you only see what needs you. Everything stays on your Mac: a local SQLite
database, no server, no account.

<p align="center">
  <img src="docs/media/suivi.gif" width="720" alt="Pilote's prospects board: a click on a contact opens their card with every exchange and the next action">
  <br><sub>Demo mode (<code>./scripts/demo.sh</code>): invented data, no real people.</sub>
</p>

> The app's interface and its code comments are in French. This README exists in nine languages; the app does not (yet).

## What Pilote does

- **One screen for the day.** Appointments (Calendar), today's and overdue reminders (Reminders, tick them off), messages
  prepared by Claude waiting for your approval, follow-ups that are due, replies you received.
- **Clients with their context.** One address book per workspace, with the stage, the next action and the full thread of
  every exchange (email, text, call, visit). Before a call, you see everything that was said.
- **Claude Code plugged in.** An MCP server gives your Claude sessions tools to read and write Pilote (`jour`, `cherche`,
  `fiche`, `enregistre_contact`, `ajoute_au_fil`, `marque`, `carte`, `ou_est`, `agents`, `journal`, `note_au_journal`,
  `publications`…). The server's instructions tell them to search before creating, to invent nothing and to send nothing
  on their own.
- **Agents.** The Claude Code sessions open on your Mac, their state and their last action, and a journal of what they
  delivered (filled by a Claude Code `Stop` hook).
- **A map of your work.** Every project, its folder, its `ETAT.md` (status file), its key documents; search everything
  (⌘K) across projects, contacts, journal and files (Spotlight).
- **Email under control.** A prepared email leaves only when you click, from your Gmail (SMTP, app password kept in the
  macOS keychain, never read by Claude). Plain text, replies stay in the right thread.
- **Publishing.** Schedule videos on YouTube, Instagram and TikTok, with an explicit approval before each one goes out
  (tokens in the keychain).
- **Radar.** Watch social media accounts (views, posting rhythm, ideas), entered by hand or through a paid source that
  never runs without your confirmation.

## With Claude Code

Your sessions do the work; Pilote is where you see it and where you answer them.

<p align="center">
  <img src="docs/media/claude.gif" width="720" alt="The Agents page: which sessions are working, the journal of what they delivered; then a message written to the session of a workspace">
  <br><sub>What your sessions are doing, and a message to one of them, without leaving Pilote.</sub>
</p>

When a session needs a decision, its question shows up on the home screen with its buttons. Your answer waits in
**“Vos réponses, prêtes à partir”** (your answers, ready to go) until you click **Envoyer** (send): nothing reaches a
session by accident.

<p align="center">
  <img src="docs/media/facteur.gif" width="720" alt="A session's question on the home screen: one click on an answer, then Send">
  <br><sub>A session asks, you answer in one click, and you choose when it leaves.</sub>
</p>

> **How your answers reach the sessions:** [`scripts/facteur.py`](scripts/facteur.py), the “Facteur” (mail carrier).
> The **Démarrer le Facteur** button on the home screen opens a Claude Code session with its instructions: it waits in
> the background and hands each answer to the right session within seconds. That is the session that asked or that you
> wrote to; otherwise the one named in `facteur.sessions` in `reglages.json`; otherwise the one in the table of
> `EQUIPE.md`. No session ID is written in the code.

## A word of warning

This is **my personal system, published as is**, made configurable: your keys, your folders and your first name live in
one settings file (see “Settings”), and everything that touches an account or an online service stays off until you turn
it on. Traces of my own use remain: my workspaces (internal key `kryva`, display name configurable), my team of Claude
sessions, French labels. All real data (contacts, messages, accounts, credentials) was removed or replaced with
invented values.

Not included: my own organisation scripts (answer delivery, watch, imports), my notes and my database.

## Try it without connecting anything: demo mode

```bash
./scripts/demo.sh             # builds the app (without installing it) and opens it with invented data
./scripts/demo.sh --captures  # retakes the screenshots below (docs/captures)
./scripts/demo.sh --gif       # replays the three demos and rebuilds the GIFs (docs/media, needs ffmpeg)
```

In demo mode (`PILOTE_DEMO=1`), Pilote sees a fictional home folder, fresh at every launch, instead of yours: database,
Claude sessions, files. It reads neither Reminders, Calendar, Mail nor Spotlight, and nothing leaves (email, message to a
session, notification, post). Screenshots and GIFs are taken by the app itself, of its own window: no screen recording
permission.

| | |
|---|---|
| ![Agents: the Claude Code sessions and their journal](docs/captures/10-claude.png) | ![Contacts: the address book, the stage and the next action](docs/captures/04-contacts.png) |
| ![Prospects: the board by stage](docs/captures/03-prospects.png) | ![Videos: the week, two accounts](docs/captures/05-semaine.png) |
| ![Tasks: drag a card to change its day](docs/captures/08-taches.png) | ![Home screen in dark mode](docs/captures/01-aujourdhui-sombre.png) |

Every piece of data in the screenshots is invented (names, companies, phone numbers in the French fiction range
06 39 98 00 0x, addresses in `.example`).

## Install

You need macOS 15 or later, Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
git clone https://github.com/pjksens/pilote.git && cd pilote
./scripts/tester.sh        # unit tests (they touch neither the app nor your database)
./scripts/construire.sh    # builds the app, installs it in ~/Applications and puts the ./pilote tool in place
```

`construire.sh` quits Pilote if it is running, then replaces `~/Applications/Pilote.app`. If another app named Pilote is already there (another identifier), it stops and replaces nothing. This copy has its own identifier (`io.github.pjksens.pilote`) and its own data folder: it never reads or writes the database of another Pilote installed on the same Mac.

**Signing.** The project signs locally (`CODE_SIGN_IDENTITY: "-"`), so macOS asks for permissions again with every new
build. To keep them, put your Apple team in `project.yml` (`DEVELOPMENT_TEAM`, `CODE_SIGN_IDENTITY: "Apple Development"`).

**Permissions.** Without settings, Pilote asks macOS for nothing. Reminders and Calendars are requested only if you turn
on `rappels_calendrier`, “control Mail” (reading and drafts, never sending) only if you turn on `mail`. The app is not
sandboxed: it reads `~/.claude` to follow your Claude Code sessions.

## Settings: connect your accounts

Everything goes through one JSON file: `~/Library/Application Support/io.github.pjksens.pilote/reglages.json`. Template:
[`docs/reglages.exemple.json`](docs/reglages.exemple.json). Pilote rereads it as soon as it changes.
`./pilote reglages` tells you what is on, what is off and what is missing.

**Without this file**, Pilote works on its own on your Mac (local database, contacts, map, planning, Claude Code
sessions) and **everything else is off**: no reading of Reminders, Calendar, Mail, Contacts or calls, no network call to
a database, to Stripe or to a social network.

This file holds your keys: keep it out of any git repository and readable by you only (`chmod 600`). Pilote never writes
a key anywhere else.

| Setting | What it turns on |
|---|---|
| `prenom` | Your first name in the app (“Camille : rappeler…”). Default: “Vous” (you). |
| `espaces` | The display names of your workspaces (internal keys `kryva`, `freelance`, `autre`). |
| `dossiers_sessions`, `routines` | The folders offered when you open a Claude Code session, and your one-click instructions. |
| `facteur` | Where the Facteur delivers: `sessions` (name → `local_…` ID) and `rappel` (a line added to every message). |
| `depot_suivi` | A git repository whose recent commits Pilote shows (read only, no `fetch`). |
| `rappels_calendrier: true` | Reminders and Calendar (EventKit). |
| `mail: true` | Mail.app: received messages, drafts. |
| `entrants: true` | The `pilote entrants` collector: calls, texts, iMessage, WhatsApp, received emails. |
| `publication: true` + `dossier_secrets` | Publishing to YouTube, Instagram, TikTok. OAuth clients in that folder: `pilote-google-oauth.json`, `pilote-tiktok-client.json`. Tokens in the keychain. |
| `radar: true` + `dossier_secrets` | Radar through ScrapeCreators (paid per credit): `cle-scrapecreators.env` (`SCRAPECREATORS_API_KEY=…`). |
| `domaines_interdits` | Domains Pilote refuses to send an email from, and flags if it sees one go out. |
| `comptes` | The sign-ups of your product and their subscription, read only (below). |
| `synchro` | The contacts of one workspace, exchanged with two remote tables (below). |

Sending email through Gmail does not use this file: it stays off until you paste a Gmail app password in the app (kept in
the keychain).

### `comptes`: your sign-ups, read only

Pilote reads **one view**, through a PostgREST-compatible REST API (Supabase, for example). It knows none of your
tables: the view translates your schema. Expected columns:

| Column | Content |
|---|---|
| `id` | account id (text) |
| `entreprise`, `nom`, `email`, `telephone` | text (company, name, email, phone) |
| `inscrit_le` | sign-up date (timestamptz) |
| `devis` | a number (integer) you want to see next to each sign-up |
| `abonnement_stripe` | the Stripe `sub_…` id, or null |
| `store_expire_le` | end of the Apple or Google subscription, or null |
| `actif` | boolean, or null |

```sql
-- Example, to adapt to your schema.
create view pilote_comptes with (security_invoker = true) as
select o.id::text as id, o.nom as entreprise, u.nom_complet as nom, u.email, u.telephone,
       o.cree_le as inscrit_le, 0 as devis, o.abonnement_stripe, o.store_expire_le, o.actif
from organisations o left join utilisateurs u on u.organisation_id = o.id;
```

**The key.** Give Pilote as few rights as possible: a token that can only **read this view**, for example a dedicated
Postgres role with nothing but `select` on it (see your database's documentation to get a token tied to that role).
**Never the Supabase `service_role` (or “secret”) key**: it opens the whole database, read and write, bypassing row level
security. Do not make the view readable by the `anon` role either: the “anon” key is public in your apps.

**Stripe** (`stripe_cle`, optional): a **restricted key** (`rk_…`) with the single permission “Subscriptions: Read”. It
tells trials from paying accounts; without it, an account with a subscription shows as “À vérifier” (to check).

**Counter** (`compteur`, optional): a command of yours, run in `dossier`, that prints a line `ACTIFS 7 / 10`, then
section titles followed by lines indented by two spaces.

### `synchro`: your contacts on a phone

Exchanges the contacts and the thread of one workspace (`espace`, default: the first one) with two tables
(`table_contacts`, `table_evenements`; default `pilote_contacts`, `pilote_evenements`) whose columns are those of
`Synchro.colonnesContact` and `Synchro.colonnesEvenement` (`Shared/Synchro.swift`). Pilote **writes** there: give it a
token limited to those two tables (`select`, `insert`, `update`), never `service_role`.

## Connect Claude Code

```bash
claude mcp add --scope user pilote -- "$(pwd)/pilote" mcp
```

Sessions opened after this command see the Pilote tools. For the agents' journal, add a `Stop` hook in
`~/.claude/settings.json` that runs `pilote journal-crochet`.

## Data

- Database: `~/Library/Application Support/io.github.pjksens.pilote/pilote.sqlite` (SQLite, WAL). The app updates as soon as another
  connection (the tool, a Claude session) writes to it.
- Try another database: `PILOTE_BASE=/path/test.sqlite ./pilote jour`.
- Sender name for emails: `PILOTE_NOM`, otherwise the full name of your macOS account.
- Settings and keys: `~/Library/Application Support/io.github.pjksens.pilote/reglages.json` (see “Settings”).
- Daily backup: a JSON copy in iCloud Drive, folder `Pilote open source` (the last 14 are kept), if iCloud Drive is on.
- Tool help: `./pilote aide`.

## How it is built

Swift 5, SwiftUI, AppKit, EventKit, the system's SQLite3, Security (keychain), CryptoKit. No external dependency. About
28,000 lines of Swift (tests excluded), 425 unit tests.

- `App/`: the Mac app (screens, Calendar, Reminders, Mail and Claude integrations).
- `Shared/`: the model, the database, the rules (shared by the app, the tool and the tests).
- `CLI/`: the `pilote` tool and the MCP server (`pilote mcp`).
- `Tests/`: unit tests, on temporary databases.

## Made by

**pjk** (Sacha Praljak). I build AI tools and show them in short videos. Pilote is built with Claude Code.

- Site: [sachapraljak.com](https://sachapraljak.com/?utm_source=github&utm_medium=readme&utm_campaign=pilote)
- Instagram: [@sachaprljk](https://www.instagram.com/sachaprljk/)
- TikTok: [@sachaprljk](https://www.tiktok.com/@sachaprljk)

If Pilote helps you, a ⭐ on the repo and a follow help a lot.

## License

MIT, see [LICENSE](LICENSE).
