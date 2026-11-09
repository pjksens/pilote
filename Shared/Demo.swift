// Mode démo (PILOTE_DEMO=1) : l'app et l'outil voient un dossier personnel fictif (base, sessions, fichiers) au lieu du
// vrai ; ils ne lisent ni Rappels, ni Calendrier, ni Mail, ni Spotlight, ni KRYVA, et rien ne part (mail, message à une
// session, notification). Rendez-vous, rappels et sessions affichés : DemoDonnees. Lancer : `./scripts/demo.sh`.
import Foundation

enum Demo {
    static let actif = ProcessInfo.processInfo.environment["PILOTE_DEMO"] == "1"

    /// Le dossier personnel vu par Pilote. En démo : PILOTE_DEMO_DOSSIER, sinon <tmp>/pilote-demo ; jamais le vrai.
    static let maison: URL = {
        let vrai = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
        guard actif else { return vrai }
        let env = ProcessInfo.processInfo.environment["PILOTE_DEMO_DOSSIER"].flatMap { $0.isEmpty ? nil : $0 }
        let d = (env.map { URL(fileURLWithPath: $0) }
                 ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("pilote-demo")).standardizedFileURL
        precondition(!(vrai.path + "/").hasPrefix(d.path + "/"),
                     "Mode démo : le dossier fictif ne peut pas être le vrai dossier personnel (ni le contenir)")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        DemoDonnees.ecrireFichiers(dans: d)
        return d
    }()

    struct Refus: LocalizedError, CustomStringConvertible {
        var description = "Mode démo : rien ne part et rien n'est lu hors du dossier fictif."
        var errorDescription: String? { description }
    }
}
