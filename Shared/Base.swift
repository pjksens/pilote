// Base locale de Pilote : un fichier SQLite partagé par l'app et l'outil en ligne de commande.
// Emplacement : ~/Library/Application Support/io.github.pjksens.pilote/pilote.sqlite (mode WAL, plusieurs lecteurs à la fois).
import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

struct ErreurBase: Error, CustomStringConvertible {
    let description: String
}

final class Base: @unchecked Sendable {
    private let db: OpaquePointer
    /// Le fichier de la base : ce qui s'écrit à côté (alertes pour PILOTE) suit la base utilisée, une copie d'essai comprise.
    let chemin: URL
    private let verrou = NSLock()

    static var dossier: URL {
        let d = Identite.dossier
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    /// PILOTE_BASE permet de travailler sur une autre base (essais).
    static var cheminParDefaut: URL {
        if let autre = ProcessInfo.processInfo.environment["PILOTE_BASE"], !autre.isEmpty { return URL(fileURLWithPath: autre) }
        return dossier.appendingPathComponent("pilote.sqlite")
    }

    init(chemin: URL = Base.cheminParDefaut) throws {
        var p: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(chemin.path, &p, flags, nil) == SQLITE_OK, let p else {
            throw ErreurBase(description: L("Impossible d'ouvrir la base \(chemin.path)"))
        }
        db = p
        self.chemin = chemin
        // L'attente d'abord : au démarrage, plusieurs connexions s'ouvrent en même temps et le passage en WAL
        // (ou la reprise d'un journal laissé par un arrêt brutal) verrouille la base un instant.
        try executer("PRAGMA busy_timeout=4000")
        // Les connexions d'un même processus passent en WAL et migrent l'une après l'autre : sur une base neuve,
        // deux passages en WAL simultanés répondaient « database is locked » sans attendre (MigrationConcurrenteTests).
        Base.verrouMigration.lock(); defer { Base.verrouMigration.unlock() }
        try executer("PRAGMA journal_mode=WAL")
        try executer("PRAGMA foreign_keys=ON")
        try migrer()
    }

    private static let verrouMigration = NSLock()

    deinit { sqlite3_close_v2(db) }

    // MARK: Schéma

    private func migrer() throws {
        try executer("""
        CREATE TABLE IF NOT EXISTS contacts (
          id TEXT PRIMARY KEY,
          espace TEXT NOT NULL DEFAULT 'kryva',
          type TEXT NOT NULL DEFAULT 'autre',
          nom TEXT NOT NULL DEFAULT '',
          entreprise TEXT NOT NULL DEFAULT '',
          ville TEXT NOT NULL DEFAULT '',
          departement TEXT NOT NULL DEFAULT '',
          telephone TEXT NOT NULL DEFAULT '',
          email TEXT NOT NULL DEFAULT '',
          linkedin TEXT NOT NULL DEFAULT '',
          facebook TEXT NOT NULL DEFAULT '',
          site TEXT NOT NULL DEFAULT '',
          etape TEXT NOT NULL DEFAULT 'a_contacter',
          prochaine_action TEXT NOT NULL DEFAULT '',
          prochaine_date TEXT NOT NULL DEFAULT '',
          priorite INTEGER NOT NULL DEFAULT 2,
          ne_plus_contacter INTEGER NOT NULL DEFAULT 0,
          org_id TEXT NOT NULL DEFAULT '',
          source TEXT,
          source_ref TEXT,
          notes TEXT NOT NULL DEFAULT '',
          cree_le TEXT NOT NULL,
          maj_le TEXT NOT NULL,
          UNIQUE (source, source_ref)
        )
        """)
        try executer("""
        CREATE TABLE IF NOT EXISTS evenements (
          id TEXT PRIMARY KEY,
          contact_id TEXT NOT NULL REFERENCES contacts(id) ON DELETE CASCADE,
          le TEXT NOT NULL,
          canal TEXT NOT NULL DEFAULT 'autre',
          sens TEXT NOT NULL DEFAULT 'interne',
          type TEXT NOT NULL DEFAULT 'note',
          texte TEXT NOT NULL DEFAULT '',
          statut TEXT NOT NULL DEFAULT 'fait',
          par TEXT NOT NULL DEFAULT '\(Moi.nom.replacingOccurrences(of: "'", with: "''"))',
          source_ref TEXT,
          UNIQUE (contact_id, source_ref)
        )
        """)
        try executer("CREATE INDEX IF NOT EXISTS evenements_contact ON evenements(contact_id, le)")
        // 27/10 : envoi de mails depuis Pilote (objet, mail auquel on répond, identifiant du mail parti).
        let colonnes = Set(try lignes("PRAGMA table_info(evenements)").compactMap { $0["name"] as? String })
        for c in ["objet", "reponse_a", "message_id"] where !colonnes.contains(c) {
            try ajouterColonne("ALTER TABLE evenements ADD COLUMN \(c) TEXT NOT NULL DEFAULT ''")
        }
        // 27/10 : synchro KRYVA avec l'admin. Une suppression devient une marque (supprime_le), maj_le partout.
        for c in ["maj_le", "supprime_le"] where !colonnes.contains(c) {
            try ajouterColonne("ALTER TABLE evenements ADD COLUMN \(c) TEXT NOT NULL DEFAULT ''")
        }
        // 05/11 (T7) : la condition d'un message préparé (et quand elle a été cochée), le rappel lié (et quand Pilote l'a coché).
        // Colonnes ajoutées vides : aucune donnée existante ne change. Hors synchro KRYVA (Synchro.colonnesEvenement).
        for c in ["condition", "condition_ok_le", "rappel_id", "rappel_ferme_le"] where !colonnes.contains(c) {
            try ajouterColonne("ALTER TABLE evenements ADD COLUMN \(c) TEXT NOT NULL DEFAULT ''")
        }
        try executer("""
            UPDATE evenements SET maj_le = COALESCE(strftime('%Y-%m-%dT%H:%M:%SZ', le), strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
            WHERE length(maj_le) != 20
            """)
        let colonnesContacts = Set(try lignes("PRAGMA table_info(contacts)").compactMap { $0["name"] as? String })
        if !colonnesContacts.contains("supprime_le") {
            try ajouterColonne("ALTER TABLE contacts ADD COLUMN supprime_le TEXT NOT NULL DEFAULT ''")
        }
        // 10/11 (Organisation, demande de PILOTE) : « aucune réponse due » à une réponse reçue (« Merci », attente du support).
        // On garde le nombre de réponses reçues couvertes : un message reçu de plus (quelle que soit sa date) rend l'alerte.
        // -1 = pas de marque. Hors synchro KRYVA (Synchro.colonnesContact).
        if !colonnesContacts.contains("aucune_reponse_due_recus") {
            try ajouterColonne("ALTER TABLE contacts ADD COLUMN aucune_reponse_due_recus INTEGER NOT NULL DEFAULT -1")
        }
        try executer("CREATE TABLE IF NOT EXISTS synchro (cle TEXT PRIMARY KEY, valeur TEXT NOT NULL)")
        try executer("CREATE INDEX IF NOT EXISTS contacts_prochaine ON contacts(prochaine_date)")
        // 27/10 : la carte de l'espace de travail (un projet = un dossier) et le journal des agents.
        try executer("""
        CREATE TABLE IF NOT EXISTS projets (
          id TEXT PRIMARY KEY,
          espace TEXT NOT NULL DEFAULT 'autre',
          nom TEXT NOT NULL DEFAULT '',
          description TEXT NOT NULL DEFAULT '',
          dossier TEXT NOT NULL DEFAULT '',
          depot TEXT NOT NULL DEFAULT '',
          site TEXT NOT NULL DEFAULT '',
          statut TEXT NOT NULL DEFAULT 'actif',
          documents TEXT NOT NULL DEFAULT '',
          notes TEXT NOT NULL DEFAULT '',
          ordre INTEGER NOT NULL DEFAULT 100,
          maj_le TEXT NOT NULL DEFAULT ''
        )
        """)
        try executer("""
        CREATE TABLE IF NOT EXISTS journal (
          id TEXT PRIMARY KEY,
          le TEXT NOT NULL,
          type TEXT NOT NULL DEFAULT 'tour',
          session TEXT NOT NULL DEFAULT '',
          session_app TEXT NOT NULL DEFAULT '',
          titre_session TEXT NOT NULL DEFAULT '',
          dossier TEXT NOT NULL DEFAULT '',
          projet_id TEXT NOT NULL DEFAULT '',
          demande TEXT NOT NULL DEFAULT '',
          texte TEXT NOT NULL DEFAULT '',
          fichiers TEXT NOT NULL DEFAULT '',
          source_ref TEXT UNIQUE
        )
        """)
        // 27/10 : tri des mails de Mail.app (calculé sur le Mac) et réglages locaux.
        try executer("""
        CREATE TABLE IF NOT EXISTS mail_tri (
          cle TEXT PRIMARY KEY,
          message_id TEXT NOT NULL,
          compte TEXT NOT NULL DEFAULT '',
          nom TEXT NOT NULL DEFAULT '',
          adresse TEXT NOT NULL DEFAULT '',
          objet TEXT NOT NULL DEFAULT '',
          recu_le TEXT NOT NULL,
          lu INTEGER NOT NULL DEFAULT 0,
          groupe TEXT NOT NULL DEFAULT 'autres',
          raison TEXT NOT NULL DEFAULT '',
          par TEXT NOT NULL DEFAULT 'regles',
          version INTEGER NOT NULL DEFAULT 0,
          repondu INTEGER NOT NULL DEFAULT 0,
          traite_le TEXT NOT NULL DEFAULT '',
          range_le TEXT NOT NULL DEFAULT '',
          vu_le TEXT NOT NULL DEFAULT ''
        )
        """)
        try executer("CREATE TABLE IF NOT EXISTS reglages (cle TEXT PRIMARY KEY, valeur TEXT NOT NULL)")
        try executer("CREATE INDEX IF NOT EXISTS journal_le ON journal(le)")
        try executer("CREATE INDEX IF NOT EXISTS journal_projet ON journal(projet_id, le)")
        try migrerRadar()
        try migrerVideos()
        try migrerFileEnvoi(); try migrerPublications()
    }

    /// 28/10 : le Radar (veille de comptes, ratio vues ÷ médiane, boîte à idées). Dates en ISO 8601 UTC, comme le reste.
    /// Une valeur absente est NULL, jamais 0. Les relevés ne s'écrasent jamais : un par (post, instant, source).
    private func migrerRadar() throws {
        try executer("""
        CREATE TABLE IF NOT EXISTS radar_comptes (
          id TEXT PRIMARY KEY,
          espace TEXT NOT NULL,
          plateforme TEXT NOT NULL,
          identifiant TEXT NOT NULL,
          nom TEXT NOT NULL DEFAULT '',
          url TEXT NOT NULL DEFAULT '',
          etat TEXT NOT NULL DEFAULT 'actif',
          verifie_le TEXT NOT NULL DEFAULT '',
          notes TEXT NOT NULL DEFAULT '',
          cree_le TEXT NOT NULL,
          UNIQUE (espace, plateforme, identifiant)
        )
        """)
        try executer("""
        CREATE TABLE IF NOT EXISTS radar_posts (
          id TEXT PRIMARY KEY,
          compte_id TEXT NOT NULL REFERENCES radar_comptes(id),
          plateforme TEXT NOT NULL,
          identifiant TEXT NOT NULL,
          url TEXT NOT NULL DEFAULT '',
          legende TEXT NOT NULL DEFAULT '',
          publie_le TEXT NOT NULL,
          cree_le TEXT NOT NULL
        )
        """)
        try executer("""
        CREATE TABLE IF NOT EXISTS radar_releves (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          post_id TEXT NOT NULL REFERENCES radar_posts(id),
          releve_le TEXT NOT NULL,
          vues INTEGER,
          likes INTEGER,
          commentaires INTEGER,
          source TEXT NOT NULL DEFAULT 'manuelle',
          UNIQUE (post_id, releve_le, source)
        )
        """)
        try executer("""
        CREATE TABLE IF NOT EXISTS radar_scans (
          id TEXT PRIMARY KEY,
          espace TEXT NOT NULL,
          source TEXT NOT NULL,
          debut TEXT NOT NULL,
          fin TEXT NOT NULL DEFAULT '',
          etat TEXT NOT NULL DEFAULT 'termine',
          nb_comptes INTEGER NOT NULL DEFAULT 0,
          nb_posts INTEGER NOT NULL DEFAULT 0,
          erreurs TEXT NOT NULL DEFAULT ''
        )
        """)
        // La boîte à idées garde sa propre copie de la source : retirer un compte ou purger des relevés ne la touche pas.
        try executer("""
        CREATE TABLE IF NOT EXISTS radar_idees (
          id TEXT PRIMARY KEY,
          post_id TEXT NOT NULL UNIQUE,
          espace TEXT NOT NULL,
          concept TEXT NOT NULL DEFAULT '',
          source_figee TEXT NOT NULL,
          brouillon TEXT NOT NULL DEFAULT '',
          statut TEXT NOT NULL DEFAULT 'a_ecrire',
          revision INTEGER NOT NULL DEFAULT 0,
          cree_le TEXT NOT NULL,
          maj_le TEXT NOT NULL
        )
        """)
        // Crédits dépensés par un relevé payant (NULL = source gratuite ou inconnu, jamais 0 par défaut).
        let colonnesScans = Set(try lignes("PRAGMA table_info(radar_scans)").compactMap { $0["name"] as? String })
        if !colonnesScans.contains("credits") { try ajouterColonne("ALTER TABLE radar_scans ADD COLUMN credits INTEGER") }
        // 04/11 : le verdict de chaque vidéo postée, UN PAR RELEVÉ (palier « 48h » puis « 7j », l'analyse de fond au 7j).
        // La clé est celle de stats.sqlite (compte_id + ref) : les chiffres restent chez Réseaux, lus en lecture seule.
        // Première forme (clé compte_id + ref, sans palier) : refaite ici, ses lignes passent en « 48h ».
        let colonnesVerdicts = Set(try lignes("PRAGMA table_info(video_verdicts)").compactMap { $0["name"] as? String })
        let ancienVerdicts = !colonnesVerdicts.isEmpty && !colonnesVerdicts.contains("palier")
        if ancienVerdicts { try executer("ALTER TABLE video_verdicts RENAME TO video_verdicts_ancienne") }
        try executer("""
        CREATE TABLE IF NOT EXISTS video_verdicts (
          compte_id TEXT NOT NULL,
          ref TEXT NOT NULL,
          palier TEXT NOT NULL DEFAULT '48h',
          verdict TEXT NOT NULL DEFAULT '',
          pourquoi TEXT NOT NULL DEFAULT '',
          lecon TEXT NOT NULL DEFAULT '',
          analyse TEXT NOT NULL DEFAULT '',
          decrochage_s REAL,
          decrochage_note TEXT NOT NULL DEFAULT '',
          base_releve_le TEXT NOT NULL DEFAULT '',
          ecrit_le TEXT NOT NULL DEFAULT '',
          par TEXT NOT NULL DEFAULT '',
          PRIMARY KEY (compte_id, ref, palier)
        )
        """)
        if ancienVerdicts {
            try executer("""
            INSERT INTO video_verdicts (compte_id, ref, palier, verdict, pourquoi, lecon, decrochage_s, decrochage_note, base_releve_le, ecrit_le, par)
            SELECT compte_id, ref, '48h', verdict, pourquoi, lecon, decrochage_s, decrochage_note, base_releve_le, ecrit_le, par FROM video_verdicts_ancienne
            """)
            try executer("DROP TABLE video_verdicts_ancienne")
        }
        try executer("CREATE INDEX IF NOT EXISTS radar_posts_compte ON radar_posts(compte_id, publie_le)")
        try executer("CREATE INDEX IF NOT EXISTS radar_releves_post ON radar_releves(post_id, releve_le)")
        // 05/11 : la liste du jour de chaque agent, gardée telle qu'elle était le matin (et ce qui s'y ajoute dans la
        // journée), pour que Sacha voie ce que chaque agent a traité et relance ce qui reste.
        try executer("""
        CREATE TABLE IF NOT EXISTS listes_agents (
          jour TEXT NOT NULL,
          pour TEXT NOT NULL,
          contact_id TEXT NOT NULL,
          motif TEXT NOT NULL DEFAULT 'du',
          action_avant TEXT NOT NULL DEFAULT '',
          date_avant TEXT NOT NULL DEFAULT '',
          note_le TEXT NOT NULL DEFAULT '',
          PRIMARY KEY (jour, pour, contact_id)
        )
        """)
        // 09/11 : l'écran unique. Les cartes que les sessions déclarent pour ce qui ne se lit nulle part (à corriger, pas pu
        // faire, à faire), par domaine et par case. L'historique va au journal ; ici, seulement l'état (Shared/Domaines.swift).
        try executer("""
        CREATE TABLE IF NOT EXISTS cartes_domaine (
          id TEXT PRIMARY KEY,
          domaine TEXT NOT NULL,
          etat TEXT NOT NULL,
          texte TEXT NOT NULL,
          pourquoi TEXT NOT NULL DEFAULT '',
          lien TEXT NOT NULL DEFAULT '',
          auteur TEXT NOT NULL DEFAULT '',
          cree_le TEXT NOT NULL,
          maj_le TEXT NOT NULL
        )
        """)
        // 09/11 (Organisation) : qui la carte attend (« Sacha », « PILOTE » ou un tiers, « l'académie ») et, quand c'est
        // Sacha, le rappel à son nom qui porte son geste (identifiant ou titre exact).
        let colonnesCartes = Set(try lignes("PRAGMA table_info(cartes_domaine)").compactMap { $0["name"] as? String })
        for c in ["attend", "rappel"] where !colonnesCartes.contains(c) {
            try ajouterColonne("ALTER TABLE cartes_domaine ADD COLUMN \(c) TEXT NOT NULL DEFAULT ''")
        }
    }

    // MARK: Requêtes

    func executer(_ sql: String, _ params: [Any?] = []) throws {
        _ = try lignes(sql, params)
    }

    /// Ajoute une colonne pendant une migration (ALTER TABLE … ADD COLUMN). Au démarrage, plusieurs connexions migrent
    /// la base en même temps : si une autre vient d'ajouter la même colonne, SQLite répond « duplicate column name ».
    /// La colonne est là, c'est ce qu'on voulait. Toute autre erreur remonte.
    func ajouterColonne(_ sql: String) throws {
        do { try executer(sql) } catch let e as ErreurBase where e.description.hasPrefix("duplicate column name") {}
    }

    /// Exécute une requête et renvoie chaque ligne sous forme de dictionnaire colonne → valeur.
    func lignes(_ sql: String, _ params: [Any?] = []) throws -> [[String: Any]] {
        verrou.lock(); defer { verrou.unlock() }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw ErreurBase(description: String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        for (i, v) in params.enumerated() {
            let idx = Int32(i + 1)
            switch v {
            case nil: sqlite3_bind_null(stmt, idx)
            case let s as String: sqlite3_bind_text(stmt, idx, s, -1, SQLITE_TRANSIENT)
            case let n as Int: sqlite3_bind_int64(stmt, idx, Int64(n))
            case let b as Bool: sqlite3_bind_int64(stmt, idx, b ? 1 : 0)
            case let d as Double: sqlite3_bind_double(stmt, idx, d)
            default: sqlite3_bind_text(stmt, idx, "\(v!)", -1, SQLITE_TRANSIENT)
            }
        }
        var out: [[String: Any]] = []
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_DONE { break }
            guard rc == SQLITE_ROW else { throw ErreurBase(description: String(cString: sqlite3_errmsg(db))) }
            var ligne: [String: Any] = [:]
            for c in 0..<sqlite3_column_count(stmt) {
                let nom = String(cString: sqlite3_column_name(stmt, c))
                switch sqlite3_column_type(stmt, c) {
                case SQLITE_INTEGER: ligne[nom] = Int(sqlite3_column_int64(stmt, c))
                case SQLITE_FLOAT: ligne[nom] = sqlite3_column_double(stmt, c)
                case SQLITE_NULL: break
                default: ligne[nom] = String(cString: sqlite3_column_text(stmt, c))
                }
            }
            out.append(ligne)
        }
        return out
    }

    /// Change à chaque écriture faite par une autre connexion (l'outil `pilote`, une autre fenêtre).
    func reglage(_ cle: String) -> String? {
        (try? lignes("SELECT valeur FROM reglages WHERE cle = ?", [cle]).first?["valeur"]) as? String
    }

    func definirReglage(_ cle: String, _ valeur: String) throws {
        try executer("INSERT INTO reglages(cle, valeur) VALUES(?, ?) ON CONFLICT(cle) DO UPDATE SET valeur = excluded.valeur", [cle, valeur])
    }

    func versionDonnees() -> Int {
        (try? lignes("PRAGMA data_version").first?["data_version"] as? Int) ?? 0
    }

    func transaction(_ bloc: () throws -> Void) throws {
        try executer("BEGIN IMMEDIATE")
        do { try bloc(); try executer("COMMIT") } catch { try? executer("ROLLBACK"); throw error }
    }
}
