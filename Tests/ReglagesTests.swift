import XCTest

/// Version publique : chaque intégration est coupée tant que reglages.json ne l'active pas.
final class ReglagesTests: XCTestCase {
    override func tearDown() {
        Reglages.remplacement = EssaiPrincipal.reglages
    }

    func testFichierVideToutCoupe() throws {
        let r = try Reglages.decoder(Data("{}".utf8))
        XCTAssertEqual(r, Reglages())
        XCTAssertEqual(r.prenomAffiche, "Vous")
        XCTAssertNil(r.secrets)
        XCTAssertNil(r.depot)
        XCTAssertTrue(r.bilan.allSatisfy { !$0.actif }, r.bilan.map(\.nom).joined(separator: ", "))
    }

    func testExempleDuDepotSeLit() throws {
        let exemple = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("docs/reglages.exemple.json")
        let r = try Reglages.decoder(Data(contentsOf: exemple))
        XCTAssertEqual(r.prenomAffiche, "Camille")
        XCTAssertEqual(r.rappelsCalendrier, true)
        XCTAssertEqual(r.mail, false)
        XCTAssertEqual(r.comptes?.vue, "pilote_comptes")
        XCTAssertEqual(r.comptes?.exclureDomaines, ["mon-produit.example"])
        XCTAssertEqual(r.comptes?.compteur?.arguments, ["node", "scripts/compteur.mjs"])
        XCTAssertNil(r.synchro)
        XCTAssertEqual(r.routines?.first?.id, "matin")
        XCTAssertEqual(r.dossiersSessions?.count, 2)
    }

    func testCleEnSerpentEtCheminsAvecTilde() throws {
        let r = try Reglages.decoder(Data("""
            {"prenom": "  ", "dossier_secrets": "~/Coffre", "depot_suivi": "/tmp/depot", "domaines_interdits": ["exemple.fr"],
             "synchro": {"url": "https://x.invalid", "cle": "k", "table_contacts": "c"}}
            """.utf8))
        XCTAssertEqual(r.prenomAffiche, "Vous")                       // prénom vide : « Vous »
        XCTAssertEqual(r.secrets?.path, Demo.maison.appendingPathComponent("Coffre").path)
        XCTAssertEqual(r.depot?.path, "/tmp/depot")
        XCTAssertEqual(r.synchro?.tableContacts, "c")
        XCTAssertNil(r.synchro?.tableEvenements)
        XCTAssertEqual(r.bilan.first { $0.nom.hasPrefix("Domaines") }?.actif, true)
        XCTAssertEqual(r.bilan.first { $0.nom.hasPrefix("Publication") }?.actif, false)   // dossier sans publication: true
    }

    func testDomainesInterditsSeulementSiReglés() {
        Reglages.remplacement = Reglages()
        XCTAssertFalse(EnvoisKryva.estInterdit("equipe@exemple.fr"))
        Reglages.remplacement = { var r = Reglages(); r.domainesInterdits = ["exemple.fr"]; return r }()
        XCTAssertTrue(EnvoisKryva.estInterdit("equipe@exemple.fr"))
        XCTAssertTrue(EnvoisKryva.estInterdit("x@notif.exemple.fr"))
        XCTAssertFalse(EnvoisKryva.estInterdit("x@pasexemple.fr"))
    }

    func testMailEtRadarCoupesSansReglage() async {
        Reglages.remplacement = Reglages()
        do {
            _ = try await Mail.executer("return 1")
            XCTFail("Mail.app ne doit pas être appelé sans `mail: true`")
        } catch {
            XCTAssertTrue(error is IntegrationCoupee || error is Demo.Refus, "\(error)")
        }
        XCTAssertNil(CleRadar.fichierScrapeCreators)
        XCTAssertNil(SecretsPublication.dossier)
    }

    func testNomsDesEspacesReglables() {
        XCTAssertEqual(Libelles.espaces.map(\.1), ["KRYVA", "Freelance", "Autre"])
        Reglages.remplacement = { var r = EssaiPrincipal.reglages; r.espaces = ["kryva": "Atelier", "autre": " "]; return r }()
        XCTAssertEqual(Libelles.espaces.map(\.0), ["kryva", "freelance", "autre"])
        XCTAssertEqual(Libelles.espaces.map(\.1), ["Atelier", "Freelance", "Autre"])
        XCTAssertEqual(Libelles2.espace("kryva"), "Atelier")
    }

    func testMessageDeRefusDitQuoiRegler() {
        XCTAssertEqual(IntegrationCoupee(reglage: "mail").errorDescription,
                       "Coupé : à activer dans reglages.json (mail). Voir le README, section « Réglages ».")
    }
}
