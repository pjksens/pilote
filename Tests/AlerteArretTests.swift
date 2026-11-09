import XCTest

/// 04/11, GO de PILOTE : filtre des expéditeurs automatiques (point b) et alerte « capteur ou veille arrêtés ».
final class AlerteArretTests: XCTestCase {
    private var paris: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Paris")!
        return c
    }()

    private func date(_ jour: Int, _ h: Int, _ m: Int) -> Date {
        paris.date(from: DateComponents(year: 2026, month: 11, day: jour, hour: h, minute: m))!
    }

    // MARK: Expéditeurs automatiques

    func testAutomatiquesProbables() {
        for a in ["jobalerts-noreply@linkedin.com", "messages-noreply@linkedin.com", "messaging-digest-noreply@linkedin.com",
                  "niet-beantwoorden@exemple.nl", "nepasrepondre@email.urssaf.fr", "testflight_no_reply@email.apple.com",
                  "ship@info.vercel.com", "hello@info.appli-exemple.com", "communication@emails.boutique-exemple.fr",
                  "bienvenue@mail.kryva.fr", "rapports@notif.kryva.fr", "devis@notif.kryva.fr", "team@newsletter.artlist.io",
                  "email@actu.journal-exemple.fr", "invitations@linkedin.com", "dmarc@postmarkapp.com", "dmarc-reports@exemple.fr", "rua@exemple.fr", "ruf@exemple.fr", "Notifications@Exemple.fr"] {
            XCTAssertTrue(ExpediteurAuto.probable(a), a)
        }
    }

    func testUnHumainInconnuNEstJamaisMarque() {
        for a in ["adrien@studio-exemple.fr", "contact@boutique-exemple.fr", "jean.exemple42@gmail.com", "anne.durand@fournisseur-exemple.fr",
                  "claire@agence-exemple.fr", "support@supabase.com", "team@supabase.com", "tim@annuaire-exemple.co", "discover_at_service_com_abcdefghij_00000000@privaterelay.appleid.com", "marie.durand@cabinet-durand.fr", "jean@example.com", "pas-une-adresse", ""] {
            XCTAssertFalse(ExpediteurAuto.probable(a), a)
        }
    }

    // MARK: Alerte d'arrêt

    func testLaNuitNeCountePas() {
        // 22 h 45 → 7 h le lendemain : 15 minutes seulement dans la plage 7 h-23 h.
        XCTAssertEqual(AlerteArret.secondesActives(de: date(3, 22, 45), a: date(4, 7, 0), calendrier: paris), 900)
        XCTAssertEqual(AlerteArret.secondesActives(de: date(4, 9, 0), a: date(4, 8, 0), calendrier: paris), 0)
        XCTAssertEqual(AlerteArret.secondesActives(de: date(4, 8, 0), a: date(4, 12, 30), calendrier: paris), 4.5 * 3600)
    }

    func testPasDeFausseAlerteAuReveil() {
        // Veille passée à 22 h 45 hier, capteur à 8 h 29 : à 8 h 30, rien à signaler (15 min + 1 h 30 < 2 h).
        let l = AlerteArret.lignes(capteur: date(4, 8, 29), veille: date(3, 22, 45), maintenant: date(4, 8, 30), calendrier: paris)
        XCTAssertEqual(l, [])
    }

    func testVeilleArreteeEstSignalee() {
        // Dernier passage de la veille hier 22 h 45 ; à 9 h 05 : 15 min + 2 h 05 > 2 h.
        let l = AlerteArret.lignes(capteur: date(4, 9, 4), veille: date(3, 22, 45), maintenant: date(4, 9, 5), calendrier: paris)
        XCTAssertEqual(l.count, 1)
        XCTAssertTrue(l[0].hasPrefix("Veille de PILOTE"), l[0])
        XCTAssertTrue(l[0].contains("03/11 à 22:45"), l[0])
    }

    func testCapteurArreteEtFichierAbsent() {
        let l = AlerteArret.lignes(capteur: date(4, 10, 0), veille: nil, maintenant: date(4, 13, 0), calendrier: paris)
        XCTAssertEqual(l.count, 2)
        XCTAssertTrue(l[0].hasPrefix("Capteur d'entrants"), l[0])
        XCTAssertTrue(l[1].contains("aucune trace"), l[1])
    }

    func testLireUtiliseLaDateDeDerniereEcriture() throws {
        let dossier = FileManager.default.temporaryDirectory.appendingPathComponent("pilote-arret-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dossier) }
        let capteur = dossier.appendingPathComponent("entrants-etat.json")
        try Data("{}".utf8).write(to: capteur)
        let maintenant = Date()
        // Veille absente : signalée. Capteur écrit à l'instant : rien.
        XCTAssertEqual(AlerteArret.lire(maintenant: maintenant, dossier: dossier, annexes: false).count, 1)
        // Capteur vieux de 3 jours (plage 7 h-23 h largement dépassée) : signalé aussi.
        try FileManager.default.setAttributes([.modificationDate: maintenant.addingTimeInterval(-3 * 86400)], ofItemAtPath: capteur.path)
        let l = AlerteArret.lire(maintenant: maintenant, dossier: dossier, annexes: false)
        XCTAssertEqual(l.count, 2, "\(l)")
    }

    func testLeControleListeLesArretsSansLesCompter() {
        var c = Controle(jour: "2026-11-04")
        XCTAssertTrue(c.texte().contains("Arrêts (capteur, veille) : aucun"))
        c.arrets = ["Capteur d'entrants (launchd, 60 s) : rien écrit depuis le 04/11 à 09:12 (plus de 2 h dans la plage 7 h-23 h)"]
        XCTAssertEqual(c.total, 0)
        XCTAssertTrue(c.texte().contains("ARRÊTS (capteur, veille) :"))
        XCTAssertTrue(c.texte().contains("Capteur d'entrants"))
    }

    // MARK: Chantier C (05/11) : seuil 30 min, Facteur, inscrits, disque, WhatsApp

    func testCapteurSignaleApres30MinutesActives() {
        // Dernier passage 9 h 00 ; à 9 h 25 rien, à 9 h 35 alerte (seuil 30 min), la veille garde 2 h.
        XCTAssertEqual(AlerteArret.lignes(capteur: date(4, 9, 0), veille: date(4, 9, 0), maintenant: date(4, 9, 25), calendrier: paris), [])
        let l = AlerteArret.lignes(capteur: date(4, 9, 0), veille: date(4, 9, 0), maintenant: date(4, 9, 35), calendrier: paris)
        XCTAssertEqual(l.count, 1)
        XCTAssertTrue(l[0].contains("plus de 30 min"), l[0])
    }

    func testPasDeFausseAlerteAuReveilDuMac() {
        // Capteur écrit à 22 h 50 (10 min actives avant 23 h), Mac réveillé à 7 h 15 (15 min actives) : 25 min < 30 min.
        XCTAssertEqual(AlerteArret.lignes(capteur: date(3, 22, 50), veille: date(4, 7, 14), maintenant: date(4, 7, 15), calendrier: paris), [])
    }

    func testFacteurEtInscritsArretesOuAbsents() {
        let l = AlerteArret.lignesAnnexes(facteur: date(4, 9, 0), inscrits: nil, inscritsStatut: nil, inscritsDepuis: nil,
                                          disqueLibre: nil, whatsapp: nil, maintenant: date(4, 9, 40), calendrier: paris)
        XCTAssertEqual(l.count, 2, "\(l)")
        XCTAssertTrue(l[0].hasPrefix("Facteur"), l[0])
        XCTAssertTrue(l[1].hasPrefix("Service des inscrits") && l[1].contains("aucune trace"), l[1])
        // Facteur et battement frais : rien.
        XCTAssertEqual(AlerteArret.lignesAnnexes(facteur: date(4, 9, 38), inscrits: date(4, 9, 39), inscritsStatut: "SUBSCRIBED", inscritsDepuis: date(4, 8, 0),
                                                 disqueLibre: 50_000_000_000, whatsapp: date(4, 9, 0), maintenant: date(4, 9, 40), calendrier: paris), [])
    }

    func testConnexionInscritsEnEchecDepuisPlusDe30Min() {
        // Le battement est frais mais la connexion est en CHANNEL_ERROR depuis 9 h 00 : alerte à 9 h 40, pas à 9 h 20 (reconnexion normale).
        func l(_ h: Int, _ m: Int) -> [String] {
            AlerteArret.lignesAnnexes(facteur: date(4, h, m), inscrits: date(4, h, m), inscritsStatut: "CHANNEL_ERROR", inscritsDepuis: date(4, 9, 0),
                                      disqueLibre: nil, whatsapp: nil, maintenant: date(4, h, m), calendrier: paris)
        }
        XCTAssertEqual(l(9, 20), [])
        XCTAssertEqual(l(9, 40).count, 1)
        XCTAssertTrue(l(9, 40)[0].contains("CHANNEL_ERROR"), l(9, 40)[0])
    }

    func testDisqueSous10Go() {
        func l(_ octets: Int64) -> [String] {
            AlerteArret.lignesAnnexes(facteur: date(4, 9, 0), inscrits: date(4, 9, 0), inscritsStatut: nil, inscritsDepuis: nil,
                                      disqueLibre: octets, whatsapp: nil, maintenant: date(4, 9, 0), calendrier: paris)
        }
        XCTAssertEqual(l(14_029_668_000), [])
        let a = l(9_100_000_000)
        XCTAssertEqual(a.count, 1)
        XCTAssertTrue(a[0].contains("9,1 Go"), a[0])
    }

    func testSecondesOuvreesIgnoreLeWeekend() {
        // 6 nov 2026 = vendredi, 9 = lundi. Vendredi 18 h → lundi 9 h = 6 h + 9 h.
        XCTAssertEqual(AlerteArret.secondesOuvrees(de: date(6, 18, 0), a: date(9, 9, 0), calendrier: paris), 15 * 3600)
    }

    func testWhatsAppAlerteApres24HOuvreesSeulement() {
        func l(_ w: Date, _ now: Date) -> [String] {
            AlerteArret.lignesAnnexes(facteur: now, inscrits: now, inscritsStatut: nil, inscritsDepuis: nil, disqueLibre: nil, whatsapp: w, maintenant: now, calendrier: paris)
        }
        XCTAssertEqual(l(date(4, 14, 22), date(5, 11, 50)), [])                         // 21 h : rien (cas réel du 05/11)
        let a = l(date(4, 14, 22), date(5, 15, 0))                                      // 24 h 38 : alerte
        XCTAssertEqual(a.count, 1)
        XCTAssertTrue(a[0].contains("il y a 24 h 38"), a[0])
        XCTAssertEqual(l(date(6, 18, 0), date(9, 9, 0)), [])                            // vendredi soir → lundi matin : le week-end ne compte pas
        XCTAssertEqual(l(date(6, 18, 0), date(9, 20, 0)).count, 1)                      // lundi 20 h : 6 h + 20 h = 26 h ouvrées
    }

    func testLigneWhatsAppDuControle() {
        XCTAssertEqual(AlerteArret.ligneWhatsApp(date(5, 6, 0), maintenant: date(5, 11, 20)), "WhatsApp : dernier message reçu il y a 5 h 20")
        XCTAssertTrue(AlerteArret.ligneWhatsApp(nil).contains("illisible"))
    }

    func testLireBattementEtFichiers() throws {
        let dossier = FileManager.default.temporaryDirectory.appendingPathComponent("pilote-batt-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dossier) }
        try Data(#"{"pid":1,"statut":"CHANNEL_ERROR","statut_depuis":"2026-11-05T08:00:00.000Z","mis_a_jour":"2026-11-05T08:01:00.000Z"}"#.utf8)
            .write(to: dossier.appendingPathComponent("inscrits-battement.json"))
        let b = AlerteArret.lireBattement(dossier: dossier)
        XCTAssertEqual(b.statut, "CHANNEL_ERROR")
        XCTAssertEqual(b.depuis, ISO8601DateFormatter().date(from: "2026-11-05T08:00:00Z"))
        XCTAssertNil(AlerteArret.lireBattement(dossier: dossier.appendingPathComponent("absent")).statut)
        // WhatsApp : relevé par le capteur dans entrants-etat.json
        XCTAssertNil(AlerteArret.dernierWhatsApp(dossier: dossier))
        try Data(#"{"whatsappRecu":"2026-11-04T14:22:15+01:00"}"#.utf8).write(to: dossier.appendingPathComponent("entrants-etat.json"))
        XCTAssertEqual(AlerteArret.dernierWhatsApp(dossier: dossier), date(4, 14, 22).addingTimeInterval(15))
    }

    func testLeControleAfficheLesInfos() {
        var c = Controle(jour: "2026-11-05")
        c.infos = ["WhatsApp : dernier message reçu il y a 5 h 20"]
        XCTAssertTrue(c.texte().contains("WhatsApp : dernier message reçu il y a 5 h 20"))
        XCTAssertEqual(c.total, 0)
    }
}
