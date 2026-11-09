// Le travail des agents (09/11, Sacha : « que je voie si ça a été fait, si c'est à faire, à quelle heure ») : la liste Rappels
// « Agents », sans échéance pour ne pas encombrer son « Aujourd'hui » sur l'iPhone. Le domaine et l'heure prévue sont écrits
// dans la note. « À toi » ne lit jamais cette liste : elle se suit dans chaque domaine.
import Foundation

struct TravailAgent: Identifiable, Hashable, Codable {
    var id: String
    var titre: String
    var domaine: Domaine?
    var prevu: Date?
    var faite: Bool
    var faiteLe: Date?
}

enum TravailAgents {
    static let liste = "Agents"

    static func lire(id: String, titre: String, notes: String, faite: Bool, faiteLe: Date?) -> TravailAgent {
        let (d, p) = note(notes)
        return TravailAgent(id: id, titre: titre, domaine: d, prevu: p, faite: faite, faiteLe: faiteLe)
    }

    /// Les deux formats d'EQUIPE.md ; la dernière mention de la note gagne :
    /// « Pour : Réseaux · Prévu : 2026-11-09T18:00 » (règle du 09/11) ;
    /// « Tri du 09/11 : travail d'agent, pour Réseaux. Échéance d'origine : 2026-11-09T18:00 (liste Contenu). »
    static func note(_ notes: String) -> (Domaine?, Date?) {
        var dernier: (position: Int, qui: String, date: String, liste: String?)?
        let ns = notes as NSString
        for motif in motifs {
            for m in motif.matches(in: notes, range: NSRange(location: 0, length: ns.length)) {
                let liste = m.numberOfRanges > 3 && m.range(at: 3).location != NSNotFound ? ns.substring(with: m.range(at: 3)) : nil
                if dernier == nil || m.range.location >= dernier!.position {
                    dernier = (m.range.location, ns.substring(with: m.range(at: 1)), ns.substring(with: m.range(at: 2)), liste)
                }
            }
        }
        guard let d = dernier else { return (nil, nil) }
        return (domaine(d.qui) ?? d.liste.flatMap(domaineDeListe), format.date(from: d.date))
    }

    /// « Réseaux », « App », « App et interface », « KRYVA · Ventes », « FREELANCE », « Papiers », « PILOTE » (sa ligne depuis le 09/11).
    static func domaine(_ texte: String) -> Domaine? {
        let t = texte.trimmingCharacters(in: .whitespacesAndNewlines)
        return Domaine.depuis(t) ?? Domaine.deSession(titre: t, dossier: "") ?? domaineDeListe(t)
    }

    static func domaineDeListe(_ liste: String) -> Domaine? {
        switch liste.trimmingCharacters(in: .whitespaces).lowercased() {
        case "contenu": return .reseaux
        case "appels": return .ventes
        case "freelance": return .freelance
        case "papiers": return .papiers
        default: return nil
        }
    }

    private static let motifs: [NSRegularExpression] = [
        #"Pour\s*:\s*([^·\n]+?)\s*·\s*Prévu\s*:\s*(\d{4}-\d{2}-\d{2}T\d{2}:\d{2})"#,
        #"travail d.agent,\s*pour\s+([^.\n]+?)\.\s*Échéance d.origine\s*:\s*(\d{4}-\d{2}-\d{2}T\d{2}:\d{2})(?:\s*\(liste ([^)]+)\))?"#,
    ].map { try! NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }

    private static let format: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd'T'HH:mm"; return f
    }()
}
