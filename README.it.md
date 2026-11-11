<p align="center">
  <img src="docs/media/hero.it.png" alt="Pilote: i tuoi clienti, i tuoi progetti e il tuo team di Claude Code, su un solo schermo">
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-15%2B-black?logo=apple" alt="macOS 15+">
  <img src="https://img.shields.io/badge/Swift-SwiftUI-F05138?logo=swift&logoColor=white" alt="Swift e SwiftUI">
  <img src="https://img.shields.io/badge/Claude%20Code-MCP%20server-C2502C" alt="Funziona con Claude Code (server MCP)">
  <img src="https://img.shields.io/badge/data-stays%20on%20your%20Mac-0A84FF" alt="I tuoi dati restano sul tuo Mac">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="MIT">
  <a href="../../stargazers"><img src="https://img.shields.io/github/stars/pjksens/pilote?style=flat&color=FFD60A&label=%E2%98%85%20stars" alt="Stelle"></a>
</p>

<p align="center">
  <a href="README.md">English</a> · <a href="README.fr.md">Français</a> · <a href="README.es.md">Español</a> · <a href="README.pt-BR.md">Português (Brasil)</a> · <a href="README.de.md">Deutsch</a> · <b>Italiano</b> · <a href="README.zh-CN.md">简体中文</a> · <a href="README.ja.md">日本語</a> · <a href="README.ko.md">한국어</a>
</p>

<p align="center">
  Creato da <b>pjk</b> (Sacha Praljak) ·
  <a href="https://sachapraljak.com/?utm_source=github&utm_medium=readme&utm_campaign=pilote">sachapraljak.com</a> ·
  <a href="https://www.instagram.com/sachaprljk/">Instagram</a> ·
  <a href="https://www.tiktok.com/@sachaprljk">TikTok</a>
</p>

<p align="center">
  <b>Se Pilote ti è utile, una ⭐ aiuta altre persone a trovarlo.</b>
</p>

**Pilote è il diario di bordo di un freelance che lavora con un team di agenti Claude Code.** Un'unica app nativa per
Mac per tutto ciò che ha bisogno di te: i tuoi clienti e ogni scambio con loro, la prossima azione per ciascuno, i tuoi
promemoria e il tuo calendario, e ciò che le tue sessioni di Claude Code stanno facendo in questo momento. Le sessioni
leggono e scrivono su Pilote tramite un server MCP, quindi lo tengono aggiornato; tu vedi solo ciò che ha bisogno di te.
Tutto resta sul tuo Mac: un database SQLite locale, nessun server, nessun account.

## Installare con un solo prompt

Incolla questo prompt in Claude Code (o in un altro agente di codice) sul tuo Mac. Controlla la macchina, compila e installa Pilote, ti fa una domanda alla volta per ogni connessione (puoi saltarle tutte), collega Pilote a Claude Code e chiude con un riepilogo di ciò che è collegato. Le tue chiavi non passano mai dalla chat. Lo stesso testo è in [`docs/INSTALL-PROMPT.md`](docs/INSTALL-PROMPT.md); per farlo a mano, vedi «Installazione» più sotto. Il prompt resta in inglese.

````text
You are going to install Pilote (a native Mac app + a command-line tool + an MCP server for Claude Code) on this Mac, then
connect it, asking me for what you need. Repository: https://github.com/pjksens/pilote . Work in English unless I write
to you in another language, then answer in mine.

GROUND RULES
- Ask me ONE question at a time and wait for my answer. Every connection is optional: if I say "skip" (or "no", or
  "later"), move on and leave it off.
- Before each connection, say in ONE sentence what it is for. Never turn anything on that I did not say yes to.
- Never ask me to paste an API key, token or password in this chat, never print one, never read a secret file back to me
  (no cat, no echo, no logging). To enter a key: create the file with permissions 600 and an empty placeholder, open it in
  an editor for me (`open -e <file>`), tell me exactly where to paste, wait for "done", then check it is not empty
  WITHOUT displaying it. If I paste a secret in the chat anyway, use it, never repeat it, and tell me once that it is now
  in this conversation's history, so I may want to rotate it later.
- Secrets never go inside the git repository. Never commit, never push, never change the repository.
- If a command fails, show me the last 20 lines of its output, say what you think went wrong, and stop and ask before
  trying something else. Do not invent results: if you did not check it, say you did not.

STEP 1. CHECK THE MACHINE
1. `sw_vers -productVersion` must be 15 or later.
2. `xcodebuild -version` must work (full Xcode, not only the command-line tools). If it does not: tell me to install
   Xcode from the App Store, open it once to accept the license, and stop until I say it is done.
3. `xcodegen --version`. If missing, check `brew --version`: if Homebrew exists, propose `brew install xcodegen` and run
   it only after I say yes. If Homebrew is missing, tell me to install it from https://brew.sh, and stop until I say it
   is done (do not run its install script yourself).
4. `git --version` must work.
Tell me in one line what you found.

STEP 2. GET THE CODE AND BUILD
1. Ask me where to put the code. Default: ~/pilote . Moving that folder later breaks the connection to Claude Code, so
   pick a place that stays. If the folder exists and is not a clone of pjksens/pilote, propose another name.
2. `git clone https://github.com/pjksens/pilote.git <folder>` then `cd <folder>`.
3. Warn me, in one sentence, that the next script quits Pilote if it is running and replaces ~/Applications/Pilote.app
   (it stops if another app named Pilote with a different identifier is there). Then run `./scripts/construire.sh`.
   It takes a few minutes. It installs ~/Applications/Pilote.app and puts the `pilote` tool in <folder>.
4. Check that ~/Applications/Pilote.app and <folder>/pilote exist.

STEP 3. SETTINGS (connections)
Pilote reads ONE file: ~/Library/Application Support/io.github.pjksens.pilote/reglages.json (the template is
docs/reglages.exemple.json). Without it, everything that touches an account or a network is off. Keep my answers in
memory and write the file once at the end of this step: `mkdir -p` its folder, then write it with `chmod 600`. Only
write the keys of the connections I accepted. If the file already exists, read it first and merge, never overwrite my
existing values.

Ask these questions, in this order, one at a time:
a. First name ("prenom"). Used in the app ("Camille: call back..."). Default "Vous". Then, optionally, the display
   names of my workspaces ("espaces": internal keys kryva, freelance, autre).
b. Reminders and Calendar ("rappels_calendrier": true): shows today's appointments and reminders. macOS will ask its
   permission the first time the app opens.
c. Mail.app ("mail": true): lets Pilote read received messages and create drafts. It never sends anything on its own.
d. Incoming messages ("entrants": true): the `pilote entrants` collector reads calls, texts, iMessage, WhatsApp and
   received emails on this Mac to log them in the right contact's thread. macOS may ask for extra permissions.
e. A git repository to follow ("depot_suivi": a path): the app shows its latest commits, read only.
f. Secrets folder ("dossier_secrets"). Only ask it if I accept g or h. Default ~/Secrets . Create it with chmod 700 if
   missing. It must not be inside a git repository or a synced folder (iCloud Drive, Dropbox).
g. Publishing to YouTube, Instagram and TikTok ("publication": true, needs the secrets folder). Each post waits for my
   explicit approval in the app before it goes out. Ask which of the two clients I have:
   - Google/YouTube: I need an OAuth client of type "Desktop app" from the Google Cloud console (YouTube Data API v3
     enabled), downloaded as client_secret_....json into ~/Downloads. When I tell you it is there, move the newest one
     to <dossier_secrets>/pilote-google-oauth.json and chmod 600 it (do not open it).
   - TikTok: I need the app's "Client key" and "Client secret" from the TikTok developer portal. Ask me for the Client
     key in the chat (it is public), and tell me to COPY the Client secret to the clipboard (do not paste it in the
     chat). Then run `./pilote publication client-tiktok --cle <Client key>` from the code folder: it reads the secret
     from the clipboard, stores it in <dossier_secrets>/pilote-tiktok-client.json and clears the clipboard.
   Instagram needs nothing here. The accounts themselves are connected afterwards in the app (Pilote > Publications,
   "Connecter"), tokens go to the macOS keychain. Tell me that last part.
h. Radar ("radar": true, needs the secrets folder): watches public numbers of social accounts through ScrapeCreators,
   a paid service billed per credit, and it never runs without my confirmation. If I have a key: create
   <dossier_secrets>/cle-scrapecreators.env containing the single line `SCRAPECREATORS_API_KEY=` , chmod 600, open it for
   me to paste the key after the "=".
i. Sign-ups of my own product ("comptes"): Pilote reads ONE view of a PostgREST/Supabase database, read only, to show
   who signed up and who pays. Only for people who have a product with accounts. If yes: ask for the project URL and
   the view name (default pilote_comptes), and point me to the "comptes" section of the README for the SQL view. The key
   must be a token that can ONLY read that view, NEVER a Supabase service_role / secret key: say it, and refuse one if I
   offer it. Optional: a Stripe restricted key (rk_..., "Subscriptions: Read" only). These keys ("comptes.cle",
   "comptes.stripe_cle") are read by Pilote inside reglages.json itself: write them as empty strings, then open
   reglages.json for me to paste each key between the quotes (do not retype the quotes), and validate the JSON after.
j. Contact sync with a phone ("synchro"): exchanges one workspace's contacts with two remote tables. Same rule for its
   key ("synchro.cle": a token limited to those two tables, never service_role), same editor procedure. Skip if unsure.
k. Forbidden sender domains ("domaines_interdits": a list): Pilote refuses to send an email from them. Only if I name some.
l. Gmail sending is NOT in this file: it is enabled inside the app by pasting a Gmail app password (kept in the macOS
   keychain). Tell me where to do it in the app and move on. Do not ask for the password.

When the file is written, run `<folder>/pilote reglages` and show me its output: it lists what is on and what is off.
Careful: that command says "actif" as soon as a block exists (for example "comptes" with an empty key), so do not call a
connection working unless its key file or key is really filled in (check the size or the emptiness, never the content).

STEP 4. CONNECT MY AGENT
1. Claude Code. Check `claude --version`. Run `claude mcp list`: if a server named "pilote" is already there, tell me
   what it points to and ask before replacing it. Then run, with the ABSOLUTE path:
   `claude mcp add --scope user pilote -- <folder>/pilote mcp`
   and check `claude mcp list` shows pilote as connected.
2. Optional, ask me first: a journal of what my sessions deliver. It needs a "Stop" hook in ~/.claude/settings.json
   that runs `<folder>/pilote journal-crochet`. If I say yes, show me the exact change, merge it into the existing JSON
   without touching anything else (create the file if missing), and validate the JSON afterwards.
3. Any other agent that supports MCP (Cursor, Codex, Gemini CLI, Windsurf...): Pilote is a plain stdio MCP server. Add a
   server named "pilote" with command `<folder>/pilote` and the single argument `mcp`, using that agent's own way of
   adding MCP servers (usually a JSON file with "mcpServers": {"pilote": {"command": "...", "args": ["mcp"]}}). If you
   are not sure how my agent does it, say so instead of guessing.

STEP 5. CHECK AND OPEN
1. Run `<folder>/pilote jour` and confirm it answers without error (an empty day is normal on a fresh install).
2. Run `open ~/Applications/Pilote.app`. Tell me the app is open and to accept the macOS permission prompts for the
   connections I turned on.

STEP 6. RECAP
Finish with a short table with three groups: CONNECTED (what you checked, and how), NOT CONNECTED (what I skipped, and
the one setting that turns it on later), and TO DO BY HAND (Gmail app password in the app; connecting each social
account in Pilote > Publications; the OAuth/TikTok steps I still owe; macOS permission prompts). Add that sessions opened
BEFORE this install do not see the Pilote tools: I must start a new Claude Code session (or restart my agent) to use
them. For each item, only write what you actually verified.
````

<p align="center">
  <img src="docs/media/suivi.gif" width="720" alt="La bacheca dei prospect di Pilote: un clic su un contatto apre la sua scheda con ogni scambio e la prossima azione">
  <br><sub>Modalità demo (<code>./scripts/demo.sh</code>): dati inventati, nessuna persona reale.</sub>
</p>

> L'interfaccia dell'app segue la lingua del tuo Mac: inglese, francese o spagnolo (inglese per qualsiasi altra lingua). I commenti del codice, lo strumento da riga di comando `pilote` e il server MCP restano in francese. Questo README esiste in nove lingue.

## Cosa fa Pilote

- **Uno schermo per la giornata.** Appuntamenti (Calendario), promemoria di oggi e in ritardo (Promemoria, li spunti),
  messaggi preparati da Claude in attesa della tua approvazione, follow-up in scadenza, risposte ricevute.
- **Clienti con il loro contesto.** Una rubrica per ogni spazio di lavoro, con la fase, la prossima azione e l'intero
  filo di ogni scambio (e-mail, SMS, chiamata, visita). Prima di una chiamata, vedi tutto ciò che è stato detto.
- **Claude Code collegato.** Un server MCP dà alle tue sessioni di Claude strumenti per leggere e scrivere su Pilote
  (`jour`, `cherche`, `fiche`, `enregistre_contact`, `ajoute_au_fil`, `marque`, `carte`, `ou_est`, `agents`, `journal`,
  `note_au_journal`, `publications`…). Le istruzioni del server dicono loro di cercare prima di creare, di non inventare
  nulla e di non inviare nulla di propria iniziativa.
- **Agenti.** Le sessioni di Claude Code aperte sul tuo Mac, il loro stato e la loro ultima azione, e un diario di ciò
  che hanno consegnato (compilato da un hook `Stop` di Claude Code).
- **Una mappa del tuo lavoro.** Ogni progetto, la sua cartella, il suo `ETAT.md` (file di stato), i suoi documenti
  chiave; cerca in tutto (⌘K) tra progetti, contatti, diario e file (Spotlight).
- **E-mail sotto controllo.** Un'e-mail preparata parte solo quando fai clic, dal tuo Gmail (SMTP, password per app
  conservata nel portachiavi di macOS, mai letta da Claude). Testo semplice, e le risposte restano nel thread giusto.
- **Pip, facoltativo.** Se [Pip](https://github.com/pjksens/heypip) (un'app per il notch del Mac che segue le chiamate) è installata, su una videochiamata del tuo calendario compare un pulsante “Launch Pip”: Pip si apre con il nome della chiamata e il contatto collegato. In via facoltativa Pilote lo apre da solo due minuti prima. Pip registra solo dopo un tuo clic e, quando Claude ha scritto il riassunto della chiamata, Pilote lo archivia nella cronologia del contatto. Legge il tuo calendario, quindi segue `rappels_calendrier`, disattivato per impostazione predefinita.
- **Pubblicazione.** Programma video su YouTube, Instagram e TikTok, con un'approvazione esplicita prima che ciascuno
  esca (token nel portachiavi).
- **Radar.** Tieni d'occhio account di social media (visualizzazioni, ritmo di pubblicazione, idee), inseriti a mano o
  tramite una fonte a pagamento che non parte mai senza la tua conferma.

## Con Claude Code

Le tue sessioni fanno il lavoro; Pilote è il posto dove lo vedi e dove rispondi loro.

<p align="center">
  <img src="docs/media/claude.gif" width="720" alt="La pagina Agenti: quali sessioni stanno lavorando, il diario di ciò che hanno consegnato; poi un messaggio scritto alla sessione di uno spazio di lavoro">
  <br><sub>Cosa stanno facendo le tue sessioni, e un messaggio a una di loro, senza uscire da Pilote.</sub>
</p>

Quando una sessione ha bisogno di una decisione, la sua domanda compare nella schermata iniziale con i suoi pulsanti. La
tua risposta aspetta in **“Your replies, ready to go”** (le tue risposte, pronte a partire) finché non fai clic su
**Send** (invia): niente arriva a una sessione per caso.

<p align="center">
  <img src="docs/media/facteur.gif" width="720" alt="La domanda di una sessione nella schermata iniziale: un clic su una risposta, poi Invia">
  <br><sub>Una sessione chiede, tu rispondi con un clic e scegli quando parte.</sub>
</p>

> **Come le tue risposte arrivano alle sessioni:** [`scripts/facteur.py`](scripts/facteur.py), il “Facteur” (il postino).
> Il pulsante **Start Facteur** nella schermata iniziale apre una sessione di Claude Code con le sue istruzioni:
> resta in attesa in background e consegna ogni risposta alla sessione giusta in pochi secondi. È la sessione che ha fatto
> la domanda o a cui hai scritto; altrimenti quella indicata in `facteur.sessions` di `reglages.json`; altrimenti quella
> della tabella di `EQUIPE.md`. Nessun identificativo di sessione è scritto nel codice.

## Un avvertimento

Questo è **il mio sistema personale, pubblicato così com'è**, reso configurabile: le tue chiavi, le tue cartelle e il tuo
nome stanno in un unico file di impostazioni (vedi “Impostazioni”), e tutto ciò che tocca un account o un servizio
online resta spento finché non lo accendi. Restano tracce del mio uso: i miei spazi di lavoro (chiave interna `kryva`,
nome visualizzato configurabile), il mio team di sessioni di Claude, etichette in francese. Tutti i dati reali (contatti,
messaggi, account, credenziali) sono stati rimossi o sostituiti con valori inventati.

Non inclusi: i miei script di organizzazione (consegna delle risposte, monitoraggio, importazioni), le mie note e il mio
database.

## Provalo senza collegare nulla: modalità demo

```bash
./scripts/demo.sh             # compila l'app (senza installarla) e la apre con dati inventati
./scripts/demo.sh --captures  # rifà gli screenshot qui sotto (docs/captures)
./scripts/demo.sh --gif       # riproduce le tre demo e ricostruisce le GIF (docs/media, richiede ffmpeg)
```

In modalità demo (`PILOTE_DEMO=1`), Pilote vede una cartella home fittizia, nuova a ogni avvio, al posto della tua:
database, sessioni di Claude, file. Non legge Promemoria, Calendario, Mail né Spotlight, e nulla esce (e-mail,
messaggio a una sessione, notifica, post). Gli screenshot e le GIF li fa l'app stessa, della propria finestra: nessun
permesso di registrazione dello schermo.

| | |
|---|---|
| ![Agenti: le sessioni di Claude Code e il loro diario](docs/captures/09-claude.png) | ![Contatti: la rubrica, la fase e la prossima azione](docs/captures/04-contacts.png) |
| ![Prospect: la bacheca per fase](docs/captures/03-prospects.png) | ![Video: la settimana, due account](docs/captures/05-semaine.png) |
| ![Attività: trascina una scheda per cambiarne il giorno](docs/captures/07-taches.png) | ![Schermata iniziale in modalità scura](docs/captures/01-aujourdhui-sombre.png) |

Ogni dato negli screenshot è inventato (nomi, aziende, numeri di telefono nell'intervallo di finzione francese
06 39 98 00 0x, indirizzi in `.example`).

## Installazione

Ti servono macOS 15 o successivo, Xcode e [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
git clone https://github.com/pjksens/pilote.git && cd pilote
./scripts/tester.sh        # test unitari (non toccano né l'app né il tuo database)
./scripts/construire.sh    # compila l'app, la installa in ~/Applications e mette a posto lo strumento ./pilote
```

`construire.sh` chiude Pilote se è in esecuzione, poi sostituisce `~/Applications/Pilote.app`. Se c'è già un'altra app chiamata Pilote (con un altro identificatore), si ferma senza sostituire nulla. Questa copia ha il suo identificatore (`io.github.pjksens.pilote`) e la sua cartella di dati: non legge né scrive mai il database di un altro Pilote installato sullo stesso Mac.

**Firma.** Il progetto firma in locale (`CODE_SIGN_IDENTITY: "-"`), quindi macOS chiede di nuovo i permessi a ogni nuova
build. Per mantenerli, inserisci il tuo team Apple in `project.yml` (`DEVELOPMENT_TEAM`,
`CODE_SIGN_IDENTITY: "Apple Development"`).

**Permessi.** Senza impostazioni, Pilote non chiede nulla a macOS. Promemoria e Calendari vengono richiesti solo se
attivi `rappels_calendrier`, “controllare Mail” (lettura e bozze, mai invio) solo se attivi `mail`. L'app non è in
sandbox: legge `~/.claude` per seguire le tue sessioni di Claude Code.

## Impostazioni: collega i tuoi account

Tutto passa da un unico file JSON: `~/Library/Application Support/io.github.pjksens.pilote/reglages.json`. Modello:
[`docs/reglages.exemple.json`](docs/reglages.exemple.json). Pilote lo rilegge non appena cambia.
`./pilote reglages` ti dice cosa è acceso, cosa è spento e cosa manca.

**Senza questo file**, Pilote funziona da solo sul tuo Mac (database locale, contatti, mappa, pianificazione, sessioni
di Claude Code) e **tutto il resto è spento**: nessuna lettura di Promemoria, Calendario, Mail, Contatti o chiamate,
nessuna chiamata di rete a un database, a Stripe o a un social network.

Questo file contiene le tue chiavi: tienilo fuori da qualsiasi repository git e leggibile solo da te (`chmod 600`).
Pilote non scrive mai una chiave altrove.

| Impostazione | Cosa attiva |
|---|---|
| `prenom` | Il tuo nome nell'app (“Camille : rappeler…”). Predefinito: “Vous” (tu). |
| `espaces` | I nomi visualizzati dei tuoi spazi di lavoro (chiavi interne `kryva`, `freelance`, `autre`). |
| `dossiers_sessions`, `routines` | Le cartelle proposte quando apri una sessione di Claude Code, e le tue istruzioni con un clic. |
| `facteur` | Dove consegna il Facteur: `sessions` (nome → ID `local_…`) e `rappel` (una riga aggiunta a ogni messaggio). |
| `depot_suivi` | Un repository git di cui Pilote mostra i commit recenti (sola lettura, nessun `fetch`). |
| `rappels_calendrier: true` | Promemoria e Calendario (EventKit). |
| `mail: true` | Mail.app: messaggi ricevuti, bozze. |
| `entrants: true` | Il collettore `pilote entrants`: chiamate, SMS, iMessage, WhatsApp, e-mail ricevute. |
| `publication: true` + `dossier_secrets` | Pubblicazione su YouTube, Instagram, TikTok. Client OAuth in quella cartella: `pilote-google-oauth.json`, `pilote-tiktok-client.json`. Token nel portachiavi. |
| `radar: true` + `dossier_secrets` | Radar tramite ScrapeCreators (a pagamento per credito): `cle-scrapecreators.env` (`SCRAPECREATORS_API_KEY=…`). |
| `domaines_interdits` | Domini da cui Pilote rifiuta di inviare un'e-mail, e che segnala se ne vede uscire una. |
| `comptes` | Le iscrizioni al tuo prodotto e il loro abbonamento, sola lettura (sotto). |
| `synchro` | I contatti di uno spazio di lavoro, scambiati con due tabelle remote (sotto). |

L'invio di e-mail tramite Gmail non usa questo file: resta spento finché non incolli una password per app di Gmail
nell'app (conservata nel portachiavi).

### `comptes`: le tue iscrizioni, sola lettura

Pilote legge **una vista**, tramite un'API REST compatibile con PostgREST (per esempio Supabase). Non conosce nessuna
delle tue tabelle: la vista traduce il tuo schema. Colonne attese:

| Colonna | Contenuto |
|---|---|
| `id` | id dell'account (testo) |
| `entreprise`, `nom`, `email`, `telephone` | testo (azienda, nome, e-mail, telefono) |
| `inscrit_le` | data di iscrizione (timestamptz) |
| `devis` | un numero (intero) che vuoi vedere accanto a ogni iscrizione |
| `abonnement_stripe` | l'id Stripe `sub_…`, oppure null |
| `store_expire_le` | fine dell'abbonamento Apple o Google, oppure null |
| `actif` | booleano, oppure null |

```sql
-- Esempio, da adattare al tuo schema.
create view pilote_comptes with (security_invoker = true) as
select o.id::text as id, o.nom as entreprise, u.nom_complet as nom, u.email, u.telephone,
       o.cree_le as inscrit_le, 0 as devis, o.abonnement_stripe, o.store_expire_le, o.actif
from organisations o left join utilisateurs u on u.organisation_id = o.id;
```

**La chiave.** Dai a Pilote il minimo dei diritti possibili: un token che possa solo **leggere questa vista**, per
esempio un ruolo Postgres dedicato con nient'altro che `select` su di essa (consulta la documentazione del tuo database
per ottenere un token legato a quel ruolo). **Mai la chiave `service_role` (o “secret”) di Supabase**: apre l'intero
database, in lettura e scrittura, aggirando la row level security. Non rendere la vista leggibile nemmeno dal ruolo
`anon`: la chiave “anon” è pubblica nelle tue app.

**Stripe** (`stripe_cle`, facoltativo): una **chiave con restrizioni** (`rk_…`) con la sola autorizzazione
“Subscriptions: Read”. Distingue le prove dagli account paganti; senza di essa, un account con un abbonamento compare
come “To check” (da verificare).

**Contatore** (`compteur`, facoltativo): un tuo comando, eseguito in `dossier`, che stampa una riga `ACTIFS 7 / 10`, poi
titoli di sezione seguiti da righe rientrate di due spazi.

### `synchro`: i tuoi contatti su un telefono

Scambia i contatti e il filo di uno spazio di lavoro (`espace`, predefinito: il primo) con due tabelle
(`table_contacts`, `table_evenements`; predefinite `pilote_contacts`, `pilote_evenements`) le cui colonne sono quelle di
`Synchro.colonnesContact` e `Synchro.colonnesEvenement` (`Shared/Synchro.swift`). Pilote **scrive** lì: dagli un token
limitato a quelle due tabelle (`select`, `insert`, `update`), mai `service_role`.

## Collegare Claude Code

```bash
claude mcp add --scope user pilote -- "$(pwd)/pilote" mcp
```

Le sessioni aperte dopo questo comando vedono gli strumenti di Pilote. Per il diario degli agenti, aggiungi un hook
`Stop` in `~/.claude/settings.json` che esegua `pilote journal-crochet`.

## Dati

- Database: `~/Library/Application Support/io.github.pjksens.pilote/pilote.sqlite` (SQLite, WAL). L'app si aggiorna non appena un'altra
  connessione (lo strumento, una sessione di Claude) vi scrive.
- Provare un altro database: `PILOTE_BASE=/path/test.sqlite ./pilote jour`.
- Nome del mittente delle e-mail: `PILOTE_NOM`, altrimenti il nome completo del tuo account macOS.
- Impostazioni e chiavi: `~/Library/Application Support/io.github.pjksens.pilote/reglages.json` (vedi “Impostazioni”).
- Backup giornaliero: una copia JSON in iCloud Drive, cartella `Pilote open source` (si tengono le ultime 14), se iCloud Drive è attivo.
- Aiuto dello strumento: `./pilote aide`.

## Come è costruito

Swift 5, SwiftUI, AppKit, EventKit, l'SQLite3 di sistema, Security (portachiavi), CryptoKit. Nessuna dipendenza esterna.
Circa 28.000 righe di Swift (test esclusi), 425 test unitari.

- `App/`: l'app per Mac (schermate, integrazioni con Calendario, Promemoria, Mail e Claude).
- `Shared/`: il modello, il database, le regole (condivisi da app, strumento e test).
- `CLI/`: lo strumento `pilote` e il server MCP (`pilote mcp`).
- `Tests/`: test unitari, su database temporanei.

## Creato da

**pjk** (Sacha Praljak). Costruisco strumenti di IA e li mostro in brevi video. Pilote è costruito con Claude Code.

- Sito: [sachapraljak.com](https://sachapraljak.com/?utm_source=github&utm_medium=readme&utm_campaign=pilote)
- Instagram: [@sachaprljk](https://www.instagram.com/sachaprljk/)
- TikTok: [@sachaprljk](https://www.tiktok.com/@sachaprljk)

Se Pilote ti è utile, una ⭐ sul repo e un follow aiutano molto.

## Licenza

MIT, vedi [LICENSE](LICENSE).
