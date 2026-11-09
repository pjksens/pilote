// « Acceptée », « Pas encore » et « Reporter » sur une ligne d'Aujourd'hui (04/11).
import XCTest

final class InvitationsTests: XCTestCase {
    var chemin: URL!

    override func setUpWithError() throws {
        chemin = FileManager.default.temporaryDirectory.appendingPathComponent("pilote-invit-\(UUID().uuidString).sqlite")
    }

    override func tearDown() {
        for suffixe in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: chemin.path + suffixe) }
    }

    /// Un contact freelance à qui on a envoyé une invitation : la routine pose « Invitation acceptée ? » à J+5.
    private func invite() throws -> (Stockage, String) {
        let s = Stockage(base: try Base(chemin: chemin))
        let c = try s.enregistrer(["nom": "Domaine Test", "espace": "freelance", "linkedin": "https://www.linkedin.com/in/test"])
        try s.ajouterEvenement(contactId: c.id, ["canal": "linkedin", "sens": "sortant", "type": "invitation", "texte": "Invitation",
                                                 "statut": "envoye", "le": "2026-10-28T08:00:00Z"])
        return (s, c.id)
    }

    func testReconnaitLaLigne() throws {
        XCTAssertTrue(Invitation.attendue("Invitation acceptée ? Si oui, message après acceptation (modèle de la routine)"))
        XCTAssertTrue(Invitation.attendue("Vérifier si l'invitation LinkedIn est acceptée"))
        XCTAssertFalse(Invitation.attendue(Invitation.actionAutreCanal))
        XCTAssertFalse(Invitation.attendue("Relance unique si pas de réponse"))
        let (s, id) = try invite()
        XCTAssertTrue(Invitation.attendue(try s.contact(id)!.prochaineAction))
    }

    func testAcceptee() throws {
        let (s, id) = try invite()
        try s.invitationAcceptee(id)
        let c = try s.contact(id)!
        XCTAssertEqual(c.prochaineDate, "")                         // quitte Aujourd'hui
        XCTAssertEqual(c.prochaineAction, Invitation.actionMessage)
        XCTAssertEqual(c.etape, "contacte")                         // accepter n'est pas répondre
        XCTAssertEqual(try s.evenements(id).first?.texte, "Invitation acceptée")
        // Le message envoyé ensuite pose la relance de la routine (la date était libre).
        try s.ajouterEvenement(contactId: id, ["canal": "linkedin", "sens": "sortant", "type": "message", "texte": "Merci", "statut": "envoye"])
        XCTAssertEqual(try s.contact(id)!.prochaineAction, "Relance unique si pas de réponse")
    }

    func testPasEncorePuisAutreCanal() throws {
        let (s, id) = try invite()
        let mercredi = Dates.iso.date(from: "2026-11-04T07:00:00Z")!
        XCTAssertFalse(try s.invitationPasEncore(id, maintenant: mercredi))
        var c = try s.contact(id)!
        XCTAssertEqual(c.prochaineDate, "2026-11-09")                // 3 jours ouvrés : jeu., ven., lun.
        XCTAssertTrue(Invitation.attendue(c.prochaineAction))       // même question, plus tard

        XCTAssertTrue(try s.invitationPasEncore(id, maintenant: mercredi))
        c = try s.contact(id)!
        XCTAssertEqual(c.prochaineAction, Invitation.actionAutreCanal)
        XCTAssertEqual(c.prochaineDate, "")
        XCTAssertEqual(Invitation.pasEncoreDepuisInvitation(try s.evenements(id)), 2)

        // Une nouvelle invitation remet le compte à zéro. Plus récente que les « pas encore » (heure réelle) : une heure fixe
        // faisait échouer ce test dès que l'horloge dépassait 09:00Z le 04/11 (constaté à 14 h, indépendant du suivi).
        try s.ajouterEvenement(contactId: id, ["canal": "linkedin", "sens": "sortant", "type": "invitation", "texte": "Invitation",
                                               "statut": "envoye", "le": Dates.iso.string(from: Date().addingTimeInterval(60))])
        XCTAssertEqual(Invitation.pasEncoreDepuisInvitation(try s.evenements(id)), 0)
    }

    func testReporter() throws {
        let (s, id) = try invite()
        let avant = try s.contact(id)!.prochaineAction
        try s.reporterAction(id, au: "2026-11-12")
        let c = try s.contact(id)!
        XCTAssertEqual(c.prochaineDate, "2026-11-12")
        XCTAssertEqual(c.prochaineAction, avant)
    }
}
