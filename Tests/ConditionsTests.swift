// T7 (05/11) : la condition d'un message préparé bloque l'envoi ; le rappel lié se coche quand elle l'est. Migration testée
// sur une base au schéma d'avant (colonnes ajoutées vides, aucune donnée perdue).
import SQLite3
import XCTest

final class ConditionsTests: XCTestCase {
    var chemin: URL!
    var s: Stockage!

    override func setUpWithError() throws {
        chemin = FileManager.default.temporaryDirectory.appendingPathComponent("pilote-conditions-\(UUID().uuidString).sqlite")
        s = Stockage(base: try Base(chemin: chemin))
    }

    override func tearDown() {
        for suffixe in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: chemin.path + suffixe) }
    }

    private func prepare(condition: String = "", rappel: String = "", canal: String = "sms",
                         texte: String = "Bonjour Frédéric, le devis de Françoise Roux est signé.") throws -> (contact: String, evenement: String) {
        let c = try s.enregistrer(["nom": "Marc Lefèvre", "espace": "kryva", "etape": "gagne", "telephone": "0600000000",
                                   "prochaine_action": "Envoyer le SMS d'acompte", "prochaine_date": Dates.aujourdhui(), "source": "test"]).id
        var champs: [String: Any] = ["canal": canal, "sens": "sortant", "type": "message", "texte": texte, "statut": "prepare", "par": "Claude"]
        if !condition.isEmpty { champs["condition"] = condition }
        if !rappel.isEmpty { champs["rappel_id"] = rappel }
        return (c, try s.ajouterEvenement(contactId: c, champs).id)
    }

    func testUneConditionNonCocheeBloqueLEnvoi() throws {
        let (c, e) = try prepare(condition: "après le test de l'acompte en euros sur un vrai devis")
        XCTAssertTrue(try XCTUnwrap(try s.evenement(e)).conditionEnAttente)
        XCTAssertThrowsError(try s.marquer(evenementId: e, statut: "envoye"))
        XCTAssertEqual(try s.evenement(e)?.statut, "prepare")                      // rien n'a bougé
        XCTAssertEqual(try s.contact(c)?.prochaineAction, "Envoyer le SMS d'acompte")
        // les autres statuts ne sont pas bloqués (« Pas envoyé », annulé)
        try s.marquer(evenementId: e, statut: "prepare")
        XCTAssertEqual(try s.evenement(e)?.statut, "prepare")
    }

    func testUnIdentifiantInconnuEstRefuse() throws {
        let (_, e) = try prepare()
        XCTAssertThrowsError(try s.marquer(evenementId: String(e.prefix(8)), statut: "envoye"))   // id court : refusé, pas « ok »
        XCTAssertEqual(try s.evenement(e)?.statut, "prepare")
    }

    func testConditionCocheeDebloqueEtSeNoteAuFil() throws {
        let (c, e) = try prepare(condition: "après le test de l'acompte", rappel: "x-apple-reminder://ABC-123")
        XCTAssertTrue(try s.rappelsAFermer().isEmpty)
        let note = try s.conditionRemplie(evenementId: e, par: "Sacha")
        XCTAssertTrue(note.contains("après le test de l'acompte"))
        XCTAssertEqual(try s.conditionRemplie(evenementId: e), "")                // déjà cochée : rien de plus
        XCTAssertFalse(try XCTUnwrap(try s.evenement(e)).conditionEnAttente)
        XCTAssertEqual(try s.rappelsAFermer(), [RappelAFermer(evenementId: e, contactId: c, rappel: "ABC-123", raison: "condition remplie")])
        try s.marquer(evenementId: e, statut: "envoye")
        XCTAssertEqual(try s.evenement(e)?.statut, "envoye")
        XCTAssertTrue(try s.evenements(c).contains { $0.texte.hasPrefix("Condition remplie, cochée par Sacha") })
    }

    func testPartiSansSaConditionLeRappelResteOuvert() throws {
        let (c, e) = try prepare(condition: "après le test", rappel: "Tester l'acompte avant d'écrire à Frédéric")
        try s.marquer(evenementId: e, statut: "envoye", malgreCondition: true)
        XCTAssertEqual(try s.evenement(e)?.statut, "envoye")
        XCTAssertTrue(try s.evenements(c).contains { $0.texte.hasPrefix("Parti alors que la condition n'était pas cochée") })
        XCTAssertTrue(try s.rappelsAFermer().isEmpty)                             // le test reste à faire : rappel ouvert
        try s.conditionRemplie(evenementId: e, par: "App")                        // vérifiée après coup
        XCTAssertEqual(try s.rappelsAFermer().map(\.rappel), ["Tester l'acompte avant d'écrire à Frédéric"])
        XCTAssertTrue(try s.evenements(c).contains { $0.texte.contains("(après l'envoi)") })
    }

    func testSansConditionLeRappelLieSeFermeALEnvoi() throws {
        let (c, e) = try prepare(rappel: "R-1")
        XCTAssertTrue(try s.rappelsAFermer().isEmpty)
        try s.marquer(evenementId: e, statut: "envoye")
        let r = try XCTUnwrap(try s.rappelsAFermer().first)
        XCTAssertEqual(r.raison, "message envoyé")
        try s.rappelFerme(r, titre: "Envoyer le SMS à Frédéric")
        XCTAssertTrue(try s.rappelsAFermer().isEmpty)                             // une seule fois
        XCTAssertTrue(try s.evenements(c).contains { $0.texte == "Rappel lié « Envoyer le SMS à Frédéric » coché par Pilote (message envoyé)." })
    }

    func testModifierLaConditionLaRemetACocher() throws {
        let (_, e) = try prepare(condition: "après le test")
        try s.modifierEvenement(e, ["condition_remplie": true, "par": "App"])
        XCTAssertFalse(try XCTUnwrap(try s.evenement(e)).conditionEnAttente)
        try s.modifierEvenement(e, ["condition": "après sa réponse au mail"])
        let ev = try XCTUnwrap(try s.evenement(e))
        XCTAssertEqual(ev.condition, "après sa réponse au mail")
        XCTAssertTrue(ev.conditionEnAttente)
        try s.modifierEvenement(e, ["condition": ""])                             // condition retirée : plus rien ne bloque
        try s.marquer(evenementId: e, statut: "envoye")
        XCTAssertEqual(try s.evenement(e)?.statut, "envoye")
    }

    func testLeCapteurNoteUnEnvoiPartiSansSaCondition() throws {
        let (c, e) = try prepare(condition: "après le test")
        let r = try s.captureSortante(contactId: c, canal: "imessage", texte: "Bonjour Frédéric, le devis de Françoise Roux est signé.",
                                      le: Date(), ref: "imessage:1")
        XCTAssertEqual(r, .marqueEnvoye(e))                                       // il est parti : jamais d'erreur au capteur
        XCTAssertTrue(try s.evenements(c).contains { $0.texte.hasPrefix("Parti alors que la condition n'était pas cochée") })
    }

    func testRefRappel() {
        XCTAssertEqual(Libelles.refRappel("x-apple-reminder://5A1B-22"), "5A1B-22")
        XCTAssertEqual(Libelles.refRappel(" Tester l'acompte "), "Tester l'acompte")
    }

    func testMigrationDUneBaseDAvantGardeTout() throws {
        let ancien = FileManager.default.temporaryDirectory.appendingPathComponent("pilote-ancienne-\(UUID().uuidString).sqlite")
        defer { for x in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: ancien.path + x) } }
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(ancien.path, &db), SQLITE_OK)
        let sql = """
        CREATE TABLE contacts (id TEXT PRIMARY KEY, espace TEXT NOT NULL DEFAULT 'kryva', type TEXT NOT NULL DEFAULT 'autre',
          nom TEXT NOT NULL DEFAULT '', entreprise TEXT NOT NULL DEFAULT '', ville TEXT NOT NULL DEFAULT '', departement TEXT NOT NULL DEFAULT '',
          telephone TEXT NOT NULL DEFAULT '', email TEXT NOT NULL DEFAULT '', linkedin TEXT NOT NULL DEFAULT '', facebook TEXT NOT NULL DEFAULT '',
          site TEXT NOT NULL DEFAULT '', etape TEXT NOT NULL DEFAULT 'a_contacter', prochaine_action TEXT NOT NULL DEFAULT '',
          prochaine_date TEXT NOT NULL DEFAULT '', priorite INTEGER NOT NULL DEFAULT 2, ne_plus_contacter INTEGER NOT NULL DEFAULT 0,
          org_id TEXT NOT NULL DEFAULT '', source TEXT, source_ref TEXT, notes TEXT NOT NULL DEFAULT '', cree_le TEXT NOT NULL,
          maj_le TEXT NOT NULL, supprime_le TEXT NOT NULL DEFAULT '', UNIQUE (source, source_ref));
        CREATE TABLE evenements (id TEXT PRIMARY KEY, contact_id TEXT NOT NULL REFERENCES contacts(id) ON DELETE CASCADE,
          le TEXT NOT NULL, canal TEXT NOT NULL DEFAULT 'autre', sens TEXT NOT NULL DEFAULT 'interne', type TEXT NOT NULL DEFAULT 'note',
          texte TEXT NOT NULL DEFAULT '', statut TEXT NOT NULL DEFAULT 'fait', par TEXT NOT NULL DEFAULT 'Sacha', source_ref TEXT,
          objet TEXT NOT NULL DEFAULT '', reponse_a TEXT NOT NULL DEFAULT '', message_id TEXT NOT NULL DEFAULT '',
          maj_le TEXT NOT NULL DEFAULT '', supprime_le TEXT NOT NULL DEFAULT '', UNIQUE (contact_id, source_ref));
        INSERT INTO contacts (id, nom, etape, prochaine_action, prochaine_date, cree_le, maj_le)
          VALUES ('c1', 'Ancien', 'contacte', 'Relance', '2026-11-12', '2026-11-01T08:00:00Z', '2026-11-01T08:00:00Z');
        INSERT INTO evenements (id, contact_id, le, sens, texte, statut, maj_le)
          VALUES ('e1', 'c1', '2026-11-01T08:00:00Z', 'sortant', 'Bonjour', 'prepare', '2026-11-01T08:00:00Z');
        """
        XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)
        sqlite3_close(db)

        let st = Stockage(base: try Base(chemin: ancien))
        let colonnes = Set(try st.base.lignes("PRAGMA table_info(evenements)").compactMap { $0["name"] as? String })
        XCTAssertTrue(colonnes.isSuperset(of: ["condition", "condition_ok_le", "rappel_id", "rappel_ferme_le"]))
        let e = try XCTUnwrap(try st.evenement("e1"))
        XCTAssertEqual(e.texte, "Bonjour")
        XCTAssertEqual(e.statut, "prepare")
        XCTAssertEqual(e.condition, "")
        XCTAssertFalse(e.conditionEnAttente)                                      // un ancien message n'est jamais bloqué
        XCTAssertEqual(try st.contact("c1")?.prochaineAction, "Relance")
        _ = try Base(chemin: ancien)                                              // une 2e ouverture ne change rien
        try st.marquer(evenementId: "e1", statut: "envoye")
        XCTAssertEqual(try st.evenement("e1")?.statut, "envoye")
    }
}
