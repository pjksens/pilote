import XCTest

/// Cette copie de Pilote ne partage rien avec une autre app Pilote du même Mac : ni identifiant, ni dossier de données,
/// ni dossier de sauvegardes, ni agents launchd, ni trousseau. Les essais ne créent aucun dossier.
final class IdentiteTests: XCTestCase {
    private let racine = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    private let ancien = "Library/Application Support/Pilote"

    func testDossierDeDonneesPropre() {
        XCTAssertEqual(Identite.dossier.lastPathComponent, Identite.app)
        XCTAssertTrue(Identite.dossier.path.hasSuffix("/Library/Application Support/\(Identite.app)"))
        XCTAssertFalse(Identite.dossier.path.hasSuffix(ancien))
        XCTAssertEqual(Reglages.fichier.deletingLastPathComponent().standardizedFileURL, Identite.dossier.standardizedFileURL)
        XCTAssertNotEqual(Identite.sauvegardes, "Pilote")
    }

    func testAgentsEtTrousseauPortentLIdentifiant() {
        for nom in [Publications.etiquette, FileEnvoi.etiquette, TrousseauPublication.service] {
            XCTAssertTrue(nom.hasPrefix(Identite.app + "."), nom)
        }
    }

    func testProjetEtConstructionAnnoncentLeMemeIdentifiant() throws {
        let projet = try String(contentsOf: racine.appendingPathComponent("project.yml"), encoding: .utf8)
        XCTAssertTrue(projet.contains("PRODUCT_BUNDLE_IDENTIFIER: \(Identite.app)\n"))
        XCTAssertTrue(projet.contains("PRODUCT_BUNDLE_IDENTIFIER: \(Identite.app).cli\n"))
        let construire = try String(contentsOf: racine.appendingPathComponent("scripts/construire.sh"), encoding: .utf8)
        XCTAssertTrue(construire.contains("ID=\(Identite.app) "))
        XCTAssertFalse(construire.contains("pkill -x Pilote"), "ne fermer que l'app installée par ce script")
    }

    /// Aucun chemin du code ne vise l'ancien dossier commun « Application Support/Pilote » ni « iCloud Drive/Pilote ».
    func testAucunCheminCommunDansLeCode() throws {
        var fautifs: [String] = []
        for dossier in ["App", "Shared", "CLI"] {
            let e = FileManager.default.enumerator(at: racine.appendingPathComponent(dossier), includingPropertiesForKeys: nil)
            while let f = e?.nextObject() as? URL {
                guard f.pathExtension == "swift", let s = try? String(contentsOf: f, encoding: .utf8) else { continue }
                if s.contains(ancien + "/") || s.contains(ancien + "\"") || s.contains("appendingPathComponent(\"Pilote\"") {
                    fautifs.append(f.lastPathComponent)
                }
            }
        }
        XCTAssertEqual(fautifs, [])
    }
}
