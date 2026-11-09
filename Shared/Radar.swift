// Le Radar : veille de comptes (concurrents KRYVA, créateurs du perso). Reconstruit d'après le guide « Le Radar » de 0xloucash
// (chapitres 05, 07, 10, A01). Ici : les calculs purs (testés), puis le stockage. La source des chiffres est interchangeable
// (voir RadarSource.swift) ; rien dans ce fichier ne touche au réseau.
import Foundation

// MARK: Calculs (fonctions pures, sans base ni réseau)

enum RadarCalcul {
    /// Au moins 5 AUTRES posts uniques, du même compte et de la même plateforme, avec des vues connues (guide, ch. 07).
    static let referencesMin = 5
    /// Les références sont prises sur les 30 jours qui précèdent le relevé.
    static let referencesJours = 30.0
    /// Un post publié depuis moins de 6 h n'est pas jugé ; au-delà de 72 h il n'est plus « du jour » (guide, ch. 07).
    static let fenetreParDefaut: ClosedRange<Double> = 6...72
    /// Gain sur 24 h : deux relevés espacés de 22 à 26 h (guide, ch. 07).
    static let ecartGain: ClosedRange<Double> = 22...26

    /// Un post tel que vu à son dernier relevé. `vues`, `likes`, `commentaires` : nil = inconnu (jamais 0 par défaut).
    struct Post: Equatable {
        let id: String
        let compteId: String
        let plateforme: String
        let publieLe: Date
        let releveLe: Date
        let vues: Int?
        let likes: Int?
        let commentaires: Int?

        /// Âge en heures AU MOMENT du relevé (les chiffres décrivent cet instant, pas aujourd'hui).
        var ageHeures: Double { releveLe.timeIntervalSince(publieLe) / 3600 }
    }

    struct Evaluation: Equatable {
        let post: Post
        let ratio: Double?
        let mediane: Double?
        let references: Int
        let vuesParHeure: Double?
        let likesPour1000Vues: Double?
        /// Pourquoi il n'y a pas de ratio (nil quand il y en a un).
        let raison: String?

        var ageHeures: Double { post.ageHeures }
        /// Piste à reprendre : le post dépasse l'habitude de son créateur.
        var estPiste: Bool { (ratio ?? 0) > 1 }
    }

    /// Médiane ; avec un nombre pair de valeurs, moyenne des deux valeurs centrales. nil si la liste est vide.
    static func mediane(_ valeurs: [Int]) -> Double? {
        guard !valeurs.isEmpty else { return nil }
        let t = valeurs.sorted()
        let m = t.count / 2
        return t.count % 2 == 1 ? Double(t[m]) : Double(t[m - 1] + t[m]) / 2
    }

    /// Vues connues des autres posts du même compte et de la même plateforme, publiés dans les 30 jours avant le relevé du candidat.
    /// Le candidat n'en fait jamais partie ; un identifiant déjà vu n'est compté qu'une fois.
    static func references(de candidat: Post, parmi tous: [Post]) -> [Int] {
        let debut = candidat.releveLe.addingTimeInterval(-referencesJours * 86_400)
        var vus: Set<String> = [candidat.id]
        var vues: [Int] = []
        for p in tous where p.compteId == candidat.compteId && p.plateforme == candidat.plateforme {
            guard !vus.contains(p.id) else { continue }
            vus.insert(p.id)
            guard p.publieLe >= debut, p.publieLe <= candidat.releveLe, let v = p.vues else { continue }
            vues.append(v)
        }
        return vues
    }

    /// ratio = vues du post ÷ médiane des vues de ses AUTRES posts. nil (indéterminé, pas « infini ») s'il y a
    /// moins de 5 références, une médiane nulle, ou des vues inconnues.
    static func evaluer(_ p: Post, parmi tous: [Post]) -> Evaluation {
        let refs = references(de: p, parmi: tous)
        let med = mediane(refs)
        let age = p.ageHeures
        let vph: Double? = {
            guard let v = p.vues, age > 0 else { return nil }
            return Double(v) / age
        }()
        let l1000: Double? = {
            guard let v = p.vues, v > 0, let l = p.likes else { return nil }
            return Double(l) / Double(v) * 1000
        }()
        var ratio: Double?
        var raison: String?
        if p.vues == nil {
            raison = "vues inconnues"
        } else if refs.count < referencesMin {
            raison = "\(refs.count) autre(s) post(s) de référence sur 30 jours, il en faut \(referencesMin)"
        } else if let med, med <= 0 {
            raison = "médiane des autres posts à 0"
        } else if let med, let v = p.vues {
            ratio = Double(v) / med
        }
        return Evaluation(post: p, ratio: ratio, mediane: med, references: refs.count,
                          vuesParHeure: vph, likesPour1000Vues: l1000, raison: raison)
    }

    static func evaluer(_ posts: [Post]) -> [Evaluation] { posts.map { evaluer($0, parmi: posts) } }

    /// Ratio décroissant, puis vues par heure décroissant, puis identifiant (ordre stable).
    static func trier(_ liste: [Evaluation]) -> [Evaluation] {
        liste.sorted { a, b in
            let ra = a.ratio ?? -1, rb = b.ratio ?? -1
            if ra != rb { return ra > rb }
            let va = a.vuesParHeure ?? -1, vb = b.vuesParHeure ?? -1
            if va != vb { return va > vb }
            return a.post.id < b.post.id
        }
    }

    /// Le classement : posts dans la fenêtre d'âge, avec un ratio calculable. Les autres sont rendus à part avec leur raison.
    static func classer(_ evaluations: [Evaluation], fenetre: ClosedRange<Double> = fenetreParDefaut)
        -> (retenus: [Evaluation], exclus: [(Evaluation, String)]) {
        var retenus: [Evaluation] = []
        var exclus: [(Evaluation, String)] = []
        for e in evaluations {
            if e.ageHeures < fenetre.lowerBound {
                exclus.append((e, "publié depuis moins de \(Int(fenetre.lowerBound)) h"))
            } else if e.ageHeures > fenetre.upperBound {
                exclus.append((e, "publié depuis plus de \(Int(fenetre.upperBound)) h"))
            } else if e.ratio == nil {
                exclus.append((e, e.raison ?? "ratio indéterminé"))
            } else {
                retenus.append(e)
            }
        }
        return (trier(retenus), exclus)
    }

    /// Les pistes : dans le classement ET au-dessus de l'habitude du créateur (ratio > 1). Jamais complétées pour faire un Top 3.
    static func top(_ retenus: [Evaluation], n: Int = 3) -> [Evaluation] {
        Array(retenus.filter(\.estPiste).prefix(n))
    }

    /// Gain de vues sur 24 h : seulement avec deux relevés espacés de 22 à 26 h et des compteurs cohérents (non décroissants).
    static func gain24h(avant: (le: Date, vues: Int), apres: (le: Date, vues: Int)) -> Int? {
        let ecart = apres.le.timeIntervalSince(avant.le) / 3600
        guard ecartGain.contains(ecart), apres.vues >= avant.vues else { return nil }
        return apres.vues - avant.vues
    }
}

// MARK: Modèles

struct RadarCompte: Codable, Identifiable, Equatable {
    let id: String
    let espace: String
    let plateforme: String
    let identifiant: String
    let nom: String
    let url: String
    let etat: String
    let verifieLe: String
    let notes: String
    let creeLe: String
}

/// Un post vu par une source, avant rangement dans la base.
struct RadarObservation {
    var plateforme: String
    var compte: String
    var identifiantPost: String
    var url: String = ""
    var legende: String = ""
    var publieLe: Date
    var releveLe: Date
    var vues: Int?
    var likes: Int?
    var commentaires: Int?
    var source: String
}

/// Ce que l'écran, la ligne de commande et l'outil MCP montrent pour un post classé ou écarté.
struct RadarLigne: Codable, Identifiable, Equatable {
    var id: String { postId }
    let postId: String
    let espace: String
    let plateforme: String
    let createur: String
    let url: String
    let legende: String
    let publieLe: String
    let releveLe: String
    let source: String
    let vues: Int?
    let likes: Int?
    let commentaires: Int?
    let ageHeures: Double
    let vuesParHeure: Double?
    let likesPour1000Vues: Double?
    let ratio: Double?
    let mediane: Double?
    let references: Int
    let piste: Bool
    /// Rang dans le Top (1 à 3), sinon nil.
    let rang: Int?
    /// Pourquoi le post est écarté ou sans ratio.
    let raison: String?
    /// Idée déjà enregistrée dans la boîte à idées.
    let ideeId: String?
}

struct RadarClassement: Codable {
    let espace: String
    let simulation: Bool
    let calculeLe: String
    let fenetreHeures: [Double]
    /// Date du relevé le plus récent pris en compte ; nil si aucun.
    let dernierReleve: String?
    let nbComptes: Int
    let nbPosts: Int
    let top: [RadarLigne]
    /// Tous les posts dans la fenêtre avec un ratio, triés (le Top en est la tête filtrée sur ratio > 1).
    let classement: [RadarLigne]
    /// Posts hors fenêtre ou sans ratio, avec la raison.
    let ecartes: [RadarLigne]
    /// Ce qui rend ce classement moins fiable (relevé ancien, peu de comptes, simulation…). Vide quand rien n'est à signaler.
    let avertissements: [String]
}

struct RadarScan: Codable {
    let id: String
    let espace: String
    let source: String
    let debut: String
    let fin: String
    let etat: String
    let nbComptes: Int
    let nbPosts: Int
    let erreurs: String
    /// Crédits dépensés (source payante) ; nil pour une source gratuite.
    var credits: Int? = nil
}

struct RadarIdee: Codable, Identifiable, Equatable {
    let id: String
    let postId: String
    let espace: String
    let concept: String
    /// Instantané de la source au moment de l'enregistrement : ne change plus jamais.
    let sourceFigee: RadarSourceFigee
    /// Notre version : le brouillon vivant, séparé de la source.
    let brouillon: String
    let statut: String
    let revision: Int
    let creeLe: String
    let majLe: String
}

struct RadarSourceFigee: Codable, Equatable {
    let plateforme: String
    let createur: String
    let url: String
    let legende: String
    let publieLe: String
    let releveLe: String
    let vues: Int?
    let likes: Int?
    let commentaires: Int?
    let ratio: Double?
    let mediane: Double?
    let references: Int
    let vuesParHeure: Double?
}

enum ErreurRadar: Error, CustomStringConvertible {
    case invalide(String)
    case introuvable(String)
    case conflit(String)
    case sourceNonConfiguree(String)

    var description: String {
        switch self {
        case .invalide(let m), .introuvable(let m), .conflit(let m), .sourceNonConfiguree(let m): return m
        }
    }
}

enum RadarVocabulaire {
    static let espaces = ["kryva", "perso"]
    static let plateformes = ["instagram", "tiktok"]
    static let statutsIdee = ["a_ecrire", "en_cours", "pret"]
}

// MARK: Stockage

extension Stockage {
    // MARK: Comptes

    static func radarCompte(_ l: [String: Any]) -> RadarCompte {
        RadarCompte(id: l["id"] as? String ?? "", espace: l["espace"] as? String ?? "", plateforme: l["plateforme"] as? String ?? "",
                    identifiant: l["identifiant"] as? String ?? "", nom: l["nom"] as? String ?? "", url: l["url"] as? String ?? "",
                    etat: l["etat"] as? String ?? "actif", verifieLe: l["verifie_le"] as? String ?? "",
                    notes: l["notes"] as? String ?? "", creeLe: l["cree_le"] as? String ?? "")
    }

    /// « @Renovo », « renovo » et « https://www.instagram.com/renovo/ » désignent le même compte.
    static func radarNormaliseIdentifiant(_ brut: String) -> String {
        var s = brut.trimmingCharacters(in: .whitespacesAndNewlines)
        if let u = URL(string: s), let h = u.host, h.contains("instagram.com") || h.contains("tiktok.com") {
            s = u.pathComponents.first { $0 != "/" } ?? s
        }
        if s.hasPrefix("@") { s.removeFirst() }
        return s.lowercased()
    }

    func radarComptes(espace: String? = nil, etat: String? = nil) throws -> [RadarCompte] {
        var sql = "SELECT * FROM radar_comptes WHERE 1 = 1"
        var p: [Any?] = []
        if let espace { sql += " AND espace = ?"; p.append(espace) }
        if let etat { sql += " AND etat = ?"; p.append(etat) }
        return try base.lignes(sql + " ORDER BY espace, plateforme, identifiant", p).map(Self.radarCompte)
    }

    @discardableResult
    func radarAjouteCompte(espace: String, plateforme: String, identifiant: String, nom: String = "", url: String = "", notes: String = "") throws -> RadarCompte {
        guard RadarVocabulaire.espaces.contains(espace) else { throw ErreurRadar.invalide("espace inconnu « \(espace) » (kryva ou perso)") }
        guard RadarVocabulaire.plateformes.contains(plateforme) else { throw ErreurRadar.invalide("plateforme inconnue « \(plateforme) » (instagram ou tiktok)") }
        let h = Self.radarNormaliseIdentifiant(identifiant)
        guard !h.isEmpty else { throw ErreurRadar.invalide("identifiant du compte vide") }
        let id = "\(espace):\(plateforme):\(h)"
        let maintenant = Dates.maintenant()
        // Réajouter un compte le remet en service sans effacer ce qui est déjà relevé.
        try base.executer("""
            INSERT INTO radar_comptes(id, espace, plateforme, identifiant, nom, url, etat, verifie_le, notes, cree_le)
            VALUES(?, ?, ?, ?, ?, ?, 'actif', ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET etat = 'actif',
              nom = CASE WHEN excluded.nom != '' THEN excluded.nom ELSE radar_comptes.nom END,
              url = CASE WHEN excluded.url != '' THEN excluded.url ELSE radar_comptes.url END,
              notes = CASE WHEN excluded.notes != '' THEN excluded.notes ELSE radar_comptes.notes END
            """, [id, espace, plateforme, h, nom, url, maintenant, notes, maintenant])
        return try radarCompte(id)!
    }

    func radarCompte(_ id: String) throws -> RadarCompte? {
        try base.lignes("SELECT * FROM radar_comptes WHERE id = ?", [id]).first.map(Self.radarCompte)
    }

    /// Met un compte en pause (« suspendu », ses relevés restent, il sort du classement) ou le retire (« retire »).
    func radarChangeEtatCompte(_ id: String, etat: String) throws {
        guard ["actif", "suspendu", "retire"].contains(etat) else { throw ErreurRadar.invalide("état inconnu « \(etat) »") }
        guard try radarCompte(id) != nil else { throw ErreurRadar.introuvable("compte « \(id) » inconnu") }
        try base.executer("UPDATE radar_comptes SET etat = ? WHERE id = ?", [etat, id])
    }

    // MARK: Relevés

    /// Identifiant de post à partir d'un lien Instagram (/reel/CODE, /p/CODE) ou TikTok (/video/ID) ; sinon le texte tel quel.
    static func radarIdentifiantPost(_ brut: String) -> String {
        let s = brut.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let u = URL(string: s), u.host != nil else { return s }
        let parts = u.pathComponents.filter { $0 != "/" }
        for (i, p) in parts.enumerated() where ["reel", "reels", "p", "video", "tv"].contains(p) && i + 1 < parts.count {
            return parts[i + 1]
        }
        return parts.last ?? s
    }

    /// Range une observation : crée le compte et le post au besoin, ajoute un relevé daté. Rejouer la même observation
    /// (même post, même instant, même source) ne crée rien de plus. Renvoie false si elle était déjà là.
    @discardableResult
    func radarObserve(_ o: RadarObservation, espace: String, maintenant: Date = Date()) throws -> Bool {
        guard o.releveLe <= maintenant.addingTimeInterval(300) else { throw ErreurRadar.invalide("relevé dans le futur (\(Dates.iso.string(from: o.releveLe)))") }
        guard o.publieLe <= o.releveLe else { throw ErreurRadar.invalide("post publié après son relevé : \(o.identifiantPost)") }
        for (nom, v) in [("vues", o.vues), ("likes", o.likes), ("commentaires", o.commentaires)] where (v ?? 0) < 0 {
            throw ErreurRadar.invalide("\(nom) négatif : \(o.identifiantPost)")
        }
        guard RadarVocabulaire.espaces.contains(espace) else { throw ErreurRadar.invalide("espace inconnu « \(espace) » (kryva ou perso)") }
        let identifiant = Self.radarIdentifiantPost(o.identifiantPost)
        guard !identifiant.isEmpty else { throw ErreurRadar.invalide("identifiant de post vide") }
        let compteIdent = Self.radarNormaliseIdentifiant(o.compte)
        guard RadarVocabulaire.plateformes.contains(o.plateforme), !compteIdent.isEmpty else { throw ErreurRadar.invalide("plateforme ou compte invalide : \(o.plateforme) \(o.compte)") }
        let compteId = "\(espace):\(o.plateforme):\(compteIdent)"
        // Un compte inconnu est créé ; un compte suspendu ou retiré le reste (seul `radarAjouteCompte` le remet en service).
        try base.executer("""
            INSERT OR IGNORE INTO radar_comptes(id, espace, plateforme, identifiant, etat, verifie_le, cree_le) VALUES(?, ?, ?, ?, 'actif', ?, ?)
            """, [compteId, espace, o.plateforme, compteIdent, Dates.maintenant(), Dates.maintenant()])
        let postId = "\(o.plateforme):\(identifiant)"
        var nouveau = false
        try base.transaction {
            try base.executer("""
                INSERT INTO radar_posts(id, compte_id, plateforme, identifiant, url, legende, publie_le, cree_le)
                VALUES(?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                  url = CASE WHEN excluded.url != '' THEN excluded.url ELSE radar_posts.url END,
                  legende = CASE WHEN excluded.legende != '' THEN excluded.legende ELSE radar_posts.legende END
                """, [postId, compteId, o.plateforme, identifiant, o.url, String(o.legende.prefix(1200)),
                      Dates.iso.string(from: o.publieLe), Dates.maintenant()])
            let avant = try base.lignes("SELECT COUNT(*) AS n FROM radar_releves WHERE post_id = ?", [postId]).first?["n"] as? Int ?? 0
            try base.executer("""
                INSERT OR IGNORE INTO radar_releves(post_id, releve_le, vues, likes, commentaires, source) VALUES(?, ?, ?, ?, ?, ?)
                """, [postId, Dates.iso.string(from: o.releveLe), o.vues, o.likes, o.commentaires, o.source])
            let apres = try base.lignes("SELECT COUNT(*) AS n FROM radar_releves WHERE post_id = ?", [postId]).first?["n"] as? Int ?? 0
            nouveau = apres > avant
        }
        return nouveau
    }

    @discardableResult
    func radarNoteScan(espace: String, source: String, debut: Date, nbComptes: Int, nbPosts: Int, erreurs: [String], credits: Int? = nil) throws -> String {
        let id = UUID().uuidString.lowercased()
        let etat = erreurs.isEmpty ? "termine" : (nbPosts > 0 ? "partiel" : "erreur")
        try base.executer("""
            INSERT INTO radar_scans(id, espace, source, debut, fin, etat, nb_comptes, nb_posts, erreurs, credits) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, [id, espace, source, Dates.iso.string(from: debut), Dates.maintenant(), etat, nbComptes, nbPosts, erreurs.joined(separator: "\n"), credits])
        return id
    }

    // MARK: Classement

    private func radarPostsVus(espace: String, simulation: Bool) throws -> (posts: [RadarCalcul.Post], details: [String: [String: Any]]) {
        // Dernier relevé de chaque post des comptes actifs. Les relevés de simulation ne se mélangent jamais aux vrais.
        let lignes = try base.lignes("""
            SELECT p.id, p.compte_id, p.plateforme, p.url, p.legende, p.publie_le,
                   c.identifiant AS createur, r.releve_le, r.vues, r.likes, r.commentaires, r.source
            FROM radar_posts p
            JOIN radar_comptes c ON c.id = p.compte_id AND c.etat = 'actif' AND c.espace = ?1
            JOIN radar_releves r ON r.id = (
              SELECT r2.id FROM radar_releves r2 WHERE r2.post_id = p.id
                AND (r2.source = 'factice') = ?2 ORDER BY r2.releve_le DESC, r2.id DESC LIMIT 1)
            """, [espace, simulation])
        var posts: [RadarCalcul.Post] = []
        var details: [String: [String: Any]] = [:]
        for l in lignes {
            guard let id = l["id"] as? String, let pub = l["publie_le"] as? String, let rel = l["releve_le"] as? String,
                  let dp = Dates.iso.date(from: pub), let dr = Dates.iso.date(from: rel) else { continue }
            posts.append(RadarCalcul.Post(id: id, compteId: l["compte_id"] as? String ?? "", plateforme: l["plateforme"] as? String ?? "",
                                          publieLe: dp, releveLe: dr, vues: l["vues"] as? Int, likes: l["likes"] as? Int,
                                          commentaires: l["commentaires"] as? Int))
            details[id] = l
        }
        return (posts, details)
    }

    private func radarLigne(_ e: RadarCalcul.Evaluation, details d: [String: Any], espace: String, rang: Int?, raison: String?, idees: [String: String]) -> RadarLigne {
        RadarLigne(postId: e.post.id, espace: espace, plateforme: e.post.plateforme, createur: d["createur"] as? String ?? "",
                   url: d["url"] as? String ?? "", legende: d["legende"] as? String ?? "",
                   publieLe: Dates.iso.string(from: e.post.publieLe), releveLe: Dates.iso.string(from: e.post.releveLe),
                   source: d["source"] as? String ?? "", vues: e.post.vues, likes: e.post.likes, commentaires: e.post.commentaires,
                   ageHeures: (e.ageHeures * 10).rounded() / 10, vuesParHeure: e.vuesParHeure.map { ($0 * 10).rounded() / 10 },
                   likesPour1000Vues: e.likesPour1000Vues.map { ($0 * 10).rounded() / 10 },
                   ratio: e.ratio.map { ($0 * 100).rounded() / 100 }, mediane: e.mediane, references: e.references,
                   piste: e.estPiste, rang: rang, raison: raison ?? e.raison, ideeId: idees[e.post.id])
    }

    /// Le Radar d'un espace : classement des posts de 6 à 72 h (par défaut), Top 3 des pistes, et ce qui est écarté avec sa raison.
    /// L'âge d'un post est celui qu'il avait à son dernier relevé : un relevé ancien décrit le passé, `dernierReleve` le dit.
    func radarClassement(espace: String, fenetre: ClosedRange<Double> = RadarCalcul.fenetreParDefaut,
                         simulation: Bool = false, maintenant: Date = Date()) throws -> RadarClassement {
        let (vus, details) = try radarPostsVus(espace: espace, simulation: simulation)
        let posts = vus.sorted { $0.id < $1.id }
        return try radarAssembler(espace: espace, evaluations: RadarCalcul.evaluer(posts), posts: posts, details: details,
                                  fenetre: fenetre, simulation: simulation, maintenant: maintenant)
    }

    private func radarAssembler(espace: String, evaluations: [RadarCalcul.Evaluation], posts: [RadarCalcul.Post], details: [String: [String: Any]],
                                fenetre: ClosedRange<Double>, simulation: Bool, maintenant: Date) throws -> RadarClassement {
        let idees = Dictionary(uniqueKeysWithValues: try base.lignes("SELECT id, post_id FROM radar_idees WHERE espace = ?", [espace])
            .compactMap { l -> (String, String)? in
                guard let p = l["post_id"] as? String, let i = l["id"] as? String else { return nil }
                return (p, i)
            })
        let (retenus, exclus) = RadarCalcul.classer(evaluations, fenetre: fenetre)
        let top = RadarCalcul.top(retenus)
        let rangs = Dictionary(uniqueKeysWithValues: top.enumerated().map { ($1.post.id, $0 + 1) })
        func ligne(_ e: RadarCalcul.Evaluation, _ raison: String? = nil) -> RadarLigne {
            radarLigne(e, details: details[e.post.id] ?? [:], espace: espace, rang: rangs[e.post.id], raison: raison, idees: idees)
        }
        let comptes = Set(posts.map(\.compteId)).count
        var avertissements: [String] = []
        let suivis = try radarComptes(espace: espace, etat: "actif").count
        if simulation { avertissements.append("SIMULATION : chiffres fabriqués, ne rien en conclure.") }
        if suivis == 0 {
            avertissements.append("Aucun compte suivi dans l'espace \(espace) (pilote radar compte-ajoute).")
        } else if posts.isEmpty {
            avertissements.append("\(suivis) compte(s) suivi(s) mais aucun relevé : faire un scan ou « pilote radar importe ».")
        }
        if let dernier = posts.map(\.releveLe).max() {
            let h = maintenant.timeIntervalSince(dernier) / 3600
            if h > 36 { avertissements.append("Dernier relevé il y a \(Int(h)) h : le classement décrit le passé, refaire un relevé avant d'en tirer un Top du jour.") }
        }
        let sansRef = Set(evaluations.filter { $0.post.vues != nil && $0.references < RadarCalcul.referencesMin }
            .map { "@" + ((details[$0.post.id]?["createur"] as? String) ?? $0.post.compteId) })
        if !sansRef.isEmpty {
            avertissements.append("Pas de ratio pour \(sansRef.sorted().joined(separator: ", ")) : moins de \(RadarCalcul.referencesMin) autres posts sur 30 jours.")
        }
        return RadarClassement(
            espace: espace, simulation: simulation, calculeLe: Dates.iso.string(from: maintenant),
            fenetreHeures: [fenetre.lowerBound, fenetre.upperBound],
            dernierReleve: posts.map(\.releveLe).max().map { Dates.iso.string(from: $0) },
            nbComptes: comptes, nbPosts: posts.count,
            top: top.map { ligne($0) }, classement: retenus.map { ligne($0) },
            ecartes: exclus.map { ligne($0.0, $0.1) }, avertissements: avertissements)
    }

    // MARK: Divers

    /// Espace d'un post (par son compte), pour enregistrer une idée sans demander l'espace.
    func radarEspaceDuPost(_ postId: String) throws -> String? {
        try base.lignes("SELECT c.espace FROM radar_posts p JOIN radar_comptes c ON c.id = p.compte_id WHERE p.id = ?", [postId]).first?["espace"] as? String
    }

    func radarScans(limite: Int = 20) throws -> [RadarScan] {
        try base.lignes("SELECT * FROM radar_scans ORDER BY debut DESC LIMIT ?", [limite]).map {
            RadarScan(id: $0["id"] as? String ?? "", espace: $0["espace"] as? String ?? "", source: $0["source"] as? String ?? "",
                      debut: $0["debut"] as? String ?? "", fin: $0["fin"] as? String ?? "", etat: $0["etat"] as? String ?? "",
                      nbComptes: $0["nb_comptes"] as? Int ?? 0, nbPosts: $0["nb_posts"] as? Int ?? 0, erreurs: $0["erreurs"] as? String ?? "",
                      credits: $0["credits"] as? Int)
        }
    }

    /// Efface les relevés de simulation et les posts qui n'ont plus aucun relevé. Les vrais relevés et les idées ne sont pas touchés.
    @discardableResult
    func radarPurgeSimulation() throws -> Int {
        var n = 0
        try base.transaction {
            n = try base.lignes("SELECT COUNT(*) AS n FROM radar_releves WHERE source = 'factice'").first?["n"] as? Int ?? 0
            try base.executer("DELETE FROM radar_releves WHERE source = 'factice'")
            try base.executer("DELETE FROM radar_posts WHERE id NOT IN (SELECT post_id FROM radar_releves) AND id NOT IN (SELECT post_id FROM radar_idees)")
            try base.executer("DELETE FROM radar_scans WHERE source = 'factice'")
        }
        return n
    }

    // MARK: Boîte à idées

    static func radarIdee(_ l: [String: Any]) -> RadarIdee? {
        guard let id = l["id"] as? String, let p = l["post_id"] as? String, let src = l["source_figee"] as? String,
              let figee = try? JSONDecoder().decode(RadarSourceFigee.self, from: Data(src.utf8)) else { return nil }
        return RadarIdee(id: id, postId: p, espace: l["espace"] as? String ?? "", concept: l["concept"] as? String ?? "",
                         sourceFigee: figee, brouillon: l["brouillon"] as? String ?? "", statut: l["statut"] as? String ?? "a_ecrire",
                         revision: l["revision"] as? Int ?? 0, creeLe: l["cree_le"] as? String ?? "", majLe: l["maj_le"] as? String ?? "")
    }

    func radarIdees(espace: String? = nil, statut: String? = nil) throws -> [RadarIdee] {
        var sql = "SELECT * FROM radar_idees WHERE 1 = 1"
        var p: [Any?] = []
        if let espace { sql += " AND espace = ?"; p.append(espace) }
        if let statut { sql += " AND statut = ?"; p.append(statut) }
        return try base.lignes(sql + " ORDER BY maj_le DESC", p).compactMap(Self.radarIdee)
    }

    func radarIdee(_ id: String) throws -> RadarIdee? {
        try base.lignes("SELECT * FROM radar_idees WHERE id = ?", [id]).first.flatMap(Self.radarIdee)
    }

    /// Enregistre une idée à partir d'un post : fige la source (URL, créateur, légende, chiffres et ratio à cet instant).
    /// Enregistrer deux fois le même post renvoie l'idée existante, sans rien changer à son brouillon.
    @discardableResult
    func radarEnregistreIdee(postId: String, espace: String, concept: String = "", simulation: Bool = false, maintenant: Date = Date()) throws -> (idee: RadarIdee, nouvelle: Bool) {
        if let l = try base.lignes("SELECT * FROM radar_idees WHERE post_id = ?", [postId]).first, let i = Self.radarIdee(l) { return (i, false) }
        let (posts, details) = try radarPostsVus(espace: espace, simulation: simulation)
        guard let p = posts.first(where: { $0.id == postId }), let d = details[postId] else {
            throw ErreurRadar.introuvable("post « \(postId) » inconnu dans l'espace \(espace)")
        }
        let e = RadarCalcul.evaluer(p, parmi: posts)
        let figee = RadarSourceFigee(
            plateforme: p.plateforme, createur: d["createur"] as? String ?? "", url: d["url"] as? String ?? "",
            legende: String((d["legende"] as? String ?? "").prefix(600)), publieLe: Dates.iso.string(from: p.publieLe),
            releveLe: Dates.iso.string(from: p.releveLe), vues: p.vues, likes: p.likes, commentaires: p.commentaires,
            ratio: e.ratio, mediane: e.mediane, references: e.references, vuesParHeure: e.vuesParHeure)
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let json = String(data: try enc.encode(figee), encoding: .utf8)!
        let id = UUID().uuidString.lowercased()
        let t = Dates.iso.string(from: maintenant)
        try base.executer("""
            INSERT INTO radar_idees(id, post_id, espace, concept, source_figee, brouillon, statut, revision, cree_le, maj_le)
            VALUES(?, ?, ?, ?, ?, '', 'a_ecrire', 0, ?, ?)
            """, [id, postId, espace, concept, json, t, t])
        return (try radarIdee(id)!, true)
    }

    /// Écrit notre version. `revision` est celle que l'appelant a lue : si l'idée a changé entre-temps, rien n'est écrit
    /// (conflit), pour qu'une édition ne perde pas le travail d'une autre.
    @discardableResult
    func radarEcritIdee(id: String, brouillon: String?, concept: String? = nil, statut: String? = nil, revision: Int, maintenant: Date = Date()) throws -> RadarIdee {
        guard let actuelle = try radarIdee(id) else { throw ErreurRadar.introuvable("idée « \(id) » inconnue") }
        if let s = statut, !RadarVocabulaire.statutsIdee.contains(s) { throw ErreurRadar.invalide("statut inconnu « \(s) » (a_ecrire, en_cours, pret)") }
        guard actuelle.revision == revision else {
            throw ErreurRadar.conflit("conflit : l'idée est à la révision \(actuelle.revision), vous avez modifié la \(revision). Rien n'a été écrit ; relisez-la.")
        }
        try base.executer("""
            UPDATE radar_idees SET brouillon = ?, concept = ?, statut = ?, revision = revision + 1, maj_le = ? WHERE id = ? AND revision = ?
            """, [brouillon ?? actuelle.brouillon, concept ?? actuelle.concept, statut ?? actuelle.statut, Dates.iso.string(from: maintenant), id, revision])
        return try radarIdee(id)!
    }
}
