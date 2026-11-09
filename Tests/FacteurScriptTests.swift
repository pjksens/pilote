import XCTest

/// Le contrat entre l'app et scripts/facteur.py : les lignes que l'app écrit (Facteur.ecrire, Decisions.noter, envoi
/// « pret ») sont celles que le script remet, et l'app relit ses remises. Lance python3 sur un dossier temporaire.
final class FacteurScriptTests: XCTestCase {
    func testLeScriptRemetCeQueLAppEcrit() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("facteur-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let pilote = "local_00000000-0000-0000-0000-000000000001"
        let atelier = "local_00000000-0000-0000-0000-000000000002"
        let reglages: [String: Any] = ["prenom": Moi.prenom ?? "", "facteur": ["sessions": ["PILOTE": pilote]]]
        try JSONSerialization.data(withJSONObject: reglages).write(to: dir.appendingPathComponent("reglages.json"))
        try Facteur.ecrire(pour: "Atelier", session: atelier, texte: "Bonjour", qui: Moi.nom, dossier: dir)
        try Decisions.noter(question: "On publie ?", choix: "Oui", ref: "essai", liste: "", pour: "PILOTE", dossier: dir)
        try Facteur.noter([1], etat: .pret, dossier: dir)

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["python3", Identite.depot.appendingPathComponent("scripts/facteur.py").path, "--attendre"]
        p.environment = ["PILOTE_DOSSIER": dir.path, "PATH": "/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin"]
        let sortie = Pipe()
        p.standardOutput = sortie
        try p.run()
        let fin = Date().addingTimeInterval(20)
        while p.isRunning && Date() < fin { Thread.sleep(forTimeInterval: 0.1) }
        guard !p.isRunning else { p.terminate(); return XCTFail("facteur.py --attendre ne s'est pas terminé") }
        XCTAssertEqual(p.terminationStatus, 0)

        let texte = String(decoding: sortie.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let courriers = texte.split(separator: "\n").compactMap {
            try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any]
        }
        XCTAssertEqual(courriers.compactMap { $0["to"] as? String }, [atelier, pilote])
        XCTAssertEqual(courriers.compactMap { $0["rang"] as? Int }, [0, 1])
        XCTAssertTrue((courriers.first?["message"] as? String ?? "").hasPrefix("Message de \(Moi.tiers), écrit dans l'app Pilote :\nBonjour"))
        XCTAssertTrue((courriers.last?["message"] as? String ?? "").hasPrefix("Décision de \(Moi.tiers), prise dans l'app Pilote :\nOn publie ? → Oui"))

        let r = Facteur.remises(dossier: dir)
        XCTAssertEqual(r[0]?.etat, .emis)
        XCTAssertEqual(r[1]?.etat, .emis)
        XCTAssertTrue(Facteur.actif(dossier: dir), "facteur.json écrit par le script, lu par l'app")
    }
}
