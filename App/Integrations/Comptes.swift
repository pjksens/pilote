// Module « comptes » : les inscrits de votre produit et leur abonnement, en LECTURE SEULE. Coupé par défaut.
// S'active dans reglages.json (`comptes`) avec l'adresse d'une API REST (PostgREST, par exemple Supabase) et une clé qui ne
// peut que lire UNE vue, `pilote_comptes` par défaut, aux colonnes fixes (README, section « Réglages ») : c'est cette vue qui
// traduit votre schéma, Pilote ne connaît aucune de vos tables. Stripe (clé restreinte, lecture des abonnements) sépare
// l'essai du payant. Le compteur des actifs est une commande à vous, optionnelle. Rien n'est écrit, nulle part.
import Foundation

struct LigneCompteur: Identifiable, Hashable {
    let id = UUID()
    let texte: String
}

struct Compteur {
    var actifs: Int = 0
    var objectif: Int = 10
    var sections: [(titre: String, lignes: [LigneCompteur])] = []
}

/// Le statut d'un compte inscrit, montré sur sa carte client.
enum StatutCompte: String {
    case inscrit, essai, essaiResilie, payant, abonne, souci, aVerifier
    var libelle: String {
        switch self {
        case .inscrit: "Inscrit"
        case .essai: "En essai"
        case .essaiResilie: "Essai résilié"
        case .payant: "Payant"
        case .abonne: "Abonné app"
        case .souci: "Paiement en souci"
        case .aVerifier: "À vérifier"
        }
    }
    var detail: String {
        switch self {
        case .inscrit: "Compte sans abonnement en cours (Stripe et stores)."
        case .essai: "Essai Stripe en cours."
        case .essaiResilie: "Essai Stripe résilié : il s'arrête à la fin de la période."
        case .payant: "Abonnement Stripe actif."
        case .abonne: "Abonnement Apple ou Google en cours : essai ou payant, le store ne le dit pas ici."
        case .souci: "Abonnement Stripe impayé ou incomplet."
        case .aVerifier: "Abonnement Stripe présent mais non lu (Stripe injoignable ?)."
        }
    }
}

struct Inscrit: Identifiable, Hashable {
    let id: String
    let entreprise: String
    let nom: String
    let email: String
    let telephone: String
    let inscritLe: Date
    let devis: Int
}

enum Comptes {
    enum ErreurComptes: LocalizedError {
        case script(String), reseau
        var errorDescription: String? {
            switch self {
            case .script: return "Le compteur n'a pas pu tourner."
            case .reseau: return "La base des comptes n'a pas répondu."
            }
        }
    }

    /// Le module réglé, ou un refus franc s'il est coupé.
    static func reglage() throws -> Reglages.Comptes {
        guard let c = Reglages.courants.comptes, !c.url.isEmpty, !c.cle.isEmpty else { throw IntegrationCoupee(reglage: "comptes") }
        return c
    }

    /// L'espace dont les cartes clients montrent le statut du compte (nil : module coupé).
    static var espace: String? {
        guard let c = Reglages.courants.comptes else { return nil }
        return c.espace ?? Libelles.espaces.first?.0
    }

    /// Où en est chaque compte (id → statut) : la vue, puis Stripe pour séparer l'essai du payant.
    /// Apple et Google ne disent pas si c'est un essai : « abonné ».
    static func statutsComptes() async throws -> [String: StatutCompte] {
        if Demo.actif { throw Demo.Refus() }
        let r = try reglage()
        let lignes = try await get(r, "\(vue(r))?select=id,abonnement_stripe,store_expire_le")
        let stripe = (try? await abonnementsStripe(r)) ?? [:]
        return statuts(lignes, stripe: stripe, maintenant: Date())
    }

    /// Le calcul seul (sans réseau), pour les essais.
    static func statuts(_ lignes: [[String: Any]], stripe: [String: (statut: String, resilie: Bool)],
                        maintenant: Date) -> [String: StatutCompte] {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        func valide(_ v: Any?) -> Bool {
            guard let t = v as? String, let d = iso.date(from: t) ?? ISO8601DateFormatter().date(from: t) else { return false }
            return d > maintenant
        }
        var statuts: [String: StatutCompte] = [:]
        for o in lignes {
            guard let id = o["id"] as? String else { continue }
            if let sub = o["abonnement_stripe"] as? String, !sub.isEmpty {
                switch stripe[sub]?.statut {
                case "trialing": statuts[id] = stripe[sub]?.resilie == true ? .essaiResilie : .essai
                case "active": statuts[id] = .payant
                case "past_due", "unpaid", "incomplete": statuts[id] = .souci
                case "canceled", "incomplete_expired": statuts[id] = .inscrit
                default: statuts[id] = .aVerifier
                }
            } else if valide(o["store_expire_le"]) {
                statuts[id] = .abonne
            } else {
                statuts[id] = .inscrit
            }
        }
        return statuts
    }

    /// Les abonnements Stripe (id → statut), toutes les pages. GET seulement, clé restreinte.
    private static func abonnementsStripe(_ r: Reglages.Comptes) async throws -> [String: (statut: String, resilie: Bool)] {
        guard let cle = r.stripeCle, !cle.isEmpty else { return [:] }
        var resultat: [String: (statut: String, resilie: Bool)] = [:]
        var apres: String?
        for _ in 0..<20 {
            var adresse = "https://api.stripe.com/v1/subscriptions?status=all&limit=100"
            if let apres { adresse += "&starting_after=\(apres)" }
            guard let u = URL(string: adresse) else { break }
            var req = URLRequest(url: u)
            req.setValue("Bearer \(cle)", forHTTPHeaderField: "Authorization")
            let (data, rep) = try await URLSession.shared.data(for: req)
            guard (rep as? HTTPURLResponse)?.statusCode == 200,
                  let objet = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let liste = objet["data"] as? [[String: Any]] else { throw ErreurComptes.reseau }
            for a in liste {
                if let id = a["id"] as? String {
                    resultat[id] = (a["status"] as? String ?? "", a["cancel_at_period_end"] as? Bool ?? false)
                }
            }
            guard objet["has_more"] as? Bool == true, let dernier = liste.last?["id"] as? String else { break }
            apres = dernier
        }
        return resultat
    }

    /// Lance la commande du compteur (réglée par vous) et range sa sortie en sections.
    static func compteur() async throws -> Compteur {
        if Demo.actif { throw Demo.Refus() }
        guard let c = try reglage().compteur, !c.arguments.isEmpty else { throw IntegrationCoupee(reglage: "comptes.compteur") }
        let sortie: String = try await Task.detached {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            p.currentDirectoryURL = Reglages.url(c.dossier)
            p.arguments = c.arguments
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "/usr/bin:/bin")
            p.environment = env
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = Pipe()
            try p.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            guard p.terminationStatus == 0 else { throw ErreurComptes.script("code \(p.terminationStatus)") }
            return String(data: data, encoding: .utf8) ?? ""
        }.value
        return analyser(sortie)
    }

    /// Format : une ligne « ACTIFS n / objectif », puis des titres de section, chacun suivi de lignes en retrait de deux espaces.
    static func analyser(_ sortie: String) -> Compteur {
        var c = Compteur()
        var titre: String?
        var lignes: [LigneCompteur] = []
        func fermer() { if let t = titre { c.sections.append((t, lignes)) }; titre = nil; lignes = [] }
        for brute in sortie.split(separator: "\n", omittingEmptySubsequences: false) {
            let l = String(brute)
            if l.hasPrefix("ACTIFS"),
               let r = l.range(of: #"(\d+)\s*/\s*(\d+)"#, options: .regularExpression) {
                let nombres = l[r].split(separator: "/").map { Int($0.trimmingCharacters(in: .whitespaces)) ?? 0 }
                c.actifs = nombres.first ?? 0
                c.objectif = nombres.last ?? 10
            }
            if l.hasPrefix("  ") {
                lignes.append(LigneCompteur(texte: l.trimmingCharacters(in: .whitespaces)))
            } else if !l.trimmingCharacters(in: .whitespaces).isEmpty, !l.hasPrefix("Fenêtre") {
                fermer()
                titre = l.replacingOccurrences(of: #"\s+:\s+\d+.*$"#, with: "", options: .regularExpression)
                    .replacingOccurrences(of: #"\s*\(.*\)\s*"#, with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
            }
        }
        fermer()
        return c
    }

    /// Comptes inscrits ces derniers jours (comptes exclus retirés), avec leur nombre de devis.
    static func inscrits(jours: Int = 14) async throws -> [Inscrit] {
        if Demo.actif { throw Demo.Refus() }
        let r = try reglage()
        let depuis = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-Double(jours) * 86400))
        let lignes = try await get(r, "\(vue(r))?select=id,entreprise,nom,email,telephone,inscrit_le,devis,actif"
                                      + "&inscrit_le=gte.\(depuis)&order=inscrit_le.desc")
        return inscrits(lignes, reglage: r)
    }

    /// Le tri seul (sans réseau), pour les essais.
    static func inscrits(_ lignes: [[String: Any]], reglage r: Reglages.Comptes) -> [Inscrit] {
        let exclus = Set(r.exclureIds ?? [])
        let domaines = (r.exclureDomaines ?? []).map { "@" + $0.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: " @")) }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return lignes.compactMap { o in
            guard let id = o["id"] as? String, !exclus.contains(id), (o["actif"] as? Bool) != false else { return nil }
            let email = o["email"] as? String ?? ""
            if domaines.contains(where: { email.lowercased().hasSuffix($0) }) { return nil }
            let cree = o["inscrit_le"] as? String ?? ""
            return Inscrit(id: id, entreprise: o["entreprise"] as? String ?? "", nom: o["nom"] as? String ?? "",
                           email: email, telephone: o["telephone"] as? String ?? "",
                           inscritLe: iso.date(from: cree) ?? ISO8601DateFormatter().date(from: cree) ?? Date(),
                           devis: (o["devis"] as? Int) ?? 0)
        }
    }

    private static func vue(_ r: Reglages.Comptes) -> String {
        let v = r.vue?.trimmingCharacters(in: .whitespaces) ?? ""
        return v.isEmpty ? "pilote_comptes" : v
    }

    private static func get(_ r: Reglages.Comptes, _ chemin: String) async throws -> [[String: Any]] {
        let base = r.url.hasSuffix("/") ? String(r.url.dropLast()) : r.url
        guard let u = URL(string: "\(base)/rest/v1/\(chemin)") else { throw ErreurComptes.reseau }
        var req = URLRequest(url: u)
        req.setValue(r.cle, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(r.cle)", forHTTPHeaderField: "Authorization")
        let (data, rep) = try await URLSession.shared.data(for: req)
        guard (rep as? HTTPURLResponse)?.statusCode == 200 else { throw ErreurComptes.reseau }
        return (try JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
    }
}
