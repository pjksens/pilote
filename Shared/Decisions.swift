// Les décisions de Sacha (règle du 03/11) : une question = un rappel « ❓ … », jamais une question dans un chat.
// Dans les notes du rappel, chaque choix tient sur une ligne « Option 1 : … » ou « A : … ».
// Un clic sur un choix coche le rappel et écrit une ligne « decision » dans entrants.jsonl ; la veille la passe
// à la session « pour » (ligne « Pour : … » des notes, sinon d'après la liste du rappel).
import Foundation

enum Decisions {
    static let marque = "❓"

    static func estDecision(_ titre: String) -> Bool { titre.trimmingCharacters(in: .whitespaces).hasPrefix(marque) }

    /// La question sans le « ❓ » de tête.
    static func question(_ titre: String) -> String {
        var t = titre.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix(marque) { t.removeFirst(marque.count) }
        return t.trimmingCharacters(in: .whitespaces)
    }

    /// Les choix lus dans les notes (« Option 1 : … », « Option A - … », « Choix 2 : … »), dans l'ordre.
    static func options(_ notes: String) -> [String] {
        notes.split(whereSeparator: \.isNewline).compactMap { brut in
            let ligne = brut.trimmingCharacters(in: .whitespaces)
            guard let sep = ligne.firstIndex(where: { $0 == ":" || $0 == "-" || $0 == "–" }) else { return nil }
            let tete = ligne[..<sep].split(separator: " ")
            // « Option 1 », « Choix A », « Option », ou une lettre seule « A : … » (format des rappels de Réseaux) ;
            // pas « Optionnel » ni « Option très longue ».
            let lettre = tete.count == 1 && tete[0].count == 1 && (tete[0].first?.isUppercase ?? false)
            guard let mot = tete.first?.lowercased(), lettre || (["option", "choix"].contains(mot) && tete.count <= 2) else { return nil }
            let reste = ligne[ligne.index(after: sep)...].trimmingCharacters(in: .whitespaces)
            return reste.isEmpty ? nil : reste
        }
    }

    /// Les notes sans les lignes de choix ni les liens (« Docs : », adresses) : le contexte montré sur la carte.
    static func contexte(_ notes: String) -> String {
        notes.split(whereSeparator: \.isNewline).map(String.init).filter { l in
            let t = l.trimmingCharacters(in: .whitespaces)
            return options(t).isEmpty && !t.contains("://") && !t.lowercased().hasPrefix("docs")
                && destinataireEcrit(t) == nil && !estChemin(t)
        }.joined(separator: "\n")
    }

    /// Les fichiers à lire pour trancher : liens file://, chemins « ~/… » ou « /Users/… », un par ligne.
    static func documents(_ notes: String) -> [String] {
        notes.split(whereSeparator: \.isNewline).compactMap { brut in
            var l = brut.trimmingCharacters(in: .whitespaces)
            if let r = l.range(of: "file://") {
                l = String(l[r.upperBound...]).components(separatedBy: " ").first ?? ""
                return l.removingPercentEncoding ?? l
            }
            if l.lowercased().hasPrefix("docs"), let sep = l.firstIndex(of: ":") {
                l = l[l.index(after: sep)...].trimmingCharacters(in: .whitespaces)
            }
            if !estChemin(l) {
                // Un chemin au milieu d'une phrase (« Textes exacts : ~/Projects/…/x.md (envoyée…) »).
                guard let r = l.range(of: #"(~|/Users)/[^\s,;«»()]+"#, options: .regularExpression) else { return nil }
                l = String(l[r])
                while l.hasSuffix(".") || l.hasSuffix(":") { l.removeLast() }
            }
            return Chemins.complet(l)
        }
    }

    private static func estChemin(_ l: String) -> Bool { l.hasPrefix("~/") || l.hasPrefix("/Users/") }

    /// Les sessions qui peuvent recevoir une décision (EQUIPE.md), et le mot qui les désigne dans « Pour : … ».
    static let destinataires: [(mot: String, nom: String)] = [
        ("papiers", "KRYVA · Papiers et admin"), ("réseaux", "KRYVA · Réseaux, image, événements"),
        ("ventes", "KRYVA · Ventes"), ("app", "KRYVA · App et interface"), ("freelance", "FREELANCE"), ("pilote", "PILOTE"),
    ]

    /// « Pour : Réseaux » dans les notes : la session à prévenir, écrite par celle qui a posé la question.
    static func destinataireEcrit(_ ligne: String) -> String? {
        let l = ligne.trimmingCharacters(in: .whitespaces).lowercased()
        guard l.hasPrefix("pour"), let sep = l.firstIndex(of: ":") else { return nil }
        let reste = l[l.index(after: sep)...]
        return destinataires.first { reste.contains($0.mot) }?.nom
    }

    /// La session qui doit apprendre le choix, d'après la liste du rappel (EQUIPE.md). PILOTE relaie la ligne
    /// à cette session ; liste mélangée (KRYVA) ou inconnue = PILOTE tranche à qui la passer.
    static func pour(liste: String, notes: String = "") -> String {
        if let nom = notes.split(whereSeparator: \.isNewline).lazy.compactMap({ destinataireEcrit(String($0)) }).first { return nom }
        switch liste {
        case "Contenu": return "KRYVA · Réseaux, image, événements"
        case "Papiers": return "KRYVA · Papiers et admin"
        case "Freelance": return "FREELANCE"
        case "Appels": return "KRYVA · Ventes"
        default: return "PILOTE"
        }
    }

    /// {"canal":"pilote","classe":"decision","extrait":question,"choix":…,"heure":…,"qui":"Sacha","ref":…,"liste":…,"pour":…}
    static func ligne(question: String, choix: String, ref: String, liste: String, heure: Date, pour: String? = nil,
                      session: String? = nil) -> String {
        var champs: [(String, String)] = [
            ("canal", "pilote"), ("classe", "decision"), ("extrait", question), ("choix", choix),
            ("heure", TachesTerminees.iso.string(from: heure)), ("qui", "\(Moi.nom)"), ("ref", ref), ("liste", liste),
            ("pour", pour ?? Self.pour(liste: liste)),
        ]
        // La question d'une session (wrap_up) : le Facteur et la veille la remettent à cette session-là.
        if let session, session.hasPrefix("local_") { champs.append(("session", session)) }
        return "{" + champs.map { TachesTerminees.json($0.0) + ":" + TachesTerminees.json($0.1) }.joined(separator: ",") + "}"
    }

    static func noter(question: String, choix: String, ref: String, liste: String, pour: String? = nil, session: String? = nil,
                      heure: Date = Date(), dossier: URL = TachesTerminees.dossierParDefaut) throws {
        try TachesTerminees(dossier: dossier).ajouter(ligne(question: question, choix: choix, ref: ref, liste: liste, heure: heure,
                                                            pour: pour, session: session))
    }

    /// Les questions de session (ref « session:… ») auxquelles Sacha a déjà répondu : elles ne s'affichent plus.
    static func questionsRepondues(dossier: URL = TachesTerminees.dossierParDefaut) -> Set<String> {
        refsRepondues(prefixe: "session:", dossier: dossier)
    }

    /// Les refs d'un genre (« session: », « idee: ») qui ont déjà une décision de Sacha dans entrants.jsonl.
    static func refsRepondues(prefixe: String, dossier: URL = TachesTerminees.dossierParDefaut) -> Set<String> {
        guard let texte = try? String(contentsOf: dossier.appendingPathComponent("entrants.jsonl"), encoding: .utf8) else { return [] }
        var r = Set<String>()
        for l in texte.split(separator: "\n") where l.contains("\"ref\":\"\(prefixe)") {
            if let d = l.data(using: .utf8), let o = try? JSONSerialization.jsonObject(with: d) as? [String: String],
               o["classe"] == "decision", let ref = o["ref"] { r.insert(ref) }
        }
        return r
    }

    // MARK: Suivi : la décision est-elle partie ?

    struct Envoyee: Identifiable, Hashable {
        let id: Int            // rang de la ligne dans entrants.jsonl
        let question: String
        let choix: String
        let pour: String
        let heure: String      // « 21:13 »
        let transmise: Bool    // remise à la session (Facteur ou veille)
        var remise: Facteur.Remise? = nil
        /// Sacha ne l'a pas encore envoyée : elle attend son clic « Envoyer ».
        var enAttente = false
    }

    /// Les décisions du jour et celles qui attendent d'être envoyées (48 h), avec leur état : remises.jsonl (Facteur,
    /// veille, clics de Sacha) ; avant le Facteur, veille-repere.json (nombre de lignes déjà transmises).
    static func envoyees(jour: String = Dates.aujourdhui(), dossier: URL = TachesTerminees.dossierParDefaut) -> [Envoyee] {
        let entrants = dossier.appendingPathComponent("entrants.jsonl")
        guard let texte = try? String(contentsOf: entrants, encoding: .utf8) else { return [] }
        let repere = (try? Data(contentsOf: dossier.appendingPathComponent("veille-repere.json")))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        let lues = repere?["lignes"] as? Int ?? 0
        let remises = Facteur.remises(dossier: dossier)
        let premier = Facteur.depart(dossier: dossier)
        let veille = Calendar.current.date(byAdding: .day, value: -1, to: Dates.date(jour) ?? Date()).map { Dates.jour.string(from: $0) } ?? jour
        return texte.split(separator: "\n", omittingEmptySubsequences: false).enumerated().compactMap { i, l in
            guard l.contains("\"decision\""), let d = l.data(using: .utf8),
                  let o = try? JSONSerialization.jsonObject(with: d) as? [String: String],
                  o["classe"] == "decision", let h = o["heure"] else { return nil }
            // Avant le Facteur, la veille seule : passée = transmise. Depuis, seule une remise notée compte.
            let r = remises[i]
            let attente = r == nil && i >= premier
            guard h.hasPrefix(jour) || (attente && h >= veille) else { return nil }
            let heure = h.dropFirst(11).prefix(5)
            return Envoyee(id: i, question: o["extrait"] ?? "", choix: o["choix"] ?? "", pour: o["pour"] ?? "PILOTE",
                           heure: String(heure), transmise: r.map { $0.etat == .remis } ?? (i < lues && !attente),
                           remise: r, enAttente: attente)
        }
    }

    /// L'heure du prochain passage de la veille (dernier passage + 15 min), d'après veille-repere.json.
    static func prochaineVeille(dossier: URL = TachesTerminees.dossierParDefaut) -> Date? {
        let u = dossier.appendingPathComponent("veille-repere.json")
        guard let d = (try? FileManager.default.attributesOfItem(atPath: u.path))?[.modificationDate] as? Date else { return nil }
        var p = d.addingTimeInterval(15 * 60)
        while p < Date() { p.addTimeInterval(15 * 60) }
        return p
    }
}
