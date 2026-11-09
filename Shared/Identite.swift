// Ce qui distingue cette app de toute autre app nommée Pilote sur le même Mac : son identifiant (celui de project.yml,
// des agents launchd et du trousseau), son dossier de données et son dossier de sauvegardes dans iCloud Drive.
// Deux copies de Pilote installées côte à côte ne lisent ni n'écrivent jamais la même base. Essai : IdentiteTests.
import Foundation

enum Identite {
    /// L'identifiant de l'app (PRODUCT_BUNDLE_IDENTIFIER dans project.yml), préfixe des agents launchd et du trousseau.
    static let app = "io.github.pjksens.pilote"

    /// ~/Library/Application Support/io.github.pjksens.pilote : la base, les réglages, les files du Facteur.
    static var dossier: URL {
        Demo.maison.appendingPathComponent("Library/Application Support/\(app)", isDirectory: true)
    }

    /// Le clone de ce dépôt, tel qu'il était à la construction (#filePath) : l'outil `pilote` et scripts/facteur.py y sont.
    /// Jamais un chemin écrit en dur : un autre Pilote cloné ailleurs sur le même Mac n'est jamais visé.
    static let depot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    /// Le dossier des sauvegardes du jour dans iCloud Drive (les 14 dernières).
    static let sauvegardes = "Pilote open source"
}
