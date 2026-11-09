// Les vidéos (règle de Sacha du 03/11) : 2 par jour du lundi au vendredi, 1 KRYVA + 1 perso,
// tournées et montées la veille ouvrée, publiées le jour. Une ligne par vidéo ; Réseaux la tient à jour.
import Foundation

struct Video: Identifiable, Hashable, Codable {
    var id: String
    var jour: String = ""        // AAAA-MM-JJ de publication ; vide = sujet de réserve
    var compte: String = "kryva" // kryva | perso
    var sujet: String = ""
    var statut: String = "a_choisir" // a_choisir | valide | tournee | prete | publiee | annulee
    var heure: String = ""       // HH:MM de publication
    var prompteur: String = ""   // chemin ou adresse du prompteur
    var fiche: String = ""       // chemin de la fiche du sujet
    var notes: String = ""
    var creeLe: String = ""
    var majLe: String = ""
}

enum VideoVocabulaire {
    static let comptes: [(String, String)] = [("kryva", "KRYVA"), ("perso", "Perso")]
    static let statuts: [(String, String)] = [
        ("a_choisir", "Sujet à choisir"), ("valide", "Sujet validé"), ("tournee", "Tournée, en montage"),
        ("prete", "Prête"), ("publiee", "Publiée"), ("annulee", "Annulée"),
    ]
    static func compte(_ c: String) -> String { Libelles.libelle(comptes, c) }
    static func statut(_ s: String) -> String { Libelles.libelle(statuts, s) }
}

/// Ce que l'écran montre pour une vidéo, selon le jour : un mot et une couleur.
enum TonVideo: String { case neutre, ambre, vert, rouge }

enum VideoCalcul {
    /// La cible d'une ligne de Ma journée qui coche une étape de vidéo : « video:AAAA-MM-JJ:compte:action ».
    static func cible(jour: String, compte: String, action: String) -> String { "video:\(jour):\(compte):\(action)" }

    /// Le statut de la vidéo quand on coche (fait) ou décoche une étape de Ma journée : tourner → tournée ; valider le montage →
    /// prête ; publier → publiée. Décocher revient au statut d'avant. nil si l'action est inconnue.
    static func statutApres(action: String, fait: Bool) -> String? {
        switch (action, fait) {
        case ("tourner", true): return "tournee"
        case ("tourner", false): return "valide"
        case ("valider", true): return "prete"
        case ("valider", false): return "tournee"
        case ("publier", true): return "publiee"
        case ("publier", false): return "prete"
        default: return nil
        }
    }

    private static var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Paris")!
        return c
    }

    private static func decaler(_ jour: String, _ pas: Int) -> String {
        guard var d = Dates.jour.date(from: jour) else { return jour }
        repeat { d = cal.date(byAdding: .day, value: pas, to: d)! } while cal.isDateInWeekend(d)
        return Dates.jour.string(from: d)
    }

    /// Le jour du tournage : la veille ouvrée de la publication (lundi → vendredi).
    static func veilleOuvree(_ jour: String) -> String { decaler(jour, -1) }
    static func lendemainOuvre(_ jour: String) -> String { decaler(jour, 1) }

    static func estOuvre(_ jour: String) -> Bool {
        guard let d = Dates.jour.date(from: jour) else { return false }
        return !cal.isDateInWeekend(d)
    }

    /// Lundi à vendredi de la semaine du jour donné (le samedi et le dimanche montrent la semaine qui vient).
    static func semaine(de jour: String) -> [String] {
        guard var d = Dates.jour.date(from: jour) else { return [] }
        while cal.isDateInWeekend(d) { d = cal.date(byAdding: .day, value: 1, to: d)! }
        let jourSemaine = cal.component(.weekday, from: d) // 2 = lundi
        let lundi = cal.date(byAdding: .day, value: 2 - jourSemaine, to: d)!
        return (0..<5).map { Dates.jour.string(from: cal.date(byAdding: .day, value: $0, to: lundi)!) }
    }

    static func decalerSemaine(_ jour: String, _ semaines: Int) -> String {
        guard let d = Dates.jour.date(from: jour) else { return jour }
        return Dates.jour.string(from: cal.date(byAdding: .day, value: 7 * semaines, to: d)!)
    }

    /// Le mot de la case : « Publiée », « Prête », « Montage », « À tourner », « Ratée »…
    static func affichage(_ v: Video?, jour: String, aujourdhui: String) -> (texte: String, ton: TonVideo) {
        guard let v, v.statut != "a_choisir" else {
            if jour < aujourdhui { return ("Rien", .rouge) }
            return ("Sujet ?", jour <= lendemainOuvre(aujourdhui) ? .rouge : .neutre)
        }
        switch v.statut {
        case "publiee": return ("Publiée", .vert)
        case "annulee": return ("Annulée", .neutre)
        default: break
        }
        if jour < aujourdhui { return ("Ratée", .rouge) }
        switch v.statut {
        case "prete": return ("Prête", .vert)
        case "tournee": return ("Montage", .ambre)
        default:
            if jour == aujourdhui { return ("Pas tournée", .rouge) }
            if veilleOuvree(jour) <= aujourdhui { return ("À tourner", .ambre) }
            return ("Validée", .neutre)
        }
    }
}

extension Base {
    /// 03/11 : les vidéos. Locale à Pilote (pas de synchro avec l'admin).
    func migrerVideos() throws {
        try executer("""
        CREATE TABLE IF NOT EXISTS videos (
          id TEXT PRIMARY KEY,
          jour TEXT NOT NULL DEFAULT '',
          compte TEXT NOT NULL DEFAULT 'kryva',
          sujet TEXT NOT NULL DEFAULT '',
          statut TEXT NOT NULL DEFAULT 'a_choisir',
          heure TEXT NOT NULL DEFAULT '',
          prompteur TEXT NOT NULL DEFAULT '',
          fiche TEXT NOT NULL DEFAULT '',
          notes TEXT NOT NULL DEFAULT '',
          cree_le TEXT NOT NULL,
          maj_le TEXT NOT NULL,
          supprime_le TEXT NOT NULL DEFAULT ''
        )
        """)
        try executer("CREATE INDEX IF NOT EXISTS videos_jour ON videos(jour, compte)")
    }
}

struct ErreurVideo: Error, CustomStringConvertible { let description: String }

extension Stockage {
    static let colonnesVideo = ["jour", "compte", "sujet", "statut", "heure", "prompteur", "fiche", "notes"]

    /// Les vidéos d'une plage de jours (bornes comprises), plus les sujets de réserve si `reserve`.
    func videos(du debut: String, au fin: String, reserve: Bool = false) throws -> [Video] {
        try base.lignes("""
            SELECT * FROM videos WHERE supprime_le = '' AND ((jour >= ? AND jour <= ?) OR (? AND jour = ''))
            ORDER BY jour, compte
            """, [debut, fin, reserve ? 1 : 0]).map(Self.video)
    }

    func video(_ id: String) throws -> Video? {
        try base.lignes("SELECT * FROM videos WHERE id = ?", [id]).first.map(Self.video)
    }

    /// Crée ou modifie une vidéo : par id, sinon par (jour, compte) quand le jour est donné. Seuls les champs fournis changent.
    @discardableResult
    func enregistrerVideo(_ champs: [String: Any]) throws -> Video {
        if let c = champs["compte"] as? String, !VideoVocabulaire.comptes.contains(where: { $0.0 == c }) {
            throw ErreurVideo(description: "compte inconnu « \(c) » (kryva ou perso)")
        }
        if let s = champs["statut"] as? String, !VideoVocabulaire.statuts.contains(where: { $0.0 == s }) {
            throw ErreurVideo(description: "statut inconnu « \(s) » (a_choisir, valide, tournee, prete, publiee, annulee)")
        }
        if let j = champs["jour"] as? String, !j.isEmpty {
            guard Dates.jour.date(from: j) != nil, j.count == 10 else { throw ErreurVideo(description: "jour attendu au format AAAA-MM-JJ") }
            guard VideoCalcul.estOuvre(j) else { throw ErreurVideo(description: "\(j) est un samedi ou un dimanche : rien le week-end") }
        }
        let maintenant = Dates.maintenant()
        var existant: Video?
        if let id = champs["id"] as? String, !id.isEmpty {
            existant = try video(id)
            if existant == nil { throw ErreurVideo(description: "vidéo introuvable : \(id)") }
        } else if let j = champs["jour"] as? String, !j.isEmpty {
            let compte = champs["compte"] as? String ?? "kryva"
            existant = try base.lignes("SELECT * FROM videos WHERE jour = ? AND compte = ? AND supprime_le = '' LIMIT 1", [j, compte])
                .first.map(Self.video)
        }
        let fournis = Self.colonnesVideo.filter { champs[$0] != nil }
        let valeurs: [Any?] = fournis.map { "\(champs[$0]!)" }
        if let existant {
            guard !fournis.isEmpty else { return existant }
            let sets = fournis.map { "\($0) = ?" }.joined(separator: ", ")
            try base.executer("UPDATE videos SET \(sets), maj_le = ? WHERE id = ?", valeurs + [maintenant, existant.id])
            return try video(existant.id)!
        }
        let id = UUID().uuidString.lowercased()
        let cols = ["id"] + fournis + ["cree_le", "maj_le"]
        let marques = Array(repeating: "?", count: cols.count).joined(separator: ", ")
        try base.executer("INSERT INTO videos (\(cols.joined(separator: ", "))) VALUES (\(marques))", [id] + valeurs + [maintenant, maintenant])
        return try video(id)!
    }

    func supprimerVideo(_ id: String) throws {
        try base.executer("UPDATE videos SET supprime_le = ?, maj_le = ? WHERE id = ?", [Dates.maintenant(), Dates.maintenant(), id])
    }

    static func video(_ l: [String: Any]) -> Video {
        func s(_ k: String) -> String { l[k] as? String ?? "" }
        return Video(id: s("id"), jour: s("jour"), compte: s("compte"), sujet: s("sujet"), statut: s("statut"), heure: s("heure"),
                     prompteur: s("prompteur"), fiche: s("fiche"), notes: s("notes"), creeLe: s("cree_le"), majLe: s("maj_le"))
    }

    // MARK: Prospects : le dernier échange de chaque contact (pour la couleur « depuis combien de jours »)

    /// Pour chaque contact : la date et une ligne du dernier échange fait (les messages préparés non envoyés ne comptent pas).
    func derniersEchanges() throws -> [String: DernierEchange] {
        var r: [String: DernierEchange] = [:]
        for l in try base.lignes("""
            SELECT e.contact_id, e.le, e.canal, e.sens, e.type, e.texte FROM evenements e
            JOIN (SELECT contact_id, MAX(le) AS m FROM evenements WHERE supprime_le = '' AND statut NOT IN ('prepare', 'a_valider', 'a_refaire') GROUP BY contact_id) d
              ON d.contact_id = e.contact_id AND d.m = e.le
            WHERE e.supprime_le = '' AND e.statut NOT IN ('prepare', 'a_valider', 'a_refaire')
            """) {
            let id = l["contact_id"] as? String ?? ""
            r[id] = DernierEchange(le: l["le"] as? String ?? "", canal: l["canal"] as? String ?? "",
                                   sens: l["sens"] as? String ?? "", type: l["type"] as? String ?? "", texte: l["texte"] as? String ?? "")
        }
        return r
    }
}

struct DernierEchange: Hashable, Codable {
    let le: String
    let canal: String
    let sens: String
    let type: String
    let texte: String

    /// « Mail envoyé le 21 oct. », « A répondu par SMS le 28 oct. »
    var resume: String {
        let quand = Dates.court(le)
        let canal = Libelles.canal(self.canal)
        switch sens {
        case "entrant": return "A répondu (\(canal)) le \(quand)"
        case "sortant": return self.canal == "autre" ? "\(Libelles.typeEvenement(type)) envoyé le \(quand)" : "\(canal) envoyé le \(quand)"
        default: return "\(Libelles.typeEvenement(type)) le \(quand)"
        }
    }

    func jours(depuis aujourdhui: Date = Date()) -> Int? {
        guard let d = Dates.date(le) else { return nil }
        return Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: d), to: Calendar.current.startOfDay(for: aujourdhui)).day
    }
}
