// Réglages de Pilote : un fichier JSON, ~/Library/Application Support/io.github.pjksens.pilote/reglages.json. Modèle : docs/reglages.exemple.json,
// mode d'emploi : README, section « Réglages ». `pilote reglages` dit ce qui est actif.
//
// Sans ce fichier, Pilote marche seul sur le Mac : base locale, sessions Claude Code, carte, planning, publications préparées.
// Tout ce qui lit un compte (Rappels, Calendrier, Mail, Contacts, appels) ou parle à un service (base Supabase, Stripe,
// YouTube, Instagram, TikTok, ScrapeCreators) est COUPÉ tant que ce fichier ne l'active pas. Les clés n'entrent jamais dans
// le dépôt : ce fichier reste hors de tout dépôt (droits 600 conseillés). Relu dès qu'il change, sans relancer l'app.
import Foundation

struct Reglages: Codable, Equatable {
    /// Un dossier de travail proposé à l'ouverture d'une session Claude Code.
    struct Dossier: Codable, Equatable {
        var nom: String
        var chemin: String
    }

    /// Une routine : une consigne lancée d'un clic dans une nouvelle session Claude Code.
    struct Routine: Codable, Equatable {
        var id: String
        var titre: String
        var detail: String?
        var dossier: String
        var consigne: String
    }

    /// Le Facteur (scripts/facteur.py) : à quelle session Claude Code remettre le courrier de chaque destinataire.
    struct Facteur: Codable, Equatable {
        /// Nom du destinataire (« PILOTE », « App »…) → identifiant de session de l'app Claude (local_…).
        /// Sans cette table, le Facteur lit la colonne « id » d'EQUIPE.md (dossier de données).
        var sessions: [String: String]?
        /// Une ligne ajoutée à chaque courrier remis (par exemple « Réponds en 5 lignes au plus. »). Défaut : rien.
        var rappel: String?
    }

    /// Le module « comptes » : les inscrits d'un produit et leur abonnement, en lecture seule.
    struct Comptes: Codable, Equatable {
        /// Adresse de l'API REST (PostgREST), par exemple https://<projet>.supabase.co.
        var url: String
        /// Une clé qui ne peut que LIRE la vue ci-dessous. Jamais une clé d'administration (service_role).
        var cle: String
        /// La vue lue (colonnes : voir le README). Défaut : pilote_comptes.
        var vue: String?
        /// Clé Stripe restreinte (rk_…) avec le seul droit « Subscriptions : Read ». Sans elle : pas d'essai/payant.
        var stripeCle: String?
        /// Comptes à ne pas compter : identifiants, et adresses e-mail de ces domaines (comptes de test, équipe).
        var exclureIds: [String]?
        var exclureDomaines: [String]?
        /// L'espace dont les cartes clients montrent le statut du compte. Défaut : le premier espace.
        var espace: String?
        /// Optionnel : une commande qui imprime le compteur des actifs (format : README).
        var compteur: Commande?
    }

    struct Commande: Codable, Equatable {
        var dossier: String
        var arguments: [String]
    }

    /// Synchro des contacts d'un espace avec deux tables distantes (par exemple pour les voir sur un téléphone).
    struct Synchro: Codable, Equatable {
        var url: String
        /// Une clé qui ne peut lire et écrire QUE ces deux tables. Jamais une clé d'administration (service_role).
        var cle: String
        var tableContacts: String?
        var tableEvenements: String?
        /// L'espace synchronisé. Défaut : le premier espace.
        var espace: String?
    }

    // Vous
    var prenom: String?
    /// Noms affichés des espaces : clé interne → nom (« kryva », « freelance », « autre »).
    var espaces: [String: String]?

    // Sessions Claude Code et suivi
    var dossiersSessions: [Dossier]?
    var routines: [Routine]?
    var facteur: Facteur?
    /// Un dépôt git dont Pilote montre les derniers commits (en ligne, prêts, à corriger). Lecture seule, sans fetch.
    var depotSuivi: String?

    // Intégrations, toutes coupées par défaut
    /// Rappels et Calendrier (EventKit).
    var rappelsCalendrier: Bool?
    /// Mail.app : lecture des messages reçus, brouillons.
    var mail: Bool?
    /// Le capteur `pilote entrants` : appels, SMS, contacts, mails reçus.
    var entrants: Bool?
    /// Publication programmée sur YouTube, Instagram, TikTok (clients OAuth dans `dossierSecrets`).
    var publication: Bool?
    /// Radar : chiffres publics via ScrapeCreators (clé dans `dossierSecrets`, payant au crédit).
    var radar: Bool?
    /// Où lire les clients OAuth et les clés de fichiers. Défaut : aucun (rien n'est lu).
    var dossierSecrets: String?
    /// Domaines depuis lesquels Pilote refuse d'envoyer un mail (et qu'il signale s'il en voit partir).
    var domainesInterdits: [String]?
    var comptes: Comptes?
    var synchro: Synchro?

    init() {}
}

// MARK: - Lecture

extension Reglages {
    static var fichier: URL { Demo.maison.appendingPathComponent("Library/Application Support/\(Identite.app)/reglages.json") }

    /// Les réglages en vigueur : relus quand le fichier change. Fichier absent ou illisible : tout est coupé.
    static var courants: Reglages { remplacement ?? Cache.partage.lire().reglages }

    /// Pour les essais seulement : des réglages en mémoire à la place du fichier.
    nonisolated(unsafe) static var remplacement: Reglages?

    /// nil si tout va bien (ou pas de fichier) ; sinon pourquoi le fichier n'a pas été lu.
    static var erreur: String? { Cache.partage.lire().erreur }

    /// Les espaces avec leur nom affiché : le réglage `espaces` remplace le nom par défaut, la clé interne ne change pas.
    static func nommer(_ defauts: [(String, String)]) -> [(String, String)] {
        let noms = courants.espaces ?? [:]
        return defauts.map { cle, nom in
            let n = noms[cle]?.trimmingCharacters(in: .whitespaces) ?? ""
            return (cle, n.isEmpty ? nom : n)
        }
    }

    static func decoder(_ data: Data) throws -> Reglages {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return try d.decode(Reglages.self, from: data)
    }

    /// Un chemin des réglages : « ~ » = le dossier personnel vu par Pilote (le dossier fictif en démo).
    static func url(_ chemin: String) -> URL {
        if chemin == "~" { return Demo.maison }
        if chemin.hasPrefix("~/") { return Demo.maison.appendingPathComponent(String(chemin.dropFirst(2))) }
        return URL(fileURLWithPath: chemin)
    }

    private final class Cache: @unchecked Sendable {
        static let partage = Cache()
        private let verrou = NSLock()
        private var date: Date?
        private var taille: Int?
        private var valeur: (reglages: Reglages, erreur: String?) = (Reglages(), nil)
        private var lu = false

        func lire() -> (reglages: Reglages, erreur: String?) {
            verrou.lock()
            defer { verrou.unlock() }
            let attributs = try? FileManager.default.attributesOfItem(atPath: Reglages.fichier.path)
            let d = attributs?[.modificationDate] as? Date
            let t = (attributs?[.size] as? NSNumber)?.intValue
            if lu, d == date, t == taille { return valeur }
            lu = true
            date = d
            taille = t
            guard attributs != nil else { valeur = (Reglages(), nil); return valeur }
            do {
                valeur = (try Reglages.decoder(Data(contentsOf: Reglages.fichier)), nil)
            } catch {
                valeur = (Reglages(), "reglages.json illisible, tout reste coupé : \(error.localizedDescription)")
            }
            return valeur
        }
    }
}

// MARK: - Ce que le reste de Pilote demande

extension Reglages {
    /// Le prénom de l'utilisateur, tel que Pilote l'écrit (« Camille : rappeler… »). Défaut : « Vous ».
    var prenomAffiche: String {
        let p = prenom?.trimmingCharacters(in: .whitespaces) ?? ""
        return p.isEmpty ? "Vous" : p
    }

    var secrets: URL? { dossierSecrets.flatMap { $0.isEmpty ? nil : Reglages.url($0) } }

    var depot: URL? { depotSuivi.flatMap { $0.isEmpty ? nil : Reglages.url($0) } }

    /// Une ligne par intégration : « actif » ou « coupé », et ce qui manque.
    var bilan: [(nom: String, actif: Bool, detail: String)] {
        var l: [(String, Bool, String)] = []
        l.append(("Rappels et Calendrier", rappelsCalendrier == true, "rappels_calendrier: true"))
        l.append(("Mail.app (lecture, brouillons)", mail == true, "mail: true"))
        l.append(("Capteur des entrants (appels, SMS, contacts)", entrants == true, "entrants: true"))
        l.append(("Publication YouTube, Instagram, TikTok", publication == true && secrets != nil,
                  "publication: true et dossier_secrets"))
        l.append(("Radar ScrapeCreators", radar == true && secrets != nil, "radar: true et dossier_secrets"))
        l.append(("Comptes (base en lecture seule)", comptes != nil, "comptes: { url, cle }"))
        l.append(("Stripe (abonnements, lecture seule)", comptes?.stripeCle?.isEmpty == false, "comptes.stripe_cle"))
        l.append(("Synchro distante des contacts", synchro != nil, "synchro: { url, cle }"))
        l.append(("Dépôt suivi", depot != nil, "depot_suivi"))
        l.append(("Domaines interdits à l'envoi", !(domainesInterdits ?? []).isEmpty, "domaines_interdits"))
        return l
    }
}

/// Refus franc d'une intégration coupée : dit quoi mettre dans reglages.json.
struct IntegrationCoupee: LocalizedError {
    let reglage: String
    var errorDescription: String? { "Coupé : à activer dans reglages.json (\(reglage)). Voir le README, section « Réglages »." }
}
