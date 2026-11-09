import XCTest
import SQLite3

/// 04/11, bug du mail de Julien : un mail Gmail rangé dans « Tous les messages » avec l'étiquette INBOX n'était jamais capté.
final class MailBoiteReceptionTests: XCTestCase {
    /// Un petit Envelope Index en mémoire (schéma réduit : mailboxes, messages, labels).
    private func indexDeMail() throws -> OpaquePointer {
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(":memory:", &db), SQLITE_OK)
        let base = db!
        let gmail = "imap://GMAIL"
        let sql = """
        CREATE TABLE mailboxes (ROWID INTEGER PRIMARY KEY, url TEXT);
        CREATE TABLE messages (ROWID INTEGER PRIMARY KEY, mailbox INTEGER, subject TEXT);
        CREATE TABLE labels (message_id INTEGER, mailbox_id INTEGER);
        INSERT INTO mailboxes VALUES (1, '\(gmail)/INBOX'), (2, '\(gmail)/[Gmail]/Tous%20les%20messages'), (3, '\(gmail)/INBOX/Junk'),
                                     (4, '\(gmail)/[Gmail]/Corbeille'), (5, 'imap://AUTRE/INBOX'), (6, 'imap://AUTRE/Inbox');
        INSERT INTO messages VALUES (10, 1, 'directement dans INBOX'),
                                    (11, 2, 'Tous les messages avec étiquette INBOX (le cas de Julien)'),
                                    (12, 2, 'Tous les messages sans étiquette INBOX'),
                                    (13, 3, 'dans INBOX/Junk'),
                                    (14, 4, 'corbeille'),
                                    (15, 2, 'Tous les messages, étiquette Corbeille seulement'),
                                    (16, 5, 'autre compte, INBOX'),
                                    (17, 6, 'autre compte, Inbox en minuscules');
        INSERT INTO labels VALUES (11, 1), (11, 2), (15, 4), (10, 1);
        """
        XCTAssertEqual(sqlite3_exec(base, sql, nil, nil, nil), SQLITE_OK, String(cString: sqlite3_errmsg(base)))
        return base
    }

    private func recus(_ db: OpaquePointer, avecEtiquettes: Bool) -> [Int] {
        let sql = "SELECT m.ROWID FROM messages m JOIN mailboxes mb ON mb.ROWID = m.mailbox WHERE "
            + MailBoiteReception.condition(avecEtiquettes: avecEtiquettes) + " ORDER BY m.ROWID"
        var st: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(db, sql, -1, &st, nil), SQLITE_OK, String(cString: sqlite3_errmsg(db)))
        defer { sqlite3_finalize(st) }
        var ids: [Int] = []
        while sqlite3_step(st) == SQLITE_ROW { ids.append(Int(sqlite3_column_int64(st, 0))) }
        return ids
    }

    func testUnMailGmailDansTousLesMessagesAvecEtiquetteInboxEstRecu() throws {
        let db = try indexDeMail()
        defer { sqlite3_close(db) }
        // 10 (INBOX), 11 (Tous les messages + étiquette INBOX : le bug), 13 (INBOX/Junk, T13), 16 et 17 (autre compte). Pas 12, 14, 15.
        XCTAssertEqual(recus(db, avecEtiquettes: true), [10, 11, 13, 16, 17])
    }

    func testSansTableLabelsOnGardeLAncienneRegle() throws {
        let db = try indexDeMail()
        defer { sqlite3_close(db) }
        XCTAssertEqual(recus(db, avecEtiquettes: false), [10, 13, 16, 17])
        XCTAssertFalse(MailBoiteReception.condition(avecEtiquettes: false).contains("labels"))
    }

    func testDossiersIndesirablesReconnus() {
        XCTAssertTrue(MailBoiteReception.estIndesirable("imap://X/INBOX/Junk"))
        XCTAssertTrue(MailBoiteReception.estIndesirable("imap://X/%5BGmail%5D/Spam"))
        XCTAssertTrue(MailBoiteReception.estIndesirable("imap://X/Junk"))
        XCTAssertFalse(MailBoiteReception.estIndesirable("imap://X/INBOX"))
        XCTAssertFalse(MailBoiteReception.estIndesirable("imap://X/INBOX/Trash"))
    }

    func testRattrapageNeReprendQueLeTravailEtLInconnuPasDejaEmis() {
        // Message neuf : toujours traité, quelle que soit sa classe.
        for classe in ["travail", "inconnu", "perso", "ignore"] {
            XCTAssertTrue(MailBoiteReception.aTraiter(rowid: 200, curseur: 199, classe: classe, dejaEmis: false), classe)
        }
        // Message déjà derrière le curseur (relu par le rattrapage) : travail / inconnu, une seule fois.
        XCTAssertTrue(MailBoiteReception.aTraiter(rowid: 198, curseur: 199, classe: "travail", dejaEmis: false))
        XCTAssertTrue(MailBoiteReception.aTraiter(rowid: 199, curseur: 199, classe: "inconnu", dejaEmis: false))
        XCTAssertFalse(MailBoiteReception.aTraiter(rowid: 198, curseur: 199, classe: "travail", dejaEmis: true))
        // Jamais de recomptage perso ou ignoré.
        XCTAssertFalse(MailBoiteReception.aTraiter(rowid: 198, curseur: 199, classe: "perso", dejaEmis: false))
        XCTAssertFalse(MailBoiteReception.aTraiter(rowid: 198, curseur: 199, classe: "ignore", dejaEmis: false))
    }
}
