// Contacts, envois et fil en plusieurs langues (10/11) : en anglais et en espagnol, les textes d'écran de Shared/ (libellés,
// parcours, remises du Facteur, refus d'envoi, erreurs Gmail et Mail, phrases du fil) ne contiennent aucun mot français ;
// en français rien ne change ; ce qui s'écrit dans la base ou part vers un agent reste en français, quelle que soit la langue.
import XCTest

final class LangueContactsTests: XCTestCase {
    var chemin: URL!
    var s: Stockage!

    override func setUpWithError() throws {
        Loc.dossierBundle = Bundle(for: Self.self).bundleURL
        chemin = FileManager.default.temporaryDirectory.appendingPathComponent("pilote-langue-contacts-\(UUID().uuidString).sqlite")
        s = Stockage(base: try Base(chemin: chemin))
    }

    override func tearDown() {
        Loc.dossierBundle = nil
        Loc.langue = "fr"
        for suffixe in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: chemin.path + suffixe) }
    }

    /// Données d'exemple volontairement françaises : noms, entreprise, nom de session. Jamais traduites.
    private let donnees = ["Hugo Bernard", "Bernard Bâtiment", "Domaine Test", "KRYVA · Ventes"]

    private func sansFrancais(_ textes: [String], _ langue: String, _ contexte: String = "", file: StaticString = #filePath, line: UInt = #line) {
        for t in textes {
            XCTAssertEqual(ContientDuFrancais(t, langue: langue, ignorer: donnees), [], "\(langue) \(contexte) : « \(t) »",
                           file: file, line: line)
        }
    }

    /// Le détecteur lui-même : il voit le français, laisse passer les données d'exemple et les mots espagnols qui lui ressemblent.
    func testLeDetecteurVoitLeFrancais() {
        XCTAssertFalse(ContientDuFrancais("Le message est envoyé pour Hugo", langue: "en").isEmpty)
        XCTAssertTrue(ContientDuFrancais("Message sent to Hugo", langue: "en").isEmpty)
        XCTAssertTrue(ContientDuFrancais("Bernard Bâtiment : le client", langue: "en", ignorer: ["Bernard Bâtiment", "le client"]).isEmpty)
        XCTAssertTrue(ContientDuFrancais("Respondió en la cita", langue: "es").isEmpty)
        XCTAssertFalse(ContientDuFrancais("Respondió en la cita", langue: "en").isEmpty)   // « en » et « la » n'existent pas en anglais
    }

    // MARK: Libellés

    func testLibellesSansFrancais() {
        for langue in ["en", "es"] {
            Loc.langue = langue
            let tous = Libelles.espaces + Libelles.types + Libelles.etapes + Libelles.canaux + Libelles.typesEvenement
            sansFrancais(tous.map(\.1), langue, "libellé")
        }
    }

    func testLibellesTraduitsEtValeursStockeesIntactes() {
        Loc.langue = "en"
        XCTAssertEqual(Libelles.etape("repondu"), "Replied")
        XCTAssertEqual(Libelles.etape("a_contacter"), "To contact")
        XCTAssertEqual(Libelles.canal("visio"), "Video call")
        XCTAssertEqual(Libelles.type("negoce"), "Merchant")
        XCTAssertEqual(Libelles.typeEvenement("rdv"), "Meeting")
        Loc.langue = "es"
        XCTAssertEqual(Libelles.etape("repondu"), "Respondió")
        XCTAssertEqual(Libelles.canal("visio"), "Videollamada")
        XCTAssertEqual(Libelles.typeEvenement("rdv"), "Cita")
        // Les clés (valeurs stockées) ne changent jamais ; une clé inconnue revient telle quelle.
        for langue in ["fr", "en", "es"] {
            Loc.langue = langue
            XCTAssertEqual(Libelles.etapes.map(\.0), ["a_contacter", "contacte", "repondu", "rdv", "gagne", "perdu"])
            XCTAssertEqual(Libelles.etape("inconnu"), "inconnu")
        }
    }

    func testFrancaisInchange() {
        Loc.langue = "fr"
        XCTAssertEqual(Libelles.etape("repondu"), "A répondu")
        XCTAssertEqual(Libelles.etape("rdv"), "Rendez-vous")
        XCTAssertEqual(Libelles.canal("visio"), "Visio")
        XCTAssertEqual(RaisonPasEnvoye.plusDActualite.libelle, "Plus d'actualité")
        XCTAssertEqual(Gmail.ErreurGmail.nonConnecte.errorDescription, "Gmail n'est pas encore connecté à Pilote.")
    }

    func testRaisonsPasEnvoye() {
        for langue in ["en", "es"] {
            Loc.langue = langue
            sansFrancais(RaisonPasEnvoye.allCases.map(\.libelle), langue, "raison")
            // Le rawValue est ce qu'on écrit au fil : toujours le français.
            XCTAssertEqual(RaisonPasEnvoye.pasLeMoment.rawValue, "Pas le moment")
        }
        Loc.langue = "en"
        XCTAssertEqual(RaisonPasEnvoye.texteAChanger.libelle, "Text needs changes")
    }

    // MARK: Le dernier échange

    func testDernierEchange() {
        let cas = [
            DernierEchange(le: "2026-11-03T09:00:00Z", canal: "sms", sens: "entrant", type: "reponse", texte: "ok"),
            DernierEchange(le: "2026-11-03T09:00:00Z", canal: "mail", sens: "sortant", type: "message", texte: "ok"),
            DernierEchange(le: "2026-11-03T09:00:00Z", canal: "autre", sens: "sortant", type: "invitation", texte: "ok"),
            DernierEchange(le: "2026-11-03T09:00:00Z", canal: "visio", sens: "interne", type: "rdv", texte: "ok"),
        ]
        for langue in ["en", "es"] {
            Loc.langue = langue
            sansFrancais(cas.map(\.resumeAffiche), langue, "dernier échange")
        }
        Loc.langue = "en"
        XCTAssertTrue(cas[0].resumeAffiche.hasPrefix("Replied (SMS) on "), cas[0].resumeAffiche)
        XCTAssertTrue(cas[3].resumeAffiche.hasPrefix("Meeting on "), cas[3].resumeAffiche)
        Loc.langue = "es"
        XCTAssertTrue(cas[0].resumeAffiche.hasPrefix("Respondió (SMS) el "), cas[0].resumeAffiche)
        // `resume` (Videos.swift) alimente les consignes envoyées aux agents : il reste en français.
        XCTAssertTrue(cas[0].resume.hasPrefix("A répondu (SMS) le "), cas[0].resume)
    }

    // MARK: Parcours d'un prospect

    private func contactEtFil() throws -> (Contact, [Evenement]) {
        let c = try s.enregistrer(["nom": "Domaine Test", "espace": "freelance", "linkedin": "https://www.linkedin.com/in/test",
                                   "source": "test"])
        try s.ajouterEvenement(contactId: c.id, ["canal": "linkedin", "sens": "sortant", "type": "invitation", "texte": "Invitation",
                                                 "statut": "envoye", "le": "2026-10-28T08:00:00Z"])
        return (c, [])
    }

    func testParcours() throws {
        let (c, _) = try contactEtFil()
        var photos: [(Contact, [Evenement])] = []
        func photo() throws { photos.append((try s.contact(c.id)!, try s.evenements(c.id))) }
        let mercredi = Dates.iso.date(from: "2026-11-04T07:00:00Z")!
        _ = try s.invitationPasEncore(c.id, maintenant: mercredi)            // « pas encore » : l'invitation attend
        try photo()
        // Invitation acceptée, message envoyé, message prêt, réponse, rendez-vous : chaque étape du parcours.
        try s.invitationAcceptee(c.id)
        try s.ajouterEvenement(contactId: c.id, ["canal": "linkedin", "sens": "sortant", "type": "message", "texte": "Merci",
                                                 "statut": "envoye", "le": "2026-11-05T08:00:00Z"])
        try photo()
        try s.ajouterEvenement(contactId: c.id, ["canal": "linkedin", "sens": "sortant", "type": "message", "texte": "Relance",
                                                 "statut": "prepare"])
        try photo()
        try s.ajouterEvenement(contactId: c.id, ["canal": "sms", "sens": "entrant", "type": "reponse", "texte": "Oui", "statut": "fait",
                                                 "le": "2026-11-06T08:00:00Z"])
        try s.ajouterEvenement(contactId: c.id, ["canal": "visio", "sens": "interne", "type": "rdv", "texte": "RDV", "statut": "fait",
                                                 "le": "2026-11-07T08:00:00Z"])
        try photo()
        for langue in ["en", "es"] {
            Loc.langue = langue
            for (contact, fil) in photos {
                let etapes = Parcours.etapes(contact: contact, fil: fil, aujourdhui: "2026-11-09")
                XCTAssertGreaterThan(etapes.count, 3)
                // `detail` de l'étape « En base » est la source du contact : une donnée.
                sansFrancais(etapes.flatMap { [$0.titre, $0.cle == "base" ? "" : $0.detail] }, langue, "parcours")
            }
        }
    }

    /// Couplage corrigé : la note « Invitation acceptée » est écrite en français dans la base et relue par `hasPrefix` :
    /// le parcours la reconnaît quelle que soit la langue de l'app.
    func testParcoursReconnaitLInvitationAccepteeEnAnglais() throws {
        let (c, _) = try contactEtFil()
        Loc.langue = "en"
        try s.invitationAcceptee(c.id)
        XCTAssertEqual(try s.evenements(c.id).first?.texte, "Invitation acceptée")
        let etapes = Parcours.etapes(contact: try s.contact(c.id)!, fil: try s.evenements(c.id), aujourdhui: "2026-11-09")
        let acceptee = try XCTUnwrap(etapes.first { $0.cle == "acceptee" })
        XCTAssertEqual(acceptee.etat, .fait)
        XCTAssertEqual(acceptee.titre, "Accepted")
        XCTAssertEqual(try XCTUnwrap(etapes.first { $0.cle == "base" }).titre, "In database")
    }

    func testParcoursDetailsDAttente() throws {
        let (c, _) = try contactEtFil()
        let mercredi = Dates.iso.date(from: "2026-11-04T07:00:00Z")!
        _ = try s.invitationPasEncore(c.id, maintenant: mercredi)
        Loc.langue = "en"
        let etapes = Parcours.etapes(contact: try s.contact(c.id)!, fil: try s.evenements(c.id), aujourdhui: "2026-11-09")
        XCTAssertEqual(try XCTUnwrap(etapes.first { $0.cle == "acceptee" }).detail, "not yet ×1")
        Loc.langue = "es"
        let es = Parcours.etapes(contact: try s.contact(c.id)!, fil: try s.evenements(c.id), aujourdhui: "2026-11-09")
        XCTAssertEqual(try XCTUnwrap(es.first { $0.cle == "acceptee" }).detail, "aún no ×1")
    }

    // MARK: Ce qui s'écrit dans la base reste en français

    func testNotesDuFilEcritesEnFrancais() throws {
        let c = try s.enregistrer(["nom": "Hugo Bernard", "espace": "kryva", "etape": "repondu", "email": "hugo@exemple.fr",
                                   "prochaine_action": "Répondre à Hugo", "prochaine_date": Dates.aujourdhui()])
        let e = try s.ajouterEvenement(contactId: c.id, ["canal": "mail", "sens": "sortant", "type": "message", "texte": "Bonjour",
                                                         "statut": "prepare", "objet": "Votre abonnement KRYVA"])
        for langue in ["en", "es"] {
            Loc.langue = langue
            let note = try s.pasEnvoye(evenementId: e.id, raison: .texteAChanger, precision: "plus court")
            // Le libellé de la raison (rawValue) et le canal sont ceux de la base : « Mail », « texte à changer ».
            XCTAssertEqual(note, "Pas envoyé (Mail) : texte à changer — plus court", langue)
            let fait = try s.pasFait(contactId: c.id, raison: .pasLeMoment, au: "2026-11-20")
            XCTAssertTrue(fait.hasPrefix("Pas fait (pas le moment), revu le 20 nov"), "\(langue) : \(fait)")
        }
    }

    func testRefusEcritsEnFrancaisPourLaBaseEtLesAgents() {
        Loc.langue = "en"
        XCTAssertEqual(EnvoiPilote.refus(nil, nil, expediteur: nil, motDePassePresent: false, francais: true),
                       ["message introuvable (ou supprimé)"])
        XCTAssertEqual(EnvoiPilote.refus(nil, nil, expediteur: nil, motDePassePresent: false), ["message not found (or deleted)"])
        Loc.langue = "es"
        XCTAssertEqual(EnvoiPilote.refus(nil, nil, expediteur: nil, motDePassePresent: false), ["mensaje no encontrado (o eliminado)"])
    }

    // MARK: Refus d'envoi

    private func refusDivers() -> [String] {
        let contact = Contact(id: "c1", nom: "Hugo Bernard", entreprise: "Bernard Bâtiment", email: "enrico@kryva.fr",
                              nePlusContacter: true)
        let sansAdresse = Contact(id: "c2", nom: "Hugo Bernard", email: "")
        let illisible = Contact(id: "c3", nom: "Hugo Bernard", email: "a@b.fr, c@d.fr")
        var tous: [String] = []
        for (e, c, de, mdp) in [
            (Evenement(id: "e1", contactId: "c1", le: "2026-11-03T09:00:00Z", canal: "sms", sens: "entrant", type: "reponse",
                       texte: "", statut: "envoye", objet: "", condition: "after the deposit test"), contact, "moi@kryva.fr", false),
            (Evenement(id: "e2", contactId: "c2", le: "", canal: "mail", sens: "sortant", type: "message", texte: "Hi",
                       statut: "annule", objet: "Subject"), sansAdresse, "moi@gmail.com", false),
            (Evenement(id: "e3", contactId: "c3", le: "", canal: "mail", sens: "sortant", type: "message", texte: "Hi",
                       statut: "prepare", objet: "Subject"), illisible, "moi@gmail.com", true),
        ] {
            tous += EnvoiPilote.refus(e, c, expediteur: de, motDePassePresent: mdp)
        }
        tous += EnvoiPilote.refus(nil, nil, expediteur: nil, motDePassePresent: false)
        tous += EnvoiPilote.refus(Evenement(id: "e4", contactId: "x", le: "", canal: "mail", sens: "sortant", type: "message", texte: "Hi",
                                            statut: "prepare", objet: "Subject"), nil, expediteur: nil, motDePassePresent: false)
        return tous
    }

    func testRefusSansFrancais() {
        for langue in ["en", "es"] {
            Loc.langue = langue
            let refus = refusDivers()
            XCTAssertGreaterThan(refus.count, 10)
            sansFrancais(refus, langue, "refus")
        }
    }

    func testRefusCondition() {
        let e = Evenement(id: "e1", contactId: "c1", le: "", canal: "mail", sens: "sortant", type: "message", texte: "Hi",
                          statut: "prepare", objet: "Subject", condition: "after the deposit test")
        for langue in ["en", "es"] {
            Loc.langue = langue
            sansFrancais([Stockage.refusCondition(e), EnvoiPilote.refusCanal(Evenement(id: "e2", contactId: "c", le: "", canal: "sms"))!],
                         langue, "refus condition")
        }
        Loc.langue = "fr"
        XCTAssertTrue(Stockage.refusCondition(e).hasPrefix("Pas envoyé : la condition n'est pas cochée (« after the deposit test »)"))
    }

    // MARK: Gmail, Mail

    func testErreursGmailEtMail() {
        let gmail: [Gmail.ErreurGmail] = [.nonConnecte, .refuse, .depuisKryva("moi@kryva.fr"), .autorisationTrousseau, .echec("535 auth")]
        let mail: [Mail.ErreurMail] = [.nonAutorise, .echec("boom"), .echec("erreur 4401"), .pasDeGmail]
        for langue in ["en", "es"] {
            Loc.langue = langue
            sansFrancais(gmail.compactMap(\.errorDescription) + mail.compactMap(\.errorDescription), langue, "erreur")
        }
        Loc.langue = "en"
        XCTAssertEqual(Gmail.ErreurGmail.refuse.errorDescription, "Gmail rejected the app password. Create a new one and reconnect Gmail.")
        Loc.langue = "es"
        XCTAssertEqual(Mail.ErreurMail.pasDeGmail.errorDescription,
                       "No hay ninguna cuenta de Gmail en Mail. Añádela en Mail › Ajustes › Cuentas.")
    }

    // MARK: Remises du Facteur

    func testRemisesDuFacteur() {
        let t = Date(timeIntervalSince1970: 1_731_000_000)
        let remises: [Facteur.Remise?] = [
            nil,
            Facteur.Remise(etat: .pret, le: t, par: "", raison: ""),
            Facteur.Remise(etat: .retire, le: t, par: "", raison: ""),
            Facteur.Remise(etat: .emis, le: t, par: "", raison: ""),
            Facteur.Remise(etat: .remis, le: t, par: "veille", raison: ""),
            Facteur.Remise(etat: .remis, le: t, par: "facteur", raison: ""),
            Facteur.Remise(etat: .echec, le: t, par: "", raison: "timeout"),
        ]
        for langue in ["en", "es"] {
            Loc.langue = langue
            for r in remises {
                for veille in [nil, t] as [Date?] {
                    let texte = Facteur.libelle(r, pour: "KRYVA · Ventes", veille: veille).texte
                    sansFrancais([texte], langue, "remise")
                }
            }
        }
        Loc.langue = "en"
        XCTAssertEqual(Facteur.libelle(remises[2], pour: "PILOTE", veille: nil).texte, "not sent")
        Loc.langue = "es"
        XCTAssertEqual(Facteur.libelle(remises[2], pour: "PILOTE", veille: nil).texte, "no enviado")
    }

    // MARK: Pluriels et noms

    func testContactSansNomEtTitre() {
        for langue in ["en", "es"] {
            Loc.langue = langue
            sansFrancais([Contact(id: "c").titre, Contact(id: "c", entreprise: "Bernard Bâtiment").titre], langue, "titre")
        }
        Loc.langue = "en"
        XCTAssertEqual(Contact(id: "c").titre, "Unnamed")
    }
}
