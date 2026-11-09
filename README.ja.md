<p align="center">
  <img src="docs/media/hero.ja.png" alt="Pilote：クライアント、プロジェクト、Claude Code のチームを、ひとつの画面に">
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-15%2B-black?logo=apple" alt="macOS 15+">
  <img src="https://img.shields.io/badge/Swift-SwiftUI-F05138?logo=swift&logoColor=white" alt="Swift と SwiftUI">
  <img src="https://img.shields.io/badge/Claude%20Code-MCP%20server-C2502C" alt="Claude Code 対応（MCP サーバー）">
  <img src="https://img.shields.io/badge/data-stays%20on%20your%20Mac-0A84FF" alt="データはあなたの Mac の中に残ります">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="MIT">
  <a href="../../stargazers"><img src="https://img.shields.io/github/stars/pjksens/pilote?style=flat&color=FFD60A&label=%E2%98%85%20stars" alt="スター数"></a>
</p>

<p align="center">
  <a href="README.md">English</a> · <a href="README.fr.md">Français</a> · <a href="README.es.md">Español</a> · <a href="README.pt-BR.md">Português (Brasil)</a> · <a href="README.de.md">Deutsch</a> · <a href="README.it.md">Italiano</a> · <a href="README.zh-CN.md">简体中文</a> · <b>日本語</b> · <a href="README.ko.md">한국어</a>
</p>

<p align="center">
  作者：<b>pjk</b>（Sacha Praljak）·
  <a href="https://sachapraljak.com/?utm_source=github&utm_medium=readme&utm_campaign=pilote">sachapraljak.com</a> ·
  <a href="https://www.instagram.com/sachaprljk/">Instagram</a> ·
  <a href="https://www.tiktok.com/@sachaprljk">TikTok</a>
</p>

<p align="center">
  <b>Pilote が役に立ったら、⭐ を付けてください。ほかの人がこのプロジェクトを見つけやすくなります。</b>
</p>

**Pilote は、Claude Code エージェントのチームと働くフリーランスのための業務ログです。** あなたの対応が必要なことをすべて集めた、macOS ネイティブのアプリです。クライアントとのやり取りのすべて、クライアントごとの次のアクション、リマインダーとカレンダー、そして Claude Code のセッションがいま何をしているか。セッションは MCP サーバー経由で Pilote を読み書きするので、Pilote は常に最新の状態に保たれ、あなたには対応が必要なことだけが見えます。すべてあなたの Mac の中で完結します。ローカルの SQLite データベースを使い、サーバーもアカウントも不要です。

<p align="center">
  <img src="docs/media/suivi.gif" width="720" alt="Pilote の見込み客ボード：連絡先をクリックすると、すべてのやり取りと次のアクションが載ったカードが開きます">
  <br><sub>デモモード（<code>./scripts/demo.sh</code>）：架空のデータで、実在の人物は登場しません。</sub>
</p>

> アプリの画面表示とコード内のコメントはフランス語です。この README は 9 言語で用意されていますが、アプリ自体は（まだ）対応していません。

## Pilote でできること

- **1 日をひとつの画面で。** 予定（カレンダー）、今日と期限切れのリマインダー（そのままチェックして完了できます）、Claude が用意してあなたの承認を待っているメッセージ、期限が来たフォローアップ、届いた返信。
- **文脈つきのクライアント管理。** ワークスペースごとに 1 つのアドレス帳があり、ステージ、次のアクション、すべてのやり取り（メール、SMS、通話、訪問）の履歴を残せます。通話の前に、これまでの経緯をすべて確認できます。
- **Claude Code と接続。** MCP サーバーが、Claude のセッションに Pilote を読み書きするためのツール（`jour`、`cherche`、`fiche`、`enregistre_contact`、`ajoute_au_fil`、`marque`、`carte`、`ou_est`、`agents`、`journal`、`note_au_journal`、`publications` など）を提供します。サーバーの指示により、セッションは作成する前に検索し、何も捏造せず、勝手に何も送信しません。
- **エージェント。** Mac で開いている Claude Code のセッション、その状態と直近の動作、そして成果物のジャーナル（Claude Code の `Stop` フックが記録します）。
- **仕事のマップ。** すべてのプロジェクト、そのフォルダー、`ETAT.md`（状態ファイル）、主要なドキュメント。プロジェクト、連絡先、ジャーナル、ファイル（Spotlight）を横断してすべてを検索できます（⌘K）。
- **メールは自分の手で。** 用意されたメールは、あなたがクリックしたときだけ、あなた自身の Gmail から送信されます（SMTP。アプリパスワードは macOS のキーチェーンに保存され、Claude が読むことはありません）。プレーンテキストで、返信は正しいスレッドにまとまります。
- **投稿。** YouTube、Instagram、TikTok への動画投稿を予約できます。公開の前には毎回、明示的な承認が必要です（トークンはキーチェーンに保存）。
- **レーダー。** SNS アカウントを観察します（再生数、投稿のペース、アイデア）。手入力のほか、有料のデータソース経由でも取得できますが、あなたの確認なしに実行されることはありません。

## Claude Code と使う

作業はセッションが行い、Pilote はその様子を見て、返事をする場所です。

<p align="center">
  <img src="docs/media/claude.gif" width="720" alt="「エージェント」ページ：どのセッションが作業中か、成果物のジャーナル。続いて、あるワークスペースのセッションに宛てたメッセージ">
  <br><sub>セッションがいま何をしているかを確認し、Pilote を離れずにそのうちの 1 つへメッセージを送れます。</sub>
</p>

セッションが判断を必要とすると、その質問がボタンつきでホーム画面に表示されます。あなたの回答は **「Vos réponses, prêtes à partir」**（あなたの回答、送信待ち）に置かれ、**Envoyer**（送信）をクリックするまで保留されます。セッションに誤って何かが届くことはありません。

<p align="center">
  <img src="docs/media/facteur.gif" width="720" alt="ホーム画面に表示されたセッションからの質問：回答をワンクリックで選び、送信します">
  <br><sub>セッションが質問し、あなたはワンクリックで答え、送り出すタイミングも自分で決めます。</sub>
</p>

> **回答がセッションに届く仕組み：** [`scripts/facteur.py`](scripts/facteur.py)、「Facteur」（郵便配達員）です。ホーム画面の **Démarrer le Facteur** ボタンを押すと、指示付きの Claude Code セッションが開きます。このセッションはバックグラウンドで待機し、各回答を数秒以内に適切なセッションへ届けます。届け先は質問したセッション、またはあなたがメッセージを書いたセッションです。なければ `reglages.json` の `facteur.sessions` で指定したセッション、それもなければ `EQUIPE.md` の表にあるセッションです。コードにはセッション ID を一切書いていません。

## ご注意

これは**私個人のシステムを、そのまま公開したもの**ですが、設定で調整できるようにしてあります。キー、フォルダー、名前は 1 つの設定ファイルにまとまっており（「設定」を参照）、アカウントやオンラインサービスに触れる機能は、あなたがオンにするまですべてオフのままです。私自身の使い方の痕跡は残っています。私のワークスペース（内部キーは `kryva`、表示名は変更可能）、Claude セッションのチーム、フランス語のラベルなどです。実際のデータ（連絡先、メッセージ、アカウント、認証情報）はすべて削除するか、架空の値に置き換えてあります。

含まれていないもの：私自身の運用スクリプト（回答の配送、監視、インポート）、私のメモ、私のデータベース。

## 何も接続せずに試す：デモモード

```bash
./scripts/demo.sh             # アプリをビルドし（インストールはせず）、架空のデータで開きます
./scripts/demo.sh --captures  # 下のスクリーンショットを撮り直します（docs/captures）
./scripts/demo.sh --gif       # 3 つのデモを再生して GIF を作り直します（docs/media、ffmpeg が必要）
```

デモモード（`PILOTE_DEMO=1`）では、Pilote はあなたのホームフォルダーの代わりに、起動のたびに新しくなる架空のホームフォルダーを見ます。データベース、Claude セッション、ファイルのすべてがそうです。リマインダー、カレンダー、メール、Spotlight は読み込まず、外部には何も送信されません（メール、セッションへのメッセージ、通知、投稿）。スクリーンショットと GIF はアプリが自分自身のウィンドウを撮影するため、画面収録の権限は不要です。

| | |
|---|---|
| ![エージェント：Claude Code のセッションとそのジャーナル](docs/captures/10-claude.png) | ![連絡先：アドレス帳、ステージ、次のアクション](docs/captures/04-contacts.png) |
| ![見込み客：ステージ別のボード](docs/captures/03-prospects.png) | ![動画：1 週間、2 つのアカウント](docs/captures/05-semaine.png) |
| ![タスク：カードをドラッグして日付を変更](docs/captures/08-taches.png) | ![ダークモードのホーム画面](docs/captures/01-aujourdhui-sombre.png) |

スクリーンショットに写っているデータはすべて架空のものです（名前、会社名、フランスの架空用番号帯 06 39 98 00 0x の電話番号、`.example` のアドレス）。

## インストール

macOS 15 以降、Xcode、[XcodeGen](https://github.com/yonaskolb/XcodeGen) が必要です。

```bash
brew install xcodegen
git clone https://github.com/pjksens/pilote.git && cd pilote
./scripts/tester.sh        # ユニットテスト（アプリにもあなたのデータベースにも触れません）
./scripts/construire.sh    # アプリをビルドして ~/Applications にインストールし、./pilote ツールを配置します
```

`construire.sh` は、Pilote が起動していれば終了させてから、`~/Applications/Pilote.app` を置き換えます。そこに別の Pilote という名前のアプリ（別の識別子）がある場合は、何も置き換えずに停止します。このコピーは独自の識別子（`io.github.pjksens.pilote`）と独自のデータフォルダを持ち、同じ Mac にある別の Pilote のデータベースを読み書きすることはありません。

**署名。** このプロジェクトはローカル署名（`CODE_SIGN_IDENTITY: "-"`）を使うため、ビルドし直すたびに macOS が権限を再度確認してきます。権限を保持したい場合は、`project.yml` に自分の Apple チームを設定してください（`DEVELOPMENT_TEAM`、`CODE_SIGN_IDENTITY: "Apple Development"`）。

**権限。** 設定がなければ、Pilote は macOS に何も要求しません。リマインダーとカレンダーは `rappels_calendrier` をオンにしたときだけ、「Mail の制御」（読み取りと下書きのみで、送信はしません）は `mail` をオンにしたときだけ要求されます。アプリはサンドボックス化されていません。Claude Code のセッションを追跡するために `~/.claude` を読み込みます。

## 設定：アカウントを接続する

設定はすべて 1 つの JSON ファイル `~/Library/Application Support/io.github.pjksens.pilote/reglages.json` で行います。テンプレートは [`docs/reglages.exemple.json`](docs/reglages.exemple.json) です。Pilote はファイルが変更されるとすぐに読み直します。`./pilote reglages` を実行すると、何がオンで、何がオフで、何が足りないかが分かります。

**このファイルがなくても**、Pilote は Mac の中だけで単独で動作します（ローカルデータベース、連絡先、マップ、スケジュール、Claude Code のセッション）。**それ以外はすべてオフ**です。リマインダー、カレンダー、メール、連絡先、通話は読み込まれず、データベース、Stripe、SNS へのネットワーク通信も行われません。

このファイルにはキーが入ります。git リポジトリには入れず、自分だけが読めるようにしてください（`chmod 600`）。Pilote がキーをほかの場所に書き込むことはありません。

| 設定 | オンにするもの |
|---|---|
| `prenom` | アプリ内で使うあなたの名前（「Camille : rappeler…」）。既定値：「Vous」（あなた）。 |
| `espaces` | ワークスペースの表示名（内部キーは `kryva`、`freelance`、`autre`）。 |
| `dossiers_sessions`, `routines` | Claude Code のセッションを開くときに候補として出るフォルダーと、ワンクリックで使える指示。 |
| `facteur` | Facteur の届け先：`sessions`（名前 → `local_…` ID）と `rappel`（各メッセージに添える 1 行）。 |
| `depot_suivi` | Pilote が最近のコミットを表示する git リポジトリ（読み取り専用で、`fetch` は行いません）。 |
| `rappels_calendrier: true` | リマインダーとカレンダー（EventKit）。 |
| `mail: true` | Mail.app：受信メッセージ、下書き。 |
| `entrants: true` | `pilote entrants` コレクター：通話、SMS、iMessage、WhatsApp、受信メール。 |
| `publication: true` + `dossier_secrets` | YouTube、Instagram、TikTok への投稿。OAuth クライアントはそのフォルダーに置きます：`pilote-google-oauth.json`、`pilote-tiktok-client.json`。トークンはキーチェーンに保存されます。 |
| `radar: true` + `dossier_secrets` | ScrapeCreators 経由のレーダー（クレジット従量課金）：`cle-scrapecreators.env`（`SCRAPECREATORS_API_KEY=…`）。 |
| `domaines_interdits` | Pilote がメールの送信を拒否するドメイン。そのドメインからの送信を見つけた場合は警告を出します。 |
| `comptes` | あなたのプロダクトのサインアップとそのサブスクリプション（読み取り専用。下記参照）。 |
| `synchro` | 1 つのワークスペースの連絡先を、2 つのリモートテーブルと同期します（下記参照）。 |

Gmail でのメール送信にはこのファイルを使いません。アプリに Gmail のアプリパスワードを貼り付けるまでオフのままです（パスワードはキーチェーンに保存されます）。

### `comptes`：サインアップを読み取り専用で見る

Pilote は、PostgREST 互換の REST API（たとえば Supabase）を通して**1 つのビュー**を読み込みます。あなたのテーブルのことは何も知りません。スキーマの違いはビューが吸収します。必要な列は次のとおりです。

| 列 | 内容 |
|---|---|
| `id` | アカウント ID（text） |
| `entreprise`, `nom`, `email`, `telephone` | テキスト（会社名、氏名、メールアドレス、電話番号） |
| `inscrit_le` | サインアップ日（timestamptz） |
| `devis` | 各サインアップの横に表示したい数値（整数） |
| `abonnement_stripe` | Stripe の `sub_…` ID、または null |
| `store_expire_le` | Apple または Google のサブスクリプションの終了日、または null |
| `actif` | boolean、または null |

```sql
-- 例です。ご自身のスキーマに合わせて調整してください。
create view pilote_comptes with (security_invoker = true) as
select o.id::text as id, o.nom as entreprise, u.nom_complet as nom, u.email, u.telephone,
       o.cree_le as inscrit_le, 0 as devis, o.abonnement_stripe, o.store_expire_le, o.actif
from organisations o left join utilisateurs u on u.organisation_id = o.id;
```

**キー。** Pilote に与える権限は最小限にしてください。**このビューの読み取りだけ**ができるトークンが理想です。たとえば、そのビューに対する `select` 権限だけを持つ専用の Postgres ロールを作ります（そのロールに紐づくトークンの取得方法は、お使いのデータベースのドキュメントを参照してください）。**Supabase の `service_role`（または「secret」）キーは絶対に使わないでください**。このキーはデータベース全体を読み書きでき、行レベルセキュリティも回避します。また、ビューを `anon` ロールから読めるようにするのも避けてください。「anon」キーはあなたのアプリの中で公開されています。

**Stripe**（`stripe_cle`、任意）：「Subscriptions: Read」の権限だけを持つ**制限付きキー**（`rk_…`）を使います。トライアル中のアカウントと有料アカウントを見分けるためのもので、これがない場合、サブスクリプションのあるアカウントは「À vérifier」（要確認）と表示されます。

**カウンター**（`compteur`、任意）：`dossier` で実行されるあなたのコマンドです。`ACTIFS 7 / 10` という行を出力し、続けてセクションの見出しと、その下に 2 スペースでインデントした行を出力します。

### `synchro`：連絡先をスマートフォンで使う

1 つのワークスペース（`espace`、既定は最初のもの）の連絡先とやり取りの履歴を、2 つのテーブル（`table_contacts`、`table_evenements`。既定は `pilote_contacts`、`pilote_evenements`）と同期します。列は `Synchro.colonnesContact` と `Synchro.colonnesEvenement`（`Shared/Synchro.swift`）のものと同じです。Pilote はそこに**書き込みます**。その 2 つのテーブルだけに限定したトークン（`select`、`insert`、`update`）を渡してください。`service_role` は絶対に渡さないでください。

## Claude Code に接続する

```bash
claude mcp add --scope user pilote -- "$(pwd)/pilote" mcp
```

このコマンドの後に開いたセッションでは、Pilote のツールが使えるようになります。エージェントのジャーナルを使うには、`~/.claude/settings.json` に `pilote journal-crochet` を実行する `Stop` フックを追加してください。

## データ

- データベース：`~/Library/Application Support/io.github.pjksens.pilote/pilote.sqlite`（SQLite、WAL）。ほかの接続（ツールや Claude のセッション）が書き込むと、アプリも即座に更新されます。
- 別のデータベースを試す：`PILOTE_BASE=/path/test.sqlite ./pilote jour`。
- メールの送信者名：`PILOTE_NOM`。未設定の場合は、macOS アカウントのフルネームを使います。
- 設定とキー：`~/Library/Application Support/io.github.pjksens.pilote/reglages.json`（「設定」を参照）。
- 毎日のバックアップ：iCloud Drive が有効な場合、`Pilote open source` フォルダに JSON のコピーを保存します（最新 14 件を保持）。
- ツールのヘルプ：`./pilote aide`。

## 仕組み

Swift 5、SwiftUI、AppKit、EventKit、システム標準の SQLite3、Security（キーチェーン）、CryptoKit。外部依存はありません。Swift のコードはおよそ 28,000 行（テストを除く）、ユニットテストは 425 件です。

- `App/`：Mac アプリ（画面、カレンダー、リマインダー、メール、Claude との連携）。
- `Shared/`：モデル、データベース、ルール（アプリ、ツール、テストで共有）。
- `CLI/`：`pilote` ツールと MCP サーバー（`pilote mcp`）。
- `Tests/`：一時データベースを使うユニットテスト。

## 作者

**pjk**（Sacha Praljak）。AI ツールを作り、短い動画で紹介しています。Pilote は Claude Code で作られています。

- サイト：[sachapraljak.com](https://sachapraljak.com/?utm_source=github&utm_medium=readme&utm_campaign=pilote)
- Instagram：[@sachaprljk](https://www.instagram.com/sachaprljk/)
- TikTok：[@sachaprljk](https://www.tiktok.com/@sachaprljk)

Pilote が役に立ったら、リポジトリへの ⭐ とフォローをいただけると大きな励みになります。

## ライセンス

MIT。[LICENSE](LICENSE) を参照してください。
