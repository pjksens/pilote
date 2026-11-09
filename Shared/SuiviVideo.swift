// Le suivi de chaque vidéo postée (demande de Sacha, 04/11) : relevés à 48 h et 7 j, rétention, conversions, verdict.
//
// UNE SOURCE PAR FAIT, rien de copié :
//   les chiffres (vues, rétention, conversions) = ~/Projects/reseaux-stats/stats.sqlite, tenu par Réseaux, LU EN LECTURE SEULE ;
//   les verdicts (a marché ou non, pourquoi, leçon) = la base de Pilote, table video_verdicts, écrits par Réseaux avec `pilote video-verdict`.
// Une « vidéo » de stats.sqlite est un post sur UN réseau : le même contenu posté sur TikTok et Instagram fait deux lignes.
//
// Limites de la donnée (vérifiées le 04/11) : peu de relevés ont la rétention (3 s, temps moyen, vue entière) ; aucune courbe de
// décrochage dans la base (champ `decrochage_s` du verdict, rempli à la main quand le Studio la montre) ; les conversions sont
// PAR SOURCE ET PAR PÉRIODE, jamais par vidéo (il faudrait un lien avec utm_content par vidéo).
import Foundation
import SQLite3

private let TRANSITOIRE = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

struct ErreurSuivi: Error, CustomStringConvertible { let description: String }

// MARK: Modèles

enum PalierReleve: String, Hashable, Codable {
    case h48, j7, autre
    /// Un relevé « à 48 h » = fait entre 24 h et 96 h après la publication ; « à 7 jours » = entre 5 et 10 jours.
    static func depuis(heures: Double?) -> PalierReleve {
        guard let h = heures else { return .autre }
        if (24...96).contains(h) { return .h48 }
        if (120...240).contains(h) { return .j7 }
        return .autre
    }
    /// « 48h » / « 7j » : le code écrit dans les verdicts et dans les sorties de `pilote video-stats` / `video-dus`.
    var code: String { self == .h48 ? "48h" : (self == .j7 ? "7j" : "autre") }
    init?(code: String) {
        switch code.lowercased().replacingOccurrences(of: " ", with: "") {
        case "48h": self = .h48
        case "7j", "7jours": self = .j7
        default: return nil
        }
    }
    /// Heures après la publication où le relevé est attendu, et dernière heure où il sert encore.
    var cible: Double { self == .h48 ? 48 : 168 }
    var limite: Double { self == .h48 ? 96 : 240 }
    /// Un relevé fait plus de 12 h avant la cible (un coup d'œil du premier jour) ne compte pas pour le palier : le vrai relevé reste dû.
    var debutUtile: Double { cible - 12 }
}

/// Où en est un palier (48 h ou 7 j) d'un post : pas encore l'heure, relevé à faire, relevé fait mais verdict à écrire, tout fait, ou fenêtre passée sans relevé.
enum EtatPalier: String, Hashable, Codable { case aAttendre = "a_attendre", aReleve = "a_relever", aJuger = "a_juger", fait, manque }

struct ReleveVideo: Hashable, Codable {
    var releveLe: String = ""
    var source: String = ""
    var vues: Int?, likes: Int?, commentaires: Int?, partages: Int?, enregistrements: Int?
    var tempsMoyenS: Double?
    var vueEntierPct: Double?
    var r3sPct: Double?
    var abonnesGagnes: Int?
    var pourToiPct: Double?
    var recherchePct: Double?
    var delaiHeures: Double?
    var palier: PalierReleve { PalierReleve.depuis(heures: delaiHeures) }

    /// « 48 h », « 7 j », « 3 h », « 19 j » : le délai après la publication, dit simplement.
    var delaiTexte: String {
        guard let h = delaiHeures else { return "?" }
        return h < 48 ? "\(Int(h.rounded())) h" : "\(Int((h / 24).rounded())) j"
    }
}

struct ConversionLigne: Hashable, Codable {
    var periode: String = ""      // « 2026-10-21..27 » ou « 2026-09-28..10-27 » (jour de fin abrégé) ou un seul jour
    var source: String = ""       // utm_source : tiktok, instagram, instagram_perso, youtube, guide_perso… ou le total
    var clics: Int?
    var inscriptions: Int?
    static let total = "total"
}

enum VerdictVocabulaire {
    static let verdicts: [(String, String)] = [("marche", "A marché"), ("moyen", "Moyen"), ("rate", "N'a pas marché"), ("trop_tot", "Trop tôt pour dire")]
    static func libelle(_ v: String) -> String { Libelles.libelle(verdicts, v) }
}

struct VerdictVideo: Hashable, Codable {
    var compteId: String
    var ref: String
    var palier: String = "48h"         // le relevé auquel répond ce verdict : 48h | 7j (l'analyse de fond se fait au 7j)
    var verdict: String = ""           // marche | moyen | rate | trop_tot
    var pourquoi: String = ""
    var lecon: String = ""
    var analyse: String = ""           // l'analyse de fond (surtout au 7j) : ce qui a marché ou non, par rapport aux vidéos précédentes, hypothèses
    var decrochageS: Double?           // seconde où les gens décrochent, si le Studio donne la courbe
    var decrochageNote: String = ""
    var baseReleveLe: String = ""      // le relevé sur lequel Réseaux s'est appuyé
    var ecritLe: String = ""
    var par: String = ""
}

struct PostVideo: Identifiable, Hashable, Codable {
    var compteId: String
    var reseau: String = ""
    var compte: String = ""            // perso | KRYVA
    var pseudo: String = ""
    var ref: String
    var titre: String = ""
    var format: String = ""
    var publieLe: String = ""          // AAAA-MM-JJTHH:MM, heure de Paris
    var dureeS: Double?
    var promoEur: Double = 0
    var visible: Bool = true
    var fichier: String = ""
    var notes: String = ""
    var releves: [ReleveVideo] = []    // du plus ancien au plus récent
    var conversions: [ConversionLigne] = []
    var verdicts: [VerdictVideo] = []  // au plus un par palier (48h, 7j)
    var sujetPlanning: String?
    var id: String { compteId + "|" + ref }

    func verdict(_ p: PalierReleve) -> VerdictVideo? { verdicts.first { $0.palier == p.code && !$0.verdict.isEmpty } }
    /// Un verdict écrit sur un relevé trop jeune pour être un 48 h (moins de 24 h après la publication) : gardé, mais il ne compte pas pour un palier.
    var verdictPrecoce: VerdictVideo? { verdicts.first { $0.palier == "autre" && !$0.verdict.isEmpty } }
    /// Le verdict le plus avancé : celui du 7 j, sinon celui du 48 h, sinon la lecture précoce.
    var verdict: VerdictVideo? { verdict(.j7) ?? verdict(.h48) ?? verdictPrecoce }

    var jour: String { String(publieLe.prefix(10)) }
    var famille: String { compte.lowercased() == "kryva" ? "kryva" : "perso" }
    var dernier: ReleveVideo? { releves.last }
    /// Le relevé du palier le plus proche de la cible (48 h ou 7 j), nil si aucun n'a été fait dans la fenêtre.
    func releve(_ p: PalierReleve) -> ReleveVideo? {
        let cible: Double = p == .h48 ? 48 : 168
        return releves.filter { $0.palier == p }.min { abs(($0.delaiHeures ?? 0) - cible) < abs(($1.delaiHeures ?? 0) - cible) }
    }
    /// Le dernier relevé qui donne la rétention (3 s, temps moyen ou vue entière) : le plus utile pour comprendre.
    var releveRetention: ReleveVideo? { releves.last { $0.r3sPct != nil || $0.tempsMoyenS != nil || $0.vueEntierPct != nil } }
}

struct SuiviCharge {
    var posts: [PostVideo] = []
    var erreur: String?
}

// MARK: Calculs purs (testés)

enum SuiviVideo {
    static var cheminStats: URL {
        if let autre = ProcessInfo.processInfo.environment["PILOTE_STATS"], !autre.isEmpty { return URL(fileURLWithPath: autre) }
        return Demo.maison.appendingPathComponent("Projects/reseaux-stats/stats.sqlite")
    }

    private static let formatMinute: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Europe/Paris")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return f
    }()

    /// Heures entre la publication et le relevé (les deux au format AAAA-MM-JJTHH:MM, heure de Paris). nil si une date est illisible.
    static func delaiHeures(publieLe: String, releveLe: String) -> Double? {
        guard let a = formatMinute.date(from: String(publieLe.prefix(16))), let b = formatMinute.date(from: String(releveLe.prefix(16))) else { return nil }
        return b.timeIntervalSince(a) / 3600
    }

    /// Les deux bornes d'une période de conversions : « 2026-10-21..27 » → (2026-10-21, 2026-10-27) ; « 2026-09-28..10-27 » → (…, 2026-10-27) ;
    /// un seul jour → (jour, jour).
    static func bornes(_ periode: String) -> (debut: String, fin: String)? {
        let p = periode.trimmingCharacters(in: .whitespaces)
        guard p.count >= 10, let _ = Dates.jour.date(from: String(p.prefix(10))) else { return nil }
        let debut = String(p.prefix(10))
        guard let r = p.range(of: "..") else { return (debut, debut) }
        let fin = String(p[r.upperBound...])
        switch fin.count {
        case 10: return (debut, fin)
        case 5: return (debut, String(debut.prefix(4)) + "-" + fin)
        case 2: return (debut, String(debut.prefix(7)) + "-" + fin)
        default: return nil
        }
    }

    /// Les sources de conversion qui parlent d'un compte. Elles sont PAR RÉSEAU, pas par vidéo : tiktok mêle les deux comptes TikTok.
    static func sourcesDuCompte(_ compteId: String) -> [String] {
        switch compteId {
        case "insta_kryva": return ["instagram"]
        case "insta_perso": return ["instagram_perso"]
        case "tiktok_kryva", "tiktok_perso": return ["tiktok"]
        case "youtube_kryva": return ["youtube"]
        default: return []
        }
    }

    /// Pour la date de publication : par source du compte (et le total de la période), la période la plus courte qui contient le jour.
    /// Vide si aucune période relevée ne couvre la publication (les posts récents n'ont pas encore de conversions).
    static func conversions(publieLe: String, compteId: String, toutes: [ConversionLigne]) -> [ConversionLigne] {
        let jour = String(publieLe.prefix(10))
        let voulues = sourcesDuCompte(compteId) + [ConversionLigne.total]
        var meilleures: [String: (ligne: ConversionLigne, longueur: Int)] = [:]
        for l in toutes where voulues.contains(l.source) {
            guard let b = bornes(l.periode), b.debut <= jour, jour <= b.fin,
                  let d = Dates.jour.date(from: b.debut), let f = Dates.jour.date(from: b.fin) else { continue }
            let longueur = Int(f.timeIntervalSince(d) / 86400)
            if let deja = meilleures[l.source], deja.longueur <= longueur { continue }
            meilleures[l.source] = (l, longueur)
        }
        return voulues.compactMap { meilleures[$0]?.ligne }
    }

    /// Le sujet prévu au planning de Pilote pour ce post : même jour de publication, même famille (kryva ou perso), pas annulé.
    static func sujetPlanning(publieLe: String, famille: String, planning: [Video]) -> String? {
        let jour = String(publieLe.prefix(10))
        let s = planning.first { $0.jour == jour && $0.compte == famille && $0.statut != "annulee" && !$0.sujet.isEmpty }?.sujet
        return s
    }

    // MARK: Lecture

    static func charger(stock: Stockage, chemin: URL = cheminStats) -> SuiviCharge {
        guard FileManager.default.fileExists(atPath: chemin.path) else {
            return SuiviCharge(posts: [], erreur: "stats.sqlite introuvable : \(chemin.path)")
        }
        do {
            let lecteur = try LecteurStats(chemin: chemin)
            let comptes = Dictionary(uniqueKeysWithValues: try lecteur.lignes("SELECT id, reseau, compte, pseudo FROM comptes").compactMap { l -> (String, [String: Any])? in
                guard let id = l["id"] as? String else { return nil }
                return (id, l)
            })
            let relevesBruts = try lecteur.lignes("""
                SELECT video_id, releve_le, source, vues, likes, commentaires, partages, enregistrements, temps_moyen_s, vue_entier_pct,
                       r3s_pct, abonnes_gagnes, pour_toi_pct, recherche_pct FROM releves ORDER BY releve_le, id
                """)
            var parVideo: [Int: [[String: Any]]] = [:]
            for r in relevesBruts { if let v = r["video_id"] as? Int { parVideo[v, default: []].append(r) } }
            let conversionsBrutes = try lecteur.lignes("SELECT jour, source, clics, inscriptions FROM conversions").map {
                ConversionLigne(periode: $0["jour"] as? String ?? "", source: $0["source"] as? String ?? "", clics: $0["clics"] as? Int, inscriptions: $0["inscriptions"] as? Int)
            }
            let planning = (try? stock.videos(du: "0000-00-00", au: "9999-99-99", reserve: false)) ?? []
            let verdicts = (try? stock.verdicts()) ?? [:]

            var posts: [PostVideo] = []
            for v in try lecteur.lignes("SELECT id, compte_id, ref, titre, format, publie_le, duree_s, promo_eur, visible, fichier, notes FROM videos") {
                guard let id = v["id"] as? Int, let compteId = v["compte_id"] as? String, let ref = v["ref"] as? String else { continue }
                func s(_ k: String) -> String { v[k] as? String ?? "" }
                let c = comptes[compteId]
                var p = PostVideo(compteId: compteId, reseau: c?["reseau"] as? String ?? "", compte: c?["compte"] as? String ?? "",
                                  pseudo: c?["pseudo"] as? String ?? "", ref: ref, titre: s("titre"), format: s("format"), publieLe: s("publie_le"),
                                  dureeS: dbl(v["duree_s"]), promoEur: dbl(v["promo_eur"]) ?? 0, visible: (v["visible"] as? Int ?? 1) != 0,
                                  fichier: s("fichier"), notes: s("notes"))
                p.releves = (parVideo[id] ?? []).map { r in
                    ReleveVideo(releveLe: r["releve_le"] as? String ?? "", source: r["source"] as? String ?? "", vues: r["vues"] as? Int,
                                likes: r["likes"] as? Int, commentaires: r["commentaires"] as? Int, partages: r["partages"] as? Int,
                                enregistrements: r["enregistrements"] as? Int, tempsMoyenS: dbl(r["temps_moyen_s"]), vueEntierPct: dbl(r["vue_entier_pct"]),
                                r3sPct: dbl(r["r3s_pct"]), abonnesGagnes: r["abonnes_gagnes"] as? Int, pourToiPct: dbl(r["pour_toi_pct"]),
                                recherchePct: dbl(r["recherche_pct"]),
                                delaiHeures: delaiHeures(publieLe: p.publieLe, releveLe: r["releve_le"] as? String ?? ""))
                }
                p.conversions = conversions(publieLe: p.publieLe, compteId: compteId, toutes: conversionsBrutes)
                p.verdicts = verdicts[p.id] ?? []
                p.sujetPlanning = sujetPlanning(publieLe: p.publieLe, famille: p.famille, planning: planning)
                posts.append(p)
            }
            posts.sort { $0.publieLe == $1.publieLe ? $0.id < $1.id : $0.publieLe > $1.publieLe }
            return SuiviCharge(posts: posts, erreur: nil)
        } catch {
            return SuiviCharge(posts: [], erreur: "Lecture de stats.sqlite impossible : \(error)")
        }
    }

    private static func dbl(_ x: Any?) -> Double? {
        if let d = x as? Double { return d }
        if let i = x as? Int { return Double(i) }
        return nil
    }

    /// Ce que `pilote video-stats` et l'outil MCP renvoient : une ligne par vidéo, avec les relevés à 48 h, à 7 j et le dernier, sans tout le détail.
    /// `sansVerdict` : seulement les posts qui ont un relevé (48 h ou 7 j) sans verdict à écrire.
    static func liste(stock: Stockage, compte: String? = nil, ref: String? = nil, sansVerdict: Bool = false, archivees: Bool = false,
                      chemin: URL = cheminStats, maintenant: Date = Date()) throws -> [ResumePost] {
        let charge = charger(stock: stock, chemin: chemin)
        if let e = charge.erreur { throw ErreurSuivi(description: e) }
        return charge.posts
            .filter { (archivees || $0.visible) && (compte == nil || $0.compteId == compte || $0.famille == compte) && (ref == nil || $0.ref == ref) }
            .filter { !sansVerdict || etat($0, .h48, maintenant: maintenant) == .aJuger || etat($0, .j7, maintenant: maintenant) == .aJuger }
            .map { ResumePost($0, maintenant: maintenant) }
    }

    // MARK: Relevés dus (déclenchés tout seuls par la veille)

    /// Heures écoulées depuis la publication (AAAA-MM-JJTHH:MM, heure de Paris). nil si la date est illisible.
    static func heuresDepuis(_ publieLe: String, maintenant: Date) -> Double? {
        guard let a = formatMinute.date(from: String(publieLe.prefix(16))) else { return nil }
        return maintenant.timeIntervalSince(a) / 3600
    }

    static func ajouterHeures(_ publieLe: String, _ h: Double) -> String {
        guard let a = formatMinute.date(from: String(publieLe.prefix(16))) else { return "" }
        return formatMinute.string(from: a.addingTimeInterval(h * 3600))
    }

    static func etat(_ p: PostVideo, _ palier: PalierReleve, maintenant: Date) -> EtatPalier {
        guard let age = heuresDepuis(p.publieLe, maintenant: maintenant) else { return .aAttendre }
        if p.verdict(palier) != nil { return .fait }
        if p.releves.contains(where: { $0.palier == palier && ($0.delaiHeures ?? 0) >= palier.debutUtile }) { return .aJuger }
        if age < palier.cible { return .aAttendre }
        return age <= palier.limite ? .aReleve : .manque
    }

    /// Ce qui reste à faire. Par défaut : les relevés à faire maintenant (fenêtre ouverte) et les verdicts à écrire des posts de moins de
    /// 21 jours. `tout` ajoute le rattrapage : relevés manqués, verdicts en retard de tous les posts, paliers à venir.
    static func dus(_ posts: [PostVideo], maintenant: Date = Date(), tout: Bool = false) -> [DuVideo] {
        var out: [DuVideo] = []
        for p in posts where p.visible {
            guard let age = heuresDepuis(p.publieLe, maintenant: maintenant) else { continue }
            for palier in [PalierReleve.h48, .j7] {
                let e = etat(p, palier, maintenant: maintenant)
                let retenu = tout ? e != .fait : (e == .aReleve || (e == .aJuger && age <= 21 * 24))
                guard retenu else { continue }
                out.append(DuVideo(compteId: p.compteId, ref: p.ref, titre: p.titre, reseau: p.reseau, compte: p.compte, publieLe: p.publieLe,
                                   palier: palier.code, etat: e, dueLe: ajouterHeures(p.publieLe, palier.cible),
                                   limiteLe: ajouterHeures(p.publieLe, palier.limite), ageHeures: (age * 10).rounded() / 10))
            }
        }
        let ordre: [EtatPalier: Int] = [.aReleve: 0, .aJuger: 1, .manque: 2, .aAttendre: 3, .fait: 4]
        return out.sorted { (ordre[$0.etat] ?? 9, $0.dueLe, $0.ref) < (ordre[$1.etat] ?? 9, $1.dueLe, $1.ref) }
    }

    static func dus(stock: Stockage, tout: Bool = false, chemin: URL = cheminStats, maintenant: Date = Date()) throws -> [DuVideo] {
        let charge = charger(stock: stock, chemin: chemin)
        if let e = charge.erreur { throw ErreurSuivi(description: e) }
        return dus(charge.posts, maintenant: maintenant, tout: tout)
    }

}

struct ResumePost: Encodable {
    var compteId: String, ref: String, titre: String, format: String, publieLe: String, reseau: String, compte: String
    var visible: Bool
    var dureeS: Double?
    var promoEur: Double?
    var sujetPlanning: String?
    var nombreReleves: Int
    var releve48h: ReleveVideo?
    var releve7j: ReleveVideo?
    var dernierReleve: ReleveVideo?
    var conversionsDeLaPeriode: [ConversionLigne]
    var etat48h: EtatPalier
    var etat7j: EtatPalier
    var verdict48h: VerdictVideo?
    var verdict7j: VerdictVideo?

    enum CodingKeys: String, CodingKey {
        case compteId, ref, titre, format, publieLe, reseau, compte, visible, dureeS, promoEur, sujetPlanning, nombreReleves
        case releve48h = "releve_48h", releve7j = "releve_7j", dernierReleve, conversionsDeLaPeriode
        case etat48h = "etat_48h", etat7j = "etat_7j", verdict48h = "verdict_48h", verdict7j = "verdict_7j"
    }

    init(_ p: PostVideo, maintenant: Date = Date()) {
        compteId = p.compteId; ref = p.ref; titre = p.titre; format = p.format; publieLe = p.publieLe; reseau = p.reseau; compte = p.compte
        visible = p.visible; dureeS = p.dureeS; promoEur = p.promoEur > 0 ? p.promoEur : nil; sujetPlanning = p.sujetPlanning
        nombreReleves = p.releves.count
        releve48h = p.releve(.h48); releve7j = p.releve(.j7); dernierReleve = p.dernier
        conversionsDeLaPeriode = p.conversions
        etat48h = SuiviVideo.etat(p, .h48, maintenant: maintenant); etat7j = SuiviVideo.etat(p, .j7, maintenant: maintenant)
        verdict48h = p.verdict(.h48); verdict7j = p.verdict(.j7)
    }
}

/// Un relevé ou un verdict dû : ce que la veille signale à PILOTE (qui prévient Réseaux).
struct DuVideo: Encodable, Hashable {
    var compteId: String, ref: String, titre: String, reseau: String, compte: String, publieLe: String
    var palier: String           // 48h | 7j
    var etat: EtatPalier         // a_relever | a_juger | manque | a_attendre
    var dueLe: String            // publication + 48 h ou 7 j
    var limiteLe: String         // publication + 96 h ou 10 j : après, le relevé ne sert plus à ce palier
    var ageHeures: Double
}

// MARK: Lecture seule de stats.sqlite

/// Ouvre stats.sqlite en LECTURE SEULE : aucune table créée, rien d'écrit. Réseaux reste le seul à y écrire.
final class LecteurStats {
    private var db: OpaquePointer?

    init(chemin: URL) throws {
        var p: OpaquePointer?
        guard sqlite3_open_v2(chemin.path, &p, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK, let p else {
            throw ErreurSuivi(description: "Impossible d'ouvrir \(chemin.path)")
        }
        db = p
        sqlite3_busy_timeout(p, 3000)
    }

    deinit { sqlite3_close_v2(db) }

    func lignes(_ sql: String) throws -> [[String: Any]] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw ErreurSuivi(description: String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        var out: [[String: Any]] = []
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_DONE { break }
            guard rc == SQLITE_ROW else { throw ErreurSuivi(description: String(cString: sqlite3_errmsg(db))) }
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
}

// MARK: Verdicts (base de Pilote)

extension Stockage {
    static func verdict(_ l: [String: Any]) -> VerdictVideo {
        func s(_ k: String) -> String { l[k] as? String ?? "" }
        let d: Double? = (l["decrochage_s"] as? Double) ?? (l["decrochage_s"] as? Int).map(Double.init)
        return VerdictVideo(compteId: s("compte_id"), ref: s("ref"), palier: s("palier").isEmpty ? "48h" : s("palier"), verdict: s("verdict"),
                            pourquoi: s("pourquoi"), lecon: s("lecon"), analyse: s("analyse"), decrochageS: d, decrochageNote: s("decrochage_note"), baseReleveLe: s("base_releve_le"), ecritLe: s("ecrit_le"), par: s("par"))
    }

    /// Tous les verdicts, rangés par « compte_id|ref » (un par palier, le 48h avant le 7j).
    func verdicts() throws -> [String: [VerdictVideo]] {
        var out: [String: [VerdictVideo]] = [:]
        for l in try base.lignes("SELECT * FROM video_verdicts ORDER BY palier") {
            let v = Self.verdict(l)
            out[v.compteId + "|" + v.ref, default: []].append(v)
        }
        return out
    }

    /// Écrit ou complète le verdict d'une vidéo POUR UN RELEVÉ (palier 48h ou 7j) : compte_id + ref de stats.sqlite. Seuls les champs fournis changent.
    /// Le palier est celui du relevé auquel le verdict répond ; s'il manque, il se déduit de `base_releve_le` (délai après la publication).
    /// Si stats.sqlite est lisible, une vidéo inconnue est refusée (faute de frappe), sinon on fait confiance.
    @discardableResult
    func enregistrerVerdict(_ champs: [String: Any], chemin: URL = SuiviVideo.cheminStats) throws -> VerdictVideo {
        guard let compteId = (champs["compte_id"] as? String)?.trimmingCharacters(in: .whitespaces), !compteId.isEmpty,
              let ref = (champs["ref"] as? String)?.trimmingCharacters(in: .whitespaces), !ref.isEmpty else {
            throw ErreurSuivi(description: "compte_id et ref obligatoires (ceux de stats.sqlite, ex. tiktok_perso + l'identifiant du post)")
        }
        if let v = champs["verdict"] as? String, !v.isEmpty, !VerdictVocabulaire.verdicts.contains(where: { $0.0 == v }) {
            throw ErreurSuivi(description: "verdict inconnu « \(v) » : marche, moyen, rate ou trop_tot")
        }
        var publieLe = ""
        if FileManager.default.fileExists(atPath: chemin.path), let lecteur = try? LecteurStats(chemin: chemin) {
            let sur = compteId.replacingOccurrences(of: "'", with: "''"), sr = ref.replacingOccurrences(of: "'", with: "''")
            let trouve = try lecteur.lignes("SELECT publie_le FROM videos WHERE compte_id = '\(sur)' AND ref = '\(sr)'")
            guard let ligne = trouve.first else {
                throw ErreurSuivi(description: "Vidéo inconnue dans stats.sqlite : \(compteId) / \(ref). Vérifier compte_id et ref (pilote video-stats).")
            }
            publieLe = ligne["publie_le"] as? String ?? ""
        }
        let palier: PalierReleve
        if let code = champs["palier"] as? String, !code.isEmpty {
            guard let p = PalierReleve(code: code), p != .autre else { throw ErreurSuivi(description: "palier inconnu « \(code) » : 48h ou 7j") }
            palier = p
        } else if let base = champs["base_releve_le"] as? String, let h = SuiviVideo.delaiHeures(publieLe: publieLe, releveLe: base),
                  PalierReleve.depuis(heures: h) != .autre {
            palier = PalierReleve.depuis(heures: h)
        } else {
            throw ErreurSuivi(description: "palier obligatoire : 48h ou 7j (le relevé auquel ce verdict répond)")
        }
        let existant = try base.lignes("SELECT * FROM video_verdicts WHERE compte_id = ? AND ref = ? AND palier = ?", [compteId, ref, palier.code]).first.map(Self.verdict)
        var v = existant ?? VerdictVideo(compteId: compteId, ref: ref, palier: palier.code)
        if let x = champs["verdict"] as? String { v.verdict = x }
        if let x = champs["pourquoi"] as? String { v.pourquoi = x }
        if let x = champs["lecon"] as? String { v.lecon = x }
        if let x = champs["analyse"] as? String { v.analyse = x }
        if champs["decrochage_s"] is NSNull { v.decrochageS = nil }
        else if let x = champs["decrochage_s"] as? Double { v.decrochageS = x }
        else if let x = champs["decrochage_s"] as? Int { v.decrochageS = Double(x) }
        if let x = champs["decrochage_note"] as? String { v.decrochageNote = x }
        if let x = champs["base_releve_le"] as? String { v.baseReleveLe = x }
        if let x = champs["par"] as? String { v.par = x }
        v.ecritLe = Dates.maintenant()
        try base.executer("""
            INSERT INTO video_verdicts (compte_id, ref, palier, verdict, pourquoi, lecon, analyse, decrochage_s, decrochage_note, base_releve_le, ecrit_le, par)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(compte_id, ref, palier) DO UPDATE SET verdict = excluded.verdict, pourquoi = excluded.pourquoi, lecon = excluded.lecon,
              analyse = excluded.analyse, decrochage_s = excluded.decrochage_s, decrochage_note = excluded.decrochage_note,
              base_releve_le = excluded.base_releve_le, ecrit_le = excluded.ecrit_le, par = excluded.par
            """, [compteId, ref, palier.code, v.verdict, v.pourquoi, v.lecon, v.analyse, v.decrochageS, v.decrochageNote, v.baseReleveLe, v.ecritLe, v.par])
        return v
    }
}
