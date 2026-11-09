// Le vrai réseau de la publication programmée : YouTube Data API v3, Instagram API with Instagram Login, TikTok (Login Kit pour
// ordinateur + Content Posting API, envoi en brouillon dans la boîte du compte).
// Jetons : trousseau du Mac seulement (service io.github.pjksens.pilote.publication, un élément par compte), jamais dans la base,
// le dépôt ni une sortie. Les clients OAuth (Google : fichier JSON de Google Cloud ; TikTok : clé et secret de l'app du portail
// développeurs) : dans le dossier `dossier_secrets` de reglages.json seulement. COUPÉE tant que reglages.json ne dit pas
// `publication: true` (et ne donne pas `dossier_secrets`).
// Seul l'outil `pilote` lit le trousseau (l'agent launchd lance le même outil) ; l'app passe par lui.
import CryptoKit
import Foundation
import Security
#if canImport(Darwin)
import Darwin
#endif

// MARK: Trousseau

enum TrousseauPublication {
    static let service = "io.github.pjksens.pilote.publication"

    struct Jetons: Codable {
        var acces: String
        var renouvellement: String = ""
        /// Fin de validité du jeton d'accès (ISO).
        var expire: String = ""
        /// Quand le jeton (Instagram) ou le renouvellement (Google) a été obtenu (ISO).
        var obtenu: String = ""
        var externeId: String = ""
    }

    static func lire(_ compte: String) throws -> Jetons? {
        var r: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: compte, kSecReturnData as String: true,
                                kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail]
        r[kSecMatchLimit as String] = kSecMatchLimitOne
        SecKeychainSetUserInteractionAllowed(false)
        defer { SecKeychainSetUserInteractionAllowed(true) }
        var resultat: AnyObject?
        let s = SecItemCopyMatching(r as CFDictionary, &resultat)
        switch s {
        case errSecSuccess:
            guard let d = resultat as? Data, let j = try? JSONDecoder().decode(Jetons.self, from: d) else {
                throw ErreurPlateforme.reconnexion("jeton illisible dans le trousseau")
            }
            return j
        case errSecItemNotFound: return nil
        case errSecInteractionNotAllowed, errSecAuthFailed, errSecUserCanceled:
            throw ErreurPlateforme.passagere("trousseau verrouillé ou accès à autoriser (Mac verrouillé ?)")
        default: throw ErreurPlateforme.passagere("trousseau : erreur \(s)")
        }
    }

    static func ecrire(_ compte: String, _ j: Jetons) throws {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                   kSecAttrAccount as String: compte]
        let d = try JSONEncoder().encode(j)
        let maj = SecItemUpdate(base as CFDictionary, [kSecValueData as String: d] as CFDictionary)
        if maj == errSecSuccess { return }
        guard maj == errSecItemNotFound else { throw ErreurPlateforme.passagere("trousseau : écriture refusée (\(maj))") }
        var ajout = base
        ajout[kSecValueData as String] = d
        ajout[kSecAttrLabel as String] = "Pilote · publication · \(compte)"
        ajout[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let s = SecItemAdd(ajout as CFDictionary, nil)
        guard s == errSecSuccess else { throw ErreurPlateforme.passagere("trousseau : ajout refusé (\(s))") }
    }

    static func effacer(_ compte: String) {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                       kSecAttrAccount as String: compte] as CFDictionary)
    }
}

// MARK: HTTP (synchrone : l'outil est un programme en ligne de commande)

struct ReponseHTTP {
    var code: Int
    var entetes: [String: String]
    var corps: Data
    var json: [String: Any] { (try? JSONSerialization.jsonObject(with: corps)) as? [String: Any] ?? [:] }
    var texte: String { String(decoding: corps.prefix(2000), as: UTF8.self) }
    func entete(_ nom: String) -> String? { entetes.first { $0.key.lowercased() == nom.lowercased() }?.value }
}

enum HTTP {
    static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 120
        c.timeoutIntervalForResource = 3600
        c.httpCookieStorage = nil
        c.urlCache = nil
        return URLSession(configuration: c)
    }()

    /// Envoie la requête ; `fichier` : le corps lu depuis le disque (gros envois). Une coupure réseau = erreur passagère.
    static func envoyer(_ r: URLRequest, fichier: URL? = nil) throws -> ReponseHTTP {
        if Demo.actif { throw Demo.Refus() }
        guard Reglages.courants.publication == true else { throw SecretsPublication.refus }
        let fin = DispatchSemaphore(value: 0)
        var sortie: (Data?, URLResponse?, Error?)
        let tache: URLSessionTask
        if let fichier {
            tache = session.uploadTask(with: r, fromFile: fichier) { d, rep, e in sortie = (d, rep, e); fin.signal() }
        } else {
            tache = session.dataTask(with: r) { d, rep, e in sortie = (d, rep, e); fin.signal() }
        }
        tache.resume()
        fin.wait()
        if let e = sortie.2 { throw ErreurPlateforme.passagere("réseau : \(e.localizedDescription)") }
        guard let h = sortie.1 as? HTTPURLResponse else { throw ErreurPlateforme.passagere("réponse illisible") }
        var entetes: [String: String] = [:]
        for (k, v) in h.allHeaderFields { entetes["\(k)"] = "\(v)" }
        return ReponseHTTP(code: h.statusCode, entetes: entetes, corps: sortie.0 ?? Data())
    }

    static func formulaire(_ champs: [String: String]) -> Data {
        var autorises = CharacterSet.alphanumerics
        autorises.insert(charactersIn: "-._~")
        return Data(champs.sorted { $0.key < $1.key }.map { k, v in
            "\(k)=\(v.addingPercentEncoding(withAllowedCharacters: autorises) ?? v)"
        }.joined(separator: "&").utf8)
    }
}

/// Le dossier des clients OAuth : seulement si la publication est activée dans reglages.json.
enum SecretsPublication {
    static var dossier: URL? { Reglages.courants.publication == true ? Reglages.courants.secrets : nil }
    static let refus = RefusPublication(raisons: ["publication coupée : à activer dans reglages.json (publication: true et dossier_secrets)"])
}

// MARK: Client OAuth Google (le JSON « Application de bureau » téléchargé depuis Google Cloud)

enum ClientGoogle {
    static var fichier: URL? { SecretsPublication.dossier?.appendingPathComponent("pilote-google-oauth.json") }

    struct Client { var id: String; var secret: String }

    /// Lit <dossier_secrets>/pilote-google-oauth.json ; s'il manque, range le dernier client_secret_*.json de Téléchargements
    /// (déplacé, lisible par vous seul). Le contenu n'est jamais affiché.
    static func charger() throws -> Client {
        guard let fichier else { throw SecretsPublication.refus }
        let fm = FileManager.default
        if !fm.fileExists(atPath: fichier.path) {
            let tel = Demo.maison.appendingPathComponent("Downloads")
            let candidats = ((try? fm.contentsOfDirectory(at: tel, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [])
                .filter { $0.lastPathComponent.hasPrefix("client_secret_") && $0.pathExtension == "json" }
                .sorted { ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
                    > ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) }
            guard let c = candidats.first else {
                throw RefusPublication(raisons: ["client Google absent : ni <dossier_secrets>/pilote-google-oauth.json ni client_secret_….json dans Téléchargements (bloc Google, étape 5)"])
            }
            try fm.createDirectory(at: fichier.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try fm.moveItem(at: c, to: fichier)
        }
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fichier.path)
        guard let d = try? Data(contentsOf: fichier), let j = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
              let i = (j["installed"] ?? j["web"]) as? [String: Any],
              let id = i["client_id"] as? String, let secret = i["client_secret"] as? String else {
            throw RefusPublication(raisons: ["client Google illisible (<dossier_secrets>/pilote-google-oauth.json) : retélécharger le JSON du client « Application de bureau »"])
        }
        guard j["installed"] != nil else {
            throw RefusPublication(raisons: ["le client Google n'est pas de type « Application de bureau » : en créer un de ce type"])
        }
        return Client(id: id, secret: secret)
    }
}

// MARK: Client TikTok (l'app « Pilote » du portail développeurs TikTok, en bac à sable)

enum ClientTikTok {
    static var fichier: URL? { SecretsPublication.dossier?.appendingPathComponent("pilote-tiktok-client.json") }

    struct Client { var cle: String; var secret: String; var port: UInt16 }

    static func charger() throws -> Client {
        guard let fichier else { throw SecretsPublication.refus }
        guard let d = try? Data(contentsOf: fichier), let j = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
              let cle = j["client_key"] as? String, let secret = j["client_secret"] as? String, !cle.isEmpty, !secret.isEmpty else {
            throw RefusPublication(raisons: ["client TikTok absent (<dossier_secrets>/pilote-tiktok-client.json) : copier « Client secret » dans le portail TikTok, puis pilote publication client-tiktok --cle <Client key>"])
        }
        return Client(cle: cle, secret: secret, port: UInt16(j["port"] as? Int ?? 0))
    }

    /// Range la clé et le secret dans <dossier_secrets> (lisible par vous seul). Le secret n'est jamais affiché. `port` : 0 = un port
    /// libre à chaque connexion (adresse de retour déclarée avec « * » au portail), sinon ce port fixe.
    static func enregistrer(cle brute: String, secret brut: String, port: UInt16 = 0) throws {
        let cle = brute.trimmingCharacters(in: .whitespacesAndNewlines), secret = brut.trimmingCharacters(in: .whitespacesAndNewlines)
        let permis = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        guard (8...64).contains(cle.count), cle.unicodeScalars.allSatisfy(permis.contains) else {
            throw RefusPublication(raisons: ["clé client TikTok illisible : la recopier depuis le portail (Client key)"])
        }
        guard (16...128).contains(secret.count), secret.unicodeScalars.allSatisfy(permis.contains), secret != cle else {
            throw RefusPublication(raisons: ["le presse-papiers ne contient pas le secret client TikTok : dans le portail, copier « Client secret » puis recommencer"])
        }
        guard let fichier else { throw SecretsPublication.refus }
        let fm = FileManager.default
        try fm.createDirectory(at: fichier.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        if !fm.fileExists(atPath: fichier.path) { fm.createFile(atPath: fichier.path, contents: nil, attributes: [.posixPermissions: 0o600]) }
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fichier.path)
        var j: [String: Any] = ["client_key": cle, "client_secret": secret]
        if port != 0 { j["port"] = Int(port) }
        // Écrit sur place (pas de fichier temporaire) : les droits 600 restent.
        try JSONSerialization.data(withJSONObject: j).write(to: fichier)
    }
}

/// Un seul renouvellement de jeton TikTok à la fois, entre l'agent et un `verifier` lancé à la main : TikTok peut changer le
/// jeton de renouvellement à chaque fois, deux renouvellements croisés perdraient le bon.
enum VerrouTikTok {
    static func avec<T>(_ f: () throws -> T) throws -> T {
        let fd = open(FileEnvoi.dossierDeLaBase.appendingPathComponent("tiktok.verrou").path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else { return try f() }
        defer { flock(fd, LOCK_UN); close(fd) }
        flock(fd, LOCK_EX)
        return try f()
    }
}

// MARK: Le vrai réseau

final class PlateformesReelles: Plateformes {
    static let versionGraph = "v27.0"
    static let scopeYouTube = "https://www.googleapis.com/auth/youtube"
    private var acces: [String: (jeton: String, fin: Date)] = [:]

    // MARK: Google : jeton d'accès

    private func jetonGoogle(_ compte: String, forcer: Bool = false) throws -> String {
        if !forcer, let a = acces[compte], a.fin > Date().addingTimeInterval(120) { return a.jeton }
        guard var j = try TrousseauPublication.lire(compte), !j.renouvellement.isEmpty else {
            throw ErreurPlateforme.reconnexion("compte pas connecté (aucun jeton dans le trousseau)")
        }
        let c = try ClientGoogle.charger()
        var r = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        r.httpMethod = "POST"
        r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        r.httpBody = HTTP.formulaire(["client_id": c.id, "client_secret": c.secret, "refresh_token": j.renouvellement, "grant_type": "refresh_token"])
        let rep = try HTTP.envoyer(r)
        if rep.code == 400 || rep.code == 401 {
            let e = rep.json["error"] as? String ?? ""
            if e == "invalid_grant" || e == "unauthorized_client" || e == "invalid_client" {
                throw ErreurPlateforme.reconnexion("Google refuse le jeton (\(e) : accès retiré, mot de passe changé ou client supprimé)")
            }
        }
        guard rep.code == 200, let a = rep.json["access_token"] as? String else {
            throw ErreurPlateforme.passagere("Google token : HTTP \(rep.code)")
        }
        let fin = Date().addingTimeInterval(Double(rep.json["expires_in"] as? Int ?? 3600))
        acces[compte] = (a, fin)
        j.acces = a
        j.expire = Dates.iso.string(from: fin)
        try? TrousseauPublication.ecrire(compte, j)
        return a
    }

    /// Un appel YouTube authentifié ; 401 : un nouveau jeton, une fois.
    private func youtube(_ compte: String, _ r: URLRequest, fichier: URL? = nil) throws -> ReponseHTTP {
        var r = r
        r.setValue("Bearer \(try jetonGoogle(compte))", forHTTPHeaderField: "Authorization")
        var rep = try HTTP.envoyer(r, fichier: fichier)
        if rep.code == 401 {
            r.setValue("Bearer \(try jetonGoogle(compte, forcer: true))", forHTTPHeaderField: "Authorization")
            rep = try HTTP.envoyer(r, fichier: fichier)
            if rep.code == 401 { throw ErreurPlateforme.reconnexion("YouTube refuse le jeton (401)") }
        }
        return rep
    }

    static func erreurYouTube(_ rep: ReponseHTTP, _ quoi: String) -> ErreurPlateforme {
        let e = rep.json["error"] as? [String: Any]
        let raison = ((e?["errors"] as? [[String: Any]])?.first?["reason"] as? String) ?? ""
        let message = (e?["message"] as? String ?? rep.texte).replacingOccurrences(of: "\n", with: " ").prefix(300)
        let m = "\(quoi) : HTTP \(rep.code)\(raison.isEmpty ? "" : " \(raison)") \(message)"
        switch (rep.code, raison) {
        case (401, _): return .reconnexion(m)
        case (403, "quotaExceeded"): return .quota(raison)
        case (403, "uploadLimitExceeded"), (400, "uploadLimitExceeded"): return .limiteChaine(raison)
        case (403, "insufficientPermissions"), (403, "forbidden"), (403, "youtubeSignupRequired"): return .reconnexion(m)
        case (403, "rateLimitExceeded"), (403, "userRateLimitExceeded"), (429, _): return .passagere(m)
        case (500...599, _): return .passagere(m)
        default: return .definitive(m)
        }
    }

    // MARK: YouTube

    static func corpsVideo(_ p: Publication) -> [String: Any] {
        ["snippet": ["title": p.titre, "description": p.texte, "categoryId": "28"],
         "status": ["privacyStatus": "private", "publishAt": p.prevuLe, "selfDeclaredMadeForKids": false,
                    "containsSyntheticMedia": p.ia]]
    }

    func youtubeTeleverser(_ p: Publication, fichier: URL, noterSession: (String) throws -> Void) throws -> String {
        let taille = (try FileManager.default.attributesOfItem(atPath: fichier.path)[.size] as? Int) ?? 0
        let type = fichier.pathExtension.lowercased() == "mov" ? "video/quicktime" : "video/mp4"
        // Reprise : la session d'avant dit où elle en est (jamais une deuxième vidéo pour la même publication).
        if !p.session.isEmpty, let u = URL(string: p.session) {
            var q = URLRequest(url: u)
            q.httpMethod = "PUT"
            q.setValue("bytes */\(taille)", forHTTPHeaderField: "Content-Range")
            q.httpBody = Data()
            let rep = try youtube(p.compte, q)
            if (rep.code == 200 || rep.code == 201), let id = rep.json["id"] as? String { return id }
            if rep.code == 308 {
                var debut = 0
                if let r = rep.entete("Range"), let fin = r.split(separator: "-").last.flatMap({ Int($0) }) { debut = fin + 1 }
                return try envoyerReste(p, session: u, fichier: fichier, debut: debut, taille: taille, type: type)
            }
            // 404 / 410 : session expirée sans vidéo ; on recommence.
            if rep.code != 404 && rep.code != 410 { throw Self.erreurYouTube(rep, "reprise de l'envoi") }
        }
        var c = URLComponents(string: "https://www.googleapis.com/upload/youtube/v3/videos")!
        c.queryItems = [URLQueryItem(name: "uploadType", value: "resumable"), URLQueryItem(name: "part", value: "snippet,status")]
        var r = URLRequest(url: c.url!)
        r.httpMethod = "POST"
        r.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        r.setValue("\(taille)", forHTTPHeaderField: "X-Upload-Content-Length")
        r.setValue(type, forHTTPHeaderField: "X-Upload-Content-Type")
        r.httpBody = try JSONSerialization.data(withJSONObject: Self.corpsVideo(p))
        let rep = try youtube(p.compte, r)
        guard rep.code == 200, let s = rep.entete("Location"), let u = URL(string: s) else { throw Self.erreurYouTube(rep, "ouverture de l'envoi") }
        try noterSession(s)
        return try envoyerReste(p, session: u, fichier: fichier, debut: 0, taille: taille, type: type)
    }

    private func envoyerReste(_ p: Publication, session: URL, fichier: URL, debut: Int, taille: Int, type: String) throws -> String {
        var r = URLRequest(url: session)
        r.httpMethod = "PUT"
        r.setValue(type, forHTTPHeaderField: "Content-Type")
        let rep: ReponseHTTP
        if debut <= 0 {
            rep = try youtube(p.compte, r, fichier: fichier)
        } else {
            let h = try FileHandle(forReadingFrom: fichier)
            defer { try? h.close() }
            try h.seek(toOffset: UInt64(debut))
            let reste = try h.readToEnd() ?? Data()
            r.setValue("bytes \(debut)-\(taille - 1)/\(taille)", forHTTPHeaderField: "Content-Range")
            r.httpBody = reste
            rep = try youtube(p.compte, r)
        }
        guard rep.code == 200 || rep.code == 201, let id = rep.json["id"] as? String else {
            if rep.code == 308 || rep.code >= 500 { throw ErreurPlateforme.passagere("envoi YouTube coupé (HTTP \(rep.code)) : reprise à la prochaine passe") }
            throw Self.erreurYouTube(rep, "envoi de la vidéo")
        }
        return id
    }

    func youtubeEtat(compte: String, video: String) throws -> EtatVideoYouTube? {
        var c = URLComponents(string: "https://www.googleapis.com/youtube/v3/videos")!
        c.queryItems = [URLQueryItem(name: "part", value: "status,processingDetails"), URLQueryItem(name: "id", value: video)]
        let rep = try youtube(compte, URLRequest(url: c.url!))
        guard rep.code == 200 else { throw Self.erreurYouTube(rep, "lecture de la vidéo") }
        guard let item = (rep.json["items"] as? [[String: Any]])?.first, let s = item["status"] as? [String: Any] else { return nil }
        return EtatVideoYouTube(confidentialite: s["privacyStatus"] as? String ?? "", publierLe: s["publishAt"] as? String ?? "",
                                envoi: s["uploadStatus"] as? String ?? "",
                                raisonRefus: (s["rejectionReason"] ?? s["failureReason"]) as? String ?? "",
                                traitement: (item["processingDetails"] as? [String: Any])?["processingStatus"] as? String ?? "")
    }

    /// thumbnails.set (après le traitement de la vidéo). 403 : la chaîne n'a pas le droit aux miniatures personnalisées
    /// (le plus souvent : pas vérifiée par téléphone) ; jamais une reconnexion du compte.
    func youtubeMiniature(compte: String, video: String, image: URL) throws {
        var c = URLComponents(string: "https://www.googleapis.com/upload/youtube/v3/thumbnails/set")!
        c.queryItems = [URLQueryItem(name: "videoId", value: video), URLQueryItem(name: "uploadType", value: "media")]
        var r = URLRequest(url: c.url!)
        r.httpMethod = "POST"
        r.setValue(image.pathExtension.lowercased() == "png" ? "image/png" : "image/jpeg", forHTTPHeaderField: "Content-Type")
        let rep = try youtube(compte, r, fichier: image)
        guard rep.code == 200 else {
            if rep.code == 403 {
                throw ErreurPlateforme.definitive("YouTube refuse la miniature personnalisée (403) : la chaîne doit avoir le droit aux miniatures (vérification par téléphone dans YouTube Studio)")
            }
            throw Self.erreurYouTube(rep, "pose de la miniature")
        }
    }

    func youtubeSupprimer(compte: String, video: String) throws {
        var c = URLComponents(string: "https://www.googleapis.com/youtube/v3/videos")!
        c.queryItems = [URLQueryItem(name: "id", value: video)]
        var r = URLRequest(url: c.url!)
        r.httpMethod = "DELETE"
        let rep = try youtube(compte, r)
        guard rep.code == 204 || rep.code == 200 || rep.code == 404 else { throw Self.erreurYouTube(rep, "suppression de la vidéo") }
    }

    /// La chaîne du jeton : (id, titre, customUrl).
    func youtubeChaine(compte: String) throws -> (id: String, titre: String, poignee: String) {
        var c = URLComponents(string: "https://www.googleapis.com/youtube/v3/channels")!
        c.queryItems = [URLQueryItem(name: "part", value: "snippet"), URLQueryItem(name: "mine", value: "true")]
        let rep = try youtube(compte, URLRequest(url: c.url!))
        guard rep.code == 200 else { throw Self.erreurYouTube(rep, "lecture de la chaîne") }
        guard let i = (rep.json["items"] as? [[String: Any]])?.first, let id = i["id"] as? String else {
            throw ErreurPlateforme.definitive("ce compte Google n'a pas de chaîne YouTube")
        }
        let s = i["snippet"] as? [String: Any] ?? [:]
        return (id, s["title"] as? String ?? "", s["customUrl"] as? String ?? "")
    }

    // MARK: Instagram

    private func jetonInstagram(_ compte: String) throws -> TrousseauPublication.Jetons {
        guard let j = try TrousseauPublication.lire(compte), !j.acces.isEmpty else {
            throw ErreurPlateforme.reconnexion("compte pas connecté (aucun jeton dans le trousseau)")
        }
        return j
    }

    static func erreurInstagram(_ rep: ReponseHTTP, _ quoi: String) -> ErreurPlateforme {
        let e = rep.json["error"] as? [String: Any] ?? [:]
        let code = e["code"] as? Int ?? 0
        let sous = e["error_subcode"] as? Int ?? 0
        let message = ((e["error_user_msg"] ?? e["message"]) as? String ?? rep.texte).replacingOccurrences(of: "\n", with: " ").prefix(300)
        let m = "\(quoi) : HTTP \(rep.code), code \(code)\(sous == 0 ? "" : "/\(sous)") \(message)"
        switch code {
        case 190, 102, 463, 467: return .reconnexion("Instagram refuse le jeton (\(m))")
        case 10, 200...299: return .reconnexion("permission refusée par Instagram (\(m))")
        case 4, 17, 32, 613, 80002: return .passagere(m)
        case 1, 2: return .passagere(m)
        case 9: return .definitive("limite de publications Instagram atteinte (100 par 24 h) : \(m)")
        default: return rep.code >= 500 ? .passagere(m) : .definitive(m)
        }
    }

    /// Jeton de la « connexion unifiée » (08/11 : seule offre de Meta pour une app neuve) : jeton d'utilisateur système du
    /// portefeuille business (EA…, sans expiration), appelé sur graph.facebook.com avec l'id du compte Instagram. Les jetons
    /// de la connexion Instagram (IG…) restent sur graph.instagram.com.
    static func connexionUnifiee(_ jeton: String) -> Bool { !jeton.hasPrefix("IG") }

    private func graph(_ chemin: String, _ champs: [String: String], jeton: String, methode: String = "GET") throws -> ReponseHTTP {
        let hote = Self.connexionUnifiee(jeton) ? "graph.facebook.com" : "graph.instagram.com"
        var c = URLComponents(string: "https://\(hote)/\(Self.versionGraph)/\(chemin)")!
        var r: URLRequest
        if methode == "GET" {
            c.queryItems = champs.map { URLQueryItem(name: $0.key, value: $0.value) } + [URLQueryItem(name: "access_token", value: jeton)]
            r = URLRequest(url: c.url!)
        } else {
            r = URLRequest(url: c.url!)
            r.httpMethod = methode
            r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            var f = champs
            f["access_token"] = jeton
            r.httpBody = HTTP.formulaire(f)
        }
        return try HTTP.envoyer(r)
    }

    /// Connexion unifiée : les comptes Instagram que le portefeuille a partagés avec l'app (/me est l'utilisateur système).
    func instagramComptesPartages(jeton: String) throws -> [(id: String, nom: String)] {
        let rep = try graph("me/assigned_instagram_accounts", ["fields": "id,username", "limit": "50"], jeton: jeton)
        guard rep.code == 200 else { throw Self.erreurInstagram(rep, "lecture des comptes partagés") }
        return (rep.json["data"] as? [[String: Any]] ?? []).map { ($0["id"] as? String ?? "", $0["username"] as? String ?? "") }
    }

    /// Quota de publication du compte Instagram (lecture seule) : (publiées sur 24 h, maximum).
    func instagramQuota(compteIG: String, jeton: String) throws -> (utilise: Int, total: Int) {
        let rep = try graph("\(compteIG)/content_publishing_limit", ["fields": "quota_usage,config"], jeton: jeton)
        guard rep.code == 200, let d = (rep.json["data"] as? [[String: Any]])?.first else {
            throw Self.erreurInstagram(rep, "lecture du quota de publication")
        }
        return (d["quota_usage"] as? Int ?? 0, (d["config"] as? [String: Any])?["quota_total"] as? Int ?? 0)
    }

    /// Le compte du jeton : (user_id, username). Connexion unifiée : le compte `compteIG` (id gardé à la connexion).
    func instagramMoi(jeton: String, compteIG: String = "") throws -> (id: String, nom: String) {
        if Self.connexionUnifiee(jeton) {
            guard !compteIG.isEmpty else {
                let l = try instagramComptesPartages(jeton: jeton)
                guard l.count == 1 else { throw ErreurPlateforme.reconnexion("jeton Meta : \(l.count) comptes Instagram partagés, lequel ? (reconnecter)") }
                return l[0]
            }
            let rep = try graph(compteIG, ["fields": "id,username"], jeton: jeton)
            guard rep.code == 200 else { throw Self.erreurInstagram(rep, "lecture du compte") }
            return (rep.json["id"] as? String ?? compteIG, rep.json["username"] as? String ?? "")
        }
        let rep = try graph("me", ["fields": "user_id,username"], jeton: jeton)
        guard rep.code == 200 else { throw Self.erreurInstagram(rep, "lecture du compte") }
        let id = (rep.json["user_id"] as? String) ?? (rep.json["user_id"] as? Int).map(String.init) ?? (rep.json["id"] as? String ?? "")
        return (id, rep.json["username"] as? String ?? "")
    }

    /// Conteneur REELS et envoi direct du fichier depuis le Mac (upload_type=resumable, rupload.facebook.com) : rien de public.
    func instagramPreparer(_ p: Publication, fichier: URL) throws -> String {
        let j = try jetonInstagram(p.compte)
        let moi = j.externeId.isEmpty ? "me" : j.externeId
        var champs = ["media_type": "REELS", "upload_type": "resumable", "caption": p.texte, "share_to_feed": "true"]
        // La couverture : l'image de la vidéo à cet instant (cover_url demanderait un serveur public).
        if p.couvertureMs >= 0 { champs["thumb_offset"] = String(p.couvertureMs) }
        let rep = try graph("\(moi)/media", champs, jeton: j.acces, methode: "POST")
        guard rep.code == 200, let id = rep.json["id"] as? String else { throw Self.erreurInstagram(rep, "création du conteneur") }
        let uri = rep.json["uri"] as? String ?? "https://rupload.facebook.com/ig-api-upload/\(Self.versionGraph)/\(id)"
        guard let u = URL(string: uri) else { throw ErreurPlateforme.definitive("adresse d'envoi Instagram illisible") }
        let taille = (try FileManager.default.attributesOfItem(atPath: fichier.path)[.size] as? Int) ?? 0
        var r = URLRequest(url: u)
        r.httpMethod = "POST"
        r.setValue("OAuth \(j.acces)", forHTTPHeaderField: "Authorization")
        r.setValue("0", forHTTPHeaderField: "offset")
        r.setValue("\(taille)", forHTTPHeaderField: "file_size")
        let envoi = try HTTP.envoyer(r, fichier: fichier)
        guard envoi.code == 200 else { throw Self.erreurInstagram(envoi, "envoi de la vidéo à Instagram") }
        return id
    }

    func instagramConteneur(compte: String, conteneur: String) throws -> ConteneurInstagram {
        let j = try jetonInstagram(compte)
        let rep = try graph(conteneur, ["fields": "status_code,status"], jeton: j.acces)
        guard rep.code == 200 else { throw Self.erreurInstagram(rep, "lecture du conteneur") }
        return ConteneurInstagram(code: rep.json["status_code"] as? String ?? "", detail: rep.json["status"] as? String ?? "")
    }

    func instagramPublier(compte: String, conteneur: String) throws -> (media: String, lien: String) {
        let j = try jetonInstagram(compte)
        let moi = j.externeId.isEmpty ? "me" : j.externeId
        let rep = try graph("\(moi)/media_publish", ["creation_id": conteneur], jeton: j.acces, methode: "POST")
        guard rep.code == 200, let media = rep.json["id"] as? String else { throw Self.erreurInstagram(rep, "publication") }
        let lien = (try? graph(media, ["fields": "permalink"], jeton: j.acces))?.json["permalink"] as? String ?? ""
        return (media, lien)
    }

    // MARK: TikTok

    static let scopesTikTok = ["user.info.basic", "user.info.profile", "video.upload"]

    /// POST /v2/oauth/token/ (échange du code ou renouvellement), avec la clé et le secret du client.
    static func demandeJetonTikTok(_ champs: [String: String]) throws -> [String: Any] {
        let c = try ClientTikTok.charger()
        var r = URLRequest(url: URL(string: "https://open.tiktokapis.com/v2/oauth/token/")!)
        r.httpMethod = "POST"
        r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        r.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        var f = champs
        f["client_key"] = c.cle
        f["client_secret"] = c.secret
        r.httpBody = HTTP.formulaire(f)
        let rep = try HTTP.envoyer(r)
        let j = rep.json
        if let e = j["error"] as? String, !e.isEmpty {
            let d = (j["error_description"] as? String ?? "").prefix(200)
            if rep.code >= 500 || rep.code == 429 { throw ErreurPlateforme.passagere("TikTok token : HTTP \(rep.code) \(e)") }
            throw ErreurPlateforme.reconnexion("TikTok refuse le jeton (\(e)\(d.isEmpty ? "" : " : \(d)"))")
        }
        guard rep.code == 200, j["access_token"] is String else { throw ErreurPlateforme.passagere("TikTok token : HTTP \(rep.code)") }
        return j
    }

    /// Les jetons d'une réponse TikTok, et la fin de validité du jeton de renouvellement (ISO).
    static func jetonsTikTok(_ j: [String: Any], ancien: TrousseauPublication.Jetons? = nil, maintenant: Date = Date())
        -> (jetons: TrousseauPublication.Jetons, finRenouvellement: String)? {
        guard let a = j["access_token"] as? String, !a.isEmpty else { return nil }
        let r = (j["refresh_token"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? ancien?.renouvellement ?? ""
        guard !r.isEmpty else { return nil }
        let fin = maintenant.addingTimeInterval(Double(j["expires_in"] as? Int ?? 3600))
        let finR = maintenant.addingTimeInterval(Double(j["refresh_expires_in"] as? Int ?? 30 * 86400))
        let id = (j["open_id"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? ancien?.externeId ?? ""
        return (TrousseauPublication.Jetons(acces: a, renouvellement: r, expire: Dates.iso.string(from: fin),
                                            obtenu: Dates.iso.string(from: maintenant), externeId: id), Dates.iso.string(from: finR))
    }

    /// Renouvelle sous le verrou et range TOUT DE SUITE le nouveau jeton de renouvellement (TikTok peut l'avoir changé).
    /// Rend le jeton d'accès et la fin du renouvellement.
    private func renouvelerTikTok(_ compte: String, forcer: Bool) throws -> (jeton: String, finRenouvellement: String?) {
        try VerrouTikTok.avec {
            guard let j = try TrousseauPublication.lire(compte), !j.renouvellement.isEmpty else {
                throw ErreurPlateforme.reconnexion("compte pas connecté (aucun jeton dans le trousseau)")
            }
            // Relu sous le verrou : un autre processus vient peut-être de renouveler.
            if !forcer, let fin = Dates.iso.date(from: j.expire), fin > Date().addingTimeInterval(120) {
                acces[compte] = (j.acces, fin)
                return (j.acces, nil)
            }
            let rep = try Self.demandeJetonTikTok(["grant_type": "refresh_token", "refresh_token": j.renouvellement])
            guard let n = Self.jetonsTikTok(rep, ancien: j) else { throw ErreurPlateforme.passagere("TikTok : réponse de renouvellement incomplète") }
            try TrousseauPublication.ecrire(compte, n.jetons)
            acces[compte] = (n.jetons.acces, Dates.iso.date(from: n.jetons.expire) ?? Date())
            return (n.jetons.acces, n.finRenouvellement)
        }
    }

    private func jetonTikTok(_ compte: String, forcer: Bool = false) throws -> String {
        if !forcer, let a = acces[compte], a.fin > Date().addingTimeInterval(120) { return a.jeton }
        return try renouvelerTikTok(compte, forcer: forcer).jeton
    }

    /// Un appel TikTok authentifié ; 401 : un nouveau jeton, une fois.
    private func tiktok(_ compte: String, _ r: URLRequest) throws -> ReponseHTTP {
        var r = r
        r.setValue("Bearer \(try jetonTikTok(compte))", forHTTPHeaderField: "Authorization")
        var rep = try HTTP.envoyer(r)
        if rep.code == 401 {
            r.setValue("Bearer \(try jetonTikTok(compte, forcer: true))", forHTTPHeaderField: "Authorization")
            rep = try HTTP.envoyer(r)
        }
        return rep
    }

    /// TikTok répond 200 avec error.code = "ok" quand tout va bien.
    static func reussiTikTok(_ rep: ReponseHTTP) -> Bool {
        rep.code == 200 && ((rep.json["error"] as? [String: Any])?["code"] as? String ?? "ok") == "ok"
    }

    static func erreurTikTok(_ rep: ReponseHTTP, _ quoi: String) -> ErreurPlateforme {
        let e = rep.json["error"] as? [String: Any] ?? [:]
        let code = e["code"] as? String ?? ""
        let message = (e["message"] as? String ?? rep.texte).replacingOccurrences(of: "\n", with: " ").prefix(300)
        let m = "\(quoi) : HTTP \(rep.code)\(code.isEmpty ? "" : " \(code)") \(message)"
        switch code {
        case "access_token_invalid", "scope_not_authorized", "scope_permission_missed": return .reconnexion("TikTok refuse le jeton (\(m))")
        case "spam_risk_too_many_pending_share":
            return .definitive("déjà trop de brouillons en attente dans la boîte TikTok (5 par 24 h) : en publier ou en supprimer dans l'app, puis reprogrammer")
        case "spam_risk_user_banned_from_posting": return .definitive("TikTok interdit de publier à ce compte pour le moment (\(m))")
        case "rate_limit_exceeded": return .passagere(m)
        default:
            if rep.code == 401 { return .reconnexion("TikTok refuse le jeton (\(m))") }
            return rep.code >= 500 || rep.code == 429 ? .passagere(m) : .definitive(m)
        }
    }

    /// Le compte du jeton : (open_id, username, display_name). username demande le scope user.info.profile.
    func tiktokMoi(compte: String) throws -> (id: String, nom: String, affiche: String) {
        var c = URLComponents(string: "https://open.tiktokapis.com/v2/user/info/")!
        c.queryItems = [URLQueryItem(name: "fields", value: "open_id,username,display_name")]
        let rep = try tiktok(compte, URLRequest(url: c.url!))
        guard Self.reussiTikTok(rep), let u = (rep.json["data"] as? [String: Any])?["user"] as? [String: Any] else {
            throw Self.erreurTikTok(rep, "lecture du compte")
        }
        return (u["open_id"] as? String ?? "", u["username"] as? String ?? "", u["display_name"] as? String ?? "")
    }

    /// Le découpage demandé par TikTok : jusqu'à 64 Mo, un seul morceau ; au-delà, des morceaux de 10 Mo, le dernier prenant le
    /// reste (moins de 20 Mo). TikTok : morceaux de 5 à 64 Mo, le dernier jusqu'à 128 Mo, 1 000 au plus, nombre = taille ÷ morceau.
    static func morceauxTikTok(taille: Int) -> (taille: Int, nombre: Int) {
        let unSeul = 64_000_000, morceau = 10_000_000
        guard taille > unSeul else { return (taille, 1) }
        return (morceau, taille / morceau)
    }

    /// Brouillon dans la boîte TikTok du compte (POST /v2/post/publish/inbox/video/init/, puis la vidéo en morceaux, dans
    /// l'ordre, sur l'adresse donnée, valable 1 h). Rien de public : Sacha reçoit une notification dans l'app TikTok.
    func tiktokEnvoyer(_ p: Publication, fichier: URL) throws -> String {
        let taille = (try FileManager.default.attributesOfItem(atPath: fichier.path)[.size] as? Int) ?? 0
        guard taille > 0 else { throw ErreurPlateforme.definitive("vidéo vide") }
        let plan = Self.morceauxTikTok(taille: taille)
        var r = URLRequest(url: URL(string: "https://open.tiktokapis.com/v2/post/publish/inbox/video/init/")!)
        r.httpMethod = "POST"
        r.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        r.httpBody = try JSONSerialization.data(withJSONObject: ["source_info": ["source": "FILE_UPLOAD", "video_size": taille,
                                                                                 "chunk_size": plan.taille, "total_chunk_count": plan.nombre]])
        let rep = try tiktok(p.compte, r)
        guard Self.reussiTikTok(rep), let d = rep.json["data"] as? [String: Any], let id = d["publish_id"] as? String,
              let s = d["upload_url"] as? String, let u = URL(string: s) else { throw Self.erreurTikTok(rep, "ouverture de l'envoi") }
        let type = fichier.pathExtension.lowercased() == "mov" ? "video/quicktime" : "video/mp4"
        let h = try FileHandle(forReadingFrom: fichier)
        defer { try? h.close() }
        for i in 0..<plan.nombre {
            let debut = i * plan.taille
            let fin = i == plan.nombre - 1 ? taille - 1 : debut + plan.taille - 1
            try h.seek(toOffset: UInt64(debut))
            let morceau = try h.read(upToCount: fin - debut + 1) ?? Data()
            guard morceau.count == fin - debut + 1 else { throw ErreurPlateforme.definitive("lecture de la vidéo incomplète") }
            var q = URLRequest(url: u)
            q.httpMethod = "PUT"
            q.setValue(type, forHTTPHeaderField: "Content-Type")
            q.setValue("bytes \(debut)-\(fin)/\(taille)", forHTTPHeaderField: "Content-Range")
            q.httpBody = morceau
            // Doc TikTok (media transfer guide) : un 5xx = passerelle ou erreur interne, « retry submitting this chunk ».
            // Le même morceau est renvoyé sur la même adresse ; repartir de zéro (nouvel envoi) refaisait tout et ratait encore (09/11).
            var essai = 0
            while true {
                essai += 1
                let e: ReponseHTTP
                do { e = try HTTP.envoyer(q) } catch ErreurPlateforme.passagere where essai < Self.essaisMorceauTikTok {
                    Thread.sleep(forTimeInterval: Self.attenteMorceauTikTok(essai: essai)); continue   // coupure réseau : même morceau
                }
                if e.code == 201 || e.code == 206 || e.code == 200 { break }
                if e.code >= 500 || e.code == 429 {
                    // TikTok dit dans Content-Range ce qu'il a reçu : le morceau peut être arrivé malgré l'erreur.
                    if let recus = Self.octetsRecusTikTok(e.entete("Content-Range")), recus > fin { break }
                    if essai < Self.essaisMorceauTikTok { Thread.sleep(forTimeInterval: Self.attenteMorceauTikTok(essai: essai)); continue }
                    throw ErreurPlateforme.passagere("envoi TikTok coupé (morceau \(i + 1)/\(plan.nombre), HTTP \(e.code), \(essai) essais"
                                                     + "\(Self.detailTikTok(e))) : nouvel envoi à la prochaine passe")
                }
                throw Self.erreurTikTok(e, "envoi du morceau \(i + 1)/\(plan.nombre)")
            }
        }
        return id
    }

    static let essaisMorceauTikTok = 6

    /// 3, 6, 12, 24, 48 s : un peu plus d'une minute et demie pour qu'une passerelle TikTok revienne.
    static func attenteMorceauTikTok(essai: Int) -> TimeInterval { 3 * pow(2, Double(max(0, essai - 1))) }

    /// « bytes 0-12345/749602001 » (en-tête d'une réponse TikTok) → 12346 octets reçus ; nil si illisible.
    static func octetsRecusTikTok(_ contentRange: String?) -> Int? {
        guard let c = contentRange?.lowercased().replacingOccurrences(of: "bytes", with: "").trimmingCharacters(in: .whitespaces),
              let tiret = c.firstIndex(of: "-") else { return nil }
        let apres = c[c.index(after: tiret)...]
        guard let dernier = Int(apres.split(separator: "/").first ?? "") else { return nil }
        return dernier + 1
    }

    /// Un bout du corps d'une erreur TikTok, pour comprendre la panne (jamais de jeton dans ces réponses).
    static func detailTikTok(_ e: ReponseHTTP) -> String {
        let t = String(decoding: e.corps.prefix(160), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "" : ", « \(t.replacingOccurrences(of: "\n", with: " ")) »"
    }

    func tiktokEtat(compte: String, envoi: String) throws -> EnvoiTikTok {
        var r = URLRequest(url: URL(string: "https://open.tiktokapis.com/v2/post/publish/status/fetch/")!)
        r.httpMethod = "POST"
        r.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        r.httpBody = try JSONSerialization.data(withJSONObject: ["publish_id": envoi])
        let rep = try tiktok(compte, r)
        guard Self.reussiTikTok(rep), let d = rep.json["data"] as? [String: Any] else { throw Self.erreurTikTok(rep, "lecture de l'envoi") }
        // (sic) « publicaly » : l'orthographe de l'API.
        let post = ((d["publicaly_available_post_id"] as? [Any])?.first).map { "\($0)" } ?? ""
        return EnvoiTikTok(statut: d["status"] as? String ?? "", raison: d["fail_reason"] as? String ?? "", post: post)
    }

    /// Jeton Instagram : renouvelé (60 jours de plus) une fois âgé d'un jour ; Google : un jeton d'accès demandé ; TikTok :
    /// renouvelé chaque jour (le jeton de renouvellement repart pour sa durée pleine).
    func entretien(compte: String) throws -> String? {
        guard let c = ComptePublication.trouver(compte) else { return nil }
        switch c.reseau {
        case .youtube:
            _ = try jetonGoogle(compte, forcer: true)
            return nil
        case .tiktok:
            return try renouvelerTikTok(compte, forcer: true).finRenouvellement
        case .instagram:
            var j = try jetonInstagram(compte)
            if Self.connexionUnifiee(j.acces) {
                // Jeton d'utilisateur système sans expiration : une lecture suffit (refusé = « à reconnecter »).
                _ = try instagramMoi(jeton: j.acces, compteIG: j.externeId)
                return nil
            }
            let obtenu = Dates.iso.date(from: j.obtenu) ?? .distantPast
            guard Date().timeIntervalSince(obtenu) > 86400 else {
                _ = try instagramMoi(jeton: j.acces)
                return nil
            }
            var u = URLComponents(string: "https://graph.instagram.com/refresh_access_token")!
            u.queryItems = [URLQueryItem(name: "grant_type", value: "ig_refresh_token"), URLQueryItem(name: "access_token", value: j.acces)]
            let rep = try HTTP.envoyer(URLRequest(url: u.url!))
            guard rep.code == 200, let a = rep.json["access_token"] as? String else { throw Self.erreurInstagram(rep, "renouvellement du jeton") }
            let fin = Date().addingTimeInterval(Double(rep.json["expires_in"] as? Int ?? 60 * 86400))
            j.acces = a
            j.obtenu = Dates.iso.string(from: Date())
            j.expire = Dates.iso.string(from: fin)
            try TrousseauPublication.ecrire(compte, j)
            return j.expire
        }
    }
}

// MARK: Connexion d'un compte (un geste de Sacha)

enum ConnexionPublication {
    struct Resultat: Encodable { var compte: String; var lu: String; var externeId: String; var expireLe: String }

    /// YouTube : ouvre la page Google dans le navigateur, attend le retour sur 127.0.0.1 (5 min au plus), garde le jeton,
    /// vérifie que la chaîne est la bonne (sinon rien n'est gardé).
    static func youtube(_ stock: Stockage, compte c: ComptePublication, ouvrir: (URL) -> Void) throws -> Resultat {
        let client = try ClientGoogle.charger()
        let ecoute = try EcouteLocale()
        defer { ecoute.fermer() }
        let verificateur = aleatoire(48)
        let defi = Data(SHA256.hash(data: Data(verificateur.utf8))).base64URL
        let etat = aleatoire(24)
        let retour = "http://127.0.0.1:\(ecoute.port)"
        var u = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        u.queryItems = [
            URLQueryItem(name: "client_id", value: client.id), URLQueryItem(name: "redirect_uri", value: retour),
            URLQueryItem(name: "response_type", value: "code"), URLQueryItem(name: "scope", value: PlateformesReelles.scopeYouTube),
            URLQueryItem(name: "access_type", value: "offline"), URLQueryItem(name: "prompt", value: "select_account consent"),
            URLQueryItem(name: "code_challenge", value: defi), URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: etat),
        ]
        ouvrir(u.url!)
        let q = try ecoute.attendre(secondes: 300) { q in
            if q["error"] != nil { return "Connexion annulée. Vous pouvez fermer cet onglet." }
            return q["state"] == etat && q["code"] != nil
                ? "Pilote a reçu l'accès. Vous pouvez fermer cet onglet et revenir à Pilote."
                : "Réponse inattendue. Vous pouvez fermer cet onglet et réessayer depuis Pilote."
        }
        if let e = q["error"] { throw RefusPublication(raisons: ["Google : \(e) (connexion annulée ou refusée)"]) }
        guard q["state"] == etat, let code = q["code"] else { throw RefusPublication(raisons: ["réponse Google inattendue : réessayer"]) }

        var r = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        r.httpMethod = "POST"
        r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        r.httpBody = HTTP.formulaire(["client_id": client.id, "client_secret": client.secret, "code": code, "code_verifier": verificateur,
                                      "redirect_uri": retour, "grant_type": "authorization_code"])
        let rep = try HTTP.envoyer(r)
        guard rep.code == 200, let acces = rep.json["access_token"] as? String else {
            throw RefusPublication(raisons: ["Google refuse l'échange (HTTP \(rep.code) \(rep.json["error"] as? String ?? ""))"])
        }
        guard let renouvellement = rep.json["refresh_token"] as? String else {
            throw RefusPublication(raisons: ["Google n'a pas donné de jeton durable : retirer l'accès « Pilote » sur myaccount.google.com/permissions puis reconnecter"])
        }
        let scopes = (rep.json["scope"] as? String ?? "").split(separator: " ").map(String.init)
        guard scopes.contains(PlateformesReelles.scopeYouTube) else {
            throw RefusPublication(raisons: ["l'accès YouTube n'a pas été coché sur la page Google : reconnecter et cocher « Gérer votre compte YouTube »"])
        }
        let fin = Date().addingTimeInterval(Double(rep.json["expires_in"] as? Int ?? 3600))
        let ancien = try? TrousseauPublication.lire(c.id)
        let nouveau = TrousseauPublication.Jetons(acces: acces, renouvellement: renouvellement, expire: Dates.iso.string(from: fin),
                                                  obtenu: Dates.iso.string(from: Date()), externeId: "")
        try TrousseauPublication.ecrire(c.id, nouveau)
        let reseau = PlateformesReelles()
        do {
            let chaine = try reseau.youtubeChaine(compte: c.id)
            guard c.reconnait(id: chaine.id, poignee: chaine.poignee) else {
                throw RefusPublication(raisons: ["mauvaise chaîne : « \(chaine.titre) » (\(chaine.poignee), \(chaine.id)) au lieu de \(c.attendu). Reconnecter et choisir la chaîne \(c.poignee) sur la page Google"])
            }
            var j = nouveau
            j.externeId = chaine.id
            try TrousseauPublication.ecrire(c.id, j)
            try Publications.compteConnecte(stock, compte: c.id, lu: "\(chaine.titre) (\(chaine.poignee))", externeId: chaine.id, expireLe: "")
            return Resultat(compte: c.id, lu: "\(chaine.titre) (\(chaine.poignee))", externeId: chaine.id, expireLe: "")
        } catch {
            if let ancien { try? TrousseauPublication.ecrire(c.id, ancien) } else { TrousseauPublication.effacer(c.id) }
            throw error
        }
    }

    /// Instagram : le jeton copié dans le tableau de bord Meta (« Générer un jeton ») est dans le presse-papiers. Pilote le lit,
    /// vérifie le compte, le range au trousseau et vide le presse-papiers. Il n'est jamais affiché.
    static func jetonMeta(_ brut: String) -> String? {
        let jeton = brut.trimmingCharacters(in: .whitespacesAndNewlines)
        guard jeton.count > 40, jeton.count < 4096, !jeton.contains(" "), jeton.hasPrefix("IG") || jeton.hasPrefix("EA") else { return nil }
        return jeton
    }

    /// Jeton rangé par PILOTE dans le trousseau en attendant la connexion (service « pilote-publication-attente », compte =
    /// l'identifiant du compte). Lu par /usr/bin/security, qui l'a créé (pas de demande d'accès) ; jamais affiché.
    static func jetonEnAttente(_ compte: String) -> String? {
        let r = FileEnvoi.lancer("/usr/bin/security", ["find-generic-password", "-s", "pilote-publication-attente", "-a", compte, "-w"])
        return r.code == 0 ? jetonMeta(r.sortie) : nil
    }

    static func instagram(_ stock: Stockage, compte c: ComptePublication, jeton brut: String) throws -> Resultat {
        guard let jeton = jetonMeta(brut) else {
            throw RefusPublication(raisons: ["pas de jeton Instagram (ni dans le presse-papiers, ni en attente dans le trousseau) : dans le tableau de bord Meta, cliquer « Générer un token » pour \(c.poignee), puis « Copier », puis recommencer"])
        }
        let reseau = PlateformesReelles()
        let moi: (id: String, nom: String)
        if PlateformesReelles.connexionUnifiee(jeton), !c.idFixe.isEmpty {
            // Id connu : lecture directe du compte (nom attendu) puis du quota de publication (droit de publier).
            moi = try reseau.instagramMoi(jeton: jeton, compteIG: c.idFixe)
            guard c.reconnait(id: moi.id, poignee: moi.nom), c.correspond(moi.nom) else {
                throw RefusPublication(raisons: ["le compte Instagram \(c.idFixe) répond @\(moi.nom) (id \(moi.id)), pas @\(c.poignee)"])
            }
            _ = try reseau.instagramQuota(compteIG: c.idFixe, jeton: jeton)
        } else if PlateformesReelles.connexionUnifiee(jeton) {
            let partages = try reseau.instagramComptesPartages(jeton: jeton)
            guard let m = partages.first(where: { c.correspond($0.nom) }) else {
                throw RefusPublication(raisons: [partages.isEmpty
                    ? "jeton Meta valide, mais aucun compte Instagram partagé avec l'app : régénérer le jeton en cochant le compte \(c.poignee) dans la fenêtre de connexion (après avoir accepté l'invitation de testeur sur instagram.com)"
                    : "ce jeton Meta partage \(partages.map { "@" + $0.nom }.joined(separator: ", ")), pas @\(c.poignee) : régénérer le jeton en cochant \(c.poignee)"])
            }
            moi = m
        } else {
            moi = try reseau.instagramMoi(jeton: jeton)
        }
        guard c.correspond(moi.nom) else {
            throw RefusPublication(raisons: ["ce jeton est celui de @\(moi.nom), pas de @\(c.poignee) : générer le jeton sur la bonne ligne"])
        }
        let maintenant = Date()
        // Connexion unifiée : jeton d'utilisateur système sans expiration (choisi dans la configuration Meta).
        let fin = PlateformesReelles.connexionUnifiee(jeton) ? "" : Dates.iso.string(from: maintenant.addingTimeInterval(60 * 86400))
        try TrousseauPublication.ecrire(c.id, TrousseauPublication.Jetons(acces: jeton, renouvellement: "", expire: fin,
                                                                           obtenu: Dates.iso.string(from: maintenant), externeId: moi.id))
        try Publications.compteConnecte(stock, compte: c.id, lu: "@\(moi.nom)", externeId: moi.id, expireLe: fin)
        return Resultat(compte: c.id, lu: "@\(moi.nom)", externeId: moi.id, expireLe: fin)
    }

    /// TikTok (Login Kit pour ordinateur) : ouvre la page TikTok dans le navigateur (le compte TikTok qui y est connecté est
    /// celui qui sera relié), attend le retour sur http://127.0.0.1:PORT/callback/ (5 min au plus), garde le jeton, lit le compte.
    /// Refusé (rien n'est gardé) : mauvais pseudo quand il est connu, ou le compte déjà relié à l'autre ligne TikTok.
    static func tiktok(_ stock: Stockage, compte c: ComptePublication, ouvrir: (URL) -> Void) throws -> Resultat {
        let client = try ClientTikTok.charger()
        let ecoute = try EcouteLocale(port: client.port)
        defer { ecoute.fermer() }
        let verificateur = aleatoire(48)
        // TikTok pour ordinateur : le défi PKCE est le SHA-256 en hexadécimal (pas en base64url comme Google).
        let defi = SHA256.hash(data: Data(verificateur.utf8)).map { String(format: "%02x", $0) }.joined()
        let etat = aleatoire(24)
        let retour = "http://127.0.0.1:\(ecoute.port)/callback/"
        var u = URLComponents(string: "https://www.tiktok.com/v2/auth/authorize/")!
        u.queryItems = [
            URLQueryItem(name: "client_key", value: client.cle), URLQueryItem(name: "scope", value: PlateformesReelles.scopesTikTok.joined(separator: ",")),
            URLQueryItem(name: "response_type", value: "code"), URLQueryItem(name: "redirect_uri", value: retour),
            URLQueryItem(name: "state", value: etat), URLQueryItem(name: "code_challenge", value: defi),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        ouvrir(u.url!)
        let q = try ecoute.attendre(secondes: 300, chemin: "/callback/", qui: "TikTok") { q in
            if q["error"] != nil { return "Connexion annulée. Vous pouvez fermer cet onglet." }
            return q["state"] == etat && q["code"] != nil
                ? "Pilote a reçu l'accès. Vous pouvez fermer cet onglet et revenir à Pilote."
                : "Réponse inattendue. Vous pouvez fermer cet onglet et réessayer depuis Pilote."
        }
        if let e = q["error"] {
            throw RefusPublication(raisons: ["TikTok : \(e)\(q["error_description"].map { " (\($0))" } ?? "") : connexion annulée ou refusée"])
        }
        guard q["state"] == etat, let code = q["code"] else { throw RefusPublication(raisons: ["réponse TikTok inattendue : réessayer"]) }
        let rep: [String: Any]
        do {
            rep = try PlateformesReelles.demandeJetonTikTok(["grant_type": "authorization_code", "code": code, "redirect_uri": retour,
                                                              "code_verifier": verificateur])
        } catch { throw RefusPublication(raisons: ["TikTok refuse l'échange : \(error)"]) }
        let accordes = Set((rep["scope"] as? String ?? q["scopes"] ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
        let manquants = PlateformesReelles.scopesTikTok.filter { !accordes.contains($0) }
        guard manquants.isEmpty else {
            throw RefusPublication(raisons: ["TikTok n'a pas tout autorisé (manque : \(manquants.joined(separator: ", "))) : vérifier les produits de l'app au portail, puis reconnecter en laissant tout coché"])
        }
        guard let n = PlateformesReelles.jetonsTikTok(rep) else { throw RefusPublication(raisons: ["TikTok n'a pas donné de jeton durable : réessayer"]) }
        let ancien = try? TrousseauPublication.lire(c.id)
        try TrousseauPublication.ecrire(c.id, n.jetons)
        do {
            let moi = try PlateformesReelles().tiktokMoi(compte: c.id)
            if !c.poignee.isEmpty, !c.correspond(moi.nom) {
                throw RefusPublication(raisons: ["mauvais compte TikTok : @\(moi.nom) au lieu de @\(c.poignee). Dans le navigateur, passer sur le bon compte TikTok, puis recommencer"])
            }
            // Pseudo inconnu : le nom affiché à la première connexion ; ensuite, le même compte (open_id) suffit, même renommé.
            let avant = try Publications.etatCompte(stock, c.id)
            let memeCompte = !avant.externeId.isEmpty && avant.externeId == moi.id
            if c.poignee.isEmpty, !memeCompte, !c.nomAffiche.isEmpty, !c.afficheCorrespond(moi.affiche) {
                throw RefusPublication(raisons: ["TikTok a relié « \(moi.affiche) »\(moi.nom.isEmpty ? "" : " (@\(moi.nom))") au lieu de « \(c.nomAffiche) ». Mauvais compte : dans le navigateur, passer sur le bon compte TikTok, puis recommencer. Compte renommé : le dire à PILOTE, qui met à jour le nom attendu"])
            }
            for autre in ComptePublication.tous where autre.reseau == .tiktok && autre.id != c.id {
                let e = try Publications.etatCompte(stock, autre.id)
                if e.etat != "jamais", !e.externeId.isEmpty, e.externeId == moi.id {
                    throw RefusPublication(raisons: ["ce compte TikTok (\(moi.nom.isEmpty ? moi.affiche : "@" + moi.nom)) est déjà relié à « \(autre.nom) » : dans le navigateur, passer sur l'autre compte TikTok, puis recommencer"])
                }
            }
            var j = n.jetons
            j.externeId = moi.id
            try TrousseauPublication.ecrire(c.id, j)
            let lu = moi.nom.isEmpty ? moi.affiche : "\(moi.affiche.isEmpty ? moi.nom : moi.affiche) (@\(moi.nom))"
            try Publications.compteConnecte(stock, compte: c.id, lu: lu, externeId: moi.id, expireLe: n.finRenouvellement)
            return Resultat(compte: c.id, lu: lu, externeId: moi.id, expireLe: n.finRenouvellement)
        } catch {
            if let ancien { try? TrousseauPublication.ecrire(c.id, ancien) } else { TrousseauPublication.effacer(c.id) }
            throw error
        }
    }

    static func aleatoire(_ n: Int) -> String {
        var octets = [UInt8](repeating: 0, count: n)
        _ = SecRandomCopyBytes(kSecRandomDefault, n, &octets)
        return Data(octets).base64URL
    }
}

extension Data {
    var base64URL: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

// MARK: Retour OAuth sur 127.0.0.1 (une seule requête, puis fermé)

final class EcouteLocale {
    private let fd: Int32
    let port: UInt16

    /// `port` 0 : un port libre choisi par le système.
    init(port: UInt16 = 0) throws {
        let s = socket(AF_INET, SOCK_STREAM, 0)
        guard s >= 0 else { throw RefusPublication(raisons: ["écoute locale impossible"]) }
        var oui: Int32 = 1
        setsockopt(s, SOL_SOCKET, SO_REUSEADDR, &oui, socklen_t(MemoryLayout<Int32>.size))
        var a = sockaddr_in()
        a.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        a.sin_family = sa_family_t(AF_INET)
        a.sin_addr.s_addr = inet_addr("127.0.0.1")
        a.sin_port = port.bigEndian
        let lie = withUnsafePointer(to: &a) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(s, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        guard lie == 0, listen(s, 4) == 0 else {
            close(s)
            throw RefusPublication(raisons: [port == 0 ? "écoute locale impossible (bind)" : "écoute locale impossible : le port \(port) est déjà pris"])
        }
        var lu = sockaddr_in()
        var l = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &lu) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(s, $0, &l) } }
        fd = s
        self.port = UInt16(bigEndian: lu.sin_port)
    }

    func fermer() { close(fd) }

    /// Attend la requête GET `chemin`?code=…&state=… ; répond la page rendue par `page`. Ignore les autres requêtes (favicon).
    /// Le navigateur ouvre souvent des connexions d'avance qui n'envoient rien (pré-connexion de Chrome) : chaque connexion
    /// est lue seulement quand elle a des données, jamais en bloquant, sinon la vraie réponse de Google attend derrière.
    func attendre(secondes: Int, chemin attendu: String = "/", qui: String = "Google", page: ([String: String]) -> String) throws -> [String: String] {
        func sansFin(_ s: String) -> String { s.hasSuffix("/") ? String(s.dropLast()) : s }
        let limite = Date().addingTimeInterval(Double(secondes))
        var clients: [Int32] = []
        defer { clients.forEach { close($0) } }
        while Date() < limite {
            var fds = [pollfd(fd: fd, events: Int16(POLLIN), revents: 0)] + clients.map { pollfd(fd: $0, events: Int16(POLLIN), revents: 0) }
            let reste = Int32(max(1, limite.timeIntervalSinceNow) * 1000)
            guard poll(&fds, nfds_t(fds.count), min(reste, 1000)) > 0 else { continue }
            if fds[0].revents & Int16(POLLIN) != 0 {
                let c = accept(fd, nil, nil)
                if c >= 0 { clients.append(c) }
                if clients.count > 16 { close(clients.removeFirst()) }
            }
            for f in fds.dropFirst() where f.revents != 0 {
                let client = f.fd
                clients.removeAll { $0 == client }
                defer { close(client) }
                var tampon = [UInt8](repeating: 0, count: 16384)
                let n = read(client, &tampon, tampon.count)
                guard n > 0 else { continue }
                let requete = String(decoding: tampon[0..<n], as: UTF8.self)
                guard let ligne = requete.split(separator: "\r\n").first, ligne.hasPrefix("GET ") else { continue }
                let chemin = ligne.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
                var q: [String: String] = [:]
                if let c = URLComponents(string: "http://127.0.0.1\(chemin)"), sansFin(c.path) == sansFin(attendu) {
                    for i in c.queryItems ?? [] { q[i.name] = i.value ?? "" }
                }
                guard q["code"] != nil || q["error"] != nil else {
                    let r = "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                    _ = r.withCString { write(client, $0, strlen($0)) }
                    continue
                }
                let html = "<!doctype html><meta charset=utf-8><title>Pilote</title><body style=\"font:17px -apple-system;margin:15vh auto;max-width:30em;text-align:center\"><p>\(page(q))</p></body>"
                let corps = Data(html.utf8)
                let tete = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(corps.count)\r\nConnection: close\r\n\r\n"
                var tout = Data(tete.utf8)
                tout.append(corps)
                _ = tout.withUnsafeBytes { write(client, $0.baseAddress, tout.count) }
                return q
            }
        }
        throw RefusPublication(raisons: ["pas de retour de \(qui) en \(secondes / 60 > 0 ? "\(secondes / 60) minutes" : "\(secondes) secondes") : relancer « Connecter »"])
    }
}

// MARK: Lecture seule : ce qui est déjà en ligne (ou programmé) sur un compte, pour ne jamais republier en double

extension PlateformesReelles {
    /// YouTube : toutes les vidéos de la chaîne (liste « uploads », privées et programmées comprises), ~3 unités de quota par 50.
    func youtubeVideos(compte: String) throws -> [[String: String]] {
        var c = URLComponents(string: "https://www.googleapis.com/youtube/v3/channels")!
        c.queryItems = [URLQueryItem(name: "part", value: "contentDetails"), URLQueryItem(name: "mine", value: "true")]
        let rep = try youtube(compte, URLRequest(url: c.url!))
        guard rep.code == 200 else { throw Self.erreurYouTube(rep, "lecture de la chaîne") }
        guard let liste = (((rep.json["items"] as? [[String: Any]])?.first?["contentDetails"] as? [String: Any])?["relatedPlaylists"]
                            as? [String: Any])?["uploads"] as? String else { return [] }
        var ids: [String] = [], page = ""
        repeat {
            var p = URLComponents(string: "https://www.googleapis.com/youtube/v3/playlistItems")!
            p.queryItems = [URLQueryItem(name: "part", value: "contentDetails"), URLQueryItem(name: "playlistId", value: liste),
                            URLQueryItem(name: "maxResults", value: "50")] + (page.isEmpty ? [] : [URLQueryItem(name: "pageToken", value: page)])
            let r = try youtube(compte, URLRequest(url: p.url!))
            guard r.code == 200 else { throw Self.erreurYouTube(r, "lecture des vidéos de la chaîne") }
            ids += (r.json["items"] as? [[String: Any]] ?? []).compactMap { ($0["contentDetails"] as? [String: Any])?["videoId"] as? String }
            page = r.json["nextPageToken"] as? String ?? ""
        } while !page.isEmpty && ids.count < 500
        var sortie: [[String: String]] = []
        for i in stride(from: 0, to: ids.count, by: 50) {
            var v = URLComponents(string: "https://www.googleapis.com/youtube/v3/videos")!
            v.queryItems = [URLQueryItem(name: "part", value: "snippet,status,contentDetails"),
                            URLQueryItem(name: "id", value: ids[i..<min(i + 50, ids.count)].joined(separator: ","))]
            let r = try youtube(compte, URLRequest(url: v.url!))
            guard r.code == 200 else { throw Self.erreurYouTube(r, "lecture des vidéos") }
            for item in r.json["items"] as? [[String: Any]] ?? [] {
                let s = item["snippet"] as? [String: Any] ?? [:], st = item["status"] as? [String: Any] ?? [:]
                sortie.append(["id": item["id"] as? String ?? "", "titre": s["title"] as? String ?? "",
                               "description": s["description"] as? String ?? "", "publieeLe": s["publishedAt"] as? String ?? "",
                               "confidentialite": st["privacyStatus"] as? String ?? "", "publierLe": st["publishAt"] as? String ?? "",
                               "duree": (item["contentDetails"] as? [String: Any])?["duration"] as? String ?? ""])
            }
        }
        return sortie
    }

    /// Instagram : les publications du compte (id, date, légende, lien, type, adresse du fichier), 500 au plus.
    func instagramMedias(compte: String) throws -> [[String: String]] {
        let j = try jetonInstagram(compte)
        let moi = j.externeId.isEmpty ? "me" : j.externeId
        var sortie: [[String: String]] = [], apres = ""
        repeat {
            var champs = ["fields": "id,caption,media_type,media_product_type,permalink,timestamp,media_url,thumbnail_url", "limit": "50"]
            if !apres.isEmpty { champs["after"] = apres }
            let rep = try graph("\(moi)/media", champs, jeton: j.acces)
            guard rep.code == 200 else { throw Self.erreurInstagram(rep, "lecture des publications") }
            for m in rep.json["data"] as? [[String: Any]] ?? [] {
                var l: [String: String] = [:]
                for k in ["id", "caption", "media_type", "media_product_type", "permalink", "timestamp", "media_url", "thumbnail_url"] {
                    l[k] = m[k] as? String ?? ""
                }
                sortie.append(l)
            }
            let paging = rep.json["paging"] as? [String: Any] ?? [:]
            apres = paging["next"] == nil ? "" : ((paging["cursors"] as? [String: Any])?["after"] as? String ?? "")
        } while !apres.isEmpty && sortie.count < 500
        return sortie
    }
}
