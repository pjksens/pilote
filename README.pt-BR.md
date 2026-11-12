<p align="center">
  <img src="docs/media/hero.pt-BR.png" alt="Pilote: seus clientes, seus projetos e sua equipe do Claude Code, em uma só tela">
</p>

<p align="center">
  <a href="https://www.youtube.com/shorts/5psKMdVdgjM"><img src="docs/media/film.jpg" width="300" alt="Filme do Pilote, assistir no YouTube"></a><br>
  <a href="https://www.youtube.com/shorts/5psKMdVdgjM">▶ Assistir ao filme (51 s)</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-15%2B-black?logo=apple" alt="macOS 15+">
  <img src="https://img.shields.io/badge/Swift-SwiftUI-F05138?logo=swift&logoColor=white" alt="Swift e SwiftUI">
  <img src="https://img.shields.io/badge/Claude%20Code-MCP%20server-C2502C" alt="Funciona com o Claude Code (servidor MCP)">
  <img src="https://img.shields.io/badge/data-stays%20on%20your%20Mac-0A84FF" alt="Seus dados ficam no seu Mac">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="MIT">
  <a href="../../stargazers"><img src="https://img.shields.io/github/stars/pjksens/pilote?style=flat&color=FFD60A&label=%E2%98%85%20stars" alt="Estrelas"></a>
</p>

<p align="center">
  <a href="README.md">English</a> · <a href="README.fr.md">Français</a> · <a href="README.es.md">Español</a> · <b>Português (Brasil)</b> · <a href="README.de.md">Deutsch</a> · <a href="README.it.md">Italiano</a> · <a href="README.zh-CN.md">简体中文</a> · <a href="README.ja.md">日本語</a> · <a href="README.ko.md">한국어</a>
</p>

<p align="center">
  Feito por <b>pjk</b> (Sacha Praljak) ·
  <a href="https://sachapraljak.com/?utm_source=github&utm_medium=readme&utm_campaign=pilote">sachapraljak.com</a> ·
  <a href="https://www.instagram.com/sachaprljk/">Instagram</a> ·
  <a href="https://www.tiktok.com/@sachaprljk">TikTok</a>
</p>

<p align="center">
  <b>Se o Pilote ajuda você, uma ⭐ ajuda outras pessoas a encontrá-lo.</b>
</p>

**O Pilote é o diário de bordo de um freelancer que trabalha com uma equipe de agentes do Claude Code.** Um único app
nativo para Mac com tudo o que precisa de você: seus clientes e cada conversa com eles, a próxima ação de cada um, seus
lembretes e sua agenda, e o que suas sessões do Claude Code estão fazendo agora mesmo. As sessões leem e escrevem no
Pilote por meio de um servidor MCP, então elas o mantêm atualizado; você só vê o que precisa de você. Tudo fica no seu
Mac: um banco de dados SQLite local, sem servidor, sem conta.

## Instalar com um único prompt

Cole este prompt no Claude Code (ou em qualquer agente de código) no seu Mac. Ele verifica sua máquina, compila e instala o Pilote, faz uma pergunta de cada vez para cada conexão (você pode pular todas), conecta o Pilote ao Claude Code e termina com um resumo do que está conectado. Suas chaves nunca passam pelo chat. O mesmo texto está em [`docs/INSTALL-PROMPT.md`](docs/INSTALL-PROMPT.md); para fazer à mão, veja «Instalação» mais abaixo. O prompt continua em inglês.

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
  <img src="docs/media/suivi.gif" width="720" alt="O quadro de prospects do Pilote: um clique em um contato abre a ficha dele com todas as conversas e a próxima ação">
  <br><sub>Modo demo (<code>./scripts/demo.sh</code>): dados inventados, nenhuma pessoa real.</sub>
</p>

> A interface do app segue o idioma do seu Mac: inglês, francês ou espanhol (inglês para qualquer outro idioma). Os comentários do código, a ferramenta de linha de comando `pilote` e o servidor MCP continuam em francês. Este README existe em nove idiomas.

## O que o Pilote faz

- **Uma tela para o dia.** Compromissos (Calendário), lembretes de hoje e atrasados (Lembretes, você os marca como
  feitos), mensagens preparadas pelo Claude aguardando sua aprovação, acompanhamentos que vencem, respostas recebidas.
- **Clientes com o seu contexto.** Uma agenda de contatos por espaço de trabalho, com a etapa, a próxima ação e todo o
  histórico de conversas (e-mail, mensagem de texto, ligação, visita). Antes de uma ligação, você vê tudo o que foi dito.
- **Claude Code conectado.** Um servidor MCP dá às suas sessões do Claude ferramentas para ler e escrever no Pilote
  (`jour`, `cherche`, `fiche`, `enregistre_contact`, `ajoute_au_fil`, `marque`, `carte`, `ou_est`, `agents`, `journal`,
  `note_au_journal`, `publications`…). As instruções do servidor mandam que elas busquem antes de criar, não inventem
  nada e não enviem nada por conta própria.
- **Agentes.** As sessões do Claude Code abertas no seu Mac, o estado delas e a última ação, e um diário do que
  entregaram (preenchido por um hook `Stop` do Claude Code).
- **Um mapa do seu trabalho.** Cada projeto, sua pasta, seu `ETAT.md` (arquivo de status), seus documentos principais;
  busque em tudo (⌘K) entre projetos, contatos, diário e arquivos (Spotlight).
- **E-mail sob controle.** Um e-mail preparado só sai quando você clica, a partir do seu Gmail (SMTP, senha de app
  guardada no chaveiro do macOS, nunca lida pelo Claude). Texto simples, e as respostas ficam na conversa certa.
- **Pip, opcional.** Se o [Pip](https://github.com/pjksens/heypip) (um app de notch para Mac que acompanha chamadas) estiver instalado, aparece um botão “Launch Pip” numa videochamada da sua agenda: o Pip abre com o nome da chamada e o contato vinculado. Opcionalmente, o Pilote o abre sozinho dois minutos antes. O Pip só grava depois do seu próprio clique e, quando o Claude escreve o resumo da chamada, o Pilote o arquiva no histórico do contato. Ele lê a sua agenda, então segue `rappels_calendrier`, desligado por padrão.
- **Publicação.** Agende vídeos no YouTube, Instagram e TikTok, com uma aprovação explícita antes de cada um sair
  (tokens no chaveiro).
- **Radar.** Acompanhe contas de redes sociais (visualizações, ritmo de postagem, ideias), inseridas à mão ou por meio
  de uma fonte paga que nunca roda sem a sua confirmação.

## Com o Claude Code

Suas sessões fazem o trabalho; o Pilote é onde você o vê e onde você responde a elas.

<p align="center">
  <img src="docs/media/claude.gif" width="720" alt="A página Agentes: quais sessões estão trabalhando, o diário do que entregaram; depois, uma mensagem escrita para a sessão de um espaço de trabalho">
  <br><sub>O que suas sessões estão fazendo, e uma mensagem para uma delas, sem sair do Pilote.</sub>
</p>

Quando uma sessão precisa de uma decisão, a pergunta dela aparece na tela inicial com seus botões. Sua resposta espera em
**“Your replies, ready to go”** (suas respostas, prontas para sair) até você clicar em **Send** (enviar): nada
chega a uma sessão por acidente.

<p align="center">
  <img src="docs/media/facteur.gif" width="720" alt="A pergunta de uma sessão na tela inicial: um clique em uma resposta e depois Enviar">
  <br><sub>Uma sessão pergunta, você responde com um clique e escolhe quando sai.</sub>
</p>

> **Como suas respostas chegam às sessões:** [`scripts/facteur.py`](scripts/facteur.py), o “Facteur” (o carteiro).
> O botão **Start Facteur** da tela inicial abre uma sessão do Claude Code com as instruções dele: ela espera em
> segundo plano e entrega cada resposta à sessão certa em poucos segundos. É a sessão que fez a pergunta ou para a qual
> você escreveu; se não, a indicada em `facteur.sessions` no `reglages.json`; se não, a da tabela do `EQUIPE.md`.
> Nenhum identificador de sessão está escrito no código.

## Um aviso

Este é o **meu sistema pessoal, publicado como está**, tornado configurável: suas chaves, suas pastas e seu primeiro
nome ficam em um único arquivo de configurações (veja “Configurações”), e tudo o que toca uma conta ou um serviço online
permanece desligado até você ligar. Restam vestígios do meu próprio uso: meus espaços de trabalho (chave interna
`kryva`, nome de exibição configurável), minha equipe de sessões do Claude, rótulos em francês. Todos os dados reais
(contatos, mensagens, contas, credenciais) foram removidos ou substituídos por valores inventados.

Não incluídos: meus próprios scripts de organização (entrega de respostas, monitoramento, importações), minhas notas e
meu banco de dados.

## Experimente sem conectar nada: modo demo

```bash
./scripts/demo.sh             # compila o app (sem instalá-lo) e o abre com dados inventados
./scripts/demo.sh --captures  # refaz as capturas de tela abaixo (docs/captures)
./scripts/demo.sh --gif       # reproduz as três demos e refaz os GIFs (docs/media, requer ffmpeg)
```

No modo demo (`PILOTE_DEMO=1`), o Pilote enxerga uma pasta pessoal fictícia, nova a cada abertura, no lugar da sua:
banco de dados, sessões do Claude, arquivos. Ele não lê Lembretes, Calendário, Mail nem Spotlight, e nada sai (e-mail,
mensagem para uma sessão, notificação, postagem). As capturas de tela e os GIFs são feitos pelo próprio app, da sua
própria janela: sem permissão de gravação de tela.

| | |
|---|---|
| ![Agentes: as sessões do Claude Code e o diário delas](docs/captures/09-claude.png) | ![Contatos: a agenda de contatos, a etapa e a próxima ação](docs/captures/04-contacts.png) |
| ![Prospects: o quadro por etapa](docs/captures/03-prospects.png) | ![Vídeos: a semana, duas contas](docs/captures/05-semaine.png) |
| ![Tarefas: arraste um cartão para mudar o dia dele](docs/captures/07-taches.png) | ![Tela inicial no modo escuro](docs/captures/01-aujourdhui-sombre.png) |

Todos os dados das capturas de tela são inventados (nomes, empresas, números de telefone na faixa de ficção francesa
06 39 98 00 0x, endereços em `.example`).

## Instalação

Você precisa do macOS 15 ou posterior, do Xcode e do [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
git clone https://github.com/pjksens/pilote.git && cd pilote
./scripts/tester.sh        # testes unitários (não tocam no app nem no seu banco de dados)
./scripts/construire.sh    # compila o app, instala em ~/Applications e coloca a ferramenta ./pilote no lugar
```

O `construire.sh` fecha o Pilote se ele estiver rodando e depois substitui `~/Applications/Pilote.app`. Se já houver outro app chamado Pilote (com outro identificador), ele para sem substituir nada. Esta cópia tem seu próprio identificador (`io.github.pjksens.pilote`) e sua própria pasta de dados: ela nunca lê nem grava o banco de dados de outro Pilote instalado no mesmo Mac.

**Assinatura.** O projeto assina localmente (`CODE_SIGN_IDENTITY: "-"`), então o macOS pede as permissões de novo a cada
nova compilação. Para mantê-las, coloque o seu time da Apple em `project.yml` (`DEVELOPMENT_TEAM`,
`CODE_SIGN_IDENTITY: "Apple Development"`).

**Permissões.** Sem configurações, o Pilote não pede nada ao macOS. Lembretes e Calendários só são solicitados se você
ativar `rappels_calendrier`, e “controlar o Mail” (leitura e rascunhos, nunca envio) só se você ativar `mail`. O app não
usa sandbox: ele lê `~/.claude` para acompanhar suas sessões do Claude Code.

## Configurações: conecte suas contas

Tudo passa por um único arquivo JSON: `~/Library/Application Support/io.github.pjksens.pilote/reglages.json`. Modelo:
[`docs/reglages.exemple.json`](docs/reglages.exemple.json). O Pilote o relê assim que ele muda.
`./pilote reglages` diz o que está ligado, o que está desligado e o que está faltando.

**Sem este arquivo**, o Pilote funciona sozinho no seu Mac (banco de dados local, contatos, mapa, planejamento, sessões
do Claude Code) e **todo o resto fica desligado**: nenhuma leitura de Lembretes, Calendário, Mail, Contatos ou
ligações, nenhuma chamada de rede a um banco de dados, ao Stripe ou a uma rede social.

Este arquivo guarda suas chaves: mantenha-o fora de qualquer repositório git e legível somente por você (`chmod 600`).
O Pilote nunca grava uma chave em nenhum outro lugar.

| Configuração | O que ela liga |
|---|---|
| `prenom` | Seu primeiro nome no app (“Camille : rappeler…”). Padrão: “Vous” (você). |
| `espaces` | Os nomes de exibição dos seus espaços de trabalho (chaves internas `kryva`, `freelance`, `autre`). |
| `dossiers_sessions`, `routines` | As pastas oferecidas ao abrir uma sessão do Claude Code, e suas instruções de um clique. |
| `facteur` | Para onde o Facteur entrega: `sessions` (nome → ID `local_…`) e `rappel` (uma linha adicionada a cada mensagem). |
| `depot_suivi` | Um repositório git cujos commits recentes o Pilote mostra (somente leitura, sem `fetch`). |
| `rappels_calendrier: true` | Lembretes e Calendário (EventKit). |
| `mail: true` | Mail.app: mensagens recebidas, rascunhos. |
| `entrants: true` | O coletor `pilote entrants`: ligações, mensagens de texto, iMessage, WhatsApp, e-mails recebidos. |
| `publication: true` + `dossier_secrets` | Publicação no YouTube, Instagram, TikTok. Clientes OAuth nessa pasta: `pilote-google-oauth.json`, `pilote-tiktok-client.json`. Tokens no chaveiro. |
| `radar: true` + `dossier_secrets` | Radar via ScrapeCreators (pago por crédito): `cle-scrapecreators.env` (`SCRAPECREATORS_API_KEY=…`). |
| `domaines_interdits` | Domínios a partir dos quais o Pilote se recusa a enviar um e-mail, e que ele sinaliza se vir um sair. |
| `comptes` | Os cadastros do seu produto e a assinatura deles, somente leitura (abaixo). |
| `synchro` | Os contatos de um espaço de trabalho, trocados com duas tabelas remotas (abaixo). |

O envio de e-mail pelo Gmail não usa este arquivo: ele permanece desligado até você colar uma senha de app do Gmail no
app (guardada no chaveiro).

### `comptes`: seus cadastros, somente leitura

O Pilote lê **uma view**, por meio de uma API REST compatível com PostgREST (Supabase, por exemplo). Ele não conhece
nenhuma das suas tabelas: a view traduz o seu esquema. Colunas esperadas:

| Coluna | Conteúdo |
|---|---|
| `id` | id da conta (texto) |
| `entreprise`, `nom`, `email`, `telephone` | texto (empresa, nome, e-mail, telefone) |
| `inscrit_le` | data de cadastro (timestamptz) |
| `devis` | um número (inteiro) que você quer ver ao lado de cada cadastro |
| `abonnement_stripe` | o id `sub_…` do Stripe, ou null |
| `store_expire_le` | fim da assinatura da Apple ou do Google, ou null |
| `actif` | booleano, ou null |

```sql
-- Exemplo, para adaptar ao seu esquema.
create view pilote_comptes with (security_invoker = true) as
select o.id::text as id, o.nom as entreprise, u.nom_complet as nom, u.email, u.telephone,
       o.cree_le as inscrit_le, 0 as devis, o.abonnement_stripe, o.store_expire_le, o.actif
from organisations o left join utilisateurs u on u.organisation_id = o.id;
```

**A chave.** Dê ao Pilote o mínimo possível de direitos: um token que só possa **ler esta view**, por exemplo um papel
(role) dedicado do Postgres com nada além de `select` nela (veja a documentação do seu banco de dados para obter um
token vinculado a esse papel). **Nunca a chave `service_role` (ou “secret”) do Supabase**: ela abre o banco de dados
inteiro, em leitura e escrita, ignorando a segurança em nível de linha. Também não deixe a view legível pelo papel
`anon`: a chave “anon” é pública nos seus apps.

**Stripe** (`stripe_cle`, opcional): uma **chave restrita** (`rk_…`) com a única permissão “Subscriptions: Read”. Ela
distingue testes de contas pagantes; sem ela, uma conta com assinatura aparece como “To check” (a verificar).

**Contador** (`compteur`, opcional): um comando seu, executado em `dossier`, que imprime uma linha `ACTIFS 7 / 10`, depois
títulos de seção seguidos de linhas recuadas com dois espaços.

### `synchro`: seus contatos em um celular

Troca os contatos e o histórico de um espaço de trabalho (`espace`, padrão: o primeiro) com duas tabelas
(`table_contacts`, `table_evenements`; padrão `pilote_contacts`, `pilote_evenements`) cujas colunas são as de
`Synchro.colonnesContact` e `Synchro.colonnesEvenement` (`Shared/Synchro.swift`). O Pilote **escreve** ali: dê a ele um
token limitado a essas duas tabelas (`select`, `insert`, `update`), nunca o `service_role`.

## Conectar o Claude Code

```bash
claude mcp add --scope user pilote -- "$(pwd)/pilote" mcp
```

As sessões abertas depois deste comando enxergam as ferramentas do Pilote. Para o diário dos agentes, adicione um hook
`Stop` em `~/.claude/settings.json` que execute `pilote journal-crochet`.

## Dados

- Banco de dados: `~/Library/Application Support/io.github.pjksens.pilote/pilote.sqlite` (SQLite, WAL). O app se atualiza assim que outra
  conexão (a ferramenta, uma sessão do Claude) escreve nele.
- Testar outro banco de dados: `PILOTE_BASE=/path/test.sqlite ./pilote jour`.
- Nome do remetente dos e-mails: `PILOTE_NOM`; caso contrário, o nome completo da sua conta do macOS.
- Configurações e chaves: `~/Library/Application Support/io.github.pjksens.pilote/reglages.json` (veja “Configurações”).
- Backup diário: uma cópia JSON no iCloud Drive, pasta `Pilote open source` (as 14 últimas são mantidas), se o iCloud Drive estiver ativado.
- Ajuda da ferramenta: `./pilote aide`.

## Como é construído

Swift 5, SwiftUI, AppKit, EventKit, o SQLite3 do sistema, Security (chaveiro), CryptoKit. Nenhuma dependência externa.
Cerca de 28.000 linhas de Swift (sem contar os testes), 425 testes unitários.

- `App/`: o app para Mac (telas, integrações com Calendário, Lembretes, Mail e Claude).
- `Shared/`: o modelo, o banco de dados, as regras (compartilhados pelo app, pela ferramenta e pelos testes).
- `CLI/`: a ferramenta `pilote` e o servidor MCP (`pilote mcp`).
- `Tests/`: testes unitários, em bancos de dados temporários.

## Feito por

**pjk** (Sacha Praljak). Eu crio ferramentas de IA e as mostro em vídeos curtos. O Pilote é feito com o Claude Code.

- Site: [sachapraljak.com](https://sachapraljak.com/?utm_source=github&utm_medium=readme&utm_campaign=pilote)
- Instagram: [@sachaprljk](https://www.instagram.com/sachaprljk/)
- TikTok: [@sachaprljk](https://www.tiktok.com/@sachaprljk)

Se o Pilote ajuda você, uma ⭐ no repositório e um follow ajudam muito.

## Licença

MIT, veja [LICENSE](LICENSE).
