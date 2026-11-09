import XCTest

final class RepartitionTests: XCTestCase {
    func testGestesDeSacha() {
        XCTAssertTrue(Libelles.pourSacha("Sacha : appeler Arthur pour fixer l'heure"))
        XCTAssertTrue(Libelles.pourSacha("Sacha vérifie si l'invitation du 27/10 est acceptée (invisible dans Gmail)."))
        XCTAssertTrue(Libelles.pourSacha("Lun. 09/11 (choix de Sacha, 05/11) : appeler pour la visio"))
        XCTAssertTrue(Libelles.pourSacha("Visio mar. 10/11, heure à fixer"))
        XCTAssertTrue(Libelles.pourSacha("Rappeler après sa visite de chantier"))
    }

    func testAttendreVerifierRelancerSontPourLAgent() {
        XCTAssertFalse(Libelles.pourSacha("SMS envoyé par Sacha le 03/11. Attendre sa réponse ; jeudi 05/11, revérifier."))
        XCTAssertFalse(Libelles.pourSacha("Relance unique si pas de réponse"))
        XCTAssertFalse(Libelles.pourSacha("Sans réponse au 13/11 : classer sans suite, plus aucune relance."))
        XCTAssertFalse(Libelles.pourSacha("Lun. 14/12 : point décidé par Sacha le 02/11 : prendre de ses nouvelles"))
        XCTAssertFalse(Libelles.pourSacha("Jeudi 05/11 : texte VALIDÉ tel quel par Sacha (04/11, statut prepare)"))
        XCTAssertFalse(Libelles.pourSacha("Invitation acceptée ? Si oui, message après acceptation (modèle de la routine)"))
        XCTAssertFalse(Libelles.pourSacha("⚠ Même société que Nicolas FAURE, déjà mailé"))
    }

    private let chemin = FileManager.default.temporaryDirectory.appendingPathComponent("repartition-\(UUID().uuidString).sqlite")

    override func tearDown() {
        for suffixe in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: chemin.path + suffixe) }
    }

    /// 05/11 : la liste du matin est gardée ; une fiche qui en sort est « traitée », les autres « restent ».
    func testJourneeAgentTraiteesEtRestantes() throws {
        let s = Stockage(base: try Base(chemin: chemin))
        let jour = "2026-11-05"
        let a = try s.enregistrer(["nom": "Alpha", "espace": "kryva", "etape": "contacte",
                                   "prochaine_action": "Attendre sa réponse", "prochaine_date": jour])
        let b = try s.enregistrer(["nom": "Bravo", "espace": "kryva", "etape": "contacte",
                                   "prochaine_action": "Revérifier Gmail", "prochaine_date": "2026-11-04"])
        let c = try s.enregistrer(["nom": "Charlie", "espace": "kryva", "etape": "contacte", "prochaine_action": "", "prochaine_date": ""])
        _ = try s.enregistrer(["nom": "Delta", "espace": "kryva", "etape": "contacte",
                               "prochaine_action": "Sacha : appeler Delta", "prochaine_date": jour])
        _ = try s.enregistrer(["nom": "Echo", "espace": "freelance", "etape": "contacte",
                               "prochaine_action": "Attendre", "prochaine_date": jour])

        var j = try s.journeeAgent(.ventes, au: jour)
        XCTAssertEqual(Set(j.restantes.map(\.contact.nom)), ["Alpha", "Bravo", "Charlie"])   // pas Delta (geste de Sacha), pas Echo (freelance)
        XCTAssertTrue(j.traitees.isEmpty)
        XCTAssertEqual(j.restantes.first { $0.contact.nom == "Charlie" }?.motif, "sans_date")

        // L'agent traite : Alpha reçoit une nouvelle date, Bravo est classée, Charlie passe à Sacha.
        var ca = try XCTUnwrap(s.contact(a.id)); ca.prochaineAction = "Relance unique le 13/11"; ca.prochaineDate = "2026-11-13"
        try s.enregistrer(ca)
        var cb = try XCTUnwrap(s.contact(b.id)); cb.etape = "perdu"; try s.enregistrer(cb)
        var cc = try XCTUnwrap(s.contact(c.id)); cc.prochaineAction = "Sacha : visio à fixer"; cc.prochaineDate = jour
        try s.enregistrer(cc)

        j = try s.journeeAgent(.ventes, au: jour)
        XCTAssertTrue(j.restantes.isEmpty)
        let devenues = Dictionary(uniqueKeysWithValues: j.traitees.map { ($0.contact.nom, $0.devenue) })
        XCTAssertEqual(devenues["Alpha"], "suite le 13/11")
        XCTAssertEqual(devenues["Bravo"], "classée perdue")
        XCTAssertEqual(devenues["Charlie"], "passée à vous")
        XCTAssertEqual(j.traitees.first { $0.contact.nom == "Alpha" }?.dateAvant, jour)   // la liste du matin est gardée
        // T5 : preuve de la traitée. Nouvelle date seule = reportée ; classée ou passée à Sacha = faite ; un fait au fil = faite.
        let preuves = Dictionary(uniqueKeysWithValues: j.traitees.map { ($0.contact.nom, $0.preuve) })
        XCTAssertEqual(preuves["Alpha"], "reportee")
        XCTAssertEqual(preuves["Bravo"], "faite")
        XCTAssertEqual(preuves["Charlie"], "faite")
        XCTAssertEqual(j.reportees.count, 1)
        XCTAssertTrue(j.sansTrace.isEmpty)
        _ = try s.ajouterEvenement(contactId: a.id, ["canal": "autre", "sens": "interne", "type": "note", "texte": "Vérifié Gmail : pas de réponse", "par": "Ventes"])
        XCTAssertEqual(try s.journeeAgent(.ventes, au: jour).traitees.first { $0.contact.nom == "Alpha" }?.preuve, "faite")
        XCTAssertEqual(Stockage.preuve(reste: false, devenue: "traitée", faitAuFil: false), "sans_trace")
        XCTAssertEqual(Stockage.preuve(reste: true, devenue: "due aujourd'hui", faitAuFil: true), "reste")

        // Une fiche qui devient due dans la journée s'ajoute ; la relance la cite avec la consigne.
        _ = try s.enregistrer(["nom": "Foxtrot", "espace": "kryva", "etape": "contacte",
                               "prochaine_action": "Lun. 02/11 : revérifier", "prochaine_date": "2026-11-02"])
        j = try s.journeeAgent(.ventes, au: jour)
        XCTAssertEqual(j.restantes.map(\.contact.nom), ["Foxtrot"])
        XCTAssertEqual(j.restantes.first?.devenue, "en retard depuis le 02/11")
        let texte = Stockage.relance(j)
        XCTAssertTrue(texte.contains("1 fiche de ta liste du jour pas encore traitée (3 déjà faites)"))
        XCTAssertTrue(texte.contains("- Foxtrot (en retard depuis le 02/11) : revérifier"))
        XCTAssertTrue(texte.contains(Stockage.consigneAgent))
        XCTAssertEqual(try s.journeeAgent(.freelance, au: jour).restantes.map(\.contact.nom), ["Echo"])
    }

    func testAgentParEspace() {
        XCTAssertEqual(Libelles.agent(espace: "kryva"), .ventes)
        XCTAssertEqual(Libelles.agent(espace: "freelance"), .freelance)
        XCTAssertEqual(Libelles.agent(espace: "autre"), .pilote)
    }
}
