// Envoi sur « envoie » (05/11, étape 1 de PILOTE) : `pilote a-envoyer` et `pilote envoie <id>`. Sélection des messages,
// chaque refus (rien ne part, rien n'est écrit), essai sans écriture, envoi = même écriture que le bouton de l'app.
// L'envoi est toujours un faux (compteur) : aucun mail, ni trousseau, ni Mail, ni réseau.
import XCTest

final class EnvoiPiloteTests: XCTestCase {
    var chemin: URL!
    var s: Stockage!
    /// Ce que le faux a « envoyé » : (à, objet, texte, reponse_a).
    var envois: [(a: String, objet: String, texte: String, reponseA: String)] = []
    var de: String? = "vous@exemple.fr"
    var mdp = true
    var dernierRecu: () throws -> String? = { nil }

    var outils: OutilsEnvoi {
        OutilsEnvoi(expediteur: { [unowned self] in self.de },
                    motDePassePresent: { [unowned self] _ in self.mdp },
                    dernierRecu: { [unowned self] _, _ in try self.dernierRecu() },
                    envoyer: { [unowned self] a, o, t, r in self.envois.append((a, o, t, r)); return "faux-\(self.envois.count)@pilote.essai" })
    }

    override func setUpWithError() throws {
        chemin = FileManager.default.temporaryDirectory.appendingPathComponent("pilote-envoi-\(UUID().uuidString).sqlite")
        s = Stockage(base: try Base(chemin: chemin))
        envois = []
        Reglages.remplacement = { var r = EssaiPrincipal.reglages; r.domainesInterdits = ["kryva.fr"]; return r }()
    }

    override func tearDown() {
        Reglages.remplacement = EssaiPrincipal.reglages
        for suffixe in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: chemin.path + suffixe) }
    }

    private func contact(email: String = "hugo@exemple.fr", stop: Bool = false) throws -> String {
        try s.enregistrer(["nom": "Hugo Bernard", "entreprise": "Bernard Bâtiment", "espace": "kryva", "etape": "repondu",
                           "email": email, "ne_plus_contacter": stop, "prochaine_action": "Répondre à Hugo",
                           "prochaine_date": Dates.aujourdhui(), "source": "test"]).id
    }

    @discardableResult
    private func prepare(_ contactId: String, canal: String = "mail", objet: String = "Votre abonnement KRYVA",
                         texte: String = "Bonjour Hugo,\nOn a bien noté votre demande.\nSacha, de l'équipe KRYVA",
                         statut: String = "prepare", reponseA: String = "", condition: String = "") throws -> String {
        var champs: [String: Any] = ["canal": canal, "sens": "sortant", "type": "message", "texte": texte, "statut": statut,
                                     "par": "Claude", "objet": objet]
        if !reponseA.isEmpty { champs["reponse_a"] = reponseA }
        if !condition.isEmpty { champs["condition"] = condition }
        return try s.ajouterEvenement(contactId: contactId, champs).id
    }

    /// Refus attendu : l'erreur dit la raison, rien n'est parti, l'événement et la fiche n'ont pas bougé.
    private func verifierRefus(_ e: String, contient attendu: String, essai: Bool = false, empreinte: String? = nil,
                               file: StaticString = #filePath, line: UInt = #line) throws {
        let avant = try s.evenement(e), ficheAvant = try avant.flatMap { try s.contact($0.contactId) }
        XCTAssertThrowsError(try EnvoiPilote.envoyer(e, stock: s, outils: outils, essai: essai, empreinte: empreinte), file: file, line: line) { err in
            guard let r = err as? RefusEnvoi else { return XCTFail("refus attendu, reçu \(err)", file: file, line: line) }
            XCTAssertTrue(r.raisons.contains { $0.contains(attendu) }, "raisons : \(r.raisons)", file: file, line: line)
            XCTAssertTrue(r.description.contains("rien n'est parti"), file: file, line: line)
        }
        XCTAssertTrue(envois.isEmpty, "le faux n'aurait jamais dû être appelé", file: file, line: line)
        XCTAssertEqual(try s.evenement(e), avant, file: file, line: line)
        XCTAssertEqual(try avant.flatMap { try s.contact($0.contactId) }, ficheAvant, file: file, line: line)
    }

    // MARK: Sélection (a-envoyer)

    func testLaListeNeGardeQueLesMessagesPrepare() throws {
        let c = try contact()
        let mail = try prepare(c)
        let dm = try prepare(c, canal: "linkedin", objet: "")
        try prepare(c, statut: "a_valider")
        try prepare(c, statut: "envoye")
        let annule = try prepare(c)
        try s.marquer(evenementId: annule, statut: "annule")
        let supprime = try prepare(c)
        try s.supprimerEvenement(supprime)
        let cond = try prepare(c, condition: "après le test de l'acompte")

        let l = try EnvoiPilote.aEnvoyer(s, outils: outils)
        XCTAssertEqual(l.map(\.evenementId), [mail, dm, cond])
        let m = try XCTUnwrap(l.first)
        XCTAssertEqual(m.id, String(mail.prefix(8)))
        XCTAssertEqual(m.contact, "Hugo Bernard (Bernard Bâtiment)")
        XCTAssertEqual(m.canal, "mail")
        XCTAssertEqual(m.objet, "Votre abonnement KRYVA")
        XCTAssertEqual(m.debut, "Bonjour Hugo, On a bien noté votre demande. Sacha, de l'équipe KRYVA")
        XCTAssertEqual(m.conditionEtat, "aucune")
        XCTAssertTrue(m.envoyable)
        XCTAssertEqual(m.refus, [])
        // un DM : pas envoyable, et seule la raison du canal compte
        XCTAssertFalse(l[1].envoyable)
        XCTAssertEqual(l[1].refus.count, 1)
        XCTAssertTrue(l[1].refus[0].hasPrefix("canal « linkedin »"))
        // condition à cocher, puis cochée
        XCTAssertEqual(l[2].conditionEtat, "à cocher")
        XCTAssertFalse(l[2].envoyable)
        try s.conditionRemplie(evenementId: cond, par: "Sacha")
        let apres = try XCTUnwrap(try EnvoiPilote.aEnvoyer(s, outils: outils).first { $0.evenementId == cond })
        XCTAssertTrue(apres.conditionEtat.hasPrefix("cochée le "))
        XCTAssertTrue(apres.envoyable)
        XCTAssertTrue(envois.isEmpty)
    }

    func testLaListeDitPourquoiUnMailNePartiraitPas() throws {
        let c = try contact()
        try prepare(c)
        mdp = false
        let l = try EnvoiPilote.aEnvoyer(s, outils: outils)
        XCTAssertFalse(l[0].envoyable)
        XCTAssertTrue(l[0].refus.contains { $0.contains("mot de passe d'application Gmail absent") })
    }

    // MARK: Refus

    func testRefusConditionNonCochee() throws {
        let e = try prepare(try contact(), condition: "après le test de l'acompte sur un vrai devis")
        try verifierRefus(e, contient: "condition pas cochée")
        try verifierRefus(e, contient: "condition pas cochée", essai: true)
    }

    func testRefusCanalPasMail() throws {
        try verifierRefus(try prepare(try contact(), canal: "sms"), contient: "canal « sms », pas « mail »")
    }

    func testRefusObjetVide() throws {
        try verifierRefus(try prepare(try contact(), objet: "  "), contient: "objet vide")
    }

    func testRefusNePlusContacter() throws {
        try verifierRefus(try prepare(try contact(stop: true)), contient: "« ne plus contacter »")
    }

    func testRefusExpediteurKryva() throws {
        let e = try prepare(try contact())
        de = "contact@kryva.fr"
        try verifierRefus(e, contient: "expéditeur dans un domaine interdit")
        de = "sacha@notif.kryva.fr"
        try verifierRefus(e, contient: "expéditeur dans un domaine interdit")
    }

    func testRefusDestinataireKryva() throws {
        try verifierRefus(try prepare(try contact(email: "demo@kryva.fr")), contient: "destinataire dans un domaine interdit")
    }

    func testRefusDejaEnvoye() throws {
        try verifierRefus(try prepare(try contact(), statut: "envoye"), contient: "déjà envoyé")
    }

    func testRefusStatutPasPrepare() throws {
        let c = try contact()
        try verifierRefus(try prepare(c, statut: "a_valider"), contient: "statut « a_valider », pas « prepare »")
        try verifierRefus(try prepare(c, statut: "a_refaire"), contient: "statut « a_refaire »")
    }

    func testRefusMotDePasseAbsent() throws {
        let e = try prepare(try contact())
        mdp = false
        try verifierRefus(e, contient: "mot de passe d'application Gmail absent")
    }

    func testRefusGmailPasConnecte() throws {
        let e = try prepare(try contact())
        de = nil
        try verifierRefus(e, contient: "Gmail n'est pas connecté")
    }

    func testRefusSansAdresseOuAdresseIllisible() throws {
        try verifierRefus(try prepare(try contact(email: "")), contient: "pas d'adresse mail")
        try verifierRefus(try prepare(try contact(email: "a@x.fr, b@y.fr")), contient: "adresse mail illisible")
    }

    func testRefusIdentifiantIllisibleOuInconnu() throws {
        XCTAssertThrowsError(try EnvoiPilote.envoyer("abc", stock: s, outils: outils, essai: true))
        XCTAssertThrowsError(try EnvoiPilote.envoyer("0000000000", stock: s, outils: outils, essai: false)) { err in
            XCTAssertTrue((err as? RefusEnvoi)?.raisons.first?.contains("introuvable") ?? false)
        }
        XCTAssertTrue(envois.isEmpty)
    }

    // MARK: Essai et envoi

    func testEssaiNEnvoieNiNEcritRien() throws {
        let c = try contact()
        let e = try prepare(c, reponseA: "CAFE@icloud.com")
        let avant = try s.evenement(e), fiche = try s.contact(c), fil = try s.evenements(c)
        let r = try EnvoiPilote.envoyer(String(e.prefix(8)), stock: s, outils: outils, essai: true)   // id court
        XCTAssertTrue(r.essai)
        XCTAssertFalse(r.envoye)
        XCTAssertEqual(r.messageId, "")
        XCTAssertEqual(r.mail.de, "vous@exemple.fr")
        XCTAssertEqual(r.mail.a, "hugo@exemple.fr")
        XCTAssertEqual(r.mail.objet, "Re: Votre abonnement KRYVA")          // comme l'app : « Re: » si reponse_a
        XCTAssertEqual(r.mail.entetes, ["From: \(Gmail.nomExpediteur) <vous@exemple.fr>", "To: <hugo@exemple.fr>",
                                        "Subject: Re: Votre abonnement KRYVA", "In-Reply-To: <CAFE@icloud.com>", "References: <CAFE@icloud.com>"])
        XCTAssertEqual(r.mail.texte, avant?.texte)
        XCTAssertTrue(r.apercu.hasPrefix("ESSAI : rien n'est envoyé ni écrit."))
        XCTAssertTrue(r.apercu.contains("Bonjour Hugo,\nOn a bien noté votre demande."))
        XCTAssertTrue(envois.isEmpty)
        XCTAssertEqual(try s.evenement(e), avant)
        XCTAssertEqual(try s.contact(c), fiche)
        XCTAssertEqual(try s.evenements(c), fil)
    }

    func testEnvoiCommeLeBoutonDeLApp() throws {
        let c = try contact()
        let e = try prepare(c, reponseA: "<CAFE@icloud.com>")
        let essai = try EnvoiPilote.envoyer(e, stock: s, outils: outils, essai: true)
        let r = try EnvoiPilote.envoyer(e, stock: s, outils: outils, essai: false, empreinte: essai.mail.empreinte)
        XCTAssertTrue(r.envoye)
        XCTAssertEqual(envois.count, 1)
        XCTAssertEqual(envois[0].a, "hugo@exemple.fr")
        XCTAssertEqual(envois[0].objet, "Re: Votre abonnement KRYVA")
        XCTAssertEqual(envois[0].texte, "Bonjour Hugo,\nOn a bien noté votre demande.\nSacha, de l'équipe KRYVA")
        XCTAssertEqual(envois[0].reponseA, "<CAFE@icloud.com>")
        let apres = try XCTUnwrap(try s.evenement(e))
        XCTAssertEqual(apres.statut, "envoye")
        XCTAssertEqual(apres.messageId, "faux-1@pilote.essai")
        XCTAssertEqual(apres.objet, "Re: Votre abonnement KRYVA")
        XCTAssertEqual(apres.reponseA, "<CAFE@icloud.com>")
        // la suite de la routine est posée, comme après le bouton (marquer → apresEnvoi)
        let fiche = try XCTUnwrap(try s.contact(c))
        XCTAssertEqual(fiche.prochaineAction, "Relance unique si pas de réponse")
        XCTAssertEqual(fiche.prochaineDate, Dates.ouvres(5, depuis: Dates.date(apres.le) ?? Date()))
        // la même chose écrite par le chemin de l'app (EnvoiPilote.finaliser) donne le même événement
        let e2 = try prepare(c, reponseA: "<CAFE@icloud.com>")
        try EnvoiPilote.finaliser(s, evenementId: e2, texte: envois[0].texte, objet: envois[0].objet, reponseA: envois[0].reponseA,
                                  messageId: "faux-1@pilote.essai")
        let b = try XCTUnwrap(try s.evenement(e2))
        XCTAssertEqual([b.statut, b.objet, b.reponseA, b.messageId, b.texte], [apres.statut, apres.objet, apres.reponseA, apres.messageId, apres.texte])
        // « envoie » une deuxième fois : refusé, rien ne repart
        envois = []
        try verifierRefus(e, contient: "déjà envoyé")
    }

    func testEmpreinteChangeeDepuisLEssai() throws {
        let e = try prepare(try contact())
        let essai = try EnvoiPilote.envoyer(e, stock: s, outils: outils, essai: true)
        try s.modifierEvenement(e, ["texte": "Un autre texte, jamais montré à Sacha."])
        try verifierRefus(e, contient: "le mail a changé depuis l'essai", empreinte: essai.mail.empreinte)
    }

    func testConditionCocheeLEnvoiPart() throws {
        let e = try prepare(try contact(), condition: "après la réponse de l'expert-comptable")
        try s.conditionRemplie(evenementId: e, par: "Sacha")
        XCTAssertTrue(try EnvoiPilote.envoyer(e, stock: s, outils: outils, essai: false).envoye)
        XCTAssertEqual(try s.evenement(e)?.statut, "envoye")
        XCTAssertEqual(envois.count, 1)
    }

    func testRepliSurLeDernierMailRecu() throws {
        let c = try contact()
        let e = try prepare(c, objet: "Re: Votre devis")
        dernierRecu = { "DERNIER@exemple.fr" }
        let r = try EnvoiPilote.envoyer(e, stock: s, outils: outils, essai: true)
        XCTAssertEqual(r.mail.reponseA, "DERNIER@exemple.fr")
        XCTAssertEqual(r.mail.objet, "Re: Votre devis")                       // pas de « Re: Re: »
        XCTAssertTrue(r.mail.filDepuis.hasPrefix("dernier mail reçu"))
        XCTAssertTrue(r.mail.entetes.contains("In-Reply-To: <DERNIER@exemple.fr>"))
        // Mail illisible : comme l'app, le mail partirait hors du fil, mais l'essai le dit
        dernierRecu = { throw Mail.ErreurMail.nonAutorise }
        let r2 = try EnvoiPilote.envoyer(e, stock: s, outils: outils, essai: true)
        XCTAssertEqual(r2.mail.reponseA, "")
        XCTAssertTrue(r2.mail.avertissements.first?.contains("hors du fil") ?? false)
        XCTAssertTrue(r2.apercu.contains("Attention : objet en « Re: »"))
        // objet sans « Re: » et sans reponse_a : aucun repli, nouveau fil
        let e3 = try prepare(c, objet: "Votre devis")
        dernierRecu = { XCTFail("repli inutile"); return nil }
        XCTAssertEqual(try EnvoiPilote.envoyer(e3, stock: s, outils: outils, essai: true).mail.filDepuis, "aucun : nouveau fil")
    }

    func testUnMailPrevuPlusTardEstSignaleSansEtreRefuse() throws {
        let c = try contact()
        try s.enregistrer(["id": c, "prochaine_date": Dates.dans(3)])
        let e = try prepare(c)
        let r = try EnvoiPilote.envoyer(e, stock: s, outils: outils, essai: true)
        XCTAssertTrue(r.mail.avertissements.contains { $0.hasPrefix("prévu le \(Dates.jjmm(Dates.dans(3)))") })
        XCTAssertTrue(try EnvoiPilote.aEnvoyer(s, outils: outils)[0].envoyable)
    }

    func testIdCourtAmbiguRefuse() throws {
        // deux événements au même début d'id (insérés à la main, la base n'en crée pas : UUID)
        let c = try contact()
        for id in ["abcdef01-0000-0000-0000-000000000001", "abcdef01-0000-0000-0000-000000000002"] {
            try s.base.executer("INSERT INTO evenements (id, contact_id, le, canal, sens, type, texte, statut, objet, maj_le) VALUES (?, ?, ?, 'mail', 'sortant', 'message', 'x', 'prepare', 'o', ?)",
                                [id, c, Dates.maintenant(), Dates.maintenant()])
        }
        XCTAssertThrowsError(try EnvoiPilote.envoyer("abcdef01", stock: s, outils: outils, essai: true)) { err in
            XCTAssertTrue((err as? RefusEnvoi)?.raisons.first?.contains("ambigu") ?? false)
        }
        XCTAssertEqual(try EnvoiPilote.resoudre("abcdef01-0000-0000-0000-000000000002", stock: s), "abcdef01-0000-0000-0000-000000000002")
    }

    // MARK: Le mail composé (le même pour l'app et l'outil)

    func testObjetDEnvoiCommeLApp() {
        XCTAssertEqual(EnvoiPilote.objetDEnvoi("Devis", reponseA: "x@y"), "Re: Devis")
        XCTAssertEqual(EnvoiPilote.objetDEnvoi("RE : Devis", reponseA: "x@y"), "RE : Devis")
        XCTAssertEqual(EnvoiPilote.objetDEnvoi("Devis", reponseA: ""), "Devis")
        XCTAssertEqual(EnvoiPilote.objetDEnvoi("", reponseA: "x@y"), "")
    }

    func testComposerUnMailEnTexteBrut() throws {
        let m = Gmail.composer(de: "vous@exemple.fr", a: "hugo@exemple.fr", objet: "Re: Votre abonnement KRYVA",
                               texte: "Bonjour,\nÀ bientôt", reponseA: "CAFE@icloud.com", messageId: "id-1@pilote.mac",
                               date: Date(timeIntervalSince1970: 0))
        let (tete, corps) = try XCTUnwrap(m.range(of: "\r\n\r\n").map { (String(m[..<$0.lowerBound]), String(m[$0.upperBound...])) })
        let lignes = tete.components(separatedBy: "\r\n")
        XCTAssertTrue(lignes.contains("From: =?UTF-8?B?\(Data(Gmail.nomExpediteur.utf8).base64EncodedString())?= <vous@exemple.fr>"))
        XCTAssertTrue(lignes.contains("To: <hugo@exemple.fr>"))
        XCTAssertTrue(lignes.contains("Subject: =?UTF-8?B?\(Data("Re: Votre abonnement KRYVA".utf8).base64EncodedString())?="))
        XCTAssertTrue(lignes.contains("Message-ID: <id-1@pilote.mac>"))
        XCTAssertTrue(lignes.contains("In-Reply-To: <CAFE@icloud.com>"))
        XCTAssertTrue(lignes.contains("References: <CAFE@icloud.com>"))
        XCTAssertTrue(lignes.contains("Content-Type: text/plain; charset=UTF-8"))
        let texte = String(data: try XCTUnwrap(Data(base64Encoded: corps.replacingOccurrences(of: "\r\n", with: ""))), encoding: .utf8)
        XCTAssertEqual(texte, "Bonjour,\r\nÀ bientôt")
        XCTAssertFalse(Gmail.composer(de: "a@b.fr", a: "c@d.fr", objet: "o", texte: "t", reponseA: "", messageId: "m").contains("In-Reply-To"))
    }

    func testJamaisDepuisKryvaMemeEnAppelDirect() {
        XCTAssertThrowsError(try Gmail.envoyerMaintenant(de: "contact@kryva.fr", motDePasse: "x", a: "a@b.fr", objet: "o",
                                                         texte: "t", reponseA: "")) { err in
            guard case Gmail.ErreurGmail.depuisKryva = err else { return XCTFail("\(err)") }
        }
    }

    // MARK: Le faux des essais de bout en bout

    func testLeFauxExigeUneCopieDeLaBase() throws {
        let fichier = FileManager.default.temporaryDirectory.appendingPathComponent("faux-\(UUID().uuidString).eml").path
        XCTAssertThrowsError(try OutilsEnvoi.selonEnvironnement(["PILOTE_ENVOI_FAUX": fichier]))
        XCTAssertThrowsError(try OutilsEnvoi.selonEnvironnement(["PILOTE_ENVOI_FAUX": fichier,
                                                                 "PILOTE_BASE": Base.dossier.appendingPathComponent("pilote.sqlite").path]))
        let faux = try OutilsEnvoi.selonEnvironnement(["PILOTE_ENVOI_FAUX": fichier, "PILOTE_BASE": chemin.path])
        XCTAssertEqual(faux.expediteur(), "vous@exemple.fr")
        XCTAssertNil(try faux.dernierRecu("a@b.fr", "Re: x"))
        let id = try faux.envoyer("hugo@exemple.fr", "Objet", "Texte", "")
        XCTAssertTrue(id.hasPrefix("essai-"))
        let ecrit = try String(contentsOfFile: fichier, encoding: .utf8)
        XCTAssertTrue(ecrit.contains("FAUX ENVOI \(id) (rien n'est parti)"))
        XCTAssertTrue(ecrit.contains("To: <hugo@exemple.fr>"))
        try? FileManager.default.removeItem(atPath: fichier)
        XCTAssertFalse(try OutilsEnvoi.selonEnvironnement(["PILOTE_ENVOI_FAUX": fichier, "PILOTE_BASE": chemin.path,
                                                           "PILOTE_FAUX_MDP": "absent"]).motDePassePresent("x"))
    }
}
