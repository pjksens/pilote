// Passe automatique de réparation des suites, accrochée au capteur de 60 s (voir Shared/Reparation.swift).
import Foundation

enum ReparationAuto {
    /// Une sauvegarde par jour, faite avant la première correction du jour : rangements/sauvegarde-reparation-auto-AAAA-MM-JJ.sqlite.
    static func passe(_ stock: Stockage, binaire: URL) -> Int {
        guard let modif = (try? FileManager.default.attributesOfItem(atPath: binaire.path))?[.modificationDate] as? Date else { return 0 }
        let vieux = VieuxMCP.anterieurs(VieuxMCP.enRoute(), aLaDateDe: modif).count
        let dossier = binaire.deletingLastPathComponent().appendingPathComponent("rangements")
        let copie = dossier.appendingPathComponent("sauvegarde-reparation-auto-\(Dates.aujourdhui()).sqlite")
        do {
            return try stock.reparationAutomatique(vieuxServeurs: vieux) {
                if !FileManager.default.fileExists(atPath: copie.path) { try stock.copierBase(vers: copie.path) }
            }
        } catch {
            FileHandle.standardError.write(Data("[réparation auto] \(error)\n".utf8))
            return 0
        }
    }
}
