import XCTest
import SQLite3

/// 04/11, cas de Paul DURAND : un inconnu qui répond à un mail envoyé par Sacha ne doit pas passer inaperçu.
final class ReponseAEnvoiTests: XCTestCase {
    private let recu = Date(timeIntervalSince1970: 1_793_000_000)
    private func il(y jours: Double) -> Date { recu.addingTimeInterval(-jours * 86400) }
    private let manuel = "paul.durand@exemple.fr"
    private let sujet = "Retour sur notre dernière discussion du 20 octobre"

    func testLesPrefixesDeReponseSontReconnusSansTenirCompteDeLaCasseNiDesAccents() {
        for p in ["RE: ", "Re: ", "re :", "TR: ", "Tr : ", "Rép : ", "AW: ", "Fwd: ", "Re: Re: ", "RE: TR: "] {
            XCTAssertTrue(ReponseAEnvoi.aPrefixeDeReponse(prefixe: p, objet: "x"), p)
        }
        for p in ["", "   ", "Retour: ", "Facture: ", "Re"] {
            XCTAssertFalse(ReponseAEnvoi.aPrefixeDeReponse(prefixe: p, objet: "Bonjour"), p)
        }
        // Certains comptes laissent le préfixe dans l'objet lui-même.
        XCTAssertTrue(ReponseAEnvoi.aPrefixeDeReponse(prefixe: "", objet: "RE: Retour sur notre discussion"))
        XCTAssertEqual(ReponseAEnvoi.decouper("Re: Re: TR: Devis").reste, "Devis")
        XCTAssertEqual(ReponseAEnvoi.decouper("Retour: vacances").reste, "Retour: vacances")
    }

    func testLeCasDeManuelMailRangeSansPrefixeDansLObjetMaisAvecSubjectPrefix() {
        // Mail range l'objet sans « RE: » (colonne subject_prefix à part) : c'est ce que le capteur lit dans `subjects`.
        let envois = [EnvoiDeSacha(adresse: manuel, sujet: sujet, conversation: 0, le: il(y: 12))]
        XCTAssertEqual(ReponseAEnvoi.raison(prefixe: "RE: ", objet: sujet, adresses: [manuel], conversation: 0, recu: recu, envois: envois), "sujet")
    }

    func testMemeConversationSuffitMemeSansPrefixe() {
        let envois = [EnvoiDeSacha(adresse: "autre@exemple.fr", sujet: "Devis", conversation: 4242, le: il(y: 3))]
        XCTAssertEqual(ReponseAEnvoi.raison(prefixe: "", objet: "Autre titre", adresses: [manuel], conversation: 4242, recu: recu, envois: envois), "fil")
        // conversation_id 0 = inconnu : jamais un rapprochement.
        let sansId = [EnvoiDeSacha(adresse: manuel, sujet: "Devis", conversation: 0, le: il(y: 3))]
        XCTAssertNil(ReponseAEnvoi.raison(prefixe: "", objet: "Autre titre", adresses: [manuel], conversation: 0, recu: recu, envois: sansId))
    }

    func testAdresseDejaEcriteAvecPrefixeMaisAutreSujet() {
        let envois = [EnvoiDeSacha(adresse: manuel, sujet: "Proposition", conversation: 0, le: il(y: 20))]
        XCTAssertEqual(ReponseAEnvoi.raison(prefixe: "TR: ", objet: "Autre sujet", adresses: [manuel], conversation: 0, recu: recu, envois: envois), "adresse")
    }

    func testPasUneReponseDansLesAutresCas() {
        let envois = [EnvoiDeSacha(adresse: manuel, sujet: sujet, conversation: 0, le: il(y: 12))]
        // Même adresse, mais ni préfixe ni même fil : un nouveau sujet, pas une réponse (limite connue, voir l'en-tête du fichier).
        XCTAssertNil(ReponseAEnvoi.raison(prefixe: "", objet: "Nouvelle idée", adresses: [manuel], conversation: 0, recu: recu, envois: envois))
        // Préfixe de réponse, mais Sacha n'a jamais écrit à cette adresse.
        XCTAssertNil(ReponseAEnvoi.raison(prefixe: "RE: ", objet: sujet, adresses: ["inconnu@exemple.fr"], conversation: 0, recu: recu, envois: envois))
        // Envoi trop ancien (plus de 90 jours), ou postérieur au message reçu.
        let vieux = [EnvoiDeSacha(adresse: manuel, sujet: sujet, conversation: 7, le: il(y: 120))]
        XCTAssertNil(ReponseAEnvoi.raison(prefixe: "RE: ", objet: sujet, adresses: [manuel], conversation: 7, recu: recu, envois: vieux))
        let apres = [EnvoiDeSacha(adresse: manuel, sujet: sujet, conversation: 7, le: recu.addingTimeInterval(60))]
        XCTAssertNil(ReponseAEnvoi.raison(prefixe: "RE: ", objet: sujet, adresses: [manuel], conversation: 7, recu: recu, envois: apres))
        XCTAssertNil(ReponseAEnvoi.raison(prefixe: "RE: ", objet: sujet, adresses: [manuel], conversation: 0, recu: recu, envois: []))
    }

    func testUneReponseAutomatiqueDAbsenceNEstPasSignalee() {
        let envois = [EnvoiDeSacha(adresse: manuel, sujet: "Pennylane", conversation: 9, le: il(y: 5))]
        XCTAssertNil(ReponseAEnvoi.raison(prefixe: "", objet: "Réponse automatique : KRYVA et Pennylane", adresses: [manuel], conversation: 9, recu: recu, envois: envois))
        XCTAssertNil(ReponseAEnvoi.raison(prefixe: "", objet: "Automatic reply: KRYVA", adresses: [manuel], conversation: 9, recu: recu, envois: envois))
        XCTAssertEqual(ReponseAEnvoi.raison(prefixe: "", objet: "KRYVA et Pennylane", adresses: [manuel], conversation: 9, recu: recu, envois: envois), "fil")
    }

    // MARK: Requête sur l'Envelope Index

    private func indexDeMail() throws -> OpaquePointer {
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(":memory:", &db), SQLITE_OK)
        let base = db!
        let sql = """
        CREATE TABLE mailboxes (ROWID INTEGER PRIMARY KEY, url TEXT);
        CREATE TABLE subjects (ROWID INTEGER PRIMARY KEY, subject TEXT);
        CREATE TABLE addresses (ROWID INTEGER PRIMARY KEY, address TEXT, comment TEXT);
        CREATE TABLE messages (ROWID INTEGER PRIMARY KEY, mailbox INTEGER, subject INTEGER, date_received INTEGER, conversation_id INTEGER, deleted INTEGER DEFAULT 0);
        CREATE TABLE recipients (ROWID INTEGER PRIMARY KEY, message INTEGER, address INTEGER, type INTEGER, position INTEGER);
        INSERT INTO mailboxes VALUES (1, 'imap://A/INBOX'), (2, 'imap://A/INBOX/Sent'), (3, 'imap://B/[Gmail]/Messages%20envoy%C3%A9s'),
                                     (4, 'imap://C/Sent%20Messages'), (5, 'imap://A/[Gmail]/Brouillons');
        INSERT INTO subjects VALUES (1, 'Proposition'), (2, 'Bonjour');
        INSERT INTO addresses VALUES (1, 'Paul.Durand@Exemple.fr', 'Paul'), (2, 'sacha@exemple.fr', 'Sacha'), (3, 'julien@exemple.fr', 'C');
        INSERT INTO messages VALUES (10, 2, 1, 2000000000, 55, 0), (11, 3, 1, 2000000100, 56, 0), (12, 4, 2, 2000000200, 57, 0),
                                    (13, 1, 2, 2000000300, 58, 0), (14, 5, 2, 2000000400, 59, 0), (15, 2, 2, 2000000500, 60, 1),
                                    (16, 2, 2, 1000000000, 61, 0);
        INSERT INTO recipients VALUES (1, 10, 1, 0, 0), (2, 11, 3, 0, 0), (3, 12, 3, 0, 0), (4, 13, 2, 0, 0), (5, 14, 3, 0, 0),
                                      (6, 15, 3, 0, 0), (7, 16, 3, 0, 0);
        """
        XCTAssertEqual(sqlite3_exec(base, sql, nil, nil, nil), SQLITE_OK, String(cString: sqlite3_errmsg(base)))
        return base
    }

    private func envoyes(_ db: OpaquePointer, conversation: Bool = true, supprime: Bool = true) -> [String] {
        var st: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(db, ReponseAEnvoi.requete(avecConversation: conversation, avecSupprime: supprime) + " ORDER BY m.ROWID", -1, &st, nil),
                       SQLITE_OK, String(cString: sqlite3_errmsg(db)))
        defer { sqlite3_finalize(st) }
        sqlite3_bind_int64(st, 1, 1_900_000_000)
        var lignes: [String] = []
        while sqlite3_step(st) == SQLITE_ROW {
            lignes.append("\(String(cString: sqlite3_column_text(st, 0)))|\(String(cString: sqlite3_column_text(st, 1)))|\(sqlite3_column_int64(st, 2))")
        }
        return lignes
    }

    func testLaRequeteNeLitQueLesBoitesDEnvoiNonSupprimeesEtRecentes() throws {
        let db = try indexDeMail()
        defer { sqlite3_close(db) }
        // 10 (…/INBOX/Sent), 11 (Gmail « Messages envoyés » encodé), 12 (Sent Messages). Pas 13 (INBOX), 14 (brouillons),
        // 15 (supprimé), 16 (avant la date limite). L'adresse est passée en minuscules.
        XCTAssertEqual(envoyes(db), ["paul.durand@exemple.fr|Proposition|55", "julien@exemple.fr|Proposition|56", "julien@exemple.fr|Bonjour|57"])
        // Sans colonne conversation_id ni deleted (schéma plus ancien) : la requête reste valable.
        let ancien = envoyes(db, conversation: false, supprime: false)
        XCTAssertEqual(ancien.count, 4)                      // 15 (supprimé) revient quand on ne filtre pas
        XCTAssertTrue(ancien.allSatisfy { $0.hasSuffix("|0") })
    }
}
