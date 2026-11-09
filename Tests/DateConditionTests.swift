// 08/11 : des messages prévus le 16/11 s'affichaient le 08/11 (jour vide ou date de la fiche). Une condition en attente qui cite
// une date fait attendre le message ; un jour de semaine faux dans la condition est refusé à l'écriture.
import XCTest

final class DateConditionTests: XCTestCase {
    let auj = "2026-11-08"

    func testConditionAvecDateFaitAttendreLeMessage() {
        // jour vide (préparé hier) + condition du 16/11 : attend le 16/11
        XCTAssertEqual(Libelles.jourDuMessage(texte: "Bonjour", le: "2026-11-07T10:00:00Z", dateFiche: "", aujourdhui: auj,
                                              condition: "Seulement le 16/11 ou après, et seulement si Marie a accepté"), "2026-11-16")
        // fiche à 09/11 (cas Moreau) : la date de la condition l'emporte ; le 07/11 (passé) est ignoré
        XCTAssertEqual(Libelles.jourDuMessage(texte: "Bonjour", le: "2026-11-08T08:00:00Z", dateFiche: "2026-11-09", aujourdhui: auj,
                                              condition: "Ventes a relu le 16/11 : aucune réponse depuis le SMS du 07/11"), "2026-11-16")
    }

    func testPremiereDateNonPasseeEtNonPlusLaPlusTardive() {
        // cas Moreau 14b05237 : part lundi 09/11 ; le 16/11 cité est la relance à annuler
        XCTAssertEqual(Libelles.jourDuMessage(texte: "Bonjour", le: "2026-11-07T10:00:00Z", dateFiche: "", aujourdhui: auj,
            condition: "Lundi 09/11 avant envoi : relire la prod ; si ce SMS part, annuler la relance du 16/11."), "2026-11-09")
    }

    func testDateDeConditionPasseeOuAbsenteNeChangeRien() {
        XCTAssertEqual(Libelles.jourDuMessage(texte: "Bonjour", le: "2026-11-07T10:00:00Z", dateFiche: "", aujourdhui: auj,
                                              condition: "Ventes a relu Gmail le 06/11 : aucune réponse"), "")
        XCTAssertEqual(Libelles.jourDuMessage(texte: "Bonjour", le: "2026-11-07T10:00:00Z", dateFiche: "", aujourdhui: auj, condition: ""), "")
        // une date en tête plus tardive que celle de la condition reste
        XCTAssertEqual(Libelles.jourDuMessage(texte: "SMS à envoyer lun. 23/11\nBonjour", le: "2026-11-07T10:00:00Z", dateFiche: "", aujourdhui: auj,
                                              condition: "relu le 16/11"), "2026-11-23")
    }

    /// 09/11 : la réponse validée à Julien (mail dans un fil, préparée le jour même) tombait à la date de la fiche (11/11).
    func testReponseDansUnFilPartLeJourOuElleEstPreparee() {
        let fil = "<CAJ@mail.gmail.com>"
        // Préparée aujourd'hui, dans un fil, sans jour en tête ni condition datée : aujourd'hui, pas la date de la fiche.
        XCTAssertEqual(Libelles.jourDuMessage(texte: "Salut Julien,", le: "2026-11-08T10:01:00Z", dateFiche: "2026-11-11",
                                              aujourdhui: auj, reponseA: fil), "")
        // Le reste ne bouge pas : sans fil, la date de la fiche ; un jour en tête ou une condition datée passent avant.
        XCTAssertEqual(Libelles.jourDuMessage(texte: "Bonjour", le: "2026-11-08T08:00:00Z", dateFiche: "2026-11-10", aujourdhui: auj),
                       "2026-11-10")
        XCTAssertEqual(Libelles.jourDuMessage(texte: "Mail à envoyer jeu. 12/11\nBonjour", le: "2026-11-08T08:00:00Z", dateFiche: "2026-11-10",
                                              aujourdhui: auj, reponseA: fil), "2026-11-12")
        XCTAssertEqual(Libelles.jourDuMessage(texte: "Bonjour", le: "2026-11-08T08:00:00Z", dateFiche: "2026-11-11", aujourdhui: auj,
                                              condition: "Ventes a relu Gmail le 13/11", reponseA: fil), "2026-11-13")
    }

    func testConditionCocheeNeRetientPlus() {
        var e = Evenement(id: "x", contactId: "c", le: "2026-11-07T10:00:00Z")
        e.condition = "relu le 16/11"
        XCTAssertEqual(e.conditionPourJour, "relu le 16/11")
        e.conditionOkLe = "2026-11-08T09:00:00Z"
        XCTAssertEqual(e.conditionPourJour, "")
    }

    func testJourDeSemaineFaux() {
        XCTAssertNotNil(Libelles.incoherenceJourSemaine("Dim. 16/11 ou après : toujours aucune réponse", aujourdhui: auj))  // lundi
        XCTAssertNil(Libelles.incoherenceJourSemaine("Lun. 16/11 ou après", aujourdhui: auj))
        XCTAssertNil(Libelles.incoherenceJourSemaine("Jeu. 12/11 : aucune réponse", aujourdhui: auj))
        XCTAssertNil(Libelles.incoherenceJourSemaine("aucune réponse depuis le 07/11", aujourdhui: auj))
    }

    func testEcritureRefuseJourDeSemaineFaux() throws {
        let chemin = FileManager.default.temporaryDirectory.appendingPathComponent("pilote-dc-\(UUID().uuidString).sqlite")
        defer { for x in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: chemin.path + x) } }
        let s = Stockage(base: try Base(chemin: chemin))
        let c = try s.enregistrer(["nom": "Test", "espace": "kryva", "source": "test"]).id
        let champs: [String: Any] = ["canal": "sms", "sens": "sortant", "type": "message", "texte": "Bonjour", "statut": "prepare",
                                     "condition": "Dim. 16/11 ou après"]
        XCTAssertThrowsError(try s.ajouterEvenement(contactId: c, champs))
        XCTAssertTrue(try s.messages(statut: "prepare").isEmpty)                    // rien écrit
        var ok = champs; ok["condition"] = "Lun. 16/11 ou après"
        let e = try s.ajouterEvenement(contactId: c, ok)
        XCTAssertThrowsError(try s.modifierEvenement(e.id, ["condition": "Dim. 16/11 ou après"]))
        XCTAssertEqual(try s.evenement(e.id)?.condition, "Lun. 16/11 ou après")
        try s.modifierEvenement(e.id, ["condition": "Lun. 16/11 ou après, et sans réponse"])
    }
}

final class LienSiteTests: XCTestCase {
    private func site(_ s: String) -> URL? { var c = Contact(id: "x"); c.site = s; return c.lienSite }

    func testLeSiteDeLaFicheDevientUneAdresseOuvrable() {
        XCTAssertEqual(site("https://www.oec.fr/page?x=1")?.absoluteString, "https://www.oec.fr/page?x=1")
        XCTAssertEqual(site("  exemple.fr/contact ")?.absoluteString, "https://exemple.fr/contact")
        XCTAssertNil(site(""))
        XCTAssertNil(site("pas de site"))
        XCTAssertNil(site("localhost"))
        XCTAssertNil(site("file:///etc/hosts"))
    }
}
