// Sources de chiffres du Radar. Le calcul et le stockage (Radar.swift) ne savent pas d'où viennent les chiffres :
// toute source rend des `RadarObservation`. Livrées : saisie à la main (JSON ou CSV), données factices (essais), ScrapeCreators
// (payante au crédit, clé lue dans `dossier_secrets` si reglages.json dit `radar: true`, aucun appel sans clé ni sans confirmation explicite en ligne de commande) et le
// traducteur de la réponse « Business Discovery » d'Instagram (sans réseau). Aucune source ne lit la session Instagram ou TikTok de Sacha.
import Foundation

struct RadarReleve {
    var observations: [RadarObservation] = []
    var erreurs: [String] = []
    /// Sources payantes seulement : crédits dépensés par ce relevé et crédits restants après lui (nil = source gratuite ou inconnu).
    var creditsDepenses: Int? = nil
    var creditsRestants: Int? = nil
}

protocol SourceRadar {
    var nom: String { get }
    /// Vrai si le relevé consomme des crédits d'un service payant : la ligne de commande demande alors une confirmation explicite.
    var depenseDesCredits: Bool { get }
    /// Rend ce que la source voit pour ces comptes. Une erreur sur un compte n'arrête pas les autres : elle va dans `erreurs`.
    func releve(comptes: [RadarCompte], maintenant: Date) throws -> RadarReleve
}

extension SourceRadar {
    var depenseDesCredits: Bool { false }
}

// MARK: Dates lues avec indulgence

enum RadarDates {
    private static func formateur(_ format: String, paris: Bool) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = paris ? TimeZone(identifier: "Europe/Paris") : TimeZone(identifier: "UTC")
        f.dateFormat = format
        return f
    }

    /// Lit une date de publication ou de relevé. Avec fuseau (« …Z », « …+01:00 », « …+0000 ») : exact. Sans fuseau
    /// (« 2026-10-09T14:08 », comme les relevés de Réseaux) : heure de Paris. Une date sans heure (« 2026-10-09 ») est refusée :
    /// la fenêtre de 6 à 72 h du Radar ne peut pas s'en servir.
    static func lire(_ brut: String) -> Date? {
        let t = brut.trimmingCharacters(in: .whitespacesAndNewlines)
        if let d = Dates.iso.date(from: t) { return d }
        let fraction = ISO8601DateFormatter()
        fraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = fraction.date(from: t) { return d }
        for f in ["yyyy-MM-dd'T'HH:mm:ssZ", "yyyy-MM-dd'T'HH:mm:ss.SSSZ"] {
            if let d = formateur(f, paris: false).date(from: t) { return d }
        }
        for f in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm"] {
            if let d = formateur(f, paris: true).date(from: t) { return d }
        }
        return nil
    }

    static func estSansHeure(_ brut: String) -> Bool {
        brut.trimmingCharacters(in: .whitespacesAndNewlines).range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil
    }
}

// MARK: Saisie à la main

/// Relevé fait à la main (ou par une session Réseaux), en JSON ou en tableau CSV :
/// `{"espace": "kryva", "releve_le": "2026-10-29T08:00:00Z", "source": "reseaux-lecture-publique", "posts": [ {...} ]}`.
/// Un post : `compte`, `plateforme` (sinon déduite du lien), `id` (ou `url`/`lien`), `vues`, `likes`, `commentaires`
/// (tous facultatifs : absent = inconnu, jamais 0), et la date de publication en `publie_le`/`date` (avec l'heure) ou `age_h`.
/// Une date sans fuseau est lue à l'heure de Paris. `source` (facultative, « manuelle » par défaut) nomme l'origine des chiffres.
struct SourceManuelle {
    let nom = "manuelle"

    struct Lot {
        let espace: String
        let source: String
        let observations: [RadarObservation]
        let erreurs: [String]
    }

    /// Noms de colonnes acceptés (sans accents, en minuscules) → nom canonique.
    private static let alias: [String: String] = [
        "compte": "compte", "createur": "compte", "handle": "compte", "auteur": "compte", "account": "compte",
        "plateforme": "plateforme", "reseau": "plateforme", "platform": "plateforme",
        "url": "url", "lien": "url", "link": "url", "permalink": "url",
        "id": "id", "ref": "id", "identifiant": "id",
        "legende": "legende", "titre": "legende", "description": "legende", "texte": "legende",
        "publie_le": "publie_le", "date": "publie_le", "date_publication": "publie_le", "publie": "publie_le",
        "age_h": "age_h",
        "vues": "vues", "views": "vues", "plays": "vues",
        "likes": "likes", "j_aime": "likes",
        "commentaires": "commentaires", "comments": "commentaires",
    ]

    private static func canon(_ cle: String) -> String {
        let k = cle.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .lowercased().replacingOccurrences(of: " ", with: "_").replacingOccurrences(of: "-", with: "_")
        return alias[k] ?? k
    }

    static func lire(json: Data, espaceParDefaut: String? = nil, maintenant: Date = Date()) throws -> Lot {
        let brut = try JSONSerialization.jsonObject(with: json)
        var racine: [String: Any] = [:]
        var posts: [[String: Any]]
        if let tableau = brut as? [[String: Any]] {
            posts = tableau
        } else if let objet = brut as? [String: Any] {
            racine = objet
            guard let p = objet["posts"] as? [[String: Any]] else { throw ErreurRadar.invalide("« posts » manquant : une liste est attendue") }
            posts = p
        } else {
            throw ErreurRadar.invalide("JSON attendu : un objet {\"espace\":…, \"posts\":[…]} ou une liste de posts")
        }
        guard let espace = (racine["espace"] as? String) ?? espaceParDefaut, RadarVocabulaire.espaces.contains(espace) else {
            throw ErreurRadar.invalide("« espace » manquant ou inconnu (kryva ou perso)")
        }
        var releve = maintenant
        if let t = racine["releve_le"] as? String {
            guard let d = RadarDates.lire(t) else { throw ErreurRadar.invalide("« releve_le » illisible ou sans heure : \(t) (format 2026-10-29T08:00:00Z)") }
            releve = d
        }
        return try construire(espace: espace, releve: releve, source: racine["source"] as? String, posts: posts)
    }

    /// Tableau CSV : première ligne = noms de colonnes (compte, lien, date, vues, likes, commentaires… voir les alias), séparateur
    /// tabulation, point-virgule ou virgule détecté sur l'en-tête.
    static func lire(csv: String, espaceParDefaut: String?, releveLe: Date = Date(), source: String? = nil) throws -> Lot {
        guard let espace = espaceParDefaut, RadarVocabulaire.espaces.contains(espace) else {
            throw ErreurRadar.invalide("un tableau CSV demande --espace kryva|perso")
        }
        let lignes = csv.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        guard let entete = lignes.first else { throw ErreurRadar.invalide("CSV vide") }
        let separateur = ["\t", ";", ","].max { entete.components(separatedBy: $0).count < entete.components(separatedBy: $1).count } ?? ","
        guard entete.contains(separateur) else { throw ErreurRadar.invalide("CSV : en-tête sans séparateur (tabulation, ; ou ,)") }
        let colonnes = decoupe(entete, separateur).map(canon)
        var posts: [[String: Any]] = []
        for l in lignes.dropFirst() {
            let cases = decoupe(l, separateur)
            var p: [String: Any] = [:]
            for (i, c) in colonnes.enumerated() where i < cases.count {
                let v = cases[i].trimmingCharacters(in: .whitespacesAndNewlines)
                if !v.isEmpty { p[c] = v }
            }
            posts.append(p)
        }
        return try construire(espace: espace, releve: releveLe, source: source, posts: posts)
    }

    private static func decoupe(_ ligne: String, _ sep: String) -> [String] {
        var champs: [String] = []
        var courant = ""
        var entreGuillemets = false
        let s = Array(ligne)
        var i = 0
        while i < s.count {
            let c = s[i]
            if c == "\"" {
                if entreGuillemets, i + 1 < s.count, s[i + 1] == "\"" { courant.append("\""); i += 1 }
                else { entreGuillemets.toggle() }
            } else if !entreGuillemets, String(c) == sep {
                champs.append(courant); courant = ""
            } else {
                courant.append(c)
            }
            i += 1
        }
        champs.append(courant)
        return champs
    }

    private static func construire(espace: String, releve: Date, source: String?, posts brutsPosts: [[String: Any]]) throws -> Lot {
        let nomSource = (source?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? "manuelle"
        guard nomSource.range(of: #"^[a-z0-9][a-z0-9_-]{0,39}$"#, options: .regularExpression) != nil, nomSource != "factice" else {
            throw ErreurRadar.invalide("« source » invalide : lettres minuscules, chiffres, - et _ (40 au plus), et pas « factice »")
        }
        var obs: [RadarObservation] = []
        var erreurs: [String] = []
        for (i, brut) in brutsPosts.enumerated() {
            let p = Dictionary(brut.map { (canon($0.key), $0.value) }, uniquingKeysWith: { a, _ in a })
            let ou = "post \(i + 1)"
            let url = (p["url"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            var plateforme = (p["plateforme"] as? String)?.lowercased()
            if plateforme == nil {
                if url.contains("instagram.com") { plateforme = "instagram" } else if url.contains("tiktok.com") { plateforme = "tiktok" }
            }
            guard let plateforme, RadarVocabulaire.plateformes.contains(plateforme) else {
                erreurs.append("\(ou) : plateforme absente ou inconnue (instagram ou tiktok, ou un lien qui la montre)"); continue
            }
            var compte = (p["compte"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if compte.isEmpty, plateforme == "tiktok", let r = url.range(of: #"tiktok\.com/@([^/?]+)"#, options: .regularExpression) {
                compte = String(url[r]).replacingOccurrences(of: "tiktok.com/@", with: "")
            }
            if compte.hasPrefix("@") { compte.removeFirst() }
            guard !compte.isEmpty else { erreurs.append("\(ou) : « compte » absent"); continue }
            guard let ident = (p["id"] as? String).flatMap({ $0.isEmpty ? nil : $0 }) ?? (url.isEmpty ? nil : url) else {
                erreurs.append("\(ou) (\(compte)) : « id » ou « url » (« lien ») absent"); continue
            }
            let publie: Date
            if let t = p["publie_le"] as? String {
                if RadarDates.estSansHeure(t) {
                    erreurs.append("\(ou) (\(compte)) : date sans heure (\(t)) : ajouter l'heure (2026-10-09T14:08) ou donner « age_h »"); continue
                }
                guard let d = RadarDates.lire(t) else { erreurs.append("\(ou) (\(compte)) : date illisible : \(t)"); continue }
                publie = d
            } else if let h = Self.nombre(p["age_h"]) {
                guard h >= 0 else { erreurs.append("\(ou) (\(compte)) : « age_h » négatif"); continue }
                publie = releve.addingTimeInterval(-h * 3600)
            } else {
                erreurs.append("\(ou) (\(compte)) : ni date de publication ni « age_h » (la date de publication est indispensable)"); continue
            }
            var chiffres: [Int?] = []
            var refuse = false
            for cle in ["vues", "likes", "commentaires"] {
                switch compteur(p[cle], cle) {
                case .success(let n): chiffres.append(n)
                case .failure(let e): erreurs.append("\(ou) (\(compte)) : \(e)"); refuse = true
                }
            }
            if refuse { continue }
            obs.append(RadarObservation(
                plateforme: plateforme, compte: compte, identifiantPost: ident, url: url, legende: p["legende"] as? String ?? "",
                publieLe: publie, releveLe: releve, vues: chiffres[0], likes: chiffres[1], commentaires: chiffres[2], source: nomSource))
        }
        return Lot(espace: espace, source: nomSource, observations: obs, erreurs: erreurs)
    }

    private static func nombre(_ v: Any?) -> Double? {
        if let d = v as? Double { return d }
        if let n = v as? Int { return Double(n) }
        if let s = v as? String { return Double(s.replacingOccurrences(of: ",", with: ".")) }
        return nil
    }

    /// Un compteur doit être un nombre entier (ou un texte fait de chiffres, avec ou sans espaces) ; « 12k » est refusé plutôt que deviné.
    private static func compteur(_ v: Any?, _ cle: String) -> Result<Int?, ErreurRadar> {
        guard let v, !(v is NSNull) else { return .success(nil) }
        if let n = v as? Int { return .success(n) }
        if let d = v as? Double, d == d.rounded() { return .success(Int(d)) }
        if let s = v as? String {
            let nu = s.filter { !$0.isWhitespace && $0 != "\u{202F}" && $0 != "\u{00A0}" }
            if nu.isEmpty { return .success(nil) }
            if let n = Int(nu) { return .success(n) }
        }
        return .failure(.invalide("« \(cle) » doit être un nombre entier, reçu : \(v)"))
    }
}

// MARK: Données factices (essais, jamais mélangées aux vraies)

/// Fabrique des posts à partir de rien pour essayer l'écran et les commandes. Les relevés portent la source « factice » :
/// le classement normal les ignore, `--simulation` ne montre qu'eux. Les chiffres sont déterministes (mêmes entrées, mêmes sorties).
struct SourceFactice: SourceRadar {
    let nom = "factice"
    /// Âges des posts fabriqués, en heures : 4 sous la fenêtre, 3 dedans, le reste en historique pour les références.
    static let ages: [Double] = [3, 9, 20, 31, 55, 70, 100, 150, 220, 300, 420, 600]

    func releve(comptes: [RadarCompte], maintenant: Date) throws -> RadarReleve {
        var r = RadarReleve()
        for c in comptes {
            // Base propre au compte (déterministe) : 2 000 à 40 000 vues.
            var graine = UInt64(truncatingIfNeeded: c.id.hashValueStable)
            func suivant() -> Double {
                graine = graine &* 6364136223846793005 &+ 1442695040888963407
                return Double((graine >> 33) % 1000) / 1000
            }
            let base = 2_000 + suivant() * 38_000
            for (i, age) in Self.ages.enumerated() {
                let bruit = 0.6 + suivant() * 0.9
                // Un post sur quatre dépasse nettement l'habitude du compte.
                let pic = i % 4 == 2 ? 3.0 + suivant() * 3 : 1
                let vues = Int(base * bruit * pic * min(1, 0.3 + age / 100))
                r.observations.append(RadarObservation(
                    plateforme: c.plateforme, compte: c.identifiant, identifiantPost: "factice-\(c.identifiant)-\(i)",
                    url: "https://exemple.invalid/\(c.identifiant)/\(i)", legende: "Post factice \(i + 1) de \(c.identifiant)",
                    publieLe: maintenant.addingTimeInterval(-age * 3600), releveLe: maintenant,
                    vues: vues, likes: Int(Double(vues) * 0.04), commentaires: Int(Double(vues) * 0.002), source: "factice"))
            }
        }
        return r
    }
}

private extension String {
    /// Empreinte stable d'un texte (`hashValue` change à chaque lancement de Swift).
    var hashValueStable: Int {
        var h: UInt64 = 1469598103934665603
        for b in utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        return Int(truncatingIfNeeded: h >> 1)
    }
}

// MARK: Instagram « Business Discovery » (traducteur sans réseau)

/// Traduit la réponse de `GET /<IG_USER_ID>?fields=business_discovery.username(X){media{…}}` (documentation Meta, lue le 28/10/2026 :
/// champs `id, caption, permalink, timestamp, media_product_type, like_count, comments_count, view_count`).
/// NON TESTÉ sur une vraie réponse : la forme vient de la documentation, pas d'un appel. Aucun appel réseau n'est fait ici.
enum InstagramDiscovery {
    static let nom = "instagram_discovery"

    /// Meta écrit les dates « 2026-10-27T12:34:56+0000 » (décalage sans deux-points), que `RadarDates` sait lire.
    static func date(_ t: String) -> Date? { RadarDates.lire(t) }

    /// Ne garde que les Reels (le Radar compare des vidéos courtes). `view_count` absent = nil (inconnu), jamais 0.
    static func observations(reponse: Data, compte: String, releveLe: Date) throws -> [RadarObservation] {
        guard let racine = try JSONSerialization.jsonObject(with: reponse) as? [String: Any] else {
            throw ErreurRadar.invalide("réponse Instagram illisible")
        }
        if let e = racine["error"] as? [String: Any] {
            throw ErreurRadar.invalide("Instagram refuse : \(e["message"] as? String ?? "erreur sans message")")
        }
        guard let bd = racine["business_discovery"] as? [String: Any], let media = (bd["media"] as? [String: Any])?["data"] as? [[String: Any]] else {
            throw ErreurRadar.invalide("réponse sans business_discovery.media.data (compte non professionnel, privé ou inconnu ?)")
        }
        var out: [RadarObservation] = []
        for m in media where (m["media_product_type"] as? String) == "REELS" {
            guard let id = m["id"] as? String, let t = m["timestamp"] as? String, let publie = date(t) else { continue }
            out.append(RadarObservation(
                plateforme: "instagram", compte: compte, identifiantPost: (m["permalink"] as? String).map(Stockage.radarIdentifiantPost) ?? id,
                url: m["permalink"] as? String ?? "", legende: m["caption"] as? String ?? "", publieLe: publie, releveLe: releveLe,
                vues: m["view_count"] as? Int, likes: m["like_count"] as? Int, commentaires: m["comments_count"] as? Int,
                source: nom))
        }
        return out
    }
}

// MARK: ScrapeCreators (source payante au crédit, branchée mais jamais lancée toute seule)

/// Où lire une clé d'API : jamais dans le dépôt, jamais dans un message ; uniquement dans `dossier_secrets` (reglages.json),
/// et seulement si `radar: true`.
enum CleRadar {
    static var fichierScrapeCreators: String? {
        guard Reglages.courants.radar == true, let d = Reglages.courants.secrets else { return nil }
        return d.appendingPathComponent("cle-scrapecreators.env").path
    }

    /// Lit `NOM=valeur` (guillemets et « export » tolérés). Rend nil si le fichier ou la variable manque, ou si la valeur est vide.
    static func lire(fichier: String? = fichierScrapeCreators, variable: String = "SCRAPECREATORS_API_KEY") -> String? {
        guard let fichier, let texte = try? String(contentsOfFile: fichier, encoding: .utf8) else { return nil }
        for ligne in texte.split(whereSeparator: \.isNewline) {
            var l = ligne.trimmingCharacters(in: .whitespaces)
            if l.hasPrefix("export ") { l = String(l.dropFirst(7)).trimmingCharacters(in: .whitespaces) }
            guard l.hasPrefix(variable + "=") else { continue }
            var v = String(l.dropFirst(variable.count + 1)).trimmingCharacters(in: .whitespaces)
            if v.count >= 2, let c = v.first, (c == "\"" || c == "'"), v.last == c { v = String(v.dropFirst().dropLast()) }
            return v.isEmpty ? nil : v
        }
        return nil
    }
}

/// Un seul appel HTTP GET. Séparé du reste pour que les tests passent sans réseau.
protocol TransportRadar {
    func get(_ url: URL, entetes: [String: String]) throws -> (statut: Int, corps: Data)
}

struct TransportReseau: TransportRadar {
    func get(_ url: URL, entetes: [String: String]) throws -> (statut: Int, corps: Data) {
        var requete = URLRequest(url: url, timeoutInterval: 30)
        for (k, v) in entetes { requete.setValue(v, forHTTPHeaderField: k) }
        var resultat: Result<(Int, Data), Error> = .failure(URLError(.unknown))
        let attente = DispatchSemaphore(value: 0)
        // Session éphémère : ni cookies ni cache disque.
        URLSession(configuration: .ephemeral).dataTask(with: requete) { data, reponse, erreur in
            if let erreur { resultat = .failure(erreur) }
            else if let h = reponse as? HTTPURLResponse { resultat = .success((h.statusCode, data ?? Data())) }
            attente.signal()
        }.resume()
        attente.wait()
        let (statut, corps) = try resultat.get()
        return (statut, corps)
    }
}

/// Doc ScrapeCreators (openapi.json lu le 28/10/2026) : base `https://api.scrapecreators.com`, en-tête `x-api-key`, 1 crédit par page
/// (Instagram `/v1/instagram/user/reels`, TikTok `/v3/tiktok/profile/videos`), chaque réponse rend `credits_charged` et `credits_remaining`.
/// Garde-fous : plafond de crédits par relevé, arrêt si le solde ne couvre pas la page suivante, arrêt si une page coûte plus que prévu,
/// jamais de nouvel essai automatique. Ne paie rien : à 0 crédit, le relevé s'arrête et renvoie vers la saisie à la main.
struct SourceScrapeCreators: SourceRadar {
    let nom = "scrapecreators"
    var depenseDesCredits: Bool { true }
    var transport: TransportRadar = TransportReseau()
    var cle: () -> String? = { CleRadar.lire() }
    var plafondCredits = 30
    var pagesMax = 2
    /// Une page qui coûte plus que ça arrête le relevé (la doc annonce 1).
    static let coutPageMax = 3
    static let hote = "https://api.scrapecreators.com"

    static let messageSansCle = "Pas de clé ScrapeCreators (radar coupé dans reglages.json, ou <dossier_secrets>/cle-scrapecreators.env absent ou vide) : aucun appel. Le Radar marche en saisie à la main (« pilote radar importe »)."
    static let messageSansCredit = "Plus de crédits ScrapeCreators : relevé arrêté, rien n'est payé. Le Radar reste en saisie à la main (« pilote radar importe »)."

    /// Ce qu'un relevé peut coûter au plus (sans appel) : pages × comptes, borné par le plafond.
    static func creditsMax(comptes: Int, pagesMax: Int, plafond: Int) -> Int { min(plafond, comptes * pagesMax) }

    static func requete(compte: RadarCompte, curseur: String?) -> URL? {
        var u = URLComponents(string: hote)
        let h = compte.identifiant
        if compte.plateforme == "tiktok" {
            u?.path = "/v3/tiktok/profile/videos"
            u?.queryItems = [URLQueryItem(name: "handle", value: h), URLQueryItem(name: "sort_by", value: "latest"),
                             URLQueryItem(name: "include_pinned", value: "false")]
            if let curseur { u?.queryItems?.append(URLQueryItem(name: "max_cursor", value: curseur)) }
        } else {
            u?.path = "/v1/instagram/user/reels"
            u?.queryItems = [URLQueryItem(name: "handle", value: h)]
            if let curseur { u?.queryItems?.append(URLQueryItem(name: "max_id", value: curseur)) }
        }
        return u?.url
    }

    struct Page {
        var observations: [RadarObservation] = []
        var plusAncien: Date?
        var curseur: String?
        var aSuite = true
        var listeVue = false
    }

    private static func entier(_ v: Any?) -> Int? {
        if let n = v as? Int { return n }
        if let d = v as? Double, d == d.rounded() { return Int(d) }
        return nil
    }

    private static func texte(_ v: Any?) -> String? {
        if let s = v as? String, !s.isEmpty { return s }
        if let n = v as? Int { return String(n) }
        return nil
    }

    /// Un compteur négatif ou absent est inconnu (nil), jamais 0.
    private static func compteur(_ v: Any?) -> Int? {
        guard let n = entier(v), n >= 0 else { return nil }
        return n
    }

    static func lire(instagram json: [String: Any], compte: String, releveLe: Date) -> Page {
        var page = Page()
        guard let items = json["items"] as? [[String: Any]] else { return page }
        page.listeVue = true
        for item in items {
            let m = (item["media"] as? [String: Any]) ?? item
            guard let code = m["code"] as? String ?? texte(m["id"]) else { continue }
            let publie: Date
            if let t = entier(m["taken_at"]) { publie = Date(timeIntervalSince1970: Double(t)) }
            else if let t = m["created_at"] as? String, let d = RadarDates.lire(t) { publie = d }
            else { continue }
            let url = (m["url"] as? String) ?? "https://www.instagram.com/reel/\(code)/"
            let legende = ((m["caption"] as? [String: Any])?["text"] as? String) ?? (m["caption"] as? String) ?? ""
            page.observations.append(RadarObservation(
                plateforme: "instagram", compte: compte, identifiantPost: Stockage.radarIdentifiantPost(url), url: url, legende: legende,
                publieLe: publie, releveLe: releveLe, vues: compteur(m["play_count"]) ?? compteur(m["ig_play_count"]),
                likes: compteur(m["like_count"]), commentaires: compteur(m["comment_count"]), source: "scrapecreators"))
            if page.plusAncien == nil || publie < page.plusAncien! { page.plusAncien = publie }
        }
        page.curseur = texte(json["max_id"]) ?? texte(json["next_max_id"])
        if let plus = json["more_available"] as? Bool, !plus { page.aSuite = false }
        return page
    }

    static func lire(tiktok json: [String: Any], compte: String, releveLe: Date) -> Page {
        var page = Page()
        guard let items = json["aweme_list"] as? [[String: Any]] else { return page }
        page.listeVue = true
        for v in items {
            guard let id = texte(v["aweme_id"]), let t = entier(v["create_time"]) else { continue }
            let publie = Date(timeIntervalSince1970: Double(t))
            let stats = v["statistics"] as? [String: Any] ?? [:]
            let url = "https://www.tiktok.com/@\(compte)/video/\(id)"
            page.observations.append(RadarObservation(
                plateforme: "tiktok", compte: compte, identifiantPost: Stockage.radarIdentifiantPost(url), url: url,
                legende: v["desc"] as? String ?? "", publieLe: publie, releveLe: releveLe, vues: compteur(stats["play_count"]),
                likes: compteur(stats["digg_count"]), commentaires: compteur(stats["comment_count"]), source: "scrapecreators"))
            if page.plusAncien == nil || publie < page.plusAncien! { page.plusAncien = publie }
        }
        page.curseur = texte(json["max_cursor"])
        if let plus = entier(json["has_more"]), plus == 0 { page.aSuite = false }
        return page
    }

    func releve(comptes: [RadarCompte], maintenant: Date) throws -> RadarReleve {
        guard let cle = cle(), !cle.isEmpty else { throw ErreurRadar.sourceNonConfiguree(Self.messageSansCle) }
        var r = RadarReleve()
        var depenses = 0
        var restant: Int?
        var arret: String?
        let limiteAge = maintenant.addingTimeInterval(-Double(RadarCalcul.referencesJours) * 86_400)
        boucle: for c in comptes {
            var curseur: String?
            for _ in 0..<max(1, pagesMax) {
                if depenses + 1 > plafondCredits {
                    arret = "plafond de \(plafondCredits) crédits atteint (\(depenses) dépensés) : \(c.identifiant) et la suite ne sont pas relevés"
                    break boucle
                }
                if let reste = restant, reste < 1 { arret = Self.messageSansCredit; break boucle }
                guard let url = Self.requete(compte: c, curseur: curseur) else { r.erreurs.append("\(c.identifiant) : adresse invalide"); continue boucle }
                let reponse: (statut: Int, corps: Data)
                do { reponse = try transport.get(url, entetes: ["x-api-key": cle, "accept": "application/json"]) }
                catch { r.erreurs.append("\(c.plateforme) \(c.identifiant) : réseau injoignable (\(error.localizedDescription))"); continue boucle }
                let json = (try? JSONSerialization.jsonObject(with: reponse.corps)) as? [String: Any]
                let facture = Self.entier(json?["credits_charged"]) ?? (reponse.statut == 200 ? 1 : 0)
                depenses += facture
                if let reste = Self.entier(json?["credits_remaining"]) { restant = reste } else if let avant = restant { restant = avant - facture }
                switch reponse.statut {
                case 200: break
                case 401, 403: arret = "clé ScrapeCreators refusée (HTTP \(reponse.statut)) : relevé arrêté, vérifier <dossier_secrets>/cle-scrapecreators.env"; break boucle
                case 402: arret = Self.messageSansCredit; break boucle
                case 429: arret = "ScrapeCreators limite le débit (HTTP 429) : relevé arrêté, rien de relancé automatiquement"; break boucle
                default:
                    let message = (json?["message"] as? String ?? json?["error"] as? String ?? "").prefix(120)
                    r.erreurs.append("\(c.plateforme) \(c.identifiant) : HTTP \(reponse.statut) \(message)")
                    continue boucle
                }
                guard let json, json["success"] as? Bool != false else {
                    r.erreurs.append("\(c.plateforme) \(c.identifiant) : réponse refusée par ScrapeCreators"); continue boucle
                }
                let page = c.plateforme == "tiktok" ? Self.lire(tiktok: json, compte: c.identifiant, releveLe: maintenant)
                                                    : Self.lire(instagram: json, compte: c.identifiant, releveLe: maintenant)
                if !page.listeVue { r.erreurs.append("\(c.plateforme) \(c.identifiant) : réponse sans liste de posts"); continue boucle }
                r.observations += page.observations
                if facture > Self.coutPageMax {
                    arret = "une page a coûté \(facture) crédits (attendu : 1) : relevé arrêté par prudence"
                    break boucle
                }
                guard page.aSuite, let suite = page.curseur, suite != curseur, let ancien = page.plusAncien, ancien >= limiteAge else { continue boucle }
                curseur = suite
            }
        }
        if let arret { r.erreurs.append(arret) }
        r.creditsDepenses = depenses
        r.creditsRestants = restant
        return r
    }
}

// MARK: Sources en attente de la décision de Sacha

/// Apify, Instagram Graph : prévues, pas branchées. Elles refusent de partir (aucun réseau, aucune dépense).
struct SourceEnAttente: SourceRadar {
    let nom: String
    func releve(comptes: [RadarCompte], maintenant: Date) throws -> RadarReleve {
        throw ErreurRadar.sourceNonConfiguree("La source « \(nom) » n'est pas branchée : à activer dans reglages.json, avec une clé dans dossier_secrets. Utiliser « pilote radar importe » (relevé à la main) en attendant.")
    }
}

enum SourcesRadar {
    static let enAttente = ["instagram_discovery", "apify"]

    static func parNom(_ nom: String) throws -> SourceRadar {
        if nom == "factice" { return SourceFactice() }
        if nom == "scrapecreators" { return SourceScrapeCreators() }
        if enAttente.contains(nom) { return SourceEnAttente(nom: nom) }
        throw ErreurRadar.invalide("source inconnue « \(nom) » (factice, scrapecreators, \(enAttente.joined(separator: ", ")))")
    }
}
