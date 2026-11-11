// Ce que font les sessions Claude Code : lu directement dans leurs fichiers (aucune coopération des agents requise).
// - ~/.claude/sessions/<pid>.json : les sessions vivantes, leur état (au travail, attend, en pause), leur nom.
// - ~/.claude/projects/<dossier>/<session>.jsonl : le fil de chaque session, dont on ne lit que la fin.
import Foundation

struct ActiviteSession: Identifiable, Hashable, Codable {
    var id: String              // identifiant Claude Code de la session
    var sessionApp: String = "" // local_… (app Claude), vide pour une session de terminal
    var titre: String = ""
    var dossier: String = ""
    var etat: String = ""       // busy | waiting | idle
    var depuis: Date?           // dernier changement d'état
    var demande: String = ""    // dernière demande de Sacha (ou du message qui a lancé le tour)
    var action: String = ""     // dernière action (outil) de l'agent
    var actionLe: Date?
    var etape: String = ""      // étape en cours de sa liste de tâches
    var recap: String = ""      // résumé de son dernier tour terminé
    var fichiers: [String] = [] // fichiers écrits depuis la dernière demande
    var contexte: Int = 0       // jetons relus à chaque action (dernier appel), le vrai coût d'une longue session
    var plan: [EtapePlan] = []  // sa liste de tâches, telle qu'il la tient (update_plan)
    var dernierTexte = ""       // ce qu'il a écrit en dernier (sa réponse, sa question)
    var question = ""           // la question de son dernier tour (wrap_up « ask »), vide s'il n'en pose pas
    var choix: [String] = []    // ses réponses proposées (les boutons du wrap_up)
    var questionRef = ""        // « session:<id>:<tour> » : la question à laquelle Sacha répond, une seule fois
    var questionGenre: String?  // « fin » (wrap_up), « dialogue » (AskUserQuestion), « texte » (phrase en « ? » de son texte)

    var libelleEtat: String {
        switch etat {
        case "busy": return L("Au travail")
        case "waiting": return L("Attend votre réponse")
        default: return L("En pause")
        }
    }
}

/// Une étape de la liste de tâches d'une session (update_plan) : pending | in_progress | completed.
struct EtapePlan: Codable, Hashable {
    var contenu: String
    var statut: String
    var faite: Bool { statut == "completed" }
    var enCours: Bool { statut == "in_progress" }
}

struct ResumeTour {
    var demande = ""
    var action = ""
    var actionLe: Date?
    var etape = ""
    var recap = ""
    var texte = ""              // dernier texte de l'agent après la demande
    var fichiers: [String] = []
    var dernierUuid = ""
    var contexte = 0
    var plan: [EtapePlan] = []
    var question = ""
    var choix: [String] = []
    var questionUuid = ""
    var questionGenre = ""      // « fin », « dialogue » ou « texte »
    var dialogueId = ""         // l'AskUserQuestion encore sans réponse
    var texteUuid = ""
}

enum Sessions {
    static let maison = Demo.maison

    /// Sessions vivantes (processus en cours), avec ce qu'elles font.
    static func vivantes() -> [ActiviteSession] {
        if Demo.actif { return DemoDonnees.sessions() }
        let dossier = maison.appendingPathComponent(".claude/sessions")
        guard let fichiers = try? FileManager.default.contentsOfDirectory(at: dossier, includingPropertiesForKeys: nil) else { return [] }
        var liste: [ActiviteSession] = []
        for f in fichiers where f.pathExtension == "json" {
            guard let data = try? Data(contentsOf: f),
                  let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let pid = o["pid"] as? Int, kill(pid_t(pid), 0) == 0,
                  let id = o["sessionId"] as? String else { continue }
            let cwd = o["cwd"] as? String ?? ""
            var a = ActiviteSession(id: id, sessionApp: o["hostSessionId"] as? String ?? "",
                                    titre: (o["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? (cwd as NSString).lastPathComponent,
                                    dossier: cwd, etat: o["status"] as? String ?? "idle")
            if let ms = o["statusUpdatedAt"] as? Double { a.depuis = Date(timeIntervalSince1970: ms / 1000) }
            if let chemin = transcript(cwd: cwd, session: id) {
                let r = resumeEnCache(chemin)
                a.demande = r.demande; a.action = r.action; a.actionLe = r.actionLe
                a.etape = r.etape; a.recap = r.recap; a.fichiers = r.fichiers; a.contexte = r.contexte
                a.plan = r.plan; a.dernierTexte = r.texte
                a.question = r.question; a.choix = r.choix
                a.questionGenre = r.question.isEmpty ? nil : r.questionGenre
                if !r.question.isEmpty { a.questionRef = "session:\(id):\(r.questionUuid)" }
            }
            liste.append(a)
        }
        let rang = ["busy": 0, "waiting": 1, "idle": 2]
        return liste.sorted { (rang[$0.etat] ?? 3, $1.depuis ?? .distantPast) < (rang[$1.etat] ?? 3, $0.depuis ?? .distantPast) }
    }

    /// Nom, identifiant app et dossier d'une session vivante, sans lire son fil (rapide, pour le journal).
    /// `pid` : le processus Claude Code lui-même (cas du connecteur MCP, lancé par la session).
    static func identite(session: String? = nil, pid: Int32? = nil) -> (session: String, titre: String, sessionApp: String, dossier: String)? {
        let dossier = maison.appendingPathComponent(".claude/sessions")
        var fichiers = (try? FileManager.default.contentsOfDirectory(at: dossier, includingPropertiesForKeys: nil)) ?? []
        if let pid { fichiers = [dossier.appendingPathComponent("\(pid).json")] }
        for f in fichiers where f.pathExtension == "json" {
            guard let data = try? Data(contentsOf: f),
                  let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = o["sessionId"] as? String, session == nil || id == session else { continue }
            let cwd = o["cwd"] as? String ?? ""
            let nom = (o["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? (cwd as NSString).lastPathComponent
            return (id, nom, o["hostSessionId"] as? String ?? "", cwd)
        }
        return nil
    }

    private static var cache: [String: (UInt64, ResumeTour)] = [:]
    private static let verrou = NSLock()

    /// Résumé d'un fil, relu seulement si le fichier a grandi depuis la dernière fois.
    static func resumeEnCache(_ url: URL) -> ResumeTour {
        let taille = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? 0
        verrou.lock()
        if let (t, r) = cache[url.path], t == taille { verrou.unlock(); return r }
        verrou.unlock()
        let r = resumer(lireFin(url))
        verrou.lock(); cache[url.path] = (taille, r); verrou.unlock()
        return r
    }

    /// Le fil d'une session : ~/.claude/projects/<dossier, chaque signe remplacé par « - »>/<session>.jsonl.
    static func transcript(cwd: String, session: String) -> URL? {
        let cle = String(cwd.map { $0.isLetter || $0.isNumber ? $0 : "-" })
        let projets = maison.appendingPathComponent(".claude/projects")
        let direct = projets.appendingPathComponent(cle).appendingPathComponent("\(session).jsonl")
        if FileManager.default.fileExists(atPath: direct.path) { return direct }
        let dossiers = (try? FileManager.default.contentsOfDirectory(at: projets, includingPropertiesForKeys: nil)) ?? []
        return dossiers.map { $0.appendingPathComponent("\(session).jsonl") }.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Les dernières lignes du fil (on ne lit que la fin : certains fils dépassent 100 Mo).
    static func lireFin(_ url: URL, octets: Int = 600_000) -> [[String: Any]] {
        guard let h = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? h.close() }
        let taille = (try? h.seekToEnd()) ?? 0
        let debut = taille > UInt64(octets) ? taille - UInt64(octets) : 0
        try? h.seek(toOffset: debut)
        guard let data = try? h.readToEnd(), let texte = String(data: data, encoding: .utf8) ?? String(data: data.dropFirst(1), encoding: .utf8) else { return [] }
        var lignes = texte.split(separator: "\n", omittingEmptySubsequences: true)
        if debut > 0, !lignes.isEmpty { lignes.removeFirst() } // première ligne coupée
        return lignes.compactMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
    }

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// Résumé du dernier tour : la demande, puis ce que l'agent a fait depuis.
    static func resumer(_ lignes: [[String: Any]]) -> ResumeTour {
        var r = ResumeTour()
        for o in lignes {
            let type = o["type"] as? String ?? ""
            guard type == "user" || type == "assistant", let m = o["message"] as? [String: Any] else { continue }
            let le = (o["timestamp"] as? String).flatMap { iso.date(from: $0) }
            if type == "user" {
                if (o["isMeta"] as? Bool) == true { continue }
                // Réponse donnée dans l'app Claude au dialogue AskUserQuestion : la question n'attend plus.
                if !r.dialogueId.isEmpty, let blocs = m["content"] as? [[String: Any]],
                   blocs.contains(where: { ($0["tool_use_id"] as? String) == r.dialogueId }) {
                    r.question = ""; r.choix = []; r.questionUuid = ""; r.questionGenre = ""; r.dialogueId = ""
                }
                if let t = texteDemande(m["content"]) {
                    r.demande = t; r.recap = ""; r.texte = ""; r.fichiers = []; r.etape = ""
                    r.question = ""; r.choix = []; r.questionUuid = ""; r.questionGenre = ""; r.dialogueId = ""
                }
                continue
            }
            if let u = o["uuid"] as? String { r.dernierUuid = u }
            if let usage = m["usage"] as? [String: Any] {
                let n = ["input_tokens", "cache_read_input_tokens", "cache_creation_input_tokens"].reduce(0) { $0 + ((usage[$1] as? Int) ?? 0) }
                if n > 0 { r.contexte = n }
            }
            guard let blocs = m["content"] as? [[String: Any]] else { continue }
            for b in blocs {
                switch b["type"] as? String {
                case "text":
                    let t = (b["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    if !t.isEmpty { r.texte = t; r.texteUuid = r.dernierUuid }
                case "tool_use":
                    let nom = b["name"] as? String ?? ""
                    let entree = b["input"] as? [String: Any] ?? [:]
                    if nom.hasSuffix("update_plan") {
                        appliquer(entree, a: &r.plan)
                        if let e = r.plan.first(where: \.enCours) { r.etape = e.contenu }
                        continue
                    }
                    if nom.hasSuffix("wrap_up") {
                        r.recap = (entree["recap"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        r.question = (entree["ask"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        r.choix = r.question.isEmpty ? [] : boutons(entree["actions"])
                        r.questionUuid = r.dernierUuid
                        r.questionGenre = r.question.isEmpty ? "" : "fin"
                        for i in r.plan.indices { r.plan[i].statut = "completed" }
                        r.etape = ""
                        continue
                    }
                    // Le dialogue de l'app Claude (03/11, Sacha : « poser la question en AskUserQuestion et dans Pilote ») :
                    // la 1re question et ses choix ; elle attend jusqu'à sa réponse, ici ou là-bas.
                    if nom == "AskUserQuestion", let q = (entree["questions"] as? [[String: Any]])?.first,
                       let texte = (q["question"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !texte.isEmpty {
                        let n = (entree["questions"] as? [[String: Any]])?.count ?? 1
                        // Deux phrases entières (pas un pluriel du catalogue) : ce code se teste sans catalogue embarqué.
                        let suite = n > 2 ? L("(+ \(n - 1) autres dans la session)") : L("(+ 1 autre dans la session)")
                        r.question = texte + (n > 1 ? " " + suite : "")
                        r.choix = (q["options"] as? [[String: Any]] ?? []).compactMap {
                            ($0["label"] as? String).map { $0.trimmingCharacters(in: .whitespaces) }.flatMap { $0.isEmpty ? nil : $0 }
                        }
                        r.questionUuid = r.dernierUuid; r.questionGenre = "dialogue"; r.dialogueId = b["id"] as? String ?? ""
                    }
                    if ["Write", "Edit", "NotebookEdit"].contains(nom), let f = entree["file_path"] as? String, !r.fichiers.contains(f) {
                        r.fichiers.append(f)
                    }
                    r.action = decrire(nom, entree)
                    r.actionLe = le
                default: break
                }
            }
        }
        // Une question laissée dans le texte, sans bouton (03/11, Réseaux : « tu veux que le prompteur dise RELOOK ? ») :
        // elle remonte quand même, pour que Sacha puisse toujours répondre depuis Pilote.
        if r.question.isEmpty, let q = questionDansTexte(r.texte) {
            r.question = q
            r.choix = q.lowercased().contains(" ou ") ? [] : ["Oui", "Non"]
            r.questionUuid = r.texteUuid; r.questionGenre = "texte"
        }
        return r
    }

    /// La dernière ligne du texte qui finit par « ? » : hors blocs de code, titres, citations et tableaux ;
    /// une citation (« … ? ») finit par « » » et ne compte pas. nil s'il n'y en a pas.
    static func questionDansTexte(_ texte: String) -> String? {
        var dansCode = false
        var trouvee: String?
        for brut in texte.split(whereSeparator: \.isNewline) {
            var l = brut.trimmingCharacters(in: .whitespaces)
            if l.hasPrefix("```") { dansCode.toggle(); continue }
            if dansCode || l.hasPrefix("#") || l.hasPrefix(">") || l.hasPrefix("|") { continue }
            l = l.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "`", with: "")
                .replacingOccurrences(of: #"^([-*•]|\d+[.)])\s+"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            guard l.hasSuffix("?"), l.count > 3 else { continue }
            trouvee = String(l.prefix(300))
        }
        return trouvee
    }

    /// Un choix tel que l'écran l'affiche. La valeur du choix reste en français (c'est la réponse écrite à la session, qui
    /// travaille en français) ; seuls les choix que l'app fabrique elle-même (Oui / Non, boutons d'un wrap_up) se traduisent.
    /// Un libellé écrit par la session reste tel quel.
    static func libelleChoix(_ choix: String) -> String {
        switch choix {
        case "Oui": return L("Oui")
        case "Non": return L("Non")
        case "Ouvrir la PR": return L("Ouvrir la PR")
        case "Fusionner": return L("Fusionner")
        case "Réparer la CI": return L("Réparer la CI")
        case "Traiter les commentaires": return L("Traiter les commentaires")
        case "Résoudre les conflits": return L("Résoudre les conflits")
        case "Vérifier": return L("Vérifier")
        case "Archiver": return L("Archiver")
        case "Nouvelle session": return L("Nouvelle session")
        default: return choix
        }
    }

    /// Les boutons d'un wrap_up : le libellé écrit, sinon le nom de l'action de l'app, en français (valeur envoyée à la
    /// session, voir `libelleChoix` pour l'affichage).
    static func boutons(_ v: Any?) -> [String] {
        let noms = ["commit": "Commit", "create_pr": "Ouvrir la PR", "merge": "Fusionner", "fix_ci": "Réparer la CI",
                    "address_comments": "Traiter les commentaires", "resolve_conflicts": "Résoudre les conflits",
                    "verify": "Vérifier", "archive": "Archiver", "new_session": "Nouvelle session"]
        return (v as? [[String: Any]] ?? []).compactMap { b in
            let l = (b["label"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if let a = b["action"] as? String, !a.isEmpty { return noms[a] ?? a }
            return l.isEmpty ? nil : l
        }
    }

    /// Rejoue un appel à update_plan : « items » remplace la liste ; « advance » finit l'étape en cours et commence
    /// la suivante ; « done » et « start » comptent à partir de 1.
    static func appliquer(_ e: [String: Any], a plan: inout [EtapePlan]) {
        if let items = e["items"] as? [[String: Any]] {
            plan = items.map { EtapePlan(contenu: $0["content"] as? String ?? "", statut: $0["status"] as? String ?? "pending") }
            return
        }
        for n in (e["done"] as? [Int]) ?? [] where n >= 1 && n <= plan.count { plan[n - 1].statut = "completed" }
        if let s = e["start"] as? Int, s >= 1, s <= plan.count {
            for i in plan.indices where plan[i].enCours { plan[i].statut = "pending" }
            plan[s - 1].statut = "in_progress"
        }
        if (e["advance"] as? Bool) == true {
            if let i = plan.firstIndex(where: \.enCours) { plan[i].statut = "completed" }
            if let j = plan.firstIndex(where: { $0.statut == "pending" }) { plan[j].statut = "in_progress" }
        }
    }

    /// Une vraie demande (pas un résultat d'outil, pas un rappel système).
    private static func texteDemande(_ contenu: Any?) -> String? {
        var t = ""
        if let s = contenu as? String { t = s }
        else if let blocs = contenu as? [[String: Any]] {
            if blocs.contains(where: { ($0["type"] as? String) == "tool_result" }) { return nil }
            t = blocs.compactMap { ($0["type"] as? String) == "text" ? $0["text"] as? String : nil }.joined(separator: "\n")
        }
        t = t.trimmingCharacters(in: .whitespacesAndNewlines)
        // Message d'une autre session : on garde l'expéditeur et le texte.
        if t.hasPrefix("<cross-session-message") {
            let nom = t.range(of: #"from-name="([^"]*)""#, options: .regularExpression)
                .map { String(t[$0]).replacingOccurrences(of: "from-name=", with: "").replacingOccurrences(of: "\"", with: "") } ?? L("une autre session")
            let corps = t.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return String(L("Message de \(nom) : \(corps)").prefix(400))
        }
        guard !t.isEmpty, !t.hasPrefix("<"), !t.hasPrefix("Caveat:"), !t.hasPrefix("[Request interrupted") else { return nil }
        return String(t.prefix(400))
    }

    /// L'action d'un outil, en clair.
    static func decrire(_ nom: String, _ e: [String: Any]) -> String {
        func base(_ k: String) -> String { ((e[k] as? String ?? "") as NSString).lastPathComponent }
        if let d = e["description"] as? String, !d.isEmpty, nom != "Agent" { return d }
        switch nom {
        case "Read": return L("Lit \(base("file_path"))")
        case "Write": return L("Écrit \(base("file_path"))")
        case "Edit": return L("Modifie \(base("file_path"))")
        case "Grep", "Glob": return L("Cherche « \(e["pattern"] as? String ?? "") »")
        case "WebSearch": return L("Cherche sur le web : \(e["query"] as? String ?? "")")
        case "WebFetch": return L("Lit une page web")
        case "Agent": return L("Confie à un agent : \(e["description"] as? String ?? "")")
        case "Skill": return L("Utilise la compétence \(e["skill"] as? String ?? "")")
        default:
            if nom.hasPrefix("mcp__") {
                let outil = nom.components(separatedBy: "__").last ?? nom
                return L("Outil \(outil.replacingOccurrences(of: "_", with: " "))")
            }
            return nom
        }
    }
}
