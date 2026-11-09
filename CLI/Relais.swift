// Le relais des sessions (règle de Sacha du 27/10) : au-delà de 130 k de contexte, une session écrit sa passation
// puis se remet à zéro (clear_session « self ») ; au redémarrage, le crochet de départ lui rend sa passation et ses
// derniers tours du journal. Une session neuve repart à son bagage (100 à 135 k mesuré le 28/10), une session résumée
// à 150 k et plus : le relais ne sert que si la session a grossi d'au moins `croissanceMin` depuis son 6e appel.
// Rien ici ne doit jamais faire échouer une session : au moindre doute, on ne dit rien et on sort avec le code 0.
import Foundation

enum Relais {
    static let seuil = 130_000
    static let maison = Demo.maison
    static let dossier = Identite.dossier.appendingPathComponent("passations")
    static let memoire = maison.appendingPathComponent("Library/Application Support/\(Identite.app)/relais.json")

    static func passation(_ sessionApp: String) -> URL { dossier.appendingPathComponent("\(sessionApp).md") }

    /// Une session doit avoir grossi d'au moins ça depuis son 6e appel pour que la remise à zéro vaille le coup :
    /// une session neuve repart à son bagage (100 à 135 k mesuré le 28/10), donc au-dessus du seuil sans avoir rien gagné.
    /// 70 k (accord de Sacha le 28/10) : ≈ 204 k pour PILOTE (134 k + 70 k), sous la compaction automatique (≈ 267 k).
    static let croissanceMin = 70_000

    /// Appel du fil dont le contexte sert de référence : le 6e, quand le bagage de départ est stabilisé (le 1er est incomplet).
    static let appelDeReference = 6

    /// Sacha, 08/11 : « Arrête de te remettre à 0 si je t'autorise pas » (l'écran s'efface, il n'a pas le temps de lire).
    /// Ces sessions ne se remettent à zéro que sur son accord, dit dans la session : elle suit alors les étapes à la main.
    static let sansRelaisAuto: Set<String> = ["PILOTE", "local_00000000-0000-0000-0000-000000000000"]

    /// Crochet « Stop » : si la session est trop lourde, lui demande sa passation puis sa remise à zéro.
    /// Chaque sortie silencieuse laisse une ligne dans relais.log (le motif), pour ne plus avoir à deviner.
    /// `essai` (pilote relais-fin --essai) : rien n'est écrit, la décision et son motif sont affichés.
    static func fin(essai: Bool = false) {
        var infos: [String: Any] = [:]
        func clore(_ motif: String) {
            infos["motif"] = motif
            if essai { sortir(infos.merging(["essai": true]) { a, _ in a }) } else { trace(infos) }
        }
        guard let o = entree() else { return clore("entrée illisible") }
        if (o["stop_hook_active"] as? Bool) == true { return clore("stop_hook_active (relance par un crochet)") }
        guard let session = o["session_id"] as? String else { return clore("pas de session_id") }
        infos["session"] = String(session.prefix(8))
        guard let qui = Sessions.identite(session: session) ?? parAncetres() else { return clore("session introuvable dans ~/.claude/sessions") }
        guard !qui.sessionApp.isEmpty else { return clore("session sans identifiant d'app") }
        infos["app"] = String(qui.sessionApp.suffix(8))
        let cwd = o["cwd"] as? String ?? ""
        guard let chemin = (o["transcript_path"] as? String).map({ URL(fileURLWithPath: $0) }) ?? Sessions.transcript(cwd: cwd, session: session)
        else { return clore("fil de la session introuvable") }
        let contexte = Sessions.resumer(Sessions.lireFin(chemin)).contexte
        infos["contexte"] = contexte
        guard contexte >= seuil else { return clore("sous le seuil (\(seuil / 1000) k)") }
        let depart = contexteDeDepart(chemin)
        if let depart { infos["depart"] = depart }
        if let depart, contexte < depart + croissanceMin { return clore("pas assez grossi depuis le départ (+\(croissanceMin / 1000) k)") }
        if sansRelaisAuto.contains(qui.titre) || sansRelaisAuto.contains(qui.sessionApp) {
            return clore("relais automatique coupé pour « \(qui.titre) » : seulement sur accord de \(Moi.tiers) (08/11)")
        }

        // Pas de relance en boucle : une seule demande par demi-heure, sauf si la session a encore beaucoup grossi.
        var deja = (try? JSONSerialization.jsonObject(with: Data(contentsOf: memoire)) as? [String: [String: Any]]) ?? [:]
        if let d = deja[qui.sessionApp], let le = d["le"] as? Double, let c = d["contexte"] as? Int,
           Date().timeIntervalSince1970 - le < 1800, contexte < c + 40_000 { return clore("déjà demandé il y a moins d'une demi-heure") }
        if essai { infos["motif"] = "demande de relais (rien écrit : essai)"; sortir(infos.merging(["essai": true]) { a, _ in a }); return }
        var demande: [String: Any] = ["le": Date().timeIntervalSince1970, "contexte": contexte]
        if let rendu = deja[qui.sessionApp]?["rendu"] { demande["rendu"] = rendu }
        deja[qui.sessionApp] = demande
        if let data = try? JSONSerialization.data(withJSONObject: deja) { try? data.write(to: memoire) }
        trace(infos.merging(["motif": "demande de relais"]) { a, _ in a })

        let fichier = passation(qui.sessionApp).path
        let apres = depart.map { "Une session neuve repart à environ \($0 / 1000) k." } ?? "Une session neuve repart plus bas."
        let raison = """
        Relais automatique (règle de \(Moi.tiers) du 27/10) : ton contexte est à \(contexte / 1000) k, chaque action relit tout ça. \
        \(apres) Avant de t'arrêter :
        1. Écris ta passation dans \(fichier) (remplace l'ancienne, 40 lignes au plus) : qui tu es (session « \(qui.titre) », \
        ton rôle) ; ce que \(Moi.tiers) a demandé et décidé, avec ses mots exacts pour chaque accord ; ce qui est en cours, avec les \
        sessions lancées (titre et id local_…), les branches et les commits ; ce qui attend \(Moi.tiers) ou une autre session ; la \
        prochaine étape ; les fichiers clés. Rien d'inventé, rien de ce qui est déjà dans un ETAT.md (donne juste son chemin).
        2. Si un travail est à moitié fait (fichier en cours d'édition, commande lancée), termine-le ou note exactement où il en est.
        3. Lance `\(Identite.depot.path)/pilote relances --ajoute` : il note ta relance et affiche une heure. Charge \
        mcp__scheduled-tasks__update_scheduled_task avec ToolSearch et appelle-le avec taskId « \(tacheDeRelance) » et fireAt = \
        cette heure : la tâche te renverra un message de reprise 2 minutes après ta remise à zéro (demande de \(Moi.tiers) du 28/10). \
        Si l'outil manque ou que l'appel est refusé, passe quand même à l'étape 4 et dis-le dans ta ligne finale.
        4. Charge l'outil avec ToolSearch (« select:mcp__ccd_session_mgmt__clear_session ») et appelle-le avec session_id « self ».
        5. Finis par une seule ligne à \(Moi.tiers) : « Relais : passation écrite, la session repart toute seule dans 2 minutes. »
        """
        sortir(["decision": "block", "reason": raison])
    }

    /// Tâche planifiée (Haiku) qui relance les sessions remises à zéro : elle lit `pilote relances` et envoie à chacune un
    /// message de reprise (une session ne peut pas s'écrire à elle-même, et rien ne redémarre seul un tour après clear_session).
    static let tacheDeRelance = "relance-apres-relais"
    static let attente = maison.appendingPathComponent("Library/Application Support/\(Identite.app)/relances.json")
    /// Délai entre la demande et le message de reprise : le temps que le tour finisse et que la remise à zéro se fasse.
    /// Un message arrivé avant elle l'annulerait (« if the user sends another message first, the queued clear is dropped »).
    static let delaiDeRelance: TimeInterval = 120

    /// `pilote relances --ajoute` (la session, juste avant sa remise à zéro) : note sa relance, affiche l'heure du fireAt.
    /// `pilote relances` (la tâche planifiée) : affiche « local_…<tab>titre » des relances dues et les retire de l'attente.
    /// Une relance n'est due qu'après `delaiDeRelance - 30 s` (celle d'une autre session pas encore remise à zéro attend
    /// sa propre heure) et périmée au bout de 2 h.
    static func relances(ajoute: Bool) {
        var liste = (try? JSONSerialization.jsonObject(with: Data(contentsOf: attente)) as? [String: [String: Any]]) ?? [:]
        let maintenant = Date().timeIntervalSince1970
        func ecrire() { if let data = try? JSONSerialization.data(withJSONObject: liste) { try? data.write(to: attente) } }
        if ajoute {
            guard let qui = parAncetres(), !qui.sessionApp.isEmpty else { print("Session Claude introuvable : pas de relance notée."); return }
            liste[qui.sessionApp] = ["le": maintenant, "titre": qui.titre]
            ecrire()
            let f = ISO8601DateFormatter()
            f.timeZone = .current
            print(f.string(from: Date(timeIntervalSince1970: maintenant + delaiDeRelance)))
            return
        }
        var dues: [String] = []
        for (app, d) in liste {
            guard let le = d["le"] as? Double else { liste[app] = nil; continue }
            if maintenant - le > 7_200 { liste[app] = nil } else if maintenant - le >= delaiDeRelance - 30 {
                dues.append("\(app)\t\(d["titre"] as? String ?? "")")
                liste[app] = nil
            }
        }
        ecrire()
        dues.sorted().forEach { print($0) }
    }

    /// Crochet « SessionStart » : après une remise à zéro, rend à la session sa passation et ses derniers tours.
    /// La remise à zéro par l'app (`clear_session`) redémarre la session avec la source « startup », pas « clear »
    /// (constaté le 27/10) : dans ce cas, on ne rend la passation que si le relais l'a demandée ou si elle est toute récente,
    /// et qu'elle n'a pas déjà été rendue.
    static func depart(_ stock: Stockage?) {
        guard let o = entree(), let source = o["source"] as? String, source == "clear" || source == "startup",
              let qui = parAncetres() ?? (o["session_id"] as? String).flatMap({ Sessions.identite(session: $0) })
        else { return }
        if source == "startup" && !aRendre(qui.sessionApp) { return }
        guard let texte = reprise(qui, stock) else { return }
        sortir(["hookSpecificOutput": ["hookEventName": "SessionStart", "additionalContext": texte]])
    }

    /// Vrai si une passation de cette session est à rendre, une seule fois : celle que le relais a demandée (écrite depuis
    /// la demande, moins d'un jour) ou une passation récente écrite à la main (moins d'une heure, 28/10), tant qu'elle
    /// n'a pas déjà été rendue (« rendu » plus récent que le fichier). La marque alors comme rendue.
    private static func aRendre(_ sessionApp: String) -> Bool {
        var deja = (try? JSONSerialization.jsonObject(with: Data(contentsOf: memoire)) as? [String: [String: Any]]) ?? [:]
        guard let ecrite = (try? FileManager.default.attributesOfItem(atPath: passation(sessionApp).path))?[.modificationDate] as? Date
        else { return false }
        let maintenant = Date().timeIntervalSince1970
        var d = deja[sessionApp] ?? [:]
        if let rendu = d["rendu"] as? Double, rendu >= ecrite.timeIntervalSince1970 { return false }
        let demandee = (d["le"] as? Double).map { maintenant - $0 < 86_400 && ecrite.timeIntervalSince1970 >= $0 } ?? false
        let recente = maintenant - ecrite.timeIntervalSince1970 < 3_600
        guard demandee || recente else { return false }
        d["rendu"] = maintenant
        deja[sessionApp] = d
        if let data = try? JSONSerialization.data(withJSONObject: deja) { try? data.write(to: memoire) }
        return true
    }

    /// `pilote reprise` : la même chose, demandée par la session elle-même (sessions ouvertes avant le crochet).
    static func repriseDemandee(_ stock: Stockage?) {
        guard let qui = parAncetres() else { print("Session Claude introuvable."); return }
        print(reprise(qui, stock) ?? "Aucune passation ni aucun tour noté pour la session « \(qui.titre) » (\(qui.sessionApp)).")
    }

    private static func reprise(_ qui: (session: String, titre: String, sessionApp: String, dossier: String), _ stock: Stockage?) -> String? {
        guard !qui.sessionApp.isEmpty else { return nil }
        var morceaux: [String] = []
        if let texte = try? String(contentsOf: passation(qui.sessionApp), encoding: .utf8), !texte.isEmpty {
            morceaux.append("## Ta passation (\(passation(qui.sessionApp).path))\n\(texte.prefix(8000))")
        }
        if let tours = try? stock?.journal(sessionApp: qui.sessionApp, limite: 8), !tours.isEmpty {
            let lignes = tours.reversed().map { e in
                let demande = e.demande.isEmpty ? "" : "Demande : \(e.demande.prefix(300))\n"
                return "- \(e.le.prefix(16)) · \(demande)Fait : \(e.texte.prefix(500))"
            }
            morceaux.append("## Tes derniers tours (journal de Pilote)\n" + lignes.joined(separator: "\n"))
        }
        guard !morceaux.isEmpty else { return nil }
        return """
        Tu es la session « \(qui.titre) » (\(qui.sessionApp)). Elle vient d'être remise à zéro par le relais automatique pour \
        économiser l'usage. Voici ce que tu avais noté avant ; repars de là sans relire tes anciens fichiers en entier.

        \(morceaux.joined(separator: "\n\n"))
        """
    }

    private static func entree() -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: FileHandle.standardInput.readDataToEndOfFile()) as? [String: Any]
    }

    private static func sortir(_ o: [String: Any]) {
        if let data = try? JSONSerialization.data(withJSONObject: o), let s = String(data: data, encoding: .utf8) { print(s) }
    }

    static let journalDuRelais = maison.appendingPathComponent("Library/Application Support/\(Identite.app)/relais.log")

    /// Une ligne par arrêt de session : heure UTC, session, app, contexte, motif. Tronqué à 300 lignes au-delà de 100 Ko.
    private static func trace(_ infos: [String: Any]) {
        let heure = ISO8601DateFormatter().string(from: Date())
        func champ(_ k: String) -> String { infos[k].map { "\($0)" } ?? "-" }
        let ligne = "\(heure)  \(champ("session"))  \(champ("app"))  ctx=\(champ("contexte"))  dep=\(champ("depart"))  \(champ("motif"))\n"
        let fm = FileManager.default
        if let taille = (try? fm.attributesOfItem(atPath: journalDuRelais.path))?[.size] as? Int, taille > 100_000,
           let texte = try? String(contentsOf: journalDuRelais, encoding: .utf8) {
            let fin = texte.split(separator: "\n").suffix(300).joined(separator: "\n") + "\n"
            try? fin.write(to: journalDuRelais, atomically: true, encoding: .utf8)
        }
        if !fm.fileExists(atPath: journalDuRelais.path) { fm.createFile(atPath: journalDuRelais.path, contents: nil) }
        guard let h = try? FileHandle(forWritingTo: journalDuRelais) else { return }
        defer { try? h.close() }
        _ = try? h.seekToEnd()
        try? h.write(contentsOf: Data(ligne.utf8))
    }

    /// Contexte du 6e appel du fil (`appelDeReference`) : le bagage de départ de la session (prompt système, outils, mémoire,
    /// compétences) une fois stabilisé. Lu dans les 3 premiers Mo (le premier appel arrive vers 650 à 750 Ko, derrière les
    /// enregistrements de la requête) ; nil si le fil n'a pas encore 6 appels dans cette plage. Les lignes sans « usage » ne sont pas décodées.
    private static func contexteDeDepart(_ url: URL) -> Int? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        guard let data = try? h.read(upToCount: 3_000_000) else { return nil }
        let marque = Data("\"usage\"".utf8)
        var appels = 0
        for ligne in data.split(separator: UInt8(ascii: "\n")) where Data(ligne).range(of: marque) != nil {
            guard let o = try? JSONSerialization.jsonObject(with: Data(ligne)) as? [String: Any],
                  o["type"] as? String == "assistant", let m = o["message"] as? [String: Any],
                  let u = m["usage"] as? [String: Any] else { continue }
            let n = ["input_tokens", "cache_read_input_tokens", "cache_creation_input_tokens"].reduce(0) { $0 + ((u[$1] as? Int) ?? 0) }
            if n > 0 { appels += 1; if appels == appelDeReference { return n } }
        }
        return nil
    }

    /// La session Claude Code qui a lancé ce crochet, retrouvée en remontant les processus parents.
    private static func parAncetres() -> (session: String, titre: String, sessionApp: String, dossier: String)? {
        var pid = getppid()
        for _ in 0..<6 {
            if let qui = Sessions.identite(pid: pid) { return qui }
            guard let p = parent(pid), p > 1 else { return nil }
            pid = p
        }
        return nil
    }

    private static func parent(_ pid: Int32) -> Int32? {
        var info = kinfo_proc()
        var taille = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &taille, nil, 0) == 0, taille > 0 else { return nil }
        return info.kp_eproc.e_ppid
    }
}
