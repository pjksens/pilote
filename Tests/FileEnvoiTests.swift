// File d'envoi des mails validés (07/11) : ce que le bouton propose, la mise en file, la passe (un mail toutes les 5 min par
// le chemin de `pilote envoie`), les sauts (mail changé, statut, « ne plus contacter »), les échecs et l'arrêt.
// L'envoi est toujours un faux (compteur), l'heure une horloge d'essai : aucun mail, ni trousseau, ni Mail, ni réseau.
import XCTest

final class FileEnvoiTests: XCTestCase {
    var chemin: URL!
    var s: Stockage!
    var envois: [(a: String, objet: String, texte: String, reponseA: String)] = []
    var de: String? = "vous@exemple.fr"
    var mdp = true
    /// Échecs SMTP à simuler : le n-ième appel à envoyer (1, 2…) échoue s'il est dans l'ensemble.
    var echecs: Set<Int> = []
    var appels = 0
    var alertes: [AlerteFile] = []
    var t0 = Date(timeIntervalSince1970: 1_794_000_000)   // un instant fixe (novembre 2026)
    var horloge: Date!

    var outils: OutilsEnvoi {
        OutilsEnvoi(expediteur: { [unowned self] in self.de },
                    motDePassePresent: { [unowned self] _ in self.mdp },
                    dernierRecu: { _, _ in XCTFail("la passe ne doit jamais chercher dans Mail"); return nil },
                    envoyer: { [unowned self] a, o, t, r in
                        self.appels += 1
                        if self.echecs.contains(self.appels) { throw Gmail.ErreurGmail.echec("connexion SMTP coupée (essai)") }
                        self.envois.append((a, o, t, r))
                        return "faux-\(self.envois.count)@pilote.essai"
                    })
    }

    override func setUpWithError() throws {
        chemin = FileManager.default.temporaryDirectory.appendingPathComponent("pilote-file-\(UUID().uuidString).sqlite")
        s = Stockage(base: try Base(chemin: chemin))
        envois = []; alertes = []; echecs = []; appels = 0
        horloge = t0
        Reglages.remplacement = { var r = EssaiPrincipal.reglages; r.domainesInterdits = ["kryva.fr"]; return r }()
    }

    override func tearDown() {
        Reglages.remplacement = EssaiPrincipal.reglages
        for suffixe in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: chemin.path + suffixe) }
    }

    private func contact(_ nom: String = "Hugo Bernard", email: String = "hugo@exemple.fr", stop: Bool = false) throws -> String {
        try s.enregistrer(["nom": nom, "entreprise": "", "espace": "kryva", "etape": "repondu", "email": email,
                           "ne_plus_contacter": stop, "prochaine_action": "Répondre", "prochaine_date": Dates.aujourdhui(),
                           "source": "test", "source_ref": UUID().uuidString]).id
    }

    @discardableResult
    private func prepare(_ contactId: String, canal: String = "mail", objet: String = "Votre abonnement KRYVA",
                         texte: String = "Bonjour,\nOn a bien noté votre demande.\nSacha, de l'équipe KRYVA",
                         statut: String = "prepare", reponseA: String = "", condition: String = "") throws -> String {
        var champs: [String: Any] = ["canal": canal, "sens": "sortant", "type": "message", "texte": texte, "statut": statut,
                                     "par": "Claude", "objet": objet]
        if !reponseA.isEmpty { champs["reponse_a"] = reponseA }
        if !condition.isEmpty { champs["condition"] = condition }
        return try s.ajouterEvenement(contactId: contactId, champs).id
    }

    private func passe(_ apres: TimeInterval, garde: ((String) -> String?)? = nil) throws -> BilanPasse {
        horloge = t0.addingTimeInterval(apres)
        return try FileEnvoi.passe(s, outils: outils, maintenant: { [unowned self] in self.horloge }, garde: garde,
                                   alerter: { [unowned self] in self.alertes.append($0) })
    }

    private func mettre(_ ids: [String], fils: [String: String] = [:]) throws -> [ElementFile] {
        try FileEnvoi.mettreEnFile(s, ids: ids, fils: fils, outils: outils, maintenant: t0)
    }

    private func etat(_ evenementId: String) throws -> ElementFile? {
        try s.base.lignes("SELECT * FROM file_envoi WHERE evenement_id = ? ORDER BY mis_le DESC LIMIT 1", [evenementId])
            .map(FileEnvoi.element).first
    }

    // MARK: Ce que le bouton propose

    func testLeBoutonNeProposeQueLesMailsPrepareEtCocheCeuxQuiPeuventPartir() throws {
        let c = try contact()
        let ok = try prepare(c)
        try prepare(c, canal: "sms", objet: "")
        try prepare(c, canal: "linkedin", objet: "")
        try prepare(c, statut: "a_valider")
        try prepare(c, statut: "envoye")
        let cond = try prepare(c, condition: "après le test de l'acompte")
        let coche = try prepare(c, condition: "après sa réponse")
        _ = try s.conditionRemplie(evenementId: coche, par: "Sacha")
        let sansObjet = try prepare(c, objet: "  ")
        let kryva = try prepare(try contact("Faux", email: "contact@kryva.fr"))
        let stop = try prepare(try contact("Parti", email: "parti@exemple.fr", stop: true))
        // 08/11 : les dates suivent l'horloge (avant, « aujourd'hui » fixe : le test cassait le jour même du 08/11)
        let apresDemain = Dates.dans(2), jjmm = apresDemain.suffix(5).split(separator: "-").reversed().joined(separator: "/")
        let demain = try prepare(c, texte: "À envoyer par Sacha lun. \(jjmm)\nBonjour,\nOn revient vers vous.\nSacha, de l'équipe KRYVA")

        let l = try FileEnvoi.candidats(s, outils: outils, aujourdhui: Dates.dans(1))
        let parId = Dictionary(uniqueKeysWithValues: l.map { ($0.id, $0) })
        XCTAssertEqual(Set(l.map(\.id)), [ok, cond, coche, sansObjet, kryva, stop, demain], "SMS, LinkedIn et non « prepare » : jamais")
        XCTAssertTrue(l.allSatisfy { $0.evenement.canal == "mail" })
        XCTAssertEqual(parId[ok]?.cocheParDefaut, true)
        XCTAssertEqual(parId[coche]?.cocheParDefaut, true, "condition cochée : il part")
        XCTAssertTrue(parId[cond]!.refus.contains { $0.contains("condition pas cochée") })
        XCTAssertTrue(parId[sansObjet]!.refus.contains { $0.contains("objet vide") })
        XCTAssertTrue(parId[kryva]!.refus.contains { $0.contains("kryva.fr") })
        XCTAssertTrue(parId[stop]!.refus.contains { $0.contains("ne plus contacter") })
        XCTAssertEqual(parId[demain]?.plusTard, true)
        XCTAssertEqual(parId[demain]?.cocheParDefaut, false, "prévu un autre jour : proposé, pas coché")
        XCTAssertTrue(parId[demain]!.envoyable)

        // Gmail pas connecté ou mot de passe absent : rien ne peut partir.
        mdp = false
        XCTAssertTrue(try FileEnvoi.candidats(s, outils: outils).allSatisfy { !$0.envoyable })
        mdp = true
        de = "equipe@kryva.fr"
        XCTAssertTrue(try FileEnvoi.candidats(s, outils: outils).allSatisfy { r in r.refus.contains { $0.contains("expéditeur dans un domaine interdit") } })
    }

    func testUnMailDejaEnFileNEstPlusPropose() throws {
        let c = try contact()
        let a = try prepare(c), b = try prepare(c)
        try mettre([a])
        XCTAssertEqual(try FileEnvoi.candidats(s, outils: outils).map(\.id), [b])
        // Et le remettre ne le double pas.
        try mettre([a, b])
        XCTAssertEqual(try FileEnvoi.actifs(s).map(\.evenementId), [a, b])
    }

    // MARK: Mise en file

    func testMiseEnFileUnToutesLesCinqMinutesEtRefusNotes() throws {
        let c = try contact()
        let a = try prepare(c), b = try prepare(c), d = try prepare(c)
        let sms = try prepare(c, canal: "sms", objet: "")
        let cond = try prepare(c, condition: "après le test")
        let l = try mettre([a, sms, b, cond, d])
        XCTAssertEqual(l.map(\.etat), ["attente", "refuse", "attente", "refuse", "attente"])
        let prevus = try FileEnvoi.enAttente(s).map { Dates.iso.date(from: $0.prevuLe)! }
        XCTAssertEqual(prevus, [t0, t0.addingTimeInterval(300), t0.addingTimeInterval(600)])
        XCTAssertTrue(l[1].raison.contains("seuls les mails"))
        XCTAssertTrue(l[3].raison.contains("condition pas cochée"))
        XCTAssertEqual(l[0].a, "hugo@exemple.fr")
        XCTAssertEqual(l[0].contact, "Hugo Bernard")
        // Rien n'a bougé sur les fiches : la mise en file n'écrit que dans sa table.
        XCTAssertEqual(try s.evenement(a)?.statut, "prepare")
        XCTAssertEqual(try s.evenement(sms)?.statut, "prepare")
        XCTAssertTrue(envois.isEmpty)
    }

    func testLaMiseEnFileAttendCinqMinutesApresLeDernierEnvoi() throws {
        let c = try contact()
        let a = try prepare(c)
        try mettre([a])
        _ = try passe(0)
        XCTAssertEqual(envois.count, 1)
        // Nouveau clic 2 min plus tard : le premier attend la fin des 5 min.
        let b = try prepare(c)
        try FileEnvoi.mettreEnFile(s, ids: [b], outils: outils, maintenant: t0.addingTimeInterval(120))
        XCTAssertEqual(try FileEnvoi.enAttente(s).first.flatMap { Dates.iso.date(from: $0.prevuLe) }, t0.addingTimeInterval(300))
    }

    // MARK: La passe

    func testTroisMailsPartentACinqMinutesParLeCheminDePiloteEnvoie() throws {
        let c1 = try contact("Un", email: "un@exemple.fr"), c2 = try contact("Deux", email: "deux@exemple.fr")
        let c3 = try contact("Trois", email: "trois@exemple.fr")
        let a = try prepare(c1, objet: "Objet un"), b = try prepare(c2, objet: "Objet deux"), d = try prepare(c3, objet: "Objet trois")
        try mettre([a, b, d])

        var bilan = try passe(0)
        XCTAssertEqual(envois.map(\.a), ["un@exemple.fr"])
        XCTAssertEqual(bilan.envoyes, ["Un"])
        XCTAssertTrue(bilan.suite.contains("Deux"), bilan.suite)
        // Même chemin que `pilote envoie` : envoye, message_id, objet et texte tels qu'envoyés.
        let ea = try XCTUnwrap(try s.evenement(a))
        XCTAssertEqual(ea.statut, "envoye")
        XCTAssertEqual(ea.messageId, "faux-1@pilote.essai")
        XCTAssertEqual(try etat(a)?.etat, "envoye")
        XCTAssertEqual(try etat(a)?.messageId, "faux-1@pilote.essai")

        _ = try passe(30); _ = try passe(299)
        XCTAssertEqual(envois.count, 1, "rien avant 5 min")
        bilan = try passe(300)
        XCTAssertEqual(envois.map(\.objet), ["Objet un", "Objet deux"])
        _ = try passe(330)
        XCTAssertEqual(envois.count, 2)
        _ = try passe(600)
        XCTAssertEqual(envois.map(\.a), ["un@exemple.fr", "deux@exemple.fr", "trois@exemple.fr"])
        XCTAssertEqual(try s.evenement(d)?.statut, "envoye")
        XCTAssertTrue(try FileEnvoi.enAttente(s).isEmpty)

        // Une alerte de fin, une seule fois, pas grave.
        _ = try passe(900)
        XCTAssertEqual(alertes.count, 1)
        XCTAssertTrue(alertes[0].texte.contains("3 envoyé(s)"), alertes[0].texte)
        XCTAssertFalse(alertes[0].grave)
    }

    func testUnePasseNEnvoieJamaisDeuxMailsMemeEnRetard() throws {
        let c = try contact()
        try mettre([try prepare(c), try prepare(c), try prepare(c)])
        _ = try passe(3600)   // Mac en veille une heure : à son réveil, un seul part
        XCTAssertEqual(envois.count, 1)
        _ = try passe(3610)
        XCTAssertEqual(envois.count, 1)
        _ = try passe(3900)
        XCTAssertEqual(envois.count, 2)
    }

    func testUnMailChangeApresLaMiseEnFileSauteEtLeSuivantPrendSaPlace() throws {
        let c = try contact()
        let a = try prepare(c), b = try prepare(c), d = try prepare(c)
        try mettre([a, b, d])
        _ = try passe(0)
        try s.modifierEvenement(b, ["texte": "Bonjour,\nUn autre texte.\nSacha, de l'équipe KRYVA"])
        let bilan = try passe(300)
        XCTAssertEqual(bilan.refuses, ["Hugo Bernard"])
        XCTAssertEqual(try etat(b)?.etat, "refuse")
        XCTAssertTrue(try etat(b)!.raison.contains("a changé"))
        XCTAssertEqual(try s.evenement(b)?.statut, "prepare", "il reste à envoyer, rien n'est parti")
        XCTAssertEqual(envois.count, 2, "le suivant part tout de suite à sa place")
        XCTAssertEqual(try s.evenement(d)?.statut, "envoye")
    }

    func testObjetFilEtAdresseChangesFontAussiSauter() throws {
        let c = try contact()
        let a = try prepare(c), b = try prepare(c)
        try mettre([a, b])
        try s.modifierEvenement(a, ["objet": "Autre objet"])
        try s.enregistrer(["id": c, "email": "autre@exemple.fr"])
        _ = try passe(0)
        XCTAssertTrue(envois.isEmpty)
        XCTAssertEqual(try etat(a)?.etat, "refuse")
        XCTAssertEqual(try etat(b)?.etat, "refuse")
    }

    func testStatutChangeNePlusContacterDejaEnvoyeEtConditionAjouteeSontRefuses() throws {
        let c1 = try contact("Un", email: "un@exemple.fr"), c2 = try contact("Deux", email: "deux@exemple.fr")
        let a = try prepare(c1), b = try prepare(c2), d = try prepare(c1), f = try prepare(c1), ok = try prepare(c1)
        try mettre([a, b, d, f, ok])
        try s.marquer(evenementId: a, statut: "a_valider")
        try s.enregistrer(["id": c2, "ne_plus_contacter": true])
        try s.marquer(evenementId: d, statut: "envoye")      // parti à la main (bouton « Envoyé ») entre-temps
        try s.modifierEvenement(f, ["condition": "après le test"])
        let bilan = try passe(0)
        XCTAssertEqual(bilan.refuses.count, 4)
        do { let r = try etat(a)!.raison; XCTAssertTrue(r.contains("pas « prepare »"), r) }
        do { let r = try etat(b)!.raison; XCTAssertTrue(r.contains("ne plus contacter"), r) }
        do { let r = try etat(d)!.raison; XCTAssertTrue(r.contains("déjà envoyé"), r) }
        do { let r = try etat(f)!.raison; XCTAssertTrue(r.contains("condition pas cochée"), r) }
        XCTAssertEqual(envois.count, 1)
        XCTAssertEqual(try etat(ok)?.etat, "envoye")
    }

    func testMotDePasseDisparuRefuseSansEnvoyer() throws {
        let c = try contact()
        let a = try prepare(c)
        try mettre([a])
        mdp = false
        _ = try passe(0)
        XCTAssertEqual(appels, 0)
        let r = try etat(a)!.raison
        XCTAssertTrue(r.contains("Gmail") || r.contains("mot de passe"), r)
    }

    func testUnEchecNArretePasLaFile() throws {
        let c = try contact()
        let a = try prepare(c), b = try prepare(c)
        try mettre([a, b])
        echecs = [1]
        let bilan = try passe(0)
        XCTAssertEqual(bilan.echecs, ["Hugo Bernard"])
        XCTAssertFalse(bilan.arretee)
        XCTAssertEqual(try etat(a)?.etat, "echec")
        XCTAssertEqual(try s.evenement(a)?.statut, "prepare", "pas parti : il reste à envoyer")
        XCTAssertEqual(alertes.count, 1)
        XCTAssertFalse(alertes[0].grave)
        _ = try passe(200)
        XCTAssertTrue(envois.isEmpty, "le suivant attend 5 min après l'échec")
        _ = try passe(300)
        XCTAssertEqual(envois.count, 1)
        XCTAssertEqual(try s.evenement(b)?.statut, "envoye")
    }

    func testDeuxEchecsDeSuiteArretentToutEtPreviennent() throws {
        let c = try contact()
        let a = try prepare(c), b = try prepare(c), d = try prepare(c), f = try prepare(c)
        try mettre([a, b, d, f])
        echecs = [1, 2]
        _ = try passe(0)
        let bilan = try passe(300)
        XCTAssertTrue(bilan.arretee)
        XCTAssertEqual(try etat(b)?.etat, "echec")
        XCTAssertEqual(try etat(d)?.etat, "annule")
        XCTAssertEqual(try etat(f)?.etat, "annule")
        XCTAssertTrue(try FileEnvoi.enAttente(s).isEmpty)
        let grave = try XCTUnwrap(alertes.first { $0.id.hasSuffix("deux-echecs") })
        XCTAssertTrue(grave.grave)
        XCTAssertTrue(grave.texte.contains("2 échecs"))
        _ = try passe(900)
        XCTAssertEqual(appels, 2, "plus rien ne part")
        XCTAssertEqual(try s.evenement(d)?.statut, "prepare")
    }

    func testUnEchecPuisUnSuccesPuisUnEchecNArretePas() throws {
        let c = try contact()
        let ids = [try prepare(c), try prepare(c), try prepare(c), try prepare(c)]
        try mettre(ids)
        echecs = [1, 3]
        for t in [0.0, 300, 600, 900] { _ = try passe(t) }
        XCTAssertEqual(try ids.map { try etat($0)!.etat }, ["echec", "envoye", "echec", "envoye"])
    }

    func testArreterLaFileAnnuleCeQuiAttend() throws {
        let c = try contact()
        let a = try prepare(c), b = try prepare(c)
        try mettre([a, b])
        _ = try passe(0)
        XCTAssertEqual(try FileEnvoi.arreter(s, raison: "Arrêtée par Sacha", maintenant: t0.addingTimeInterval(60)), 1)
        _ = try passe(600)
        XCTAssertEqual(envois.count, 1)
        XCTAssertEqual(try etat(b)?.etat, "annule")
        XCTAssertEqual(try s.evenement(b)?.statut, "prepare")
        // Il redevient proposable.
        XCTAssertEqual(try FileEnvoi.candidats(s, outils: outils).map(\.id), [b])
    }

    func testEnvoiInterrompuArreteLaFileEtPrevient() throws {
        let c = try contact()
        let a = try prepare(c), b = try prepare(c)
        try mettre([a, b])
        // Une passe morte en plein envoi : la ligne est restée « envoi », le message pas noté.
        try s.base.executer("UPDATE file_envoi SET etat = 'envoi' WHERE evenement_id = ?", [a])
        let bilan = try passe(0)
        XCTAssertTrue(bilan.arretee)
        XCTAssertEqual(try etat(a)?.etat, "incertain")
        XCTAssertEqual(try etat(b)?.etat, "annule")
        XCTAssertTrue(envois.isEmpty, "rien ne repart sans vérification")
        XCTAssertTrue(alertes.contains { $0.grave && $0.texte.contains("Messages envoyés") })
    }

    func testEnvoiInterrompuMaisNoteEstRepris() throws {
        let c = try contact()
        let a = try prepare(c), b = try prepare(c)
        try mettre([a, b])
        try s.base.executer("UPDATE file_envoi SET etat = 'envoi' WHERE evenement_id = ?", [a])
        try EnvoiPilote.finaliser(s, evenementId: a, texte: try s.evenement(a)!.texte, objet: "Votre abonnement KRYVA", reponseA: "",
                                  messageId: "deja@pilote.essai")
        _ = try passe(0)
        XCTAssertEqual(try etat(a)?.etat, "envoye")
        XCTAssertEqual(try etat(a)?.messageId, "deja@pilote.essai")
        XCTAssertEqual(envois.count, 0, "la reprise ne compte pas comme un envoi de cette passe… et le suivant attend 5 min")
        _ = try passe(300)
        XCTAssertEqual(envois.count, 1)
    }

    func testLeFilTrouveALaMiseEnFileEstRenduALEnvoi() throws {
        let c = try contact()
        let re = try prepare(c, objet: "Re: Votre devis")
        let neuf = try prepare(c, objet: "Votre devis")
        try mettre([re, neuf], fils: [re: "<recu-1@exemple.fr>", neuf: "<ne-doit-pas-servir@exemple.fr>"])
        _ = try passe(0)
        _ = try passe(300)
        XCTAssertEqual(envois.map(\.reponseA), ["<recu-1@exemple.fr>", ""])
        XCTAssertEqual(try s.evenement(re)?.reponseA, "<recu-1@exemple.fr>")
    }

    func testGardeDEssaiRefuseToutAutreAdresse() throws {
        let moi = try contact("Moi", email: "vous@exemple.fr"), autre = try contact("Autre", email: "autre@exemple.fr")
        let a = try prepare(autre), b = try prepare(moi)
        try mettre([a, b])
        let garde: (String) -> String? = { $0 == "vous@exemple.fr" ? nil : "essai : pas \($0)" }
        _ = try passe(0, garde: garde)
        XCTAssertEqual(envois.map(\.a), ["vous@exemple.fr"])
        XCTAssertEqual(try etat(a)?.etat, "refuse")
    }

    func testCopieDeLaBase() {
        XCTAssertFalse(FileEnvoi.surCopie([:]))
        XCTAssertFalse(FileEnvoi.surCopie(["PILOTE_BASE": Base.dossier.appendingPathComponent("pilote.sqlite").path]))
        XCTAssertTrue(FileEnvoi.surCopie(["PILOTE_BASE": "/tmp/copie.sqlite"]))
    }
}
