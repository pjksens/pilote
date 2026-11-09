import XCTest

/// Au démarrage, plusieurs connexions ouvrent la base en même temps et chacune la migre. Deux connexions pouvaient lire
/// le schéma avant que l'une n'ajoute une colonne : la seconde échouait sur « duplicate column name: message_id »
/// et l'app affichait « La base de Pilote ne s'ouvre pas ».
final class MigrationConcurrenteTests: XCTestCase {
    private var dossier: URL!

    override func setUpWithError() throws {
        dossier = FileManager.default.temporaryDirectory.appendingPathComponent("migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dossier)
    }

    func testUneColonneDejaAjouteeParUneAutreConnexionNEstPasUneErreur() throws {
        let base = try Base(chemin: dossier.appendingPathComponent("a.sqlite"))
        try base.executer("CREATE TABLE essai (id TEXT)")
        try base.ajouterColonne("ALTER TABLE essai ADD COLUMN objet TEXT NOT NULL DEFAULT ''")
        XCTAssertNoThrow(try base.ajouterColonne("ALTER TABLE essai ADD COLUMN objet TEXT NOT NULL DEFAULT ''"))
        // Les autres erreurs remontent toujours.
        XCTAssertThrowsError(try base.ajouterColonne("ALTER TABLE absente ADD COLUMN objet TEXT"))
    }

    func testPlusieursConnexionsOuvrentUneBaseNeuveEnMemeTemps() throws {
        for essai in 0..<20 {
            let chemin = dossier.appendingPathComponent("base-\(essai).sqlite")
            let erreurs = Erreurs()
            DispatchQueue.concurrentPerform(iterations: 6) { _ in
                do { _ = try Base(chemin: chemin) } catch { erreurs.ajouter("\(error)") }
            }
            XCTAssertEqual(erreurs.liste, [], "essai \(essai)")
        }
    }
}

private final class Erreurs: @unchecked Sendable {
    private let verrou = NSLock()
    private var contenu: [String] = []
    func ajouter(_ e: String) { verrou.lock(); contenu.append(e); verrou.unlock() }
    var liste: [String] { verrou.lock(); defer { verrou.unlock() }; return contenu }
}
