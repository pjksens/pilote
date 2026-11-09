// Suivi des prospects (04/11) : la suite après un envoi, le message jamais caché, le contrôle du matin.
import XCTest

final class SuiviProspectsTests: XCTestCase {
    var chemin: URL!
    var s: Stockage!
    let auj = Dates.aujourdhui()

    override func setUpWithError() throws {
        chemin = FileManager.default.temporaryDirectory.appendingPathComponent("pilote-suivi-\(UUID().uuidString).sqlite")
        s = Stockage(base: try Base(chemin: chemin))
    }

    override func tearDown() {
        for suffixe in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: chemin.path + suffixe) }
    }

    private func contact(_ nom: String, etape: String = "contacte", action: String = "Relance mail proposée", date: String? = nil,
                         source: String = "test") throws -> String {
        try s.enregistrer(["nom": nom, "espace": "kryva", "etape": etape, "prochaine_action": action,
                           "prochaine_date": date ?? auj, "source": source]).id
    }

    private func envoi(_ id: String, le: String? = nil) throws {
        try s.ajouterEvenement(contactId: id, ["canal": "mail", "sens": "sortant", "type": "message", "texte": "Bonjour", "statut": "envoye",
                                               "le": le ?? Dates.maintenant()])
    }

    // MARK: (a) un envoi met la fiche à jour

    func testEnvoiLeJourDeLEcheanceRepousseLaFiche() throws {
        let id = try contact("Échéance aujourd'hui")
        try envoi(id)
        let c = try s.contact(id)!
        XCTAssertEqual(c.prochaineAction, "Relance unique si pas de réponse")
        XCTAssertEqual(c.prochaineDate, Dates.ouvres(5))           // avant le 04/11 : restait à la date du jour
    }

    func testEnvoiNeRemplacePasUneActionPlusTard() throws {
        let plusTard = Dates.dans(10)
        let id = try contact("Action plus tard", action: "Rendez-vous", date: plusTard)
        try envoi(id)
        let c = try s.contact(id)!
        XCTAssertEqual(c.prochaineDate, plusTard)
        XCTAssertEqual(c.prochaineAction, "Rendez-vous")
    }

    func testUneAutreActionDuJourResteEtLeControleLaSignale() throws {
        let id = try contact("Action sans rapport", action: "Taux tranché par Sacha le 03/11 : 20 % (réponse 75, relayée par mail)")
        try envoi(id)
        let c = try s.contact(id)!
        XCTAssertEqual(c.prochaineDate, auj)                                   // pas écrasée
        XCTAssertTrue(c.prochaineAction.hasPrefix("Taux tranché"))
        XCTAssertTrue(try s.suitesARetablir().isEmpty)                         // la réparation non plus
        XCTAssertEqual(try s.controle().envoyesEncoreDus.map(\.contactId), [id])  // mais elle est signalée
        XCTAssertTrue(Libelles.actionEstUnEnvoi("DM Instagram @atelier (lien lu)"))
        XCTAssertTrue(Libelles.actionEstUnEnvoi("SMS à valider par Sacha"))
        XCTAssertTrue(Libelles.actionEstUnEnvoi("Avant l'envoi : tape « AB Traiteur »"))
        XCTAssertTrue(Libelles.actionEstUnEnvoi("Jeudi 05/11 : texte VALIDÉ tel quel par Sacha (04/11, statut prepare) : « Envoyer depuis Gmail »"))
        XCTAssertTrue(Libelles.actionEstUnEnvoi("Texte validé par Sacha (prepare, 04/11 soir). Jeu. 05/11 14:15 : relancer"))
        XCTAssertFalse(Libelles.actionEstUnEnvoi("Appeler Jean à 14 h"))
    }

    /// 04/11, demande de PILOTE : les actions réellement vues sur Paul LEROUX, Omar BENALI, Victor GARNIER et Karim DUBOIS.
    /// Les trois premières sont des envois (la suite se pose le jour de l'échéance) ; « Taux tranché… » ne l'est pas, par choix.
    func testLesActionsPerimeesDuQuatreNovembre() throws {
        let envois = [
            "SMS rangé a_valider le 04/11 : un seul message, puis fin.",
            "3e mail rangé a_valider le 04/11 (validé le 02/11, à reconfirmer : il propose un appel). Le texte annonce que c'est le dernier mail.",
            "SMS à valider par Sacha (Pilote, Textes à valider), à envoyer mer. 04/11 matin : lui demander son métier.",
        ]
        for (i, action) in envois.enumerated() {
            XCTAssertTrue(Libelles.actionEstUnEnvoi(action), action)
            let id = try contact("Périmée \(i)", action: action)
            try envoi(id)
            let c = try s.contact(id)!
            XCTAssertEqual(c.prochaineAction, "Relance unique si pas de réponse", action)
            XCTAssertEqual(c.prochaineDate, Dates.ouvres(5), action)
        }
        let taux = "Taux tranché par Sacha le 03/11 : 20 % (réponse 75, relayée par PILOTE). Relancer par WhatsApp mer. 04/11 s'il n'a pas répondu."
        XCTAssertFalse(Libelles.actionEstUnEnvoi(taux))
    }

    func testEnvoiEnRetardPoseLaSuite() throws {
        let id = try contact("En retard", date: "2026-10-20")
        try envoi(id)
        XCTAssertEqual(try s.contact(id)!.prochaineDate, Dates.ouvres(5))
    }

    func testMarquerEnvoyePoseLaSuiteLeJourDeLEcheance() throws {
        let id = try contact("Passe par marquer")
        let e = try s.ajouterEvenement(contactId: id, ["canal": "mail", "sens": "sortant", "type": "message", "texte": "Bonjour",
                                                       "statut": "prepare"])
        XCTAssertEqual(try s.contact(id)!.prochaineDate, auj)       // prêt, pas encore envoyé : rien ne bouge
        try s.marquer(evenementId: e.id, statut: "envoye")
        XCTAssertEqual(try s.contact(id)!.prochaineDate, Dates.ouvres(5))
    }

    // MARK: (a) réparer les fiches restées dues

    /// Remet une fiche dans l'état d'avant la correction : envoi du jour, date = aujourd'hui.
    private func fichePeriee(_ nom: String) throws -> String {
        let id = try contact(nom)
        try envoi(id)
        try s.enregistrer(["id": id, "prochaine_action": "Relance mail proposée", "prochaine_date": auj])
        return id
    }

    func testRepareLesFichesRestees() throws {
        let a = try fichePeriee("Périmée A")
        let b = try fichePeriee("Périmée B")
        let liste = try s.suitesARetablir()
        XCTAssertEqual(Set(liste.map(\.contactId)), [a, b])
        XCTAssertEqual(try s.contact(a)!.prochaineDate, auj)         // lister ne touche à rien
        try s.retablirSuites(liste)
        XCTAssertEqual(try s.contact(a)!.prochaineDate, Dates.ouvres(5))
        XCTAssertEqual(try s.contact(b)!.prochaineAction, "Relance unique si pas de réponse")
        XCTAssertTrue(try s.suitesARetablir().isEmpty)               // relançable sans effet
    }

    func testRepareNeToucheNiAuxTextesEnCoursNiAuxArretes() throws {
        let enCours = try fichePeriee("Texte en cours")
        try s.ajouterEvenement(contactId: enCours, ["canal": "mail", "sens": "sortant", "type": "message", "texte": "Relance", "statut": "prepare"])
        let stop = try fichePeriee("Ne plus contacter")
        try s.enregistrer(["id": stop, "ne_plus_contacter": true])
        let ancien = try contact("Envoi d'hier", date: auj)
        try envoi(ancien, le: Dates.iso.string(from: Date().addingTimeInterval(-86_400 * 2)))
        try s.enregistrer(["id": ancien, "prochaine_action": "Relance mail proposée", "prochaine_date": auj])
        XCTAssertTrue(try s.suitesARetablir().isEmpty)
    }

    // MARK: (c) un message prêt ne se cache pas

    func testMessagePretDepuisHierResteVisibleAujourdhui() {
        let futur = Dates.dans(6)
        // préparé hier, fiche datée plus tard, aucun jour écrit : part aujourd'hui (le bug du 04/11)
        XCTAssertEqual(Libelles.jourDuMessage(texte: "Bonjour", le: "2026-11-03T10:00:00Z", dateFiche: futur, aujourdhui: "2026-11-04"), "")
        // préparé aujourd'hui pour une fiche datée plus tard : attend (règle du 03/11)
        XCTAssertEqual(Libelles.jourDuMessage(texte: "Bonjour", le: "2026-11-04T08:00:00Z", dateFiche: "2026-11-09", aujourdhui: "2026-11-04"), "2026-11-09")
        // le jour écrit en tête passe avant : un message du 03/11 daté jeudi attend jeudi
        XCTAssertEqual(Libelles.jourDuMessage(texte: "Mail à envoyer par Sacha jeu. 05/11 à 14:15\nBonjour", le: "2026-11-03T10:00:00Z",
                                              dateFiche: "2026-11-09", aujourdhui: "2026-11-04"), "2026-11-05")
    }

    // MARK: (b) le contrôle du matin

    func testControleSignaleSansRienCorriger() throws {
        let sansTexte = try contact("Due sans texte", action: "Relance mail proposée")
        let avecTexte = try contact("Due avec texte")
        try s.ajouterEvenement(contactId: avecTexte, ["canal": "mail", "sens": "sortant", "type": "message", "texte": "Bonjour", "statut": "a_valider"])
        let invitation = try contact("Invitation à vérifier", action: "Invitation acceptée ? Si oui, message après acceptation (modèle de la routine)")
        let periee = try fichePeriee("Envoyée mais due")
        let plusTard = try contact("Pas due", date: Dates.dans(5))
        let c = try s.controle()
        XCTAssertEqual(c.dusSansTexte.map(\.contactId), [sansTexte])
        XCTAssertEqual(c.envoyesEncoreDus.map(\.contactId), [periee])
        XCTAssertFalse(c.dusSansTexte.map(\.contactId).contains(avecTexte))
        XCTAssertFalse(c.dusSansTexte.map(\.contactId).contains(invitation))
        XCTAssertFalse(c.dusSansTexte.map(\.contactId).contains(plusTard))
        XCTAssertEqual(try s.contact(sansTexte)!.prochaineDate, auj)      // rien n'a bougé
        XCTAssertEqual(try s.contact(sansTexte)!.etape, "contacte")
    }

    func testR1EtapeSansFaitJamaisRetrogradee() throws {
        let vide = try contact("A répondu sans trace", etape: "repondu")
        let reponse = try contact("A répondu pour de vrai", etape: "repondu")
        try s.ajouterEvenement(contactId: reponse, ["canal": "mail", "sens": "entrant", "type": "reponse", "texte": "Oui", "statut": "fait"])
        let rdv = try contact("Rendez-vous sans trace", etape: "rdv")
        let c = try s.controle()
        XCTAssertEqual(Set(c.etapesSansFait.map(\.contactId)), [vide, rdv])
        XCTAssertEqual(try s.contact(vide)!.etape, "repondu")               // on signale, on ne rétrograde pas
    }

    func testR2DateSansActionOuSansSource() throws {
        let sansAction = try contact("Date sans action", action: "")
        let sansSource = try contact("Date sans source", source: "")
        let ok = try contact("Date avec source", source: "linkedin")
        let c = try s.controle()
        XCTAssertEqual(Set(c.datesSansSource.map(\.contactId)), [sansAction, sansSource])
        XCTAssertFalse(c.datesSansSource.map(\.contactId).contains(ok))
        XCTAssertTrue(c.texte().hasPrefix("Contrôle du \(auj)"))
    }

    // MARK: « Pas envoyé » avec une raison

    private func messagePret(_ id: String, texte: String = "Bonjour") throws -> Evenement {
        try s.ajouterEvenement(contactId: id, ["canal": "mail", "sens": "sortant", "type": "message", "texte": texte, "statut": "prepare"])
    }

    private func notes(_ id: String) throws -> [Evenement] {
        try s.evenements(id).filter { $0.type == "note" }
    }

    func testPasLeMomentGardeLeMessageEtLeReporte() throws {
        let id = try contact("Pas le moment")
        let e = try messagePret(id)
        let demain = Dates.ouvres(1)
        let note = try s.pasEnvoye(evenementId: e.id, raison: .pasLeMoment, precision: "il est en vacances", au: demain)
        XCTAssertTrue(note.contains("pas le moment"))
        XCTAssertTrue(note.contains("il est en vacances"))
        let c = try s.contact(id)!
        XCTAssertEqual(c.prochaineDate, demain)
        let m = try s.aEnvoyer().first { $0.0.id == e.id }!
        XCTAssertEqual(m.0.statut, "prepare")                                     // toujours prêt
        XCTAssertEqual(Libelles.jourDuMessage(texte: m.0.texte, le: m.0.le, dateFiche: c.prochaineDate, aujourdhui: auj), demain)  // mais caché jusqu'à demain
        XCTAssertEqual(try notes(id).count, 1)                                    // et la raison est au fil
        XCTAssertEqual(try notes(id).first?.par, "Sacha")
    }

    func testTexteAChangerRenvoieALAgentSansPerdreLaRaison() throws {
        let id = try contact("Texte à changer")
        let e = try messagePret(id)
        try s.pasEnvoye(evenementId: e.id, raison: .texteAChanger, precision: "trop long, tutoyer")
        XCTAssertTrue(try s.aEnvoyer().isEmpty)
        XCTAssertEqual(try s.messages(statut: "a_refaire").map { $0.0.id }, [e.id])
        XCTAssertTrue(try notes(id).first!.texte.contains("trop long, tutoyer"))
    }

    func testPlusDActualiteAnnuleSansToucherLaFiche() throws {
        let id = try contact("Plus d'actualité")
        let e = try messagePret(id)
        try s.pasEnvoye(evenementId: e.id, raison: .plusDActualite)
        XCTAssertTrue(try s.aEnvoyer().isEmpty)
        let c = try s.contact(id)!
        XCTAssertEqual(c.prochaineDate, auj)                                      // la ligne du jour continue de poser la question
        XCTAssertEqual(c.prochaineAction, "Relance mail proposée")
        XCTAssertTrue(try notes(id).first!.texte.hasPrefix("Pas envoyé"))
        XCTAssertEqual(try s.controle().dusSansTexte.map(\.contactId), [id])        // et le contrôle la signale
    }

    func testPasFaitReporteOuAbandonneAvecRaison() throws {
        let a = try contact("Suivi reporté", action: "Appeler pour caler le rendez-vous")
        let b = try contact("Suivi abandonné", action: "Appeler pour caler le rendez-vous")
        let demain = Dates.ouvres(1)
        try s.pasFait(contactId: a, raison: .pasLeMoment, precision: "il rappelle lui-même", au: demain)
        XCTAssertEqual(try s.contact(a)!.prochaineDate, demain)
        XCTAssertEqual(try s.contact(a)!.prochaineAction, "Appeler pour caler le rendez-vous")
        try s.pasFait(contactId: b, raison: .plusDActualite, precision: "a signé ailleurs")
        XCTAssertEqual(try s.contact(b)!.prochaineAction, "")
        XCTAssertEqual(try s.contact(b)!.prochaineDate, "")
        XCTAssertTrue(try notes(b).first!.texte.contains("a signé ailleurs"))
        XCTAssertTrue(try notes(a).first!.texte.contains("pas le moment"))
    }

    // MARK: chaque modification laisse une trace

    func testChangementsDeFicheResumesEtNotesAuFil() throws {
        let id = try contact("Modif fiche")
        let avant = try s.contact(id)!
        var apres = avant
        apres.etape = "repondu"
        apres.prochaineAction = "Appeler jeudi"
        apres.prochaineDate = "2026-11-12"
        let note = try s.consignerChangements(avant: avant, apres: apres)
        XCTAssertNotNil(note)
        XCTAssertTrue(note!.contains("étape"))
        XCTAssertTrue(note!.contains("Appeler jeudi"))
        XCTAssertTrue(note!.contains(Dates.court("2026-11-12")))
        XCTAssertEqual(try notes(id).count, 1)
        XCTAssertEqual(try notes(id).first?.par, "Sacha")
        XCTAssertNil(try s.consignerChangements(avant: apres, apres: apres))       // rien de changé : rien d'écrit
        XCTAssertEqual(try notes(id).count, 1)
        var texteSeul = avant
        texteSeul.notes = "autre"                                                  // un champ non suivi ne laisse pas de trace
        XCTAssertNil(try s.consignerChangements(avant: avant, apres: texteSeul))
    }

    func testReporterLaisseUneTrace() throws {
        let id = try contact("Reporté", action: "Appeler pour caler le rendez-vous")
        let demain = Dates.ouvres(1)
        let note = try s.reporterEtNoter(id, au: demain)
        XCTAssertTrue(note.contains("Reporté"))
        XCTAssertTrue(note.contains("Appeler pour caler"))
        XCTAssertEqual(try s.contact(id)!.prochaineDate, demain)
        XCTAssertEqual(try notes(id).count, 1)
    }

    // MARK: « C'est fait » sur une action d'envoi pose la suite (04/11, PILOTE)

    func testCestFaitSurUnEnvoiPoseLaSuiteAuLieuDeVider() throws {
        let id = try contact("Relance faite", etape: "a_contacter", action: "Relance mail proposée")
        let note = try s.actionFaite(contactId: id)
        let c = try s.contact(id)!
        XCTAssertEqual(c.prochaineAction, "Relance unique si pas de réponse")
        XCTAssertEqual(c.prochaineDate, Dates.ouvres(5))
        XCTAssertEqual(c.etape, "contacte")                                    // un envoi fait avancer l'étape
        XCTAssertTrue(note.hasPrefix("Fait : Relance mail proposée"))
        XCTAssertTrue(try s.evenements(id).contains { $0.texte == note })       // et la trace est au fil
        XCTAssertTrue(try s.controle().sansDate.isEmpty)
    }

    func testCestFaitSurUnEnvoiAvantSonEcheancePoseQuandMemeLaSuite() throws {
        let id = try contact("Envoi en avance", action: "DM Instagram @atelier", date: Dates.dans(10))
        try s.actionFaite(contactId: id)
        XCTAssertEqual(try s.contact(id)!.prochaineDate, Dates.ouvres(5))
    }

    func testCestFaitSurUneInvitationAttendLAcceptation() throws {
        let id = try contact("Invitation envoyée", etape: "a_contacter", action: "Envoyer l'invitation LinkedIn")
        try s.actionFaite(contactId: id)
        XCTAssertTrue(Invitation.attendue(try s.contact(id)!.prochaineAction))
    }

    func testCestFaitSurUneAutreActionLibereLaDate() throws {
        let id = try contact("Appel fait", action: "Appeler Jean à 14 h")
        try s.actionFaite(contactId: id)
        let c = try s.contact(id)!
        XCTAssertEqual(c.prochaineAction, "")
        XCTAssertEqual(c.prochaineDate, "")
        XCTAssertEqual(c.etape, "contacte")
    }

    func testCestFaitNeReculePasUneEtapeEtLaisseLInvitationAuxBoutons() throws {
        let repondu = try contact("A répondu", etape: "repondu", action: "Relance mail proposée")
        try s.actionFaite(contactId: repondu)
        XCTAssertEqual(try s.contact(repondu)!.etape, "repondu")
        let attente = try contact("Invitation à vérifier", action: "Invitation acceptée ? Si oui, message après acceptation")
        try s.actionFaite(contactId: attente)
        XCTAssertEqual(try s.contact(attente)!.prochaineAction, "")        // « Acceptée / Pas encore » sont les vrais boutons
    }

    // MARK: Réparation automatique tant qu'un vieux serveur MCP tourne (04/11, PILOTE)

    func testRepereLesServeursMCPPlusAnciensQueLeBinaire() {
        let ps = """
         4319 Wed Nov  4 13:12:30 2026     /Users/vous/Projects/pilote/pilote mcp
        16035 Wed Nov  4 14:10:37 2026     /Users/vous/Projects/pilote/pilote mcp
        18847 Wed Nov  4 14:27:26 2026     /Users/vous/Projects/pilote/pilote mcp
          777 Wed Nov  4 14:10:37 2026     /usr/bin/autre mcp
          888 Wed Nov  4 14:10:37 2026     /Users/vous/Projects/pilote/pilote entrants --capter
        """
        let serveurs = VieuxMCP.serveurs(dans: ps)
        XCTAssertEqual(serveurs.map(\.pid), [4319, 16035, 18847])
        let binaire = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 14, minute: 24, second: 40))!
        XCTAssertEqual(VieuxMCP.anterieurs(serveurs, aLaDateDe: binaire).map(\.pid), [4319, 16035])
    }

    func testReparationAutomatiqueSeulementAvecUnVieuxServeurEtNoteChaqueCorrection() throws {
        let id = try contact("Périmée auto")
        try envoi(id)
        try s.enregistrer(["id": id, "prochaine_action": "Relance mail proposée", "prochaine_date": auj])   // l'ancien code l'a laissée due
        var copies = 0
        XCTAssertEqual(try s.reparationAutomatique(vieuxServeurs: 0, sauvegarder: { copies += 1 }), 0)    // aucun vieux serveur : on ne touche à rien
        XCTAssertEqual(copies, 0)
        XCTAssertEqual(try s.contact(id)!.prochaineDate, auj)
        XCTAssertEqual(try s.reparationAutomatique(vieuxServeurs: 2, sauvegarder: { copies += 1 }), 1)
        XCTAssertEqual(copies, 1)                                                                          // une sauvegarde avant la correction
        XCTAssertEqual(try s.contact(id)!.prochaineDate, Dates.ouvres(5))
        let note = try s.evenements(id).first { $0.par == "Pilote" }
        XCTAssertTrue(note?.texte.contains("Suite posée par Pilote") == true)
        XCTAssertTrue(note?.texte.contains("Relance mail proposée") == true)                               // l'avant est écrit au fil
        XCTAssertEqual(try s.reparationAutomatique(vieuxServeurs: 2, sauvegarder: { copies += 1 }), 0)     // relançable sans effet
        XCTAssertEqual(copies, 1)
    }

    func testCopieDeLaBase() throws {
        _ = try contact("Pour la copie")
        let copie = FileManager.default.temporaryDirectory.appendingPathComponent("pilote-copie-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: copie) }
        try s.copierBase(vers: copie.path)
        let b = Stockage(base: try Base(chemin: copie))
        XCTAssertEqual(try b.contacts().count, 1)
    }

    // MARK: Capteur : « Répondre à… » et envois sortants (04/11, GO de PILOTE)

    func testTexteEnvoyeEtTexteDuMessagePret() {
        let pret = "WhatsApp à envoyer par Sacha mer. 04/11\n\nBonjour Léa, c'est Sacha de KRYVA. Avez-vous pu regarder le devis ? Je reste disponible."
        XCTAssertTrue(Sortants.correspond(envoye: "Bonjour Léa, c'est Sacha de KRYVA. Avez-vous pu regarder le devis ? Je reste disponible.", prepare: pret))
        XCTAssertTrue(Sortants.correspond(envoye: "bonjour lea c'est sacha de kryva avez-vous pu regarder le devis je reste disponible", prepare: pret))
        XCTAssertFalse(Sortants.correspond(envoye: "Bonjour Léa, c'est Sacha de KRYVA.", prepare: pret))          // un bout seulement
        XCTAssertFalse(Sortants.correspond(envoye: "Ok merci à demain", prepare: pret))
        XCTAssertFalse(Sortants.correspond(envoye: "ok", prepare: "ok"))                                          // trop court pour prouver quoi que ce soit
    }

    private func prepare(_ id: String, canal: String, texte: String) throws -> String {
        try s.ajouterEvenement(contactId: id, ["canal": canal, "sens": "sortant", "type": "message", "texte": texte, "statut": "prepare"]).id
    }

    func testEnvoiCaptePassePrepareAEnvoyeSiContactCanalEtTexteCorrespondent() throws {
        let id = try contact("Léa", etape: "a_contacter", action: "Envoyer le SMS")
        let ev = try prepare(id, canal: "sms", texte: "Bonjour Léa, c'est Sacha de KRYVA. Avez-vous pu regarder le devis ?")
        let r = try s.captureSortante(contactId: id, canal: "imessage", texte: "Bonjour Léa, c'est Sacha de KRYVA. Avez-vous pu regarder le devis ?",
                                      le: Date(), ref: "imessage:1")
        XCTAssertEqual(r, .marqueEnvoye(ev))
        XCTAssertEqual(try s.evenement(ev)!.statut, "envoye")
        let c = try s.contact(id)!
        XCTAssertEqual(c.etape, "contacte")
        XCTAssertEqual(c.prochaineAction, "Relance unique si pas de réponse")                // la suite d'un envoi est posée
        XCTAssertTrue(try s.evenements(id).contains { $0.texte.hasPrefix("Envoi capté") })
    }

    func testEnvoiDouteuxNeChangeAucunStatutEtLaisseUneNote() throws {
        let id = try contact("Théo")
        let ev = try prepare(id, canal: "sms", texte: "Bonjour Théo, voici le texte exact prévu par Sacha pour cette relance.")
        let r = try s.captureSortante(contactId: id, canal: "imessage", texte: "Salut Théo, ça roule ?", le: Date(), ref: "imessage:2")
        XCTAssertEqual(r, .aVerifier)
        XCTAssertEqual(try s.evenement(ev)!.statut, "prepare")                                 // statut intact
        XCTAssertTrue(try s.evenements(id).contains { $0.texte.hasPrefix("Envoi possible") && $0.texte.contains("à vérifier") })
        _ = try s.captureSortante(contactId: id, canal: "imessage", texte: "Salut Théo, ça roule ?", le: Date(), ref: "imessage:2")
        XCTAssertEqual(try s.evenements(id).filter { $0.texte.hasPrefix("Envoi possible") }.count, 1)   // jamais deux fois la même note
    }

    func testMauvaisCanalOuRienDePretNeMarqueRien() throws {
        let id = try contact("Camille")
        XCTAssertEqual(try s.captureSortante(contactId: id, canal: "imessage", texte: "Un message quelconque assez long", le: Date(), ref: "imessage:3"), .rien)
        let ev = try prepare(id, canal: "mail", texte: "Bonjour Camille, voici le mail prévu pour vous aujourd'hui.")
        XCTAssertEqual(try s.captureSortante(contactId: id, canal: "imessage", texte: "Bonjour Camille, voici le mail prévu pour vous aujourd'hui.",
                                             le: Date(), ref: "imessage:4"), .aVerifier)      // même texte, mais ce n'est pas le canal prévu
        XCTAssertEqual(try s.evenement(ev)!.statut, "prepare")
        // WhatsApp : le message prêt doit dire WhatsApp
        let w = try contact("Wanda")
        let pw = try prepare(w, canal: "autre", texte: "WhatsApp à envoyer par Sacha jeu. 05/11\nBonjour Wanda, un petit mot de la part de Sacha.")
        XCTAssertEqual(try s.captureSortante(contactId: w, canal: "whatsapp", texte: "Bonjour Wanda, un petit mot de la part de Sacha.", le: Date(), ref: "whatsapp:9"),
                       .marqueEnvoye(pw))
    }

    func testReponseRecueCreeLActionRepondreDuJour() throws {
        let id = try contact("Marc Durieux", etape: "contacte", action: "Relance unique si pas de réponse", date: Dates.dans(5))
        let note = try s.actionRepondre(contactId: id)
        let c = try s.contact(id)!
        XCTAssertEqual(c.prochaineAction, "Répondre à Marc Durieux")
        XCTAssertEqual(c.prochaineDate, auj)
        XCTAssertTrue(note?.contains("Avant : « Relance unique si pas de réponse »") == true)
        XCTAssertNil(try s.actionRepondre(contactId: id))                                   // une 2e réponse : déjà posée, rien de plus
        XCTAssertEqual(try s.evenements(id).filter { $0.texte.hasPrefix("Réponse reçue") }.count, 1)
    }

    func testReponseRecueNEcraseQueVideEnvoiOuPasse() throws {
        let rdv = try contact("Rendez-vous pris", etape: "rdv", action: "Rendez-vous le jeudi à 14 h", date: Dates.dans(3))
        XCTAssertNil(try s.actionRepondre(contactId: rdv))
        XCTAssertEqual(try s.contact(rdv)!.prochaineAction, "Rendez-vous le jeudi à 14 h")
        let vide = try contact("Fiche vide", action: "", date: "")
        XCTAssertNotNil(try s.actionRepondre(contactId: vide))
        let passee = try contact("Action passée", action: "Appeler le comptable", date: "2026-10-01")
        XCTAssertNotNil(try s.actionRepondre(contactId: passee))
        let perdu = try contact("Perdu", etape: "perdu", action: "", date: "")
        XCTAssertNil(try s.actionRepondre(contactId: perdu))
        let stop = try s.enregistrer(["nom": "Stop", "espace": "kryva", "etape": "contacte", "ne_plus_contacter": true, "source": "test"]).id
        XCTAssertNil(try s.actionRepondre(contactId: stop))
    }

    // MARK: Jours fériés (04/11 : 21 fiches tombaient le 11/11, férié)

    func testFeriesFrancais() {
        XCTAssertEqual(Dates.feries(2026), ["2026-01-01", "2026-04-06", "2026-05-01", "2026-05-08", "2026-05-14", "2026-05-25",
                                            "2026-07-14", "2026-08-15", "2026-11-01", "2026-11-11", "2026-12-25"])
        XCTAssertEqual(Dates.feries(2027), ["2027-01-01", "2027-03-29", "2027-05-01", "2027-05-06", "2027-05-08", "2027-05-17",
                                            "2027-07-14", "2027-08-15", "2027-11-01", "2027-11-11", "2027-12-25"])
    }

    func testOuvresSauteLesFeries() {
        let mardi10 = Dates.date("2026-11-10")!
        XCTAssertEqual(Dates.ouvres(1, depuis: mardi10), "2026-11-12")          // le mercredi 11/11 est férié
        XCTAssertEqual(Dates.ouvres(5, depuis: Dates.date("2026-11-04")!), "2026-11-12")   // J+5 ouvrés depuis le 04/11 : 12/11, plus 11/11
        XCTAssertEqual(Dates.ouvres(1, depuis: Dates.date("2026-12-24")!), "2026-12-28")   // 25/12 férié (vendredi), puis le week-end
        XCTAssertEqual(Dates.ouvres(1, depuis: Dates.date("2027-03-26")!), "2027-03-30")   // lundi de Pâques 29/03
        XCTAssertEqual(Dates.ouvres(1, depuis: Dates.date("2026-11-05")!), "2026-11-06")   // sans férié, rien ne change
    }

    // MARK: Contrôle R3 : un prospect actif sans prochaine date

    func testControleSignaleUnProspectActifSansDate() throws {
        let sansRien = try contact("Sans rien", action: "", date: "")
        let actionSansDate = try contact("Action sans date", action: "Rappeler", date: "")
        let ok = try contact("Avec date", date: Dates.dans(3))
        let gagne = try contact("Gagné", etape: "gagne", action: "", date: "")
        let perdu = try contact("Perdu", etape: "perdu", action: "", date: "")
        let stop = try s.enregistrer(["nom": "Stop", "espace": "kryva", "etape": "contacte", "ne_plus_contacter": true, "source": "test"]).id
        let c = try s.controle()
        XCTAssertEqual(Set(c.sansDate.map(\.contactId)), [sansRien, actionSansDate])
        for id in [ok, gagne, perdu, stop] { XCTAssertFalse(c.sansDate.map(\.contactId).contains(id)) }
        XCTAssertEqual(c.total, 2)
        XCTAssertTrue(c.texte().contains("Actifs sans prochaine date (R3) (2)"))
    }

    func testStockAContacterSansDateEstListeMaisPasCompte() throws {
        let stock = try contact("Jamais contacté", etape: "a_contacter", action: "", date: "")
        let fuite = try contact("Contacté sans suite", etape: "contacte", action: "", date: "")
        let c = try s.controle()
        XCTAssertEqual(c.sansDateAContacter.map(\.contactId), [stock])
        XCTAssertEqual(c.sansDate.map(\.contactId), [fuite])
        XCTAssertEqual(c.total, 1)                                           // le stock n'entre pas dans le total (ni la notification de 7 h)
        XCTAssertTrue(c.texte().contains("Stock à contacter : 1"))
    }

    // MARK: Boucle « Relance unique » (04/11, PILOTE) : après la relance, la dernière étape, jamais une autre relance

    func testApresLaRelanceUniqueLaSuiteEstLaDerniereEtape() throws {
        let id = try contact("Relancé", action: "Relance unique si pas de réponse")
        try envoi(id)
        let c = try XCTUnwrap(try s.contact(id))
        let date = Dates.ouvres(5)
        XCTAssertEqual(c.prochaineAction, "Sans réponse au \(Dates.jjmm(date)) : classer sans suite, plus aucune relance.")
        XCTAssertEqual(c.prochaineDate, date)
        XCTAssertFalse(Libelles.estRelanceUnique(c.prochaineAction))
    }

    func testLePremierEnvoiPoseToujoursLaRelanceUnique() throws {
        let id = try contact("Premier message", action: "Écrire le premier message")
        try envoi(id)
        XCTAssertEqual(try s.contact(id)?.prochaineAction, "Relance unique si pas de réponse")
    }

    func testCEstFaitSurLaRelanceUniquePoseLaDerniereEtape() throws {
        let id = try contact("Fait à la main", action: "Relance unique si pas de réponse")
        _ = try s.actionFaite(contactId: id)
        let c = try XCTUnwrap(try s.contact(id))
        XCTAssertTrue(c.prochaineAction.hasPrefix("Sans réponse au "))
        XCTAssertTrue(c.prochaineAction.contains("classer sans suite"))
        XCTAssertEqual(c.prochaineDate, Dates.ouvres(5))
    }

    func testLaReparationPoseAussiLaDerniereEtapeApresUneRelanceUnique() throws {
        let id = try contact("A réparer", action: "Relance unique si pas de réponse")
        try s.ajouterEvenement(contactId: id, ["canal": "mail", "sens": "sortant", "type": "message", "texte": "Bonjour", "statut": "envoye"])
        // on remet l'état « ancien MCP » (l'envoi n'a pas fait avancer la fiche) pour tester le rétablissement
        try s.base.executer("UPDATE contacts SET prochaine_action = 'Relance unique si pas de réponse', prochaine_date = ? WHERE id = ?", [auj, id])
        let liste = try s.suitesARetablir()
        XCTAssertEqual(liste.first { $0.contactId == id }?.nouvelleAction.hasPrefix("Sans réponse au "), true)
    }

    // MARK: T3 (05/11) : un client « gagné » reste suivi

    func testReponseDUnClientGagneCreeLActionEtLeRendDu() throws {
        // Cas Julien Morel (freelance, gagné, production en cours) : action d'envoi datée plus tard, puis il répond.
        let id = try s.enregistrer(["nom": "Julien Morel", "espace": "freelance", "etape": "gagne",
                                    "prochaine_action": "Mail du 05/11 envoyé (visio lun. 09/11 notée). Attendre sa réponse",
                                    "prochaine_date": Dates.dans(4), "source": "test"]).id
        XCTAssertFalse(try s.dus().map(\.id).contains(id))                      // pas encore dû
        try s.ajouterEvenement(contactId: id, ["canal": "mail", "sens": "entrant", "type": "reponse", "texte": "Bonjour Sacha", "statut": "fait"])
        XCTAssertNotNil(try s.actionRepondre(contactId: id))
        let c = try XCTUnwrap(try s.contact(id))
        XCTAssertEqual(c.etape, "gagne")                                          // jamais reculé à « a répondu »
        XCTAssertEqual(c.prochaineAction, "Répondre à Julien Morel")
        XCTAssertEqual(c.prochaineDate, auj)
        XCTAssertTrue(try s.dus().map(\.id).contains(id))                        // dans les dus
        let liste = try s.listeAgent(.freelance)
        XCTAssertTrue(liste.dus.map(\.id).contains(id))                          // chez FREELANCE, l'agent de l'espace
        XCTAssertFalse(try s.dusSacha().map(\.id).contains(id))
    }

    func testClientGagneDateApparaitDansLesDus() throws {
        let id = try contact("Client daté", etape: "gagne", action: "Point sur la production", date: auj)
        XCTAssertTrue(try s.dus().map(\.id).contains(id))
        let perdu = try contact("Perdu daté", etape: "perdu", action: "Point", date: auj)
        XCTAssertFalse(try s.dus().map(\.id).contains(perdu))
    }

    func testReponseEnvoyeeAUnClientGagneNeLaisseRienDu() throws {
        let id = try contact("Client répondu", etape: "gagne", action: "Répondre à Client répondu", date: auj)
        try envoi(id)
        let c = try XCTUnwrap(try s.contact(id))
        XCTAssertEqual(c.etape, "gagne")
        XCTAssertEqual(c.prochaineAction, "Relance unique si pas de réponse")
        XCTAssertEqual(c.prochaineDate, Dates.ouvres(5))
        XCTAssertFalse(try s.dus().map(\.id).contains(id))
    }

    func testRepondreEstUnEnvoiPourUnProspectAussi() throws {
        XCTAssertTrue(Libelles.actionEstUnEnvoi("Répondre à Marc Durieux"))
        let id = try contact("Prospect répondu", etape: "repondu", action: "Répondre à Prospect répondu", date: auj)
        try envoi(id)
        XCTAssertEqual(try s.contact(id)?.prochaineAction, "Relance unique si pas de réponse")
    }

    func testUnClientGagneNEstJamaisClasseSansSuite() throws {
        let id = try contact("Client relancé", etape: "gagne", action: "Relance unique si pas de réponse")
        try envoi(id)
        let c = try XCTUnwrap(try s.contact(id))
        XCTAssertTrue(c.prochaineAction.hasPrefix("Client sans réponse au "), c.prochaineAction)
        XCTAssertFalse(Libelles.estSansSuite(c.prochaineAction))
        XCTAssertFalse(Libelles.actionEstUnEnvoi(c.prochaineAction))
        _ = try s.actionFaite(contactId: id)
        XCTAssertEqual(try s.contact(id)?.etape, "gagne")
    }

    // MARK: T27 (05/11) : « C'est fait » sur la dernière étape classe la fiche sans suite

    func testCEstFaitSurClasserSansSuiteClasseLaFichePerdue() throws {
        let id = try contact("Sans réponse", action: "Sans réponse au 12/11 : classer sans suite, plus aucune relance.", date: auj)
        let note = try s.actionFaite(contactId: id)
        let c = try XCTUnwrap(try s.contact(id))
        XCTAssertEqual(c.etape, "perdu")
        XCTAssertEqual(c.prochaineAction, "")
        XCTAssertEqual(c.prochaineDate, "")
        XCTAssertTrue(note.contains("classée sans suite"))
        XCTAssertTrue(try s.evenements(id).contains { $0.texte == note })
        XCTAssertFalse(try s.controle().sansDate.map(\.contactId).contains(id))   // plus d'orpheline (R3)
        XCTAssertFalse(try s.dus().map(\.id).contains(id))
        XCTAssertFalse(c.nePlusContacter)                                         // « ne plus contacter » reste une décision de Sacha
    }

    func testEstSansSuite() {
        XCTAssertTrue(Libelles.estSansSuite("Sans réponse au 12/11 : classer sans suite, plus aucune relance."))
        XCTAssertFalse(Libelles.estSansSuite("Relance unique si pas de réponse"))
        XCTAssertFalse(Libelles.estSansSuite("Sans réponse au 12/11 : relancer par SMS"))
    }

    func testJjmm() {
        XCTAssertEqual(Dates.jjmm("2026-11-12"), "12/11")
        XCTAssertEqual(Dates.jjmm("2026-11-12T08:00:00Z"), "12/11")
        XCTAssertEqual(Dates.jjmm(""), "")
    }

    // MARK: Piste 2 : « envoyé depuis kryva.fr »

    func testEstKryvaSeulementLeDomaineEtSesSousDomaines() {
        for a in ["equipe@kryva.fr", "Contact@KRYVA.FR", " devis@mail.kryva.fr ", "x@notif.kryva.fr"] { XCTAssertTrue(EnvoisKryva.estInterdit(a, domaines: ["kryva.fr"]), a) }
        for a in ["vous@exemple.fr", "x@notkryva.fr", "x@kryva.fr.evil.com", "kryva.fr", "", "x@kryva.com"] { XCTAssertFalse(EnvoisKryva.estInterdit(a, domaines: ["kryva.fr"]), a) }
    }

    func testLignesKryvaGardentLes48HeuresEtIgnorentLesAutresExpediteurs() {
        Reglages.remplacement = { var r = EssaiPrincipal.reglages; r.domainesInterdits = ["kryva.fr"]; return r }()
        defer { Reglages.remplacement = EssaiPrincipal.reglages }
        let maintenant = Date(timeIntervalSince1970: 1_800_000_000)
        func envoi(_ heuresAvant: Double, _ exp: String, _ a: String = "artisan@exemple.fr", _ objet: String = "Votre devis") -> EnvoiKryva {
            EnvoiKryva(ts: maintenant.timeIntervalSince1970 - heuresAvant * 3600, expediteur: exp, destinataire: a, objet: objet)
        }
        let etat = EtatEnvoisKryva(verifieLe: maintenant.timeIntervalSince1970 - 60, envois: [
            envoi(2, "contact@kryva.fr"), envoi(40, "x@mail.kryva.fr", ""), envoi(50, "contact@kryva.fr"), envoi(1, "vous@exemple.fr")])
        let l = EnvoisKryva.lignes(etat, maintenant: maintenant)
        XCTAssertEqual(l.count, 2)
        XCTAssertEqual(l[0].nom, "artisan@exemple.fr")                      // le plus récent d'abord
        XCTAssertEqual(l[1].nom, "destinataire inconnu")
        XCTAssertTrue(l[0].detail.contains("depuis contact@kryva.fr") && l[0].detail.contains("Votre devis"))
        XCTAssertTrue(EnvoisKryva.lignes(nil, maintenant: maintenant).isEmpty)
    }

    func testVerificationPerimeeApres6HeuresOuSansFichier() {
        let m = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertTrue(EnvoisKryva.perimee(nil, maintenant: m))
        XCTAssertFalse(EnvoisKryva.perimee(EtatEnvoisKryva(verifieLe: m.timeIntervalSince1970 - 3600, envois: []), maintenant: m))
        XCTAssertTrue(EnvoisKryva.perimee(EtatEnvoisKryva(verifieLe: m.timeIntervalSince1970 - 7 * 3600, envois: []), maintenant: m))
    }

    func testControleCompteLesMailsKryvaSeulementSiOnLeDemande() throws {
        Reglages.remplacement = { var r = EssaiPrincipal.reglages; r.domainesInterdits = ["kryva.fr"]; return r }()
        defer { Reglages.remplacement = EssaiPrincipal.reglages }
        _ = try contact("Avec date", date: Dates.dans(3))
        let m = Date()
        let etat = EtatEnvoisKryva(verifieLe: m.timeIntervalSince1970, envois: [
            EnvoiKryva(ts: m.timeIntervalSince1970 - 3600, expediteur: "contact@kryva.fr", destinataire: "a@b.fr", objet: "Bonjour")])
        XCTAssertEqual(try s.controle(envoisKryva: etat).total, 0)          // par défaut : aucun relevé lu (les tests ne touchent pas le vrai fichier)
        let c = try s.controle(envoisKryva: etat, verifierKryva: true, maintenant: m)
        XCTAssertEqual(c.envoyesDepuisKryva.count, 1)
        XCTAssertEqual(c.total, 1)
        XCTAssertFalse(c.verifKryvaPerimee)
        XCTAssertTrue(c.texte().contains("Mails partis d'un domaine interdit (48 h) (1)"))
        let sansReleve = try s.controle(envoisKryva: nil, verifierKryva: true, maintenant: m)
        XCTAssertTrue(sansReleve.verifKryvaPerimee)
        XCTAssertEqual(sansReleve.total, 0)                                  // pas de relevé : pas de faux positif, mais le texte le dit
        XCTAssertTrue(sansReleve.texte().contains("pas à jour"))
    }

    func testEtatEnvoisKryvaSeRelitTelQuEcrit() throws {
        let f = FileManager.default.temporaryDirectory.appendingPathComponent("envois-kryva-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: f) }
        XCTAssertNil(EnvoisKryva.lire(f))
        let e = EtatEnvoisKryva(verifieLe: 1_800_000_000, envois: [EnvoiKryva(ts: 1_799_999_000, expediteur: "a@kryva.fr", destinataire: "b@c.fr", objet: "Objet é")])
        EnvoisKryva.ecrire(e, f)
        XCTAssertEqual(EnvoisKryva.lire(f), e)
    }
}

final class ParcoursTests: XCTestCase {
    private func c(_ etape: String = "a_contacter", action: String = "") -> Contact {
        var x = Contact(id: "c1"); x.etape = etape; x.prochaineAction = action; x.creeLe = "2026-11-01T08:00:00Z"; x.source = "linkedin"
        return x
    }
    private func e(_ type: String, _ sens: String = "sortant", _ statut: String = "envoye", canal: String = "linkedin", le: String,
                   texte: String = "") -> Evenement {
        var x = Evenement(id: UUID().uuidString, contactId: "c1", le: le)
        x.type = type; x.sens = sens; x.statut = statut; x.canal = canal; x.texte = texte
        return x
    }
    private func titres(_ l: [EtapeParcours]) -> [String] { l.map(\.cle) }
    private func etat(_ l: [EtapeParcours], _ cle: String) -> EtapeParcours.Etat { l.first { $0.cle == cle }!.etat }

    func testProspectSansRienEstEnBaseEtLeMessageEstLaSuite() {
        let l = Parcours.etapes(contact: c(), fil: [], aujourdhui: "2026-11-04")
        XCTAssertEqual(titres(l), ["base", "message", "reponse", "relance", "fin"])
        XCTAssertEqual(etat(l, "base"), .fait)
        XCTAssertEqual(etat(l, "message"), .courante)
        XCTAssertEqual(l.first { $0.cle == "message" }?.detail, "à préparer")
    }

    func testInvitationEnvoyeeOnAttendLAcceptation() {
        let fil = [e("invitation", le: "2026-11-02T09:00:00Z")]
        let l = Parcours.etapes(contact: c("contacte"), fil: fil, aujourdhui: "2026-11-04")
        XCTAssertEqual(titres(l), ["base", "invitation", "acceptee", "message", "reponse", "relance", "fin"])
        XCTAssertEqual(etat(l, "invitation"), .fait)
        XCTAssertEqual(etat(l, "acceptee"), .courante)
        XCTAssertTrue(l.first { $0.cle == "acceptee" }!.attente)
        XCTAssertEqual(l.first { $0.cle == "acceptee" }?.detail, "depuis 2 j")
    }

    func testAccepteeMessageEnvoyeOnAttendLaReponse() {
        let fil = [e("invitation", le: "2026-11-02T09:00:00Z"),
                   e("note", "interne", "fait", le: "2026-11-03T09:00:00Z", texte: "Invitation acceptée"),
                   e("message", le: "2026-11-03T10:00:00Z")]
        let l = Parcours.etapes(contact: c("contacte"), fil: fil, aujourdhui: "2026-11-04")
        XCTAssertEqual(etat(l, "acceptee"), .fait)
        XCTAssertEqual(etat(l, "message"), .fait)
        XCTAssertEqual(etat(l, "reponse"), .courante)
        XCTAssertTrue(l.first { $0.cle == "reponse" }!.attente)
        XCTAssertEqual(etat(l, "relance"), .aVenir)
    }

    func testReponseSauteLaRelanceEtLeMessagePretSeVoit() {
        let fil = [e("message", canal: "sms", le: "2026-11-02T09:00:00Z"),
                   e("reponse", "entrant", "fait", canal: "sms", le: "2026-11-03T09:00:00Z")]
        let l = Parcours.etapes(contact: c("repondu"), fil: fil, aujourdhui: "2026-11-04")
        XCTAssertEqual(etat(l, "reponse"), .fait)
        XCTAssertEqual(etat(l, "relance"), .saute)
        XCTAssertEqual(etat(l, "fin"), .courante)
        let pret = Parcours.etapes(contact: c(), fil: [e("message", "sortant", "prepare", canal: "sms", le: "2026-11-04T12:52:00Z")],
                                   aujourdhui: "2026-11-04")
        XCTAssertEqual(etat(pret, "message"), .courante)
        XCTAssertEqual(pret.first { $0.cle == "message" }?.detail, "prêt, à envoyer")
    }

    func testRelanceFaiteEtFinDeParcours() {
        let fil = [e("message", canal: "mail", le: "2026-10-20T09:00:00Z"), e("message", canal: "mail", le: "2026-10-27T09:00:00Z")]
        let l = Parcours.etapes(contact: c("contacte"), fil: fil, aujourdhui: "2026-11-04")
        XCTAssertEqual(etat(l, "relance"), .fait)
        XCTAssertEqual(etat(l, "reponse"), .courante)
        let gagne = Parcours.etapes(contact: c("gagne"), fil: fil, aujourdhui: "2026-11-04")
        XCTAssertEqual(gagne.last?.titre, "Gagné")
        XCTAssertFalse(gagne.contains { $0.etat == .courante })
    }

}
