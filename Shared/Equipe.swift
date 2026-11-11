// L'équipe de sessions Claude en pyramide.
// - La hiérarchie vient d'un seul endroit : les deux tableaux de EQUIPE.md, dans le dossier de données (Identite.dossier)
//   (« Sessions de domaine » et « Chantiers en cours »). Les fichiers de ~/.claude/sessions n'ont aucun champ parent.
// - L'état vient de Sessions.vivantes() : on relie les deux par l'identifiant app (local_…), jamais par le titre.
// - Les sous-agents sont estimés dans ~/.claude/projects/<projet>/<session>/subagents/ (voir sousAgentsActifs).
// Lecture seule : rien n'est archivé, déplacé ni écrit.
import Foundation

enum NiveauEquipe: String, Codable {
    case pilote      // étage 1
    case domaine     // étage 2
    case chantier    // étage 3
    case horsCarte   // session vivante absente d'EQUIPE.md
}

struct MembreEquipe: Identifiable, Hashable, Codable {
    var nom: String
    var sessionApp: String
    var niveau: NiveauEquipe
    var domaine = ""
    var dossiers = ""
    var remonteA = ""       // tel qu'écrit dans le tableau des chantiers
    var id: String { sessionApp.isEmpty ? nom : sessionApp }
}

/// Un membre de l'équipe, avec ce qu'il fait en ce moment (nil = la session ne tourne pas).
struct NoeudPyramide: Identifiable {
    var membre: MembreEquipe
    var activite: ActiviteSession?
    var sousAgents = 0              // estimation, voir Equipe.sousAgentsActifs
    var badges: [String] = []
    var id: String { membre.id }
    var enLigne: Bool { activite != nil }

    /// « au travail », « attend Sacha », « au repos » ou « hors ligne ».
    var libelleEtat: String {
        guard let a = activite else { return L("hors ligne") }
        switch a.etat {
        case "busy": return L("au travail")
        case "waiting": return L("attend Sacha")
        default: return L("au repos")
        }
    }

    /// Poids du contexte relu à chaque action, en k.
    var contexteK: Int? {
        guard let a = activite, a.contexte > 0 else { return nil }
        return a.contexte / 1000
    }

    /// Dernière étape en cours, sinon dernière action, avec l'heure de la dernière action.
    var dernier: (texte: String, quand: Date?)? {
        guard let a = activite else { return nil }
        let t = a.etape.isEmpty ? a.action : a.etape
        return t.isEmpty ? nil : (t, a.actionLe)
    }
}

/// Une colonne de la pyramide : une session de domaine (étage 2) et ses chantiers (étage 3).
/// `tete` est nil pour les chantiers rattachés directement à PILOTE ou à un nom inconnu.
struct ColonnePyramide: Identifiable {
    var id: String
    var titre: String
    var tete: NoeudPyramide?
    var chantiers: [NoeudPyramide]
}

struct Pyramide {
    var fichierTrouve = false
    var pilote: NoeudPyramide?
    var colonnes: [ColonnePyramide] = []
    var horsCarte: [NoeudPyramide] = []

    var tous: [NoeudPyramide] {
        (pilote.map { [$0] } ?? []) + colonnes.flatMap { ($0.tete.map { [$0] } ?? []) + $0.chantiers } + horsCarte
    }
}

enum Equipe {
    static var fichier: URL { Identite.dossier.appendingPathComponent("EQUIPE.md") }
    static let seuilRelais = 130_000
    static let delaiArchivage: TimeInterval = 24 * 3600
    /// Un sous-agent est dit actif si son fil a bougé depuis moins de ce délai (et qu'il n'est pas marqué fini).
    static let fenetreSousAgents: TimeInterval = 150

    // MARK: Lecture d'EQUIPE.md

    /// Les membres lus dans EQUIPE.md, dans l'ordre des tableaux. Liste vide si le fichier manque.
    static func membres() -> [MembreEquipe] {
        guard let texte = try? String(contentsOf: fichier, encoding: .utf8) else { return [] }
        return analyser(texte)
    }

    /// Analyse tolérante : repère les tableaux par leur première colonne (« Session » ou « Chantier »),
    /// retrouve les autres colonnes par leur nom, ignore ce qu'il ne comprend pas.
    static func analyser(_ texte: String) -> [MembreEquipe] {
        var resultat: [MembreEquipe] = []
        var vus = Set<String>()
        for tableau in tableaux(texte) {
            guard let entete = tableau.first, let premiere = entete.first.map(normaliser) else { continue }
            let estDomaine = premiere == "session", estChantier = premiere == "chantier"
            guard estDomaine || estChantier else { continue }
            let colonnes = entete.map(normaliser)
            func cellule(_ ligne: [String], _ noms: [String]) -> String {
                guard let i = colonnes.firstIndex(where: { c in noms.contains(where: { c.hasPrefix($0) }) }), i < ligne.count else { return "" }
                return ligne[i]
            }
            for ligne in tableau.dropFirst() {
                guard let nom = ligne.first, !nom.isEmpty else { continue }
                let id = cellule(ligne, ["id"])
                let cle = id.isEmpty ? nom : id
                guard vus.insert(cle).inserted else { continue }
                var m = MembreEquipe(nom: nom, sessionApp: id, niveau: .chantier)
                if estDomaine {
                    m.niveau = normaliser(nom) == "pilote" ? .pilote : .domaine
                    m.domaine = cellule(ligne, ["domaine"])
                    m.dossiers = cellule(ligne, ["dossiers"])
                } else {
                    m.remonteA = cellule(ligne, ["remonte"])
                }
                resultat.append(m)
            }
        }
        return resultat
    }

    /// Les tableaux markdown du texte : liste de lignes de cellules (la ligne de séparation `|---|` est retirée).
    private static func tableaux(_ texte: String) -> [[[String]]] {
        var tous: [[[String]]] = []
        var courant: [[String]] = []
        for brut in texte.split(separator: "\n", omittingEmptySubsequences: false) {
            let ligne = brut.trimmingCharacters(in: .whitespaces)
            guard ligne.hasPrefix("|") else {
                if !courant.isEmpty { tous.append(courant); courant = [] }
                continue
            }
            let cellules = decouper(ligne)
            if cellules.allSatisfy({ $0.allSatisfy { "-: ".contains($0) } }) { continue } // séparateur
            courant.append(cellules)
        }
        if !courant.isEmpty { tous.append(courant) }
        return tous
    }

    private static func decouper(_ ligne: String) -> [String] {
        var cellules: [String] = []
        var actuelle = ""
        var precedent: Character = " "
        for c in ligne {
            if c == "|" && precedent != "\\" {
                cellules.append(nettoyer(actuelle)); actuelle = ""
            } else {
                actuelle.append(c)
            }
            precedent = c
        }
        cellules.append(nettoyer(actuelle))
        if cellules.first == "" { cellules.removeFirst() } // avant le premier |
        if cellules.last == "" { cellules.removeLast() }   // après le dernier |
        return cellules
    }

    private static func nettoyer(_ s: String) -> String {
        s.replacingOccurrences(of: "\\|", with: "|")
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "`", with: "")
            .trimmingCharacters(in: .whitespaces)
    }

    static func normaliser(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func premierMot(_ s: String) -> String {
        normaliser(s).split(whereSeparator: { !$0.isLetter && !$0.isNumber }).first.map(String.init) ?? ""
    }

    /// La session (PILOTE ou de domaine) désignée par la colonne « Remonte à » d'un chantier.
    /// Tolérant : casse et accents ignorés, id accepté, et premier mot (« MARQUE » pour « MARQUE, IMAGE, UX/UI »).
    static func parent(_ remonteA: String, parmi sessions: [MembreEquipe]) -> MembreEquipe? {
        let cible = normaliser(remonteA)
        guard !cible.isEmpty else { return nil }
        if let m = sessions.first(where: { normaliser($0.nom) == cible || $0.sessionApp == remonteA }) { return m }
        let mot = premierMot(remonteA)
        return mot.isEmpty ? nil : sessions.first(where: { premierMot($0.nom) == mot })
    }

    // MARK: Sous-agents

    /// Nombre estimé de sous-agents (outil Agent) au travail pour une session.
    /// Source : ~/.claude/projects/<projet>/<session>/subagents/agent-<id>.jsonl (le fil du sous-agent) et
    /// agent-<id>.meta.json (champ `finished`, présent seulement sur une minorité de sous-agents terminés).
    /// Règle : fil modifié depuis moins de `fenetreSousAgents` secondes ET pas marqué `finished`.
    /// Limites : un sous-agent bloqué sur une longue commande sans écrire peut manquer ; un sous-agent qui vient de
    /// finir sans marqueur compte jusqu'à la fin de la fenêtre. C'est donc une estimation, pas une preuve.
    static func sousAgentsActifs(pour a: ActiviteSession, maintenant: Date = Date()) -> Int {
        guard let fil = Sessions.transcript(cwd: a.dossier, session: a.id) else { return 0 }
        let dossier = fil.deletingLastPathComponent().appendingPathComponent(a.id).appendingPathComponent("subagents")
        guard let fichiers = try? FileManager.default.contentsOfDirectory(at: dossier, includingPropertiesForKeys: [.contentModificationDateKey]) else { return 0 }
        var n = 0
        for f in fichiers where f.pathExtension == "jsonl" && f.lastPathComponent.hasPrefix("agent-") {
            guard let m = (try? f.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
                  maintenant.timeIntervalSince(m) < fenetreSousAgents else { continue }
            let meta = URL(fileURLWithPath: String(f.path.dropLast(".jsonl".count)) + ".meta.json")
            if let data = try? Data(contentsOf: meta),
               let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               (o["finished"] as? Bool) == true { continue }
            n += 1
        }
        return n
    }

    // MARK: Construction de la pyramide

    static func badges(niveau: NiveauEquipe, activite: ActiviteSession?, maintenant: Date) -> [String] {
        guard let a = activite else { return [] }
        var b: [String] = []
        if niveau == .chantier, a.etat == "idle", let d = a.depuis, maintenant.timeIntervalSince(d) > delaiArchivage {
            b.append(L("À valider puis archiver"))
        }
        if a.contexte >= seuilRelais { b.append(L("Relais")) }
        return b
    }

    /// Croise EQUIPE.md et les sessions vivantes. `comptage` donne le nombre de sous-agents actifs d'une session.
    static func pyramide(membres: [MembreEquipe] = Equipe.membres(),
                         vivantes: [ActiviteSession] = Sessions.vivantes(),
                         maintenant: Date = Date(),
                         comptage: (ActiviteSession) -> Int = { sousAgentsActifs(pour: $0) }) -> Pyramide {
        var p = Pyramide(fichierTrouve: FileManager.default.fileExists(atPath: fichier.path))
        let parApp = Dictionary(vivantes.filter { !$0.sessionApp.isEmpty }.map { ($0.sessionApp, $0) }, uniquingKeysWith: { a, _ in a })
        func noeud(_ m: MembreEquipe) -> NoeudPyramide {
            let a = m.sessionApp.isEmpty ? nil : parApp[m.sessionApp]
            return NoeudPyramide(membre: m, activite: a, sousAgents: a.map(comptage) ?? 0,
                                 badges: badges(niveau: m.niveau, activite: a, maintenant: maintenant))
        }
        p.pilote = membres.first(where: { $0.niveau == .pilote }).map(noeud)
        let hauts = membres.filter { $0.niveau == .pilote || $0.niveau == .domaine }
        let domaines = membres.filter { $0.niveau == .domaine }
        var parParent: [String: [NoeudPyramide]] = [:]
        var sansParent: [NoeudPyramide] = []
        var sousPilote: [NoeudPyramide] = []
        for c in membres where c.niveau == .chantier {
            if let h = parent(c.remonteA, parmi: hauts) {
                if h.niveau == .pilote { sousPilote.append(noeud(c)) } else { parParent[h.id, default: []].append(noeud(c)) }
            } else {
                sansParent.append(noeud(c))
            }
        }
        if !sousPilote.isEmpty {
            p.colonnes.append(ColonnePyramide(id: "sous-pilote", titre: L("Directement sous PILOTE"), tete: nil, chantiers: sousPilote))
        }
        for d in domaines {
            p.colonnes.append(ColonnePyramide(id: d.id, titre: d.nom, tete: noeud(d), chantiers: parParent[d.id] ?? []))
        }
        if !sansParent.isEmpty {
            p.colonnes.append(ColonnePyramide(id: "sans-parent", titre: L("Sans session parente"), tete: nil, chantiers: sansParent))
        }
        let connus = Set(membres.compactMap { $0.sessionApp.isEmpty ? nil : $0.sessionApp })
        p.horsCarte = vivantes.filter { !connus.contains($0.sessionApp) }.map { a in
            let m = MembreEquipe(nom: a.titre, sessionApp: a.sessionApp, niveau: .horsCarte, domaine: "", dossiers: a.dossier)
            return NoeudPyramide(membre: m, activite: a, sousAgents: comptage(a),
                                 badges: badges(niveau: .horsCarte, activite: a, maintenant: maintenant))
        }
        return p
    }

    // MARK: Texte (ligne de commande)

    private static let formatHeure: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "HH:mm"
        return f
    }()

    /// « 14:02 » aujourd'hui, « 26 oct. 14:02 » sinon (le jour suit la langue de l'app, l'heure reste en 24 h).
    static func heure(_ d: Date, maintenant: Date = Date()) -> String {
        let h = formatHeure.string(from: d)
        return Calendar.current.isDate(d, inSameDayAs: maintenant) ? h : Loc.date(d, "dMMM") + " " + h
    }

    static func court(_ s: String, _ n: Int) -> String {
        let propre = s.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        return propre.count > n ? String(propre.prefix(n - 1)) + "…" : propre
    }

    static func ligne(_ n: NoeudPyramide, maintenant: Date = Date()) -> String {
        var morceaux = [n.libelleEtat]
        if let k = n.contexteK { morceaux.append("\(k) k") }
        if n.sousAgents > 0 { morceaux.append("\(n.sousAgents) sous-agent\(n.sousAgents > 1 ? "s" : "") (estimé)") }
        if let d = n.dernier {
            morceaux.append(court(d.texte, 60) + (d.quand.map { " (\(heure($0, maintenant: maintenant)))" } ?? ""))
        }
        var s = "\(n.membre.nom) : " + morceaux.joined(separator: " · ")
        if !n.badges.isEmpty { s += "  [" + n.badges.joined(separator: "] [") + "]" }
        return s
    }

    /// L'arbre en texte : PILOTE, ses chantiers directs et ses sessions de domaine, puis leurs chantiers.
    static func texte(_ p: Pyramide, maintenant: Date = Date()) -> String {
        guard let racine = p.pilote else {
            return p.fichierTrouve ? "EQUIPE.md ne contient pas de ligne PILOTE." : "EQUIPE.md est introuvable : \(fichier.path)"
        }
        var sortie = ["Étage 1  " + ligne(racine, maintenant: maintenant)]
        var enfants: [(String, NoeudPyramide?, [NoeudPyramide])] = [] // (étiquette, session de domaine, chantiers)
        for c in p.colonnes { enfants.append((c.titre, c.tete, c.chantiers)) }
        for (i, e) in enfants.enumerated() {
            let dernierBloc = i == enfants.count - 1
            let tige = dernierBloc ? "   " : "│  "
            if let tete = e.1 {
                sortie.append((dernierBloc ? "└─ " : "├─ ") + "Étage 2  " + ligne(tete, maintenant: maintenant))
            } else {
                sortie.append((dernierBloc ? "└─ " : "├─ ") + e.0)
            }
            for (j, c) in e.2.enumerated() {
                sortie.append(tige + (j == e.2.count - 1 ? "└─ " : "├─ ") + "Étage 3  " + ligne(c, maintenant: maintenant))
            }
        }
        if !p.horsCarte.isEmpty {
            sortie.append("")
            sortie.append("Hors carte (vivantes mais absentes d'EQUIPE.md) :")
            for n in p.horsCarte { sortie.append("  " + ligne(n, maintenant: maintenant)) }
        }
        let enLigne = p.tous.filter(\.enLigne).count
        sortie.append("")
        sortie.append("\(enLigne) session\(enLigne > 1 ? "s" : "") en ligne sur \(p.tous.count). Sous-agents : estimation (fil modifié depuis moins de \(Int(fenetreSousAgents)) s, non marqué fini).")
        return sortie.joined(separator: "\n")
    }
}
