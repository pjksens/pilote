// Sessions Claude Code de l'app Claude : celles qui tournent (~/.claude/sessions) et les récentes
// (données de l'app Claude). Ouverture et lancement par les liens claude://code/…
import AppKit
import Foundation

struct SessionClaude: Identifiable, Hashable {
    let id: String              // local_… (identifiant de l'app Claude)
    let titre: String
    let dossier: String
    let etat: String            // busy | waiting | idle | "" si la session ne tourne pas
    let derniereActivite: Date?
    let favorite: Bool

    var libelleEtat: String {
        switch etat {
        case "busy": return L("Au travail")
        case "waiting": return L("Attend votre réponse")
        case "idle": return L("En pause")
        default: return ""
        }
    }

    var dossierCourt: String {
        dossier.replacingOccurrences(of: Demo.maison.path, with: "~")
    }
}

struct RoutineClaude: Identifiable {
    let id: String
    let titre: String
    let detail: String
    let dossier: String
    let consigne: String
}

enum Claude {
    static let maison = Demo.maison

    /// Les dossiers proposés à l'ouverture d'une session : reglages.json (`dossiers_sessions`), sinon le dossier personnel.
    /// Calculé : la langue se lit à l'appel.
    static var dossiers: [(String, String)] {
        let r = (Reglages.courants.dossiersSessions ?? []).map { ($0.nom, Reglages.url($0.chemin).path) }
        return r.isEmpty ? [(L("Dossier personnel"), maison.path)] : r
    }

    /// Les routines lancées d'un clic : reglages.json (`routines`), aucune par défaut. Titre et détail viennent de vos réglages.
    static var routines: [RoutineClaude] {
        (Reglages.courants.routines ?? []).map {
            RoutineClaude(id: $0.id, titre: $0.titre, detail: $0.detail ?? "", dossier: Reglages.url($0.dossier).path,
                          consigne: $0.consigne)
        }
    }

    /// Sessions qui tournent en ce moment (processus vivant), avec leur état.
    static func enCours() -> [String: String] {
        let dossier = maison.appendingPathComponent(".claude/sessions")
        guard let fichiers = try? FileManager.default.contentsOfDirectory(at: dossier, includingPropertiesForKeys: nil) else { return [:] }
        var etats: [String: String] = [:]
        for f in fichiers where f.pathExtension == "json" {
            guard let data = try? Data(contentsOf: f),
                  let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let pid = o["pid"] as? Int, kill(pid_t(pid), 0) == 0,
                  let id = o["hostSessionId"] as? String else { continue }
            etats[id] = o["status"] as? String ?? "idle"
        }
        return etats
    }

    /// Fichiers de session déjà lus, par date de modification : un fichier inchangé n'est pas relu (412 fichiers, 130 Mo en tout).
    /// `nil` = fichier à ignorer (archivé ou illisible). L'état « tourne / ne tourne pas » est repris à chaque appel.
    private final class CacheSessions: @unchecked Sendable {
        private let verrou = NSLock()
        private var entrees: [String: (modifie: Date, session: SessionClaude?)] = [:]
        func entree(_ chemin: String, modifie: Date) -> (SessionClaude?)? {
            verrou.lock(); defer { verrou.unlock() }
            guard let e = entrees[chemin], e.modifie == modifie else { return nil }
            return .some(e.session)
        }
        func ranger(_ chemin: String, modifie: Date, session: SessionClaude?) {
            verrou.lock(); defer { verrou.unlock() }
            entrees[chemin] = (modifie, session)
        }
        func oublier(sauf gardes: Set<String>) {
            verrou.lock(); defer { verrou.unlock() }
            entrees = entrees.filter { gardes.contains($0.key) }
        }
    }
    private static let cacheSessions = CacheSessions()

    /// Sessions de l'app Claude, les plus récentes d'abord (archivées exclues).
    static func sessions(limite: Int = 40) -> [SessionClaude] {
        if Demo.actif { return [] }
        let racine = maison.appendingPathComponent("Library/Application Support/Claude/claude-code-sessions")
        let etats = enCours()
        var trouvees: [SessionClaude] = []
        var vus = Set<String>()
        let enumerateur = FileManager.default.enumerator(at: racine, includingPropertiesForKeys: [.contentModificationDateKey])
        while let f = enumerateur?.nextObject() as? URL {
            guard f.pathExtension == "json", f.lastPathComponent.hasPrefix("local_") else { continue }
            let chemin = f.path
            vus.insert(chemin)
            let modifie = (try? f.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            let session: SessionClaude?
            if modifie != .distantPast, let connue = cacheSessions.entree(chemin, modifie: modifie) {
                session = connue
            } else {
                session = lire(f)
                if modifie != .distantPast { cacheSessions.ranger(chemin, modifie: modifie, session: session) }
            }
            guard let s = session else { continue }
            trouvees.append(SessionClaude(id: s.id, titre: s.titre, dossier: s.dossier, etat: etats[s.id] ?? "",
                                          derniereActivite: s.derniereActivite, favorite: s.favorite))
        }
        cacheSessions.oublier(sauf: vus)
        return trouvees.sorted { ($0.derniereActivite ?? .distantPast) > ($1.derniereActivite ?? .distantPast) }
            .prefix(limite).map { $0 }
    }

    /// Lit un fichier de session de l'app Claude (nil : archivé ou illisible).
    private static func lire(_ f: URL) -> SessionClaude? {
        guard let data = try? Data(contentsOf: f),
              let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = o["sessionId"] as? String, (o["isArchived"] as? Bool) != true else { return nil }
        let ms = (o["lastActivityAt"] as? Double) ?? Double(o["lastActivityAt"] as? String ?? "") ?? 0
        return SessionClaude(id: id, titre: (o["title"] as? String) ?? L("Sans titre"), dossier: (o["cwd"] as? String) ?? "",
                             etat: "", derniereActivite: ms > 0 ? Date(timeIntervalSince1970: ms / 1000) : nil,
                             favorite: (o["isStarred"] as? Bool) ?? false)
    }

    static func ouvrir(_ s: SessionClaude) { ouvrir(id: s.id) }

    /// Ouvre une session de l'app Claude par son identifiant local_….
    static func ouvrir(id: String) {
        if Demo.actif { return }
        guard !id.isEmpty else { return }
        var c = URLComponents(string: "claude://code/continue")!
        c.queryItems = [URLQueryItem(name: "session", value: id)]
        if let url = c.url { NSWorkspace.shared.open(url) }
    }

    /// Prépare une nouvelle session dans l'app Claude (consigne + dossier). Sacha la lance.
    static func nouvelle(consigne: String, dossier: String) {
        if Demo.actif { return }
        var c = URLComponents(string: "claude://code/new")!
        var items: [URLQueryItem] = []
        if !consigne.isEmpty { items.append(URLQueryItem(name: "q", value: consigne)) }
        if !dossier.isEmpty { items.append(URLQueryItem(name: "folder", value: dossier)) }
        c.queryItems = items
        if let url = c.url { NSWorkspace.shared.open(url) }
    }
}
