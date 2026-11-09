// Lecture des fiches .md pour le panneau de droite (03/11, Sacha : « ouvrir tous les fichiers depuis Pilote »).
// Découpe en blocs simples : titres, listes, citations, code, tableaux, traits, paragraphes. Le gras et les liens
// à l'intérieur d'une ligne sont rendus par AttributedString côté app.
import Foundation

enum BlocMarkdown: Hashable {
    case titre(niveau: Int, texte: String)
    case puce(retrait: Int, texte: String)
    case numero(retrait: Int, numero: String, texte: String)
    case tache(fait: Bool, texte: String)
    case citation(String)
    case code(String)
    case tableau([[String]])
    case trait
    case paragraphe(String)
}

enum Markdown {
    static func blocs(_ texte: String) -> [BlocMarkdown] {
        var blocs: [BlocMarkdown] = []
        var paragraphe: [String] = []
        var code: [String]?
        var tableau: [[String]] = []

        func vider() {
            if !paragraphe.isEmpty { blocs.append(.paragraphe(paragraphe.joined(separator: "\n"))); paragraphe = [] }
            if !tableau.isEmpty { blocs.append(.tableau(tableau)); tableau = [] }
        }

        for brut in texte.components(separatedBy: "\n") {
            let ligne = brut.replacingOccurrences(of: "\t", with: "    ")
            let t = ligne.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("```") {
                if let c = code { blocs.append(.code(c.joined(separator: "\n"))); code = nil } else { vider(); code = [] }
                continue
            }
            if code != nil { code?.append(ligne); continue }
            if t.isEmpty { vider(); continue }
            if t.hasPrefix("|") {
                if !paragraphe.isEmpty { vider() }
                let cellules = t.trimmingCharacters(in: CharacterSet(charactersIn: "|")).components(separatedBy: "|")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                // La ligne « |---|---| » sous l'en-tête ne s'affiche pas.
                if cellules.allSatisfy({ !$0.isEmpty && $0.allSatisfy { "-: ".contains($0) } }) { continue }
                tableau.append(cellules)
                continue
            }
            if !tableau.isEmpty { vider() }
            let retrait = (ligne.prefix { $0 == " " }.count) / 2
            let dieses = t.prefix { $0 == "#" }.count
            if dieses > 0, dieses <= 6, t.dropFirst(dieses).hasPrefix(" ") {
                vider(); blocs.append(.titre(niveau: dieses, texte: String(t.dropFirst(dieses + 1)))); continue
            }
            if t == "---" || t == "***" || t == "___" { vider(); blocs.append(.trait); continue }
            if t.hasPrefix("- [ ] ") || t.hasPrefix("- [x] ") || t.hasPrefix("- [X] ") {
                vider(); blocs.append(.tache(fait: !t.hasPrefix("- [ ] "), texte: String(t.dropFirst(6)))); continue
            }
            if t.hasPrefix("- ") || t.hasPrefix("* ") || t.hasPrefix("+ ") {
                vider(); blocs.append(.puce(retrait: retrait, texte: String(t.dropFirst(2)))); continue
            }
            if let point = t.firstIndex(where: { $0 == "." || $0 == ")" }), point > t.startIndex,
               t[..<point].allSatisfy(\.isNumber), t[t.index(after: point)...].hasPrefix(" ") {
                vider()
                blocs.append(.numero(retrait: retrait, numero: String(t[..<point]),
                                     texte: String(t[t.index(point, offsetBy: 2)...])))
                continue
            }
            if t.hasPrefix(">") {
                vider(); blocs.append(.citation(t.dropFirst().trimmingCharacters(in: .whitespaces))); continue
            }
            paragraphe.append(t)
        }
        if let c = code { blocs.append(.code(c.joined(separator: "\n"))) }
        vider()
        return blocs
    }
}
