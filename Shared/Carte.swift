// La carte de l'espace de travail (un projet = un dossier, ses documents, son site) et le journal des agents.
// Utilisé tel quel par l'app et par l'outil `pilote` (et donc par toutes les sessions Claude Code).
import Foundation

struct Projet: Identifiable, Hashable, Codable {
    var id: String
    var espace: String = "autre"        // kryva | krydor | freelance | perso | cours | administratif
    var nom: String = ""
    var description: String = ""
    var dossier: String = ""            // chemin, avec ~ pour la maison
    var depot: String = ""              // dépôt GitHub (propriétaire/nom)
    var site: String = ""
    var statut: String = "actif"        // actif | en_pause | archive
    var documents: String = ""          // une ligne par document : « Libellé : chemin »
    var notes: String = ""
    var ordre: Int = 100
    var majLe: String = ""

    var cheminComplet: String { Chemins.complet(dossier) }

    /// ETAT.md à la racine du dossier : fait, en cours, prochaine étape, fichiers clés (tenu par les sessions).
    func lireEtat() -> String? {
        guard !dossier.isEmpty else { return nil }
        let f = URL(fileURLWithPath: cheminComplet).appendingPathComponent("ETAT.md")
        guard let t = try? String(contentsOf: f, encoding: .utf8) else { return nil }
        return String(t.prefix(3000))
    }

    /// Documents clés, ligne par ligne (« Libellé : chemin » ou un chemin seul).
    var listeDocuments: [(libelle: String, chemin: String)] {
        documents.split(separator: "\n").compactMap { ligne in
            let l = ligne.trimmingCharacters(in: .whitespaces)
            guard !l.isEmpty else { return nil }
            if let r = l.range(of: " : ") {
                return (String(l[..<r.lowerBound]), String(l[r.upperBound...]))
            }
            return ((l as NSString).lastPathComponent, l)
        }
    }
}

struct EntreeJournal: Identifiable, Hashable, Codable {
    var id: String
    var le: String
    var type: String = "tour"           // tour (fin de réponse d'un agent) | livrable | note
    var session: String = ""
    var sessionApp: String = ""
    var titreSession: String = ""
    var dossier: String = ""
    var projetId: String = ""
    var demande: String = ""
    var texte: String = ""
    var fichiers: String = ""

    var listeFichiers: [String] { fichiers.split(separator: "\n").map(String.init).filter { !$0.isEmpty } }
}

struct ResultatsRecherche: Codable {
    var contacts: [Contact] = []
    var projets: [Projet] = []
    var journal: [EntreeJournal] = []
    var fichiers: [String] = []
}

enum Libelles2 {
    /// (clé stockée, libellé affiché) : calculé, la langue se lit à l'appel. Les noms peuvent être renommés dans reglages.json.
    static var espaces: [(String, String)] {
        Reglages.nommer([
            ("kryva", "KRYVA"), ("krydor", "Krydor"), ("freelance", "Freelance"), ("perso", L("Projets perso")), ("outils", L("Outils")),
            ("cours", L("Cours")), ("administratif", L("Papiers et secrets")),
        ])
    }
    static func espace(_ cle: String) -> String { espaces.first { $0.0 == cle }?.1 ?? cle }
    static var statuts: [(String, String)] { [("actif", L("Actif")), ("en_pause", L("En pause")), ("archive", L("Archivé"))] }
    static func statut(_ cle: String) -> String { statuts.first { $0.0 == cle }?.1 ?? cle }
}

enum Chemins {
    static let maison = Demo.maison.path
    static func complet(_ s: String) -> String {
        s == "~" ? maison : (s.hasPrefix("~/") ? maison + s.dropFirst(1) : s)
    }
    static func court(_ s: String) -> String {
        s.hasPrefix(maison) ? "~" + s.dropFirst(maison.count) : s
    }
}

extension Stockage {
    static let colonnesProjet = ["espace", "nom", "description", "dossier", "depot", "site", "statut", "documents", "notes", "ordre"]

    // MARK: Projets

    func projets() throws -> [Projet] {
        let rang = Dictionary(uniqueKeysWithValues: Libelles2.espaces.enumerated().map { ($1.0, $0) })
        return try base.lignes("SELECT * FROM projets").map(Self.projet)
            .sorted { (rang[$0.espace] ?? 99, $0.ordre, $0.nom) < (rang[$1.espace] ?? 99, $1.ordre, $1.nom) }
    }

    func projet(_ id: String) throws -> Projet? {
        try base.lignes("SELECT * FROM projets WHERE id = ?", [id]).first.map(Self.projet)
    }

    /// Crée ou modifie un projet (par id ; sans id, l'id est tiré du nom). Seuls les champs fournis changent.
    @discardableResult
    func enregistrerProjet(_ champs: [String: Any]) throws -> Projet {
        var champs = champs
        if let d = champs["dossier"] as? String { champs["dossier"] = Chemins.court(Chemins.complet(d)) }
        let id = (champs["id"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? Self.identifiant(champs["nom"] as? String ?? "projet")
        let fournis = Self.colonnesProjet.filter { champs[$0] != nil }
        if try projet(id) == nil {
            let cols = ["id", "maj_le"] + fournis
            try base.executer("INSERT INTO projets (\(cols.joined(separator: ", "))) VALUES (\(cols.map { _ in "?" }.joined(separator: ", ")))",
                              [id, Dates.maintenant()] + fournis.map { Self.valeurProjet($0, champs[$0]) })
        } else if !fournis.isEmpty {
            try base.executer("UPDATE projets SET \(fournis.map { "\($0) = ?" }.joined(separator: ", ")), maj_le = ? WHERE id = ?",
                              fournis.map { Self.valeurProjet($0, champs[$0]) } + [Dates.maintenant(), id])
        }
        return try projet(id)!
    }

    /// Le projet dont le dossier contient ce chemin (le plus précis gagne).
    func projetPour(dossier: String) throws -> Projet? {
        let chemin = Chemins.complet(dossier)
        guard !chemin.isEmpty else { return nil }
        return try projets().filter { p in
            let d = p.cheminComplet
            return !d.isEmpty && (chemin == d || chemin.hasPrefix(d.hasSuffix("/") ? d : d + "/"))
        }.max { $0.cheminComplet.count < $1.cheminComplet.count }
    }

    // MARK: Journal

    func journal(limite: Int = 200, projetId: String? = nil, depuis: String? = nil) throws -> [EntreeJournal] {
        var conditions: [String] = [], params: [Any?] = []
        if let projetId { conditions.append("projet_id = ?"); params.append(projetId) }
        if let depuis { conditions.append("le >= ?"); params.append(depuis) }
        let ou = conditions.isEmpty ? "" : "WHERE " + conditions.joined(separator: " AND ")
        return try base.lignes("SELECT * FROM journal \(ou) ORDER BY le DESC LIMIT \(limite)", params).map(Self.entree)
    }

    /// Les derniers tours d'une session de l'app (identifiant local_…, stable d'une remise à zéro à l'autre).
    func journal(sessionApp: String, limite: Int = 8) throws -> [EntreeJournal] {
        try base.lignes("SELECT * FROM journal WHERE session_app = ? ORDER BY le DESC LIMIT \(limite)", [sessionApp]).map(Self.entree)
    }

    /// Ajoute une entrée au journal (sans doublon : même source_ref = même entrée). Le projet est déduit du dossier.
    @discardableResult
    func ajouterJournal(_ champs: [String: Any]) throws -> EntreeJournal? {
        var champs = champs
        if let ref = champs["source_ref"] as? String, !ref.isEmpty,
           let deja = try base.lignes("SELECT * FROM journal WHERE source_ref = ?", [ref]).first {
            return Self.entree(deja)
        }
        if let d = champs["dossier"] as? String { champs["dossier"] = Chemins.court(d) }
        if (champs["projet_id"] as? String ?? "").isEmpty, let d = champs["dossier"] as? String, let p = try projetPour(dossier: d) {
            champs["projet_id"] = p.id
        }
        if let f = champs["fichiers"] as? [String] { champs["fichiers"] = f.joined(separator: "\n") }
        let id = UUID().uuidString.lowercased()
        let colonnes = ["le", "type", "session", "session_app", "titre_session", "dossier", "projet_id", "demande", "texte", "fichiers", "source_ref"]
        let fournis = colonnes.filter { champs[$0] != nil }
        var valeurs: [Any?] = fournis.map { c -> Any? in
            let s = Self.texte(champs[c]) ?? ""
            return c == "source_ref" && s.isEmpty ? nil : s
        }
        var cols = fournis
        if champs["le"] == nil { cols.append("le"); valeurs.append(Dates.maintenant()) }
        try base.executer("INSERT INTO journal (id, \(cols.joined(separator: ", "))) VALUES (?, \(cols.map { _ in "?" }.joined(separator: ", ")))",
                          [id] + valeurs)
        return try base.lignes("SELECT * FROM journal WHERE id = ?", [id]).first.map(Self.entree)
    }

    // MARK: Recherche partout

    func chercherPartout(_ texte: String, fichiers avecFichiers: Bool = true) throws -> ResultatsRecherche {
        let t = texte.trimmingCharacters(in: .whitespaces)
        guard t.count >= 2 else { return ResultatsRecherche() }
        let motif = "%\(t)%"
        var r = ResultatsRecherche()
        r.contacts = Array(try chercher(t).prefix(12))
        r.projets = try base.lignes("""
            SELECT * FROM projets WHERE nom LIKE ?1 OR description LIKE ?1 OR dossier LIKE ?1 OR documents LIKE ?1
              OR notes LIKE ?1 OR depot LIKE ?1 OR site LIKE ?1
            """, [motif]).map(Self.projet)
        r.journal = try base.lignes("""
            SELECT * FROM journal WHERE texte LIKE ?1 OR demande LIKE ?1 OR fichiers LIKE ?1 OR titre_session LIKE ?1
            ORDER BY le DESC LIMIT 15
            """, [motif]).map(Self.entree)
        if avecFichiers {
            let dossiers = try projets().map(\.cheminComplet)
                + ["~/Documents", "~/Downloads", "~/Library/Mobile Documents/com~apple~CloudDocs"].map(Chemins.complet)
            r.fichiers = Fichiers.chercher(t, dans: dossiers)
        }
        return r
    }

    // MARK: Conversions

    static func identifiant(_ nom: String) -> String {
        let base = nom.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
            .lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }
        let s = String(base).split(separator: "-").joined(separator: "-")
        return s.isEmpty ? UUID().uuidString.lowercased() : s
    }

    private static func valeurProjet(_ col: String, _ v: Any?) -> Any? {
        col == "ordre" ? ((v as? Int) ?? Int(texte(v) ?? "") ?? 100) : (texte(v) ?? "")
    }

    static func projet(_ l: [String: Any]) -> Projet {
        func s(_ k: String) -> String { l[k] as? String ?? "" }
        return Projet(id: s("id"), espace: s("espace"), nom: s("nom"), description: s("description"), dossier: s("dossier"),
                      depot: s("depot"), site: s("site"), statut: s("statut"), documents: s("documents"), notes: s("notes"),
                      ordre: l["ordre"] as? Int ?? 100, majLe: s("maj_le"))
    }

    static func entree(_ l: [String: Any]) -> EntreeJournal {
        func s(_ k: String) -> String { l[k] as? String ?? "" }
        return EntreeJournal(id: s("id"), le: s("le"), type: s("type"), session: s("session"), sessionApp: s("session_app"),
                             titreSession: s("titre_session"), dossier: s("dossier"), projetId: s("projet_id"),
                             demande: s("demande"), texte: s("texte"), fichiers: s("fichiers"))
    }
}

/// Recherche de fichiers par Spotlight (nom d'abord, puis contenu), limitée aux dossiers de la carte.
enum Fichiers {
    static let exclus = ["/node_modules/", "/.git/", "/.next/", "/build/", "/DerivedData/", "/.build/", "/Pods/", "/dist/",
                         "/.vercel/", "/out/", "/graphify-out/", "/.playwright-mcp/", "/Library/Caches/"]

    static func chercher(_ texte: String, dans dossiers: [String], limite: Int = 40) -> [String] {
        let existants = Array(Set(dossiers)).filter { FileManager.default.fileExists(atPath: $0) }
        guard !existants.isEmpty else { return [] }
        let portee = existants.flatMap { ["-onlyin", $0] }
        var vus = Set<String>(), sortie: [String] = []
        for args in [["-name", texte] + portee, portee + [texte]] {
            for chemin in mdfind(args) where !vus.contains(chemin) && !exclus.contains(where: { chemin.contains($0) }) {
                vus.insert(chemin)
                sortie.append(chemin)
                if sortie.count >= limite { return sortie }
            }
        }
        return sortie
    }

    private static func mdfind(_ arguments: [String]) -> [String] {
        if Demo.actif { return [] }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        p.arguments = arguments
        let sortie = Pipe()
        p.standardOutput = sortie
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return [] }
        let data = sortie.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: data, encoding: .utf8)?.split(separator: "\n").map(String.init) ?? []
    }
}
