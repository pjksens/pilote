import XCTest

/// 04/11 : le capteur ne doit pas ranger une deuxième fois un mail déjà noté à la main au fil (cas de Julien Morel).
final class FilDoublonTests: XCTestCase {
    private let manuel = "Bonjour Sacha\nmerci pour votre message.\nDésolé j'ai pas encore eu le temps de me pencher dessus car j'ai une priorité."
    private let capteur = "Bonjour Sacha merci pour votre message. Désolé j'ai pas encore eu le temps de me pencher dessus car j'ai une priorité que je dois…"

    func testLeMemeMailNoteALaMainEtParLeCapteurEstReconnu() {
        XCTAssertTrue(FilDoublon.memeMessage(texteA: capteur, leA: "2026-11-04T16:21:58Z", texteB: manuel, leB: "2026-11-04T16:21:41Z"))
    }

    func testPlusDeDixMinutesOuUnAutreTexteNeSontPasDesDoublons() {
        XCTAssertFalse(FilDoublon.memeMessage(texteA: capteur, leA: "2026-11-04T16:35:00Z", texteB: manuel, leB: "2026-11-04T16:21:41Z"))
        XCTAssertFalse(FilDoublon.memeMessage(texteA: "Merci, je regarde ça demain et je reviens vers vous.", leA: "2026-11-04T16:21:58Z",
                                              texteB: manuel, leB: "2026-11-04T16:21:41Z"))
        XCTAssertFalse(FilDoublon.memeMessage(texteA: capteur, leA: "pas une date", texteB: manuel, leB: "2026-11-04T16:21:41Z"))
    }

    func testLePrefixeDeCanalEtLesTextesCourts() {
        XCTAssertTrue(FilDoublon.memeMessage(texteA: "WhatsApp : Bonjour Sacha, je vous fais un retour cet après-midi", leA: "2026-11-02T09:12:33Z",
                                             texteB: "bonjour sacha je vous fais un retour cet apres-midi", leB: "2026-11-02T09:12:00+00:00"))
        XCTAssertFalse(FilDoublon.memeMessage(texteA: "ok", leA: "2026-11-02T09:12:33Z", texteB: "ok merci", leB: "2026-11-02T09:12:40Z"))
        XCTAssertTrue(FilDoublon.memeMessage(texteA: "ok", leA: "2026-11-02T09:12:33Z", texteB: "OK", leB: "2026-11-02T09:12:40Z"))
        XCTAssertFalse(FilDoublon.memeMessage(texteA: "", leA: "2026-11-02T09:12:33Z", texteB: "", leB: "2026-11-02T09:12:40Z"))
    }

    func testLeFilNeRecoitPasDeuxFoisLeMemeMail() throws {
        let chemin = FileManager.default.temporaryDirectory.appendingPathComponent("pilote-doublon-\(UUID().uuidString).sqlite")
        defer { for s in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: chemin.path + s) } }
        let stock = Stockage(base: try Base(chemin: chemin))
        let c = try stock.enregistrer(["nom": "Client Test", "espace": "freelance"])
        // 1. Noté à la main (sans source_ref), avec le texte complet.
        let main = try stock.ajouterEvenement(contactId: c.id, ["canal": "mail", "sens": "entrant", "type": "reponse", "texte": manuel,
                                                                "le": "2026-11-04T16:21:41Z", "par": "Claude"])
        // 2. Le capteur range le même mail : pas de deuxième entrée, il reçoit l'entrée existante.
        let deja = try stock.ajouterEvenement(contactId: c.id, ["canal": "mail", "sens": "entrant", "type": "reponse", "texte": capteur,
                                                                "le": "2026-11-04T16:21:58Z", "par": "Capteur Pilote", "source_ref": "mail:198500"])
        XCTAssertEqual(deja.id, main.id)
        XCTAssertEqual(try stock.evenements(c.id).filter { $0.sens == "entrant" }.count, 1)
        // 3. Un autre mail du même contact, quelques minutes plus tard, est bien rangé.
        let autre = try stock.ajouterEvenement(contactId: c.id, ["canal": "mail", "sens": "entrant", "type": "reponse",
                                                                 "texte": "Merci, je valide les visuels lundi comme convenu.",
                                                                 "le": "2026-11-04T16:25:00Z", "par": "Capteur Pilote", "source_ref": "mail:198501"])
        XCTAssertNotEqual(autre.id, main.id)
        XCTAssertEqual(try stock.evenements(c.id).filter { $0.sens == "entrant" }.count, 2)
        // 4. Une entrée manuelle (sans source_ref) n'est jamais écartée : la règle ne vise que le capteur.
        let manuelle2 = try stock.ajouterEvenement(contactId: c.id, ["canal": "mail", "sens": "entrant", "type": "reponse", "texte": manuel,
                                                                     "le": "2026-11-04T16:22:00Z", "par": "Claude"])
        XCTAssertNotEqual(manuelle2.id, main.id)
    }
}
