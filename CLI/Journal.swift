// Le journal des agents, côté outil : la fin de chaque réponse d'une session (crochet « Stop » de Claude Code)
// et les livrables qu'un agent note lui-même. Rien ici ne doit jamais faire échouer une session.
import Foundation

/// Appelé par le crochet « Stop » de Claude Code, à la fin de chaque réponse d'une session.
/// Entrée standard : {"session_id", "transcript_path", "cwd", …}. Toujours silencieux, toujours code 0.
func journalDepuisCrochet(_ stock: Stockage) {
    let data = FileHandle.standardInput.readDataToEndOfFile()
    guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let session = o["session_id"] as? String else { return }
    let cwd = o["cwd"] as? String ?? ""
    guard let chemin = (o["transcript_path"] as? String).map({ URL(fileURLWithPath: $0) }) ?? Sessions.transcript(cwd: cwd, session: session)
    else { return }
    let r = Sessions.resumer(Sessions.lireFin(chemin))
    var texte = r.recap.isEmpty ? r.texte : r.recap
    if texte.isEmpty, let dernier = o["last_assistant_message"] as? String { texte = dernier }
    texte = texte.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !texte.isEmpty, !r.dernierUuid.isEmpty else { return }
    let qui = Sessions.identite(session: session)
    _ = try? stock.ajouterJournal([
        "type": "tour",
        "session": session,
        "session_app": qui?.sessionApp ?? "",
        "titre_session": qui?.titre ?? (cwd as NSString).lastPathComponent,
        "dossier": cwd,
        "demande": r.demande,
        "texte": String(texte.prefix(1500)),
        "fichiers": Array(r.fichiers.prefix(20)),
        "source_ref": "tour:\(r.dernierUuid)",
    ])
}

/// Une entrée notée par un agent (livrable, décision, note). La session est retrouvée par le processus parent.
func noterAuJournal(_ stock: Stockage, _ champs: [String: Any]) throws -> EntreeJournal? {
    var champs = champs
    if champs["type"] == nil { champs["type"] = "livrable" }
    if (champs["session"] as? String ?? "").isEmpty, let qui = Sessions.identite(pid: getppid()) {
        champs["session"] = qui.session
        champs["session_app"] = qui.sessionApp
        if champs["titre_session"] == nil { champs["titre_session"] = qui.titre }
        if champs["dossier"] == nil { champs["dossier"] = qui.dossier }
    }
    return try stock.ajouterJournal(champs)
}
