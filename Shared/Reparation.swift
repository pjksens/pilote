// Réparation automatique des suites (04/11, PILOTE : « fais tourner repare-suites tout seul jusqu'à ce qu'il n'y ait plus de
// serveur MCP antérieur au binaire, en notant chaque correction au fil »).
// Un serveur MCP « pilote mcp » lancé avant le dernier build garde l'ancien code : il peut encore laisser une fiche « due » après un
// envoi. Tant qu'un tel serveur tourne, chaque passe du capteur (60 s) rétablit les suites oubliées. On ne tue aucun processus.
import Foundation

enum VieuxMCP {
    struct Serveur: Equatable {
        var pid: Int
        var debut: Date
    }

    private static let formatDebut: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE MMM d HH:mm:ss yyyy"
        return f
    }()

    /// Les serveurs MCP de Pilote dans la sortie de `ps -axo pid=,lstart=,command=` (ex. « 4319 Wed Nov  4 13:12:30 2026 /…/pilote mcp »).
    static func serveurs(dans sortie: String) -> [Serveur] {
        let motif = try! NSRegularExpression(pattern: #"^\s*(\d+)\s+(\w{3}\s+\w{3}\s+\d+\s+\d{2}:\d{2}:\d{2}\s+\d{4})\s+(.*)$"#)
        return sortie.split(separator: "\n").compactMap { ligne in
            let l = String(ligne)
            guard let m = motif.firstMatch(in: l, range: NSRange(l.startIndex..., in: l)), m.numberOfRanges == 4,
                  let r1 = Range(m.range(at: 1), in: l), let r2 = Range(m.range(at: 2), in: l), let r3 = Range(m.range(at: 3), in: l),
                  let pid = Int(l[r1]) else { return nil }
            let commande = String(l[r3])
            guard commande.hasSuffix("/pilote mcp") else { return nil }
            let debut = l[r2].split(whereSeparator: \.isWhitespace).joined(separator: " ")
            guard let d = formatDebut.date(from: debut) else { return nil }
            return Serveur(pid: pid, debut: d)
        }
    }

    /// Ceux qui ont démarré avant la dernière écriture du binaire : ils tournent avec l'ancien code.
    static func anterieurs(_ serveurs: [Serveur], aLaDateDe binaire: Date) -> [Serveur] {
        serveurs.filter { $0.debut < binaire }
    }

    /// Les serveurs MCP de Pilote en route sur ce Mac (lecture seule : `ps`).
    static func enRoute() -> [Serveur] {
        if Demo.actif { return [] }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/ps")
        p.arguments = ["-axo", "pid=,lstart=,command="]
        let sortie = Pipe()
        p.standardOutput = sortie
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return [] }
        let donnees = sortie.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return serveurs(dans: String(decoding: donnees, as: UTF8.self))
    }
}

extension Stockage {
    /// Une passe automatique : si un serveur MCP plus ancien que le binaire tourne, rétablit les suites oubliées (une note au fil par
    /// fiche). `sauvegarder` est appelé UNE fois, avant la première correction de la passe. Renvoie le nombre de fiches corrigées.
    @discardableResult
    func reparationAutomatique(vieuxServeurs: Int, jour: String = Dates.aujourdhui(), sauvegarder: () throws -> Void) throws -> Int {
        guard vieuxServeurs > 0 else { return 0 }
        let liste = try suitesARetablir(jour: jour)
        guard !liste.isEmpty else { return 0 }
        try sauvegarder()
        try retablirSuites(liste)
        return liste.count
    }

    /// Copie cohérente de la base (VACUUM INTO) ; le fichier ne doit pas exister.
    func copierBase(vers chemin: String) throws {
        try base.executer("VACUUM INTO ?", [chemin])
    }
}
