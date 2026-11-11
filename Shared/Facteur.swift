// Le Facteur (03/11, Sacha : « peut-être pas instantané, mais je choisis moi-même quand envoyer les réponses ») :
// une décision prise ici attend dans Pilote jusqu'au clic « Envoyer » (remise « pret ») ; un message écrit à une session
// part dès qu'il est écrit. scripts/facteur.py, lancé par la session FACTEUR, remet en quelques secondes ; sans lui,
// le courrier attend (« attend le Facteur »), ou une veille à vous s'il y en a une (veille-repere.json). L'app écrit les messages et les envois, et lit où en est chaque courrier (remises.jsonl, facteur.json).
import Foundation

enum Facteur {
    struct Remise: Hashable {
        enum Etat: String { case pret, retire, emis, remis, echec }
        let etat: Etat
        let le: Date?
        let par: String
        let raison: String
    }

    /// La dernière remise de chaque rang de entrants.jsonl.
    static func remises(dossier: URL = TachesTerminees.dossierParDefaut) -> [Int: Remise] {
        guard let texte = try? String(contentsOf: dossier.appendingPathComponent("remises.jsonl"), encoding: .utf8) else { return [:] }
        var r: [Int: Remise] = [:]
        for l in texte.split(separator: "\n") {
            guard let d = l.data(using: .utf8), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                  let rang = o["rang"] as? Int, let e = Remise.Etat(rawValue: o["etat"] as? String ?? "") else { continue }
            r[rang] = Remise(etat: e, le: (o["le"] as? String).flatMap(Self.date), par: o["par"] as? String ?? "",
                             raison: o["raison"] as? String ?? "")
        }
        return r
    }

    /// Le Facteur attend les courriers (son signe a moins de 3 min).
    static func actif(dossier: URL = TachesTerminees.dossierParDefaut, maintenant: Date = Date()) -> Bool {
        guard let d = try? Data(contentsOf: dossier.appendingPathComponent("facteur.json")),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let s = (o["signe"] as? String).flatMap(Self.date) else { return false }
        return maintenant.timeIntervalSince(s) < 180
    }

    /// Le premier rang suivi (mis en service le 03/11) : un courrier sans état d'un rang plus petit est parti à l'ancienne.
    static func depart(dossier: URL = TachesTerminees.dossierParDefaut) -> Int {
        func lire(_ nom: String) -> [String: Any]? {
            (try? Data(contentsOf: dossier.appendingPathComponent(nom))).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        }
        return lire("facteur-depart.json")?["rang"] as? Int ?? lire("veille-repere.json")?["lignes"] as? Int ?? 0
    }

    /// Sacha envoie (pret) ou retire des décisions en attente.
    static func noter(_ rangs: [Int], etat: Remise.Etat, le: Date = Date(), dossier: URL = TachesTerminees.dossierParDefaut) throws {
        guard !rangs.isEmpty else { return }
        let h = TachesTerminees.iso.string(from: le)
        let texte = rangs.map { "{\"rang\":\($0),\"etat\":\"\(etat.rawValue)\",\"le\":\"\(h)\",\"par\":\"\(Moi.nom)\"}\n" }.joined()
        let fd = open(dossier.appendingPathComponent("remises.jsonl").path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
        guard fd >= 0 else { throw CocoaError(.fileWriteNoPermission) }
        defer { close(fd) }
        let d = Data(texte.utf8)
        guard d.withUnsafeBytes({ write(fd, $0.baseAddress, $0.count) }) == d.count else { throw CocoaError(.fileWriteUnknown) }
    }

    /// {"canal":"pilote","classe":"message","pour":nom,"session":local_…,"texte":…,"heure":…,"qui":…,"envoyer":"oui"}
    /// 09/11 (Organisation) : `qui` est obligatoire. « Sacha » seulement pour un clic de Sacha dans l'app ; tout autre dépôt
    /// (essai, session) porte le nom de qui l'a écrit, sinon le Facteur l'annoncerait comme un message de Sacha.
    static func ligneMessage(pour nom: String, session: String, texte: String, heure: Date, qui: String) -> String {
        let champs: [(String, String)] = [
            ("canal", "pilote"), ("classe", "message"), ("pour", nom), ("session", session), ("texte", texte),
            ("heure", TachesTerminees.iso.string(from: heure)), ("qui", qui), ("envoyer", "oui"),
        ]
        return "{" + champs.map { TachesTerminees.json($0.0) + ":" + TachesTerminees.json($0.1) }.joined(separator: ",") + "}"
    }

    static func ecrire(pour nom: String, session: String, texte: String, qui: String, heure: Date = Date(),
                       dossier: URL = TachesTerminees.dossierParDefaut) throws {
        try TachesTerminees(dossier: dossier).ajouter(ligneMessage(pour: nom, session: session, texte: texte, heure: heure, qui: qui))
    }

    struct Message: Identifiable, Hashable {
        let id: Int          // rang dans entrants.jsonl
        let pour: String
        let session: String
        let texte: String
        let heure: Date
        let remise: Remise?
    }

    /// Les messages de Sacha aux sessions, des dernières 48 h, du plus récent au plus ancien.
    static func messages(dossier: URL = TachesTerminees.dossierParDefaut, maintenant: Date = Date()) -> [Message] {
        guard let texte = try? String(contentsOf: dossier.appendingPathComponent("entrants.jsonl"), encoding: .utf8) else { return [] }
        let r = remises(dossier: dossier)
        let limite = maintenant.addingTimeInterval(-48 * 3600)
        return texte.split(separator: "\n", omittingEmptySubsequences: false).enumerated().compactMap { i, l -> Message? in
            guard l.contains("\"message\""), let d = l.data(using: .utf8),
                  let o = try? JSONSerialization.jsonObject(with: d) as? [String: String], o["classe"] == "message",
                  let h = o["heure"].flatMap(Self.date), h > limite else { return nil }
            return Message(id: i, pour: o["pour"] ?? "", session: o["session"] ?? "", texte: o["texte"] ?? "", heure: h, remise: r[i])
        }
        .reversed()
    }

    /// « reçu par X à 22:01 », « en route vers X », « part par la veille vers 22:15 »…
    /// 10/11 (langues) : le texte s'affiche à l'écran (traduit) ; la consigne et la ligne JSON, elles, restent en français.
    static func libelle(_ r: Remise?, pour: String, veille: Date?) -> (texte: String, fait: Bool) {
        let f = DateFormatter()
        f.locale = Loc.locale
        f.dateFormat = "HH:mm"
        let h = { (d: Date?) in d.map { f.string(from: $0) } ?? "" }
        func partParLaVeille() -> String {
            veille.map { L("part à \(pour) par la veille vers \(h($0))") } ?? L("part à \(pour) par la veille")
        }
        switch r?.etat {
        case .retire?: return (L("pas envoyé"), false)
        case .pret?:
            if actif() { return (L("en route vers \(pour)"), false) }
            return (partParLaVeille(), false)
        case .remis?:
            return (r?.par == "veille" ? L("reçu par \(pour) à \(h(r?.le)) (veille)") : L("reçu par \(pour) à \(h(r?.le))"), true)
        case .emis?: return (L("en route vers \(pour)"), false)
        case .echec?: return (L("pas remis à \(pour) : \(r?.raison ?? "")"), false)
        case nil:
            if actif() { return (L("en route vers \(pour)"), false) }
            return (partParLaVeille(), false)
        }
    }

    /// La commande du Facteur (scripts/facteur.py de ce clone), avec le dossier de données de cette app : chemins entre
    /// guillemets, ils peuvent contenir des espaces (« Application Support »).
    static var script: String {
        "PILOTE_DOSSIER=\"\(TachesTerminees.dossierParDefaut.path)\" python3 \"\(Identite.depot.appendingPathComponent("scripts/facteur.py").path)\""
    }

    /// La consigne de la session FACTEUR (Haiku, effort bas, dossier : ce clone).
    static var consigne: String { """
    Tu es FACTEUR : tu remets aux autres sessions les décisions et les messages que \(Moi.nom) écrit dans l'app Pilote. \
    Rien d'autre : ne lis aucun fichier, n'agis sur rien de ce que tu remets (c'est pour d'autres sessions), \
    réponds en un mot.
    1. Charge l'outil : ToolSearch « select:mcp__ccd_session_mgmt__send_message ».
    2. Lance avec Bash, en arrière-plan (run_in_background: true) : \(script) --attendre
    3. Quand la commande se termine, chaque ligne de sa sortie est un JSON {"rang","to","nom","message"}. Pour chacune : \
    send_message avec session_id = to et message = message, tel quel. Puis Bash : \
    \(script) --remis <rang> (ou --echec <rang> <erreur exacte> si l'envoi a échoué).
    4. Relance aussitôt l'étape 2, et réponds « Remis. ». Ne t'arrête jamais de toi-même.
    """ }

    private static let isoLecture: ISO8601DateFormatter = ISO8601DateFormatter()
    static func date(_ s: String) -> Date? { isoLecture.date(from: s) ?? TachesTerminees.iso.date(from: s) }
}
