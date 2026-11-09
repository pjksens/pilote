// Capteur de messages entrants : iMessage, WhatsApp (Mac) et Mail (Gmail et autres comptes de Mail.app).
// LECTURE SEULE : aucune fonction d'envoi dans ce fichier, et les bases des autres apps sont ouvertes en lecture seule.
// Le tri se fait par règles, sans IA : aucun jeton consommé tant que rien n'arrive.
//   1. expéditeur = contact de Pilote (téléphone, e-mail ou nom)      → travail  : fil du contact + entrants.jsonl
//   2. expéditeur = dans les Contacts du Mac, pas dans Pilote         → perso    : rien gardé, sauf un repère « déjà vu » (empreinte)
//   3. expéditeur inconnu                                             → inconnu  : entrants.jsonl seulement, 120 caractères
//   4. mails : newsletters et envois automatiques                     → ignorés (List-Id, noreply en tête d'adresse) ;
//      les autres envois automatiques probables restent « inconnu » mais portent "auto": true (la veille ne les transmet pas)
// 05/11 (chantier A « ne rien cacher ») : règles détaillées dans Shared/TriEntrants.swift (rebond, nom « via LinkedIn »,
// domaine d'entreprise, envoi de Sacha au texte d'une fiche, groupes suivis, plateformes suivies) ; les messages écartés
// (ignore, perso) laissent une ligne dans entrants-ecartes.jsonl, gardée 14 jours.
// `pilote entrants --capter` fait une passe (launchd la lance toutes les 60 s) ; `--suivre` affiche chaque nouvelle ligne
// de entrants.jsonl dès qu'elle arrive (pour l'outil Monitor de PILOTE).
import CryptoKit
import Foundation
import SQLite3

// MARK: - Lecture SQLite seule

struct EntErreur: Error, CustomStringConvertible {
    let description: String
    var refus: Bool {
        let m = description.lowercased()
        return m.contains("authorization denied") || m.contains("not permitted") || m.contains("unable to open") || m.contains("permission")
    }
}

typealias EntLigne = [String: Any]

extension Dictionary where Key == String, Value == Any {
    func entS(_ k: String) -> String { (self[k] as? String) ?? "" }
    func entI(_ k: String) -> Int {
        if let v = self[k] as? Int { return v }
        if let v = self[k] as? Double { return Int(v) }
        return 0
    }
    func entD(_ k: String) -> Double {
        if let v = self[k] as? Double { return v }
        if let v = self[k] as? Int { return Double(v) }
        return 0
    }
}

/// Base d'une autre app, ouverte en lecture seule (rien ne peut y être écrit).
final class EntLecture {
    private var db: OpaquePointer?

    init(_ chemin: String) throws {
        var p: OpaquePointer?
        let rc = sqlite3_open_v2(chemin, &p, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil)
        guard rc == SQLITE_OK, let p else {
            let m = p.map { String(cString: sqlite3_errmsg($0)) } ?? "code \(rc)"
            sqlite3_close_v2(p)
            throw EntErreur(description: m)
        }
        db = p
        sqlite3_busy_timeout(p, 3000)
        // L'ouverture seule ne révèle pas toujours un refus d'accès : on force une lecture.
        _ = try lignes("SELECT count(*) AS n FROM sqlite_master")
    }

    deinit { sqlite3_close_v2(db) }

    func lignes(_ sql: String, _ params: [Any] = []) throws -> [EntLigne] {
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else {
            throw EntErreur(description: String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(st) }
        for (i, v) in params.enumerated() {
            let n = Int32(i + 1)
            switch v {
            case let x as Int: sqlite3_bind_int64(st, n, Int64(x))
            case let x as Double: sqlite3_bind_double(st, n, x)
            case let x as String: sqlite3_bind_text(st, n, x, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            default: sqlite3_bind_null(st, n)
            }
        }
        var sortie: [EntLigne] = []
        while true {
            let rc = sqlite3_step(st)
            if rc == SQLITE_DONE { break }
            guard rc == SQLITE_ROW else { throw EntErreur(description: String(cString: sqlite3_errmsg(db))) }
            var l: EntLigne = [:]
            for c in 0..<sqlite3_column_count(st) {
                let nom = String(cString: sqlite3_column_name(st, c))
                switch sqlite3_column_type(st, c) {
                case SQLITE_INTEGER: l[nom] = Int(sqlite3_column_int64(st, c))
                case SQLITE_FLOAT: l[nom] = sqlite3_column_double(st, c)
                case SQLITE_TEXT: l[nom] = String(cString: sqlite3_column_text(st, c))
                case SQLITE_BLOB:
                    if let b = sqlite3_column_blob(st, c) { l[nom] = Data(bytes: b, count: Int(sqlite3_column_bytes(st, c))) }
                default: break
                }
            }
            sortie.append(l)
        }
        return sortie
    }
}

// MARK: - Annuaire : lecture des carnets (le tri lui-même est dans Shared/TriEntrants.swift, testé)

extension EntAnnuaire {
    mutating func lireContactsWhatsApp(_ g: String) {
        do {
            let b = try EntLecture(g + "/ContactsV2.sqlite")
            for r in try b.lignes("SELECT ZFULLNAME, ZGIVENNAME, ZLASTNAME, ZPHONENUMBER, ZLID, ZBUSINESSNAME FROM ZWAADDRESSBOOKCONTACT") {
                var tels: [String] = [], noms: [String] = []
                if let t = EntNorm.tel(r.entS("ZPHONENUMBER")) { tels.append(t); macTel.insert(t) }
                for n in [r.entS("ZFULLNAME"), r.entS("ZGIVENNAME") + " " + r.entS("ZLASTNAME")] {
                    if let k = EntNorm.nom(n) { noms.append(k); macNom.insert(k) }
                }
                if !r.entS("ZLID").isEmpty { lid[r.entS("ZLID")] = (tels, noms) }
            }
        } catch { avertissements.append("contacts WhatsApp illisibles : \(error)") }
        if let b = try? EntLecture(g + "/LID.sqlite"),
           let paires = try? b.lignes("SELECT ZLID, ZPHONENUMBER FROM ZWAPHONENUMBERLIDPAIR") {
            for p in paires {
                guard let t = EntNorm.tel(p.entS("ZPHONENUMBER")) else { continue }
                let l = p.entS("ZLID").contains("@") ? p.entS("ZLID") : p.entS("ZLID") + "@lid"
                var v = lid[l] ?? ([], [])
                if !v.tels.contains(t) { v.tels.append(t) }
                lid[l] = v
            }
        }
    }

    /// Contacts du Mac (app Contacts). Demande l'accès complet au disque ; sans lui, seuls les contacts WhatsApp servent.
    mutating func lireContactsMac() {
        guard Reglages.courants.entrants == true else { return }
        let racine = Demo.maison.path + "/Library/Application Support/AddressBook"
        var bases = [racine + "/AddressBook-v22.abcddb"]
        if let sources = try? FileManager.default.contentsOfDirectory(atPath: racine + "/Sources") {
            bases += sources.map { racine + "/Sources/\($0)/AddressBook-v22.abcddb" }
        }
        var lues = 0
        for chemin in bases {
            guard let b = try? EntLecture(chemin) else { continue }
            lues += 1
            for r in (try? b.lignes("SELECT ZFIRSTNAME AS f, ZLASTNAME AS l, ZORGANIZATION AS o, ZNICKNAME AS n FROM ZABCDRECORD")) ?? [] {
                for n in [r.entS("f") + " " + r.entS("l"), r.entS("o"), r.entS("n")] { if let k = EntNorm.nom(n) { macNom.insert(k) } }
            }
            for r in (try? b.lignes("SELECT ZFULLNUMBER AS t FROM ZABCDPHONENUMBER")) ?? [] { EntNorm.tels(r.entS("t")).forEach { macTel.insert($0) } }
            for r in (try? b.lignes("SELECT ZADDRESS AS a FROM ZABCDEMAILADDRESS")) ?? [] { macMail.insert(r.entS("a").lowercased()) }
        }
        if lues == 0 { avertissements.append("Contacts du Mac illisibles (accès complet au disque à accorder) : seuls les contacts WhatsApp servent au tri perso") }
    }
}

// MARK: - État (curseurs, statuts, repères « déjà vu »)

struct EntStatut: Codable { var ok: Bool; var message: String; var le: String }
struct EntVu: Codable { var premier: String; var dernier: String; var n: Int }

/// Un vocal de travail ou d'inconnu qui attend sa transcription locale (la ligne de entrants.jsonl part quand elle est faite).
struct EntAttente: Codable {
    var ref: String
    var canal: String
    var classe: String
    var ligne: String                 // la ligne de entrants.jsonl (JSON), complétée à la fin
    var fichier: String
    var sourceId: Int                 // Z_PK WhatsApp ou ROWID iMessage, pour retrouver le fichier s'il arrive plus tard
    var evenementId: String           // événement du fil à compléter ("" si l'expéditeur n'est pas un contact)
    var duree: Int
    var essais: Int
}

struct EntEtat: Codable {
    var attente: [EntAttente]? = nil       // vocaux en attente de transcription
    var curseurs: [String: Int] = [:]
    var statuts: [String: EntStatut] = [:]
    var vus: [String: EntVu] = [:]        // empreinte de l'expéditeur perso → quand et combien de fois (aucun nom, aucun texte)
    var passe = ""
    var cumul: [String: Int] = [:]         // classe → nombre depuis l'installation
    var whatsappRecu: String? = nil        // 05/11 (T39) : date du dernier message REÇU dans la base WhatsApp Mac, relevée par le capteur (lui seul a l'accès au disque)
    var suivis: [String: EntSuivi]? = nil  // T14 : numéros à qui Sacha a envoyé le texte d'une fiche (60 jours)
}

// MARK: - Sources

enum EntSource {
    static let groupeWhatsApp = Demo.maison.path + "/Library/Group Containers/group.net.whatsapp.WhatsApp.shared"
    static let limite = 300

    // WhatsApp (Mac)

    /// Date du dernier message reçu dans ChatStorage.sqlite (T39 : le statut « ok » reste vrai même si WhatsApp Mac est fermé).
    static func dernierRecuWhatsApp() -> Date? {
        guard let b = try? EntLecture(groupeWhatsApp + "/ChatStorage.sqlite"),
              let r = try? b.lignes("SELECT max(ZMESSAGEDATE) AS d FROM ZWAMESSAGE WHERE ZISFROMME = 0").first else { return nil }
        let d = r.entD("d")
        return d > 0 ? Date(timeIntervalSinceReferenceDate: d) : nil
    }

    static func whatsapp(apres: Int?, depuis: Date?, jusqua: Date?, annuaire: () -> EntAnnuaire) throws -> (messages: [EntMessage], curseur: Int) {
        let b = try EntLecture(groupeWhatsApp + "/ChatStorage.sqlite")
        if apres == nil && depuis == nil {
            return ([], (try b.lignes("SELECT max(Z_PK) AS m FROM ZWAMESSAGE").first?.entI("m")) ?? 0)
        }
        let t2001 = 978307200.0
        var filtre = "m.Z_PK > ?", params: [Any] = [apres ?? 0]
        if let d = depuis {
            filtre = "m.ZMESSAGEDATE >= ?"
            params = [d.timeIntervalSince1970 - t2001]
            if let j = jusqua { filtre += " AND m.ZMESSAGEDATE <= ?"; params.append(j.timeIntervalSince1970 - t2001) }
        }
        let lignes = try b.lignes("""
            SELECT m.Z_PK AS pk, m.ZMESSAGEDATE AS d, m.ZMESSAGETYPE AS t, m.ZTEXT AS txt, m.ZISFROMME AS moi, m.ZPUSHNAME AS push,
                   mi.Z_PK AS media, s.ZPARTNERNAME AS partner, s.ZCONTACTJID AS jid, s.ZSESSIONTYPE AS stype,
                   g.ZMEMBERJID AS mjid, g.ZCONTACTNAME AS mnom, mi.ZMOVIEDURATION AS duree, mi.ZTITLE AS titre,
                   mi.ZMEDIALOCALPATH AS chemin
            FROM ZWAMESSAGE m
            LEFT JOIN ZWACHATSESSION s ON s.Z_PK = m.ZCHATSESSION
            LEFT JOIN ZWAGROUPMEMBER g ON g.Z_PK = m.ZGROUPMEMBER
            LEFT JOIN ZWAMEDIAITEM mi ON mi.Z_PK = m.ZMEDIAITEM
            WHERE \(filtre) ORDER BY m.Z_PK LIMIT \(limite)
            """, params)
        var curseur = apres ?? 0
        var sortie: [EntMessage] = []
        let a = lignes.isEmpty ? nil : annuaire()
        for r in lignes {
            curseur = max(curseur, r.entI("pk"))
            let sortant = r.entI("moi") != 0
            let type = r.entI("t")
            if [6, 10, 12, 14].contains(type) { continue }       // événements système, messages supprimés
            var genre = ""
            switch type {
            case 1: genre = "image"
            case 2: genre = "video"
            case 3: genre = "vocal"
            case 4: genre = "contact"
            case 5: genre = "localisation"
            case 8: genre = "document"
            case 11: genre = "gif"
            case 15: genre = "autocollant"
            default: break
            }
            var texte = r.entS("txt")
            if texte.isEmpty && genre == "document" { texte = r.entS("titre") }
            if genre.isEmpty && texte.isEmpty && r.entI("media") != 0 { genre = "piece_jointe" }
            if texte.isEmpty && genre.isEmpty { continue }
            let groupe = r.entI("stype") == 1
            if sortant && (groupe || !genre.isEmpty || texte.isEmpty) { continue }   // mes envois : texte seul, jamais en groupe
            var m = EntMessage(canal: "whatsapp", ref: "whatsapp:\(r.entI("pk"))",
                               date: Date(timeIntervalSince1970: r.entD("d") + t2001))
            m.sortant = sortant
            m.texte = texte
            m.genre = genre
            m.duree = Int(r.entD("duree"))
            if genre == "vocal", !r.entS("chemin").isEmpty { m.fichier = groupeWhatsApp + "/Message/" + r.entS("chemin") }
            m.groupe = groupe
            if groupe { m.nomGroupe = EntNorm.propre(r.entS("partner")) }   // le nom du groupe (entrants-groupes.txt)
            m.curseur = r.entI("pk")
            // Identité : la conversation (1 à 1) ou le membre qui parle (groupe).
            let jid = groupe ? r.entS("mjid") : r.entS("jid")
            let partenaire = EntNorm.propre(groupe ? r.entS("mnom") : r.entS("partner"))
            func ajouter(jid: String) {
                guard let arobase = jid.firstIndex(of: "@") else { return }
                let base = String(jid[..<arobase]).split(separator: ":").first.map(String.init) ?? ""
                if jid.hasSuffix("@lid") {
                    if let v = a?.lid[jid] { m.tels += v.tels; m.noms += v.noms }
                } else if let t = EntNorm.tel(base) {
                    m.tels.append(t)
                    m.adresse = "+" + base
                }
            }
            ajouter(jid: jid)
            if let k = EntNorm.nom(partenaire) { m.noms.append(k) }
            if let t = EntNorm.tel(partenaire) { m.tels.append(t); if m.adresse.isEmpty { m.adresse = partenaire } }
            m.affiche = partenaire.isEmpty ? EntNorm.propre(r.entS("push")) : partenaire
            if m.affiche.isEmpty { m.affiche = m.adresse }
            sortie.append(m)
        }
        return (sortie, curseur)
    }

    // iMessage et SMS (chat.db, accès complet au disque)

    static func texteDeCorpsStructure(_ blob: Data) -> String? {
        let b = [UInt8](blob), marque = Array("NSString".utf8)
        guard b.count > marque.count + 6 else { return nil }
        var debut: Int?
        for i in 0...(b.count - marque.count) where Array(b[i..<(i + marque.count)]) == marque { debut = i + marque.count; break }
        guard var i = debut else { return nil }
        let limite = min(b.count - 2, i + 12)
        while i < limite && b[i] != 0x2b { i += 1 }
        guard i < limite else { return nil }
        i += 1
        var longueur = Int(b[i]), depart = i + 1
        if b[i] == 0x81, i + 2 < b.count { longueur = Int(b[i + 1]) | Int(b[i + 2]) << 8; depart = i + 3 }
        else if b[i] == 0x82, i + 4 < b.count { longueur = Int(b[i + 1]) | Int(b[i + 2]) << 8 | Int(b[i + 3]) << 16 | Int(b[i + 4]) << 24; depart = i + 5 }
        guard longueur > 0, depart + longueur <= b.count else { return nil }
        return String(decoding: b[depart..<(depart + longueur)], as: UTF8.self)
    }

    static func imessage(apres: Int?, depuis: Date?, jusqua: Date?, annuaire: () -> EntAnnuaire) throws -> (messages: [EntMessage], curseur: Int) {
        let b = try EntLecture(Demo.maison.path + "/Library/Messages/chat.db")
        if apres == nil && depuis == nil {
            return ([], (try b.lignes("SELECT max(ROWID) AS m FROM message").first?.entI("m")) ?? 0)
        }
        let t2001 = 978307200.0
        var filtre = "m.ROWID > ?", params: [Any] = [apres ?? 0]
        if let d = depuis {
            filtre = "m.date >= ?"
            params = [Int((d.timeIntervalSince1970 - t2001) * 1_000_000_000)]
            if let j = jusqua { filtre += " AND m.date <= ?"; params.append(Int((j.timeIntervalSince1970 - t2001) * 1_000_000_000)) }
        }
        let lignes = try b.lignes("""
            SELECT m.ROWID AS rid, m.date AS d, m.text AS txt, m.attributedBody AS ab, m.is_from_me AS moi, m.item_type AS it,
                   m.associated_message_type AS amt, h.id AS hid,
                   (SELECT c.style FROM chat_message_join j JOIN chat c ON c.ROWID = j.chat_id WHERE j.message_id = m.ROWID LIMIT 1) AS style,
                   (SELECT group_concat(COALESCE(a.mime_type, ''), ',') FROM message_attachment_join ma
                      JOIN attachment a ON a.ROWID = ma.attachment_id WHERE ma.message_id = m.ROWID) AS mimes,
                   (SELECT a.filename FROM message_attachment_join ma JOIN attachment a ON a.ROWID = ma.attachment_id
                      WHERE ma.message_id = m.ROWID AND a.mime_type LIKE 'audio%' LIMIT 1) AS audio
            FROM message m LEFT JOIN handle h ON h.ROWID = m.handle_id
            WHERE \(filtre) ORDER BY m.ROWID LIMIT \(limite)
            """, params)
        var curseur = apres ?? 0
        var sortie: [EntMessage] = []
        for r in lignes {
            curseur = max(curseur, r.entI("rid"))
            let sortant = r.entI("moi") != 0
            if r.entI("amt") != 0 || r.entI("it") != 0 { continue }   // réactions, événements de groupe
            let brut = r.entD("d")
            let secondes = brut > 1e12 ? brut / 1e9 : brut
            var texte = r.entS("txt")
            if texte.isEmpty, let blob = r["ab"] as? Data { texte = texteDeCorpsStructure(blob) ?? "" }
            texte = texte.replacingOccurrences(of: "\u{FFFC}", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            var genre = ""
            let mimes = r.entS("mimes")
            if mimes.contains("audio") { genre = "vocal" }
            else if mimes.contains("image") { genre = "image" }
            else if mimes.contains("video") { genre = "video" }
            else if !mimes.isEmpty { genre = "piece_jointe" }
            if texte.isEmpty && genre.isEmpty { continue }
            if sortant && (!genre.isEmpty || r.entI("style") == 43) { continue }   // mes envois : texte seul, jamais en groupe
            let hid = r.entS("hid")
            var m = EntMessage(canal: "imessage", ref: "imessage:\(r.entI("rid"))", date: Date(timeIntervalSince1970: secondes + t2001))
            m.sortant = sortant
            m.texte = texte
            m.genre = genre
            m.groupe = r.entI("style") == 43
            if genre == "vocal", !r.entS("audio").isEmpty { m.fichier = NSString(string: r.entS("audio")).expandingTildeInPath }
            m.curseur = r.entI("rid")
            m.adresse = hid
            m.affiche = hid
            if hid.contains("@") { m.mails = [hid.lowercased()] }
            else if let t = EntNorm.tel(hid) { m.tels = [t] }
            else { m.automatique = true }                       // numéro court ou nom d'expéditeur (banque, livraison, codes)
            sortie.append(m)
        }
        return (sortie, curseur)
    }

    /// Retrouve le fichier audio d'un vocal déjà vu (WhatsApp l'enregistre parfois après le message).
    static func fichierVocal(canal: String, id: Int) -> String? {
        guard Reglages.courants.entrants == true else { return nil }
        if canal == "whatsapp" {
            guard let b = try? EntLecture(groupeWhatsApp + "/ChatStorage.sqlite"),
                  let c = try? b.lignes("""
                      SELECT mi.ZMEDIALOCALPATH AS chemin FROM ZWAMESSAGE m JOIN ZWAMEDIAITEM mi ON mi.Z_PK = m.ZMEDIAITEM WHERE m.Z_PK = ?
                      """, [id]).first?.entS("chemin"), !c.isEmpty else { return nil }
            return groupeWhatsApp + "/Message/" + c
        }
        if canal == "imessage" {
            guard let b = try? EntLecture(Demo.maison.path + "/Library/Messages/chat.db"),
                  let f = try? b.lignes("""
                      SELECT a.filename AS f FROM message_attachment_join ma JOIN attachment a ON a.ROWID = ma.attachment_id
                      WHERE ma.message_id = ? AND a.mime_type LIKE 'audio%' LIMIT 1
                      """, [id]).first?.entS("f"), !f.isEmpty else { return nil }
            return NSString(string: f).expandingTildeInPath
        }
        return nil
    }

    // Mail (Envelope Index de Mail.app : tous les comptes, boîtes de réception seulement)

    /// T37 (05/11) : appels manqués (CallHistory, même accès complet au disque que Messages). Un appel manqué = ZORIGINATED = 0 et ZANSWERED = 0.
    /// Ligne : numéro, heure, fiche si le numéro est connu ; sinon « inconnu » (un artisan qui rappelle). Aucun message n'est envoyé.
    static func appels(apres: Int?, depuis: Date?, jusqua: Date?, annuaire: () -> EntAnnuaire) throws -> (messages: [EntMessage], curseur: Int) {
        let b = try EntLecture(Demo.maison.path + "/Library/Application Support/CallHistoryDB/CallHistory.storedata")
        if apres == nil && depuis == nil {
            return ([], (try b.lignes("SELECT max(Z_PK) AS m FROM ZCALLRECORD").first?.entI("m")) ?? 0)
        }
        let t2001 = 978307200.0
        var filtre = "Z_PK > ?", params: [Any] = [apres ?? 0]
        if let d = depuis {
            filtre = "ZDATE >= ?"
            params = [d.timeIntervalSince1970 - t2001]
            if let j = jusqua { filtre += " AND ZDATE <= ?"; params.append(j.timeIntervalSince1970 - t2001) }
        }
        let lignes = try b.lignes("""
            SELECT Z_PK AS rid, ZDATE AS d, CAST(ZADDRESS AS TEXT) AS adr, ZNAME AS nom, ZORIGINATED AS sortant, ZANSWERED AS repondu
            FROM ZCALLRECORD WHERE \(filtre) ORDER BY Z_PK LIMIT \(limite)
            """, params)
        var curseur = apres ?? 0
        var sortie: [EntMessage] = []
        for r in lignes {
            curseur = max(curseur, r.entI("rid"))
            if r.entI("sortant") != 0 || r.entI("repondu") != 0 { continue }       // seulement les appels manqués
            let numero = r.entS("adr")
            var m = EntMessage(canal: "appel", ref: "appel:\(r.entI("rid"))", date: Date(timeIntervalSince1970: r.entD("d") + t2001))
            m.curseur = r.entI("rid")
            m.adresse = numero
            m.affiche = r.entS("nom").isEmpty ? (numero.isEmpty ? "numéro masqué" : numero) : r.entS("nom")
            m.objet = "appel manqué"
            m.texte = "Appel manqué" + (numero.isEmpty ? " (numéro masqué)" : " de \(numero)")
            if numero.contains("@") { m.mails = [numero.lowercased()] }
            else if let t = EntNorm.tel(numero) { m.tels = [t] }
            sortie.append(m)
        }
        return (sortie, curseur)
    }

    static func cheminMail() -> String? {
        let racine = Demo.maison.path + "/Library/Mail"
        guard let versions = try? FileManager.default.contentsOfDirectory(atPath: racine) else { return nil }
        for v in versions.filter({ $0.hasPrefix("V") }).sorted(by: { (Int($0.dropFirst()) ?? 0) > (Int($1.dropFirst()) ?? 0) }) {
            let c = racine + "/\(v)/MailData/Envelope Index"
            if FileManager.default.fileExists(atPath: c) { return c }
        }
        return nil
    }

    // Les motifs d'envoi automatique sont dans Shared/TriEntrants.swift (TriMail.motifsAutomatiques).

    /// `--diag-tout` (essai à blanc) : lit aussi les messages hors boîte de réception et supprimés, pour comprendre un mail raté.
    static var diagTout = false

    static func mail(apres: Int?, depuis: Date?, jusqua: Date?, annuaire: () -> EntAnnuaire) throws -> (messages: [EntMessage], curseur: Int) {
        guard let chemin = cheminMail() else { throw EntErreur(description: "unable to open ~/Library/Mail (not permitted ou Mail jamais lancé)") }
        let b = try EntLecture(chemin)
        let colonnes = Set(try b.lignes("PRAGMA table_info(messages)").map { $0.entS("name") })
        for requise in ["ROWID", "date_received", "sender", "subject", "mailbox"] where !colonnes.contains(requise) {
            throw EntErreur(description: "schéma Mail inconnu, colonne absente : \(requise) (colonnes : \(colonnes.sorted().joined(separator: ",")))")
        }
        if diagTout {                                      // diagnostic : schéma de l'index (stderr), pour comprendre où Mail range les libellés Gmail
            for t in try b.lignes("SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name").map({ $0.entS("name") }) {
                let cols = (try? b.lignes("PRAGMA table_info(\(t))").map { $0.entS("name") }) ?? []
                FileHandle.standardError.write(Data("schema \(t): \(cols.joined(separator: ","))\n".utf8))
            }
            for u in (try? b.lignes("SELECT url, total_count AS n FROM mailboxes ORDER BY url")) ?? [] {
                FileHandle.standardError.write(Data("boite \(u.entS("url")) (\(u.entI("n")))\n".utf8))
            }
        }
        if apres == nil && depuis == nil {
            return ([], (try b.lignes("SELECT max(ROWID) AS m FROM messages").first?.entI("m")) ?? 0)
        }
        let etiquettes = !(try b.lignes("SELECT 1 AS x FROM sqlite_master WHERE type = 'table' AND name = 'labels'")).isEmpty
        // Passe normale : les messages neufs (ROWID > curseur) ET le rattrapage des dernières heures (étiquette INBOX arrivée après coup).
        var filtre = "(m.ROWID > ? OR m.date_received >= ?)"
        var params: [Any] = [apres ?? 0, Int(Date().timeIntervalSince1970 - MailBoiteReception.fenetreRattrapage)]
        if let d = depuis {
            filtre = "m.date_received >= ?"
            params = [Int(d.timeIntervalSince1970)]
            if let j = jusqua { filtre += " AND m.date_received <= ?"; params.append(Int(j.timeIntervalSince1970)) }
        }
        if colonnes.contains("deleted") && !diagTout { filtre += " AND m.deleted = 0" }
        let liste = colonnes.contains("list_id_hash") ? "m.list_id_hash AS lh" : "0 AS lh"
        let resume = colonnes.contains("summary") ? "LEFT JOIN summaries su ON su.ROWID = m.summary" : ""
        let resumeCol = colonnes.contains("summary") ? "su.summary AS resume" : "'' AS resume"
        let lignes = try b.lignes("""
            SELECT m.ROWID AS rid, m.date_received AS d, a.address AS addr, a.comment AS cmt, s.subject AS subj, \(colonnes.contains("subject_prefix") ? "m.subject_prefix" : "''") AS pref, \(colonnes.contains("conversation_id") ? "m.conversation_id" : "0") AS conv, \(resumeCol), \(liste), mb.url AS boite, \(colonnes.contains("deleted") ? "m.deleted" : "0") AS del, \(etiquettes ? "(SELECT group_concat(lb.url, ' ; ') FROM labels l JOIN mailboxes lb ON lb.ROWID = l.mailbox_id WHERE l.message_id = m.ROWID)" : "''") AS etiq
            FROM messages m
            LEFT JOIN addresses a ON a.ROWID = m.sender
            LEFT JOIN subjects s ON s.ROWID = m.subject
            \(resume)
            JOIN mailboxes mb ON mb.ROWID = m.mailbox
            WHERE \(filtre)\(diagTout ? "" : " AND " + MailBoiteReception.condition(avecEtiquettes: etiquettes)) ORDER BY m.ROWID LIMIT \(limite)
            """, params)
        // Mes envois des 90 derniers jours (une seule requête par passe, seulement s'il y a du courrier à examiner).
        let envois: [EnvoiDeSacha] = lignes.isEmpty ? [] : {
            let sql = ReponseAEnvoi.requete(avecConversation: colonnes.contains("conversation_id"), avecSupprime: colonnes.contains("deleted"))
            let depuisEnvois = Int(Date().timeIntervalSince1970 - ReponseAEnvoi.fenetre)
            return ((try? b.lignes(sql, [depuisEnvois])) ?? []).map { e in
                var t = e.entD("d")
                if t < 1_000_000_000 { t += 978307200 }
                return EnvoiDeSacha(adresse: e.entS("adresse"), sujet: e.entS("sujet"), conversation: e.entI("conv"), le: Date(timeIntervalSince1970: t))
            }
        }()
        var curseur = apres ?? 0
        var sortie: [EntMessage] = []
        for r in lignes {
            curseur = max(curseur, r.entI("rid"))
            var secondes = r.entD("d")
            if secondes < 1_000_000_000 { secondes += 978307200 }      // dates de Mail parfois depuis 2001
            let adresse = r.entS("addr").lowercased()
            guard !adresse.isEmpty else { continue }
            var m = EntMessage(canal: "mail", ref: "mail:\(r.entI("rid"))", date: Date(timeIntervalSince1970: secondes))
            m.adresse = adresse
            m.mails = [adresse]
            m.objet = r.entS("subj")
            m.texte = r.entS("resume")
            m.curseur = r.entI("rid")
            m.envoisAdresse = envois.filter { m.mails.contains($0.adresse) }
                .map { Dates.iso.string(from: $0.le) + " " + $0.sujet }.joined(separator: " ¦ ")
            m.reponseEnvoi = ReponseAEnvoi.raison(prefixe: r.entS("pref"), objet: m.objet, adresses: m.mails, conversation: r.entI("conv"),
                                                  recu: m.date, envois: envois) ?? ""
            m.indesirable = MailBoiteReception.estIndesirable(r.entS("boite"))
            m.boite = r.entS("boite") + (r.entI("del") != 0 ? " [supprimé]" : "") + (r.entS("etiq").isEmpty ? "" : " + étiquettes : " + r.entS("etiq"))
            // Nom sans « via LinkedIn », plateforme suivie, automatique, rebond, auto probable (Shared/TriEntrants.swift).
            TriMail.preparer(&m, commentaire: r.entS("cmt"), listeId: r.entI("lh") != 0)
            sortie.append(m)
        }
        return (sortie, curseur)
    }
}

// MARK: - Commande

enum Entrants {
    static let etiquette = "io.github.pjksens.pilote.entrants"

    static var dossier: URL {
        if let d = ProcessInfo.processInfo.environment["PILOTE_ENTRANTS_DIR"], !d.isEmpty {
            let u = URL(fileURLWithPath: d, isDirectory: true)
            try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
            return u
        }
        return Base.dossier
    }
    static var fichier: URL { dossier.appendingPathComponent("entrants.jsonl") }
    static var fichierEtat: URL { dossier.appendingPathComponent("entrants-etat.json") }
    static var plist: URL { URL(fileURLWithPath: Demo.maison.path + "/Library/LaunchAgents/\(etiquette).plist") }

    static let aide = """
    pilote entrants : capteur de messages entrants (iMessage, WhatsApp, Mail) — lecture seule, tri sans IA

      pilote entrants --suivre [--dernieres n]  affiche chaque nouvelle ligne de entrants.jsonl dès qu'elle arrive (pour Monitor)
      pilote entrants --capter                  une passe (launchd la lance toutes les 60 s)
            [--source whatsapp,imessage,mail,appel] [--depuis 2h|AAAA-MM-JJTHH:MM] [--jusqua AAAA-MM-JJTHH:MM] [--a-blanc]
            [--diag]                            (avec --a-blanc : liste TOUS les messages lus avec classe et raison, même ignorés ou déjà émis)
            [--diag-tout]                       (avec --diag : lit aussi les mails hors boîte de réception et supprimés, affiche la boîte)
            [--transcrire]                      (avec --a-blanc : transcrit aussi les vocaux de l'aperçu ; sinon la transcription est automatique)
      pilote entrants --etat                    curseurs, accès par source, dernière passe, vocaux en attente de transcription
      pilote entrants --lire [n]                les n dernières lignes (20 par défaut)
      pilote entrants --rejouer <fichier.jsonl> rejoue le tri des mails de ces lignes avec les règles actuelles (rien n'est écrit)
      pilote entrants --installer | --desinstaller   tâche de fond launchd (\(etiquette))
    Fichiers : ~/Library/Application Support/io.github.pjksens.pilote/entrants.jsonl, entrants-etat.json, entrants-ignorer.txt (adresses à ignorer, une par ligne),
      entrants-groupes.txt (groupes WhatsApp suivis, un morceau de nom par ligne), entrants-ecartes.jsonl (ignore et perso, 14 jours)
    """

    static func lancer(_ args: [String]) {
        setvbuf(stdout, nil, _IOLBF, 0)
        if args.contains("--suivre") { suivre(dernieres: Int(option("--dernieres", args) ?? "") ?? 0) }
        else if args.contains("--capter") { capter(args) }
        else if args.contains("--etat") { etatCommande() }
        else if let f = option("--rejouer", args) { rejouer(f) }
        else if args.contains("--lire") { lire(Int(option("--lire", args) ?? "") ?? 20) }
        else if args.contains("--installer") { installer() }
        else if args.contains("--desinstaller") { desinstaller() }
        else { print(aide) }
    }

    static func option(_ nom: String, _ args: [String]) -> String? {
        guard let i = args.firstIndex(of: nom), i + 1 < args.count, !args[i + 1].hasPrefix("--") else { return nil }
        return args[i + 1]
    }

    // MARK: Passe

    /// Rejoue le tri des lignes mail d'un fichier entrants.jsonl (adresse, qui, objet, extrait) avec les règles actuelles et la vraie
    /// base Pilote. Lecture seule : rien n'est écrit, ni au fil ni dans entrants.jsonl. Sert à prouver un changement de règle.
    static func rejouer(_ chemin: String) {
        let stock = (try? Base()).map { Stockage(base: $0) }
        let a = EntAnnuaire(contacts: (try? stock?.contacts()) ?? [])
        let t = (try? String(contentsOfFile: chemin, encoding: .utf8)) ?? ""
        for l in t.split(separator: "\n") {
            guard let d = l.data(using: .utf8), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                  (o["canal"] as? String) == "mail", let adresse = o["adresse"] as? String else { continue }
            var m = EntMessage(canal: "mail", ref: (o["ref"] as? String) ?? "", date: Date())
            m.adresse = adresse.lowercased()
            m.mails = [m.adresse]
            m.objet = (o["objet"] as? String) ?? ""
            m.texte = (o["extrait"] as? String) ?? ""
            m.reponseEnvoi = (o["reponse_a_envoi"] as? String) ?? ""
            TriMail.preparer(&m, commentaire: (o["qui"] as? String) ?? "", listeId: false)
            let r = a.classer(m)
            let sortie: [String: Any] = [
                "ref": m.ref, "heure": (o["heure"] as? String) ?? "", "adresse": m.adresse, "objet": EntNorm.extrait(m.objet, max: 60),
                "avant": ["classe": o["classe"] ?? "", "auto": (o["auto"] as? Bool) ?? false, "contact_id": o["contact_id"] ?? ""],
                "apres": ["classe": r.classe, "via": r.via, "auto": TriMail.masquer(m, classe: r.classe, via: r.via), "plateforme": m.plateforme,
                          "contact_id": r.contact?.id ?? "", "qui": r.classe == "travail" ? (r.contact?.nom ?? "") : m.affiche, "rebond": m.rebond,
                          "linkedin": m.linkedin, "signal_seul": m.signalSeul],
            ]
            if let j = try? JSONSerialization.data(withJSONObject: sortie, options: [.sortedKeys, .withoutEscapingSlashes]) {
                print(String(decoding: j, as: UTF8.self))
            }
        }
    }

    static func lireEtat() -> EntEtat {
        guard let d = try? Data(contentsOf: fichierEtat), let e = try? JSONDecoder().decode(EntEtat.self, from: d) else { return EntEtat() }
        return e
    }

    static func ecrireEtat(_ e: EntEtat) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let d = try? enc.encode(e) else { return }
        try? d.write(to: fichierEtat, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fichierEtat.path)
    }

    static func date(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        if let m = try? NSRegularExpression(pattern: #"^(\d+)([mhj])$"#).firstMatch(in: s, range: NSRange(location: 0, length: s.utf16.count)),
           let n = Double((s as NSString).substring(with: m.range(at: 1))) {
            let u = (s as NSString).substring(with: m.range(at: 2))
            return Date().addingTimeInterval(-n * (u == "m" ? 60 : u == "h" ? 3600 : 86400))
        }
        if let d = Dates.iso.date(from: s) { return d }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Europe/Paris")
        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
            f.dateFormat = format
            if let d = f.date(from: s) { return d }
        }
        return nil
    }

    static let heureLocale: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Europe/Paris")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXX"
        return f
    }()

    static func refsDejaEmises() -> Set<String> {
        guard let t = try? String(contentsOf: fichier, encoding: .utf8) else { return [] }
        var refs = Set<String>()
        for l in t.split(separator: "\n") {
            if let d = l.data(using: .utf8), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let r = o["ref"] as? String { refs.insert(r) }
        }
        return refs
    }

    static func ajouterLigne(_ ligne: [String: Any]) {
        guard var d = try? JSONSerialization.data(withJSONObject: ligne, options: [.sortedKeys, .withoutEscapingSlashes]) else { return }
        d.append(0x0A)
        if !FileManager.default.fileExists(atPath: fichier.path) {
            FileManager.default.createFile(atPath: fichier.path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        guard let h = try? FileHandle(forWritingTo: fichier) else { return }
        defer { try? h.close() }
        _ = try? h.seekToEnd()
        try? h.write(contentsOf: d)
    }

    static func capter(_ args: [String]) {
        // Une seule passe à la fois (launchd et un essai à la main ne se marchent pas dessus).
        let verrou = open(dossier.appendingPathComponent("entrants.verrou").path, O_CREAT | O_RDWR, 0o600)
        if verrou >= 0 && flock(verrou, LOCK_EX | LOCK_NB) != 0 { exit(0) }

        let aBlanc = args.contains("--a-blanc")
        EntSource.diagTout = aBlanc && args.contains("--diag-tout")
        let depuis = date(option("--depuis", args)), jusqua = date(option("--jusqua", args))
        // Coupé tant que reglages.json ne dit pas `entrants: true` : aucune source lue (le reste de la passe tourne).
        let sources = Reglages.courants.entrants == true
            ? (option("--source", args) ?? "whatsapp,imessage,mail,appel").split(separator: ",").map(String.init) : []
        var etat = lireEtat()
        let maintenant = Dates.maintenant()
        let stock = (try? Base()).map { Stockage(base: $0) }

        var annuaireCache: EntAnnuaire?
        func annuaire() -> EntAnnuaire {
            if let a = annuaireCache { return a }
            var a = EntAnnuaire(contacts: (try? stock?.contacts()) ?? [])
            a.lireContactsWhatsApp(EntSource.groupeWhatsApp)
            a.lireContactsMac()
            a.ignorer = a.chargerIgnorer(dossier)
            a.groupesSuivis = a.chargerGroupes(dossier)
            a.suivis = etat.suivis ?? [:]
            annuaireCache = a
            return a
        }
        var ecartes: [[String: Any]] = []                      // T47 : ignore et perso, écrits en fin de passe

        let dejaEmises = (depuis != nil || sources.contains("mail")) ? refsDejaEmises() : []
        let moteurPret = EntTranscription.pret()
        var bilan: [String: Int] = [:]
        var apercu: [[String: Any]] = []

        let lecteurs: [(String, (Int?, Date?, Date?, () -> EntAnnuaire) throws -> ([EntMessage], Int))] = [
            ("whatsapp", { try EntSource.whatsapp(apres: $0, depuis: $1, jusqua: $2, annuaire: $3) }),
            ("imessage", { try EntSource.imessage(apres: $0, depuis: $1, jusqua: $2, annuaire: $3) }),
            ("mail", { try EntSource.mail(apres: $0, depuis: $1, jusqua: $2, annuaire: $3) }),
            ("appel", { try EntSource.appels(apres: $0, depuis: $1, jusqua: $2, annuaire: $3) }),
        ]
        for (nom, lire) in lecteurs where sources.contains(nom) {
            do {
                let (messages, curseur) = try lire(etat.curseurs[nom], depuis, jusqua, annuaire)
                for m in messages {
                    if aBlanc, args.contains("--diag") {            // 04/11 : audit de tri, montre TOUT message lu avec sa classe et la raison
                        let r = annuaire().classer(m)
                        apercu.append(["diag": true, "ref": m.ref, "heure": Dates.iso.string(from: m.date), "adresse": m.adresse, "objet": m.objet, "qui": m.affiche,
                                       "classe": r.classe, "via": r.via, "automatique": m.automatique, "auto": TriMail.masquer(m, classe: r.classe, via: r.via),
                                       "plateforme": m.plateforme, "rebond": m.rebond, "groupe": m.nomGroupe, "contact_id": r.contact?.id ?? "",
                                       "sortant": m.sortant, "reponse_envoi": m.reponseEnvoi, "boite": m.boite,
                                       "indesirable": m.indesirable, "garde_indesirable": TriMail.garderIndesirable(m, contact: r.contact),
                                       "texte": EntNorm.extrait(m.texte, max: 600), "envois_a_cette_adresse": m.envoisAdresse])
                        continue
                    }
                    if m.sortant {                                  // 04/11 : mes envois ne sont ni classés ni émis (GO de PILOTE, point c)
                        if !aBlanc, depuis == nil, let stock {
                            traiterSortant(m, annuaire(), stock)
                            // T14 : le texte d'une fiche envoyé à un numéro absent de Pilote : ses réponses ne seront plus « perso ».
                            if let (cle, s) = suiviPourEnvoi(m, annuaire(), stock) {
                                etat.suivis = (etat.suivis ?? [:]).merging([cle: s]) { _, n in n }
                                annuaireCache?.suivis[cle] = s
                                bilan["suivis_ajoutes", default: 0] += 1
                            }
                        }
                        continue
                    }
                    // Mail : un message déjà derrière le curseur est relu par le rattrapage (étiquette INBOX arrivée après coup).
                    let rattrapage = nom == "mail" && depuis == nil && m.curseur <= (etat.curseurs["mail"] ?? 0)
                    if rattrapage && dejaEmises.contains(m.ref) { continue }
                    let r = annuaire().classer(m)
                    if rattrapage && !MailBoiteReception.aTraiter(rowid: m.curseur, curseur: etat.curseurs["mail"] ?? 0, classe: r.classe, dejaEmis: false) { continue }
                    // T13 : un mail d'Indésirables sans fiche ni plateforme suivie reste écarté (trace 14 jours, comme T47).
                    if !TriMail.garderIndesirable(m, contact: r.contact) {
                        if !aBlanc, depuis == nil, !rattrapage { ecartes.append(Ecartes.ligne(m, classe: "ignore", via: "indésirable")) }
                        continue
                    }
                    bilan[r.classe, default: 0] += 1
                    switch r.classe {
                    case "perso", "ignore":
                        guard !aBlanc, depuis == nil else { continue }
                        ecartes.append(Ecartes.ligne(m, classe: r.classe, via: r.via))   // T47 : une trace, gardée 14 jours
                        guard r.classe == "perso" else { continue }
                        let cle = EntNorm.empreinte(m.canal + "|" + (m.tels.first ?? m.mails.first ?? m.noms.first ?? m.adresse))
                        var v = etat.vus[cle] ?? EntVu(premier: maintenant, dernier: maintenant, n: 0)
                        v.dernier = maintenant
                        v.n += 1
                        etat.vus[cle] = v
                    case "travail", "inconnu":
                        if dejaEmises.contains(m.ref) || (etat.attente ?? []).contains(where: { $0.ref == m.ref }) { continue }
                        var ligne = construireLigne(m, r.classe, r.contact, r.via)
                        if r.classe == "inconnu", !m.reponseEnvoi.isEmpty, !aBlanc, depuis == nil { bilan["reponses_sans_fiche", default: 0] += 1 }
                        // Un vocal de travail ou d'inconnu est transcrit en local (jamais un vocal perso : cette branche ne les voit pas).
                        let transcrit = m.genre == "vocal" && moteurPret
                        if aBlanc {
                            if transcrit && args.contains("--transcrire"), let chemin = Self.fichierPourEssai(m),
                               let t = EntTranscription.transcrire(chemin, qui: r.contact?.nom ?? m.affiche, entreprise: r.contact?.entreprise ?? "", delai: 300).texte {
                                conclureLigne(&ligne, classe: r.classe, duree: m.duree, texte: t, note: "")
                            }
                            apercu.append(ligne); continue
                        }
                        var evenementId = ""
                        if r.classe == "travail", let c = r.contact, let stock {     // un rebond porte la fiche sans aller au fil
                            evenementId = ajouterAuFil(stock, c, m, &etat, enCours: transcrit) ?? ""
                            // 04/11 (GO de PILOTE, point a) : une réponse d'un contact connu crée l'action « Répondre à… » du jour.
                            // 05/11 : pas pour un signal LinkedIn sans message (invitation acceptée) : note au fil seulement.
                            if !evenementId.isEmpty, !m.signalSeul, depuis == nil, !aBlanc, let note = try? stock.actionRepondre(contactId: c.id) {
                                prevenirAgent(c, note)
                            }
                        }
                        if transcrit, let json = try? JSONSerialization.data(withJSONObject: ligne, options: [.sortedKeys, .withoutEscapingSlashes]) {
                            etat.attente = (etat.attente ?? []) + [EntAttente(
                                ref: m.ref, canal: m.canal, classe: r.classe, ligne: String(decoding: json, as: UTF8.self), fichier: m.fichier,
                                sourceId: m.curseur, evenementId: evenementId, duree: m.duree, essais: 0)]
                        } else {
                            ajouterLigne(ligne)
                        }
                    default: break
                    }
                }
                if depuis == nil && !aBlanc { etat.curseurs[nom] = max(etat.curseurs[nom] ?? 0, curseur) }
                if !aBlanc { etat.statuts[nom] = EntStatut(ok: true, message: "ok", le: maintenant) }
                if nom == "whatsapp", !aBlanc, let d = EntSource.dernierRecuWhatsApp() { etat.whatsappRecu = Dates.iso.string(from: d) }
            } catch {
                let e = (error as? EntErreur) ?? EntErreur(description: "\(error)")
                let message = e.refus
                    ? "accès refusé : accorder « Accès complet au disque » à \(binaire()) (\(e.description))"
                    : e.description
                if !aBlanc { etat.statuts[nom] = EntStatut(ok: false, message: message, le: maintenant) }
                FileHandle.standardError.write(Data("[\(maintenant)] \(nom) : \(message)\n".utf8))
            }
        }
        for a in annuaireCache?.avertissements ?? [] {
            if !aBlanc { etat.statuts["contacts"] = EntStatut(ok: false, message: a, le: maintenant) }
        }
        if annuaireCache != nil, annuaireCache?.avertissements.isEmpty == true, !aBlanc {
            etat.statuts["contacts"] = EntStatut(ok: true, message: "ok", le: maintenant)
        }
        if !aBlanc {
            ecrireEcartes(ecartes)
            // T14 : un numéro suivi depuis plus de 60 jours redevient ordinaire.
            if let s = etat.suivis {
                let limite = Date().addingTimeInterval(-60 * 86400)
                etat.suivis = s.filter { (Dates.iso.date(from: $0.value.le) ?? Date()) > limite }
            }
            etat.passe = maintenant
            for (k, v) in bilan { etat.cumul[k, default: 0] += v }
            // Les repères « déjà vu » de plus de 90 jours s'effacent.
            let limite = Date().addingTimeInterval(-90 * 86400)
            etat.vus = etat.vus.filter { (Dates.iso.date(from: $0.value.dernier) ?? Date()) > limite }
            ecrireEtat(etat)                                   // curseurs et file d'attente sont sauvés AVANT la transcription (longue)
            let (faits, echecs) = traiterAttente(&etat, stock)
            if faits > 0 { bilan["vocaux_transcrits"] = faits }
            if echecs > 0 { bilan["vocaux_non_transcrits"] = echecs }
            // 04/11 : tant qu'un serveur MCP plus vieux que le binaire tourne, on rétablit les suites qu'il a pu oublier.
            if depuis == nil, let stock {
                let n = ReparationAuto.passe(stock, binaire: URL(fileURLWithPath: binaire()))
                if n > 0 { bilan["suites_reparees"] = n }
                // 04/11 piste 2 : relevé « envoyé depuis kryva.fr » (au plus toutes les 5 min), signalé au contrôle du matin.
                if let k = ReleveKryva.passe(), k > 0 { bilan["envois_kryva_48h"] = k }
            }
        }
        var sortie: [String: Any] = ["passe": maintenant, "bilan": bilan]
        if aBlanc { sortie["apercu"] = apercu }
        if let d = try? JSONSerialization.data(withJSONObject: sortie, options: [.sortedKeys, .withoutEscapingSlashes]) {
            print(String(data: d, encoding: .utf8) ?? "")
        }
    }

    static func construireLigne(_ m: EntMessage, _ classe: String, _ c: Contact?, _ via: String) -> [String: Any] {
        let max = classe == "travail" ? 300 : 120
        let fiche = classe == "travail" ? c : nil               // un rebond nomme la fiche sans la prendre pour l'expéditeur
        var ligne: [String: Any] = [
            "ref": m.ref, "canal": m.canal, "classe": classe,
            "qui": fiche?.nom ?? m.affiche, "heure": heureLocale.string(from: m.date),
            "contact_id": c?.id ?? "",
        ]
        if !m.adresse.isEmpty { ligne["adresse"] = m.adresse }
        if classe == "inconnu" && !m.reponseEnvoi.isEmpty {     // 04/11 (Paul DURAND) : réponse à un envoi de Sacha, sans fiche Pilote
            ligne["reponse_a_envoi"] = m.reponseEnvoi
            ligne["alerte"] = "réponse à un mail envoyé par \(Moi.tiers), sans fiche Pilote : crée la fiche ou rattache"
        }
        // 04/11 : reste en base, la veille ne l'envoie pas à PILOTE. 05/11 : seulement un inconnu pur (TriMail.masquer).
        if TriMail.masquer(m, classe: classe, via: via) { ligne["auto"] = true }
        if m.indesirable { ligne["indesirable"] = true }                      // T13 : trouvé dans Indésirables
        if !m.plateforme.isEmpty { ligne["plateforme"] = m.plateforme }      // 05/11 : montrée en ligne courte par la veille
        if m.linkedin { ligne["linkedin"] = true }
        if !m.nomGroupe.isEmpty { ligne["groupe"] = m.nomGroupe }
        switch via {
        case "rebond":
            ligne["rebond"] = true
            ligne["alerte"] = c.map { "mail de \(Moi.tiers) NON REMIS à \($0.nom.isEmpty ? $0.entreprise : $0.nom) (\($0.email)) : vérifier l'adresse, noter l'échec à la fiche" }
                ?? "mail de \(Moi.tiers) NON REMIS (adresse citée : \(m.rebondPour.first ?? "?")) : retrouver la fiche, noter l'échec"
        case "domaine":
            ligne["alerte"] = "rattaché par le domaine (\(EntNorm.domaine(m.adresse) ?? "")) : autre adresse que la fiche, à ajouter si c'est la même personne"
        case "envoi":
            ligne["alerte"] = c.map { "numéro absent de la fiche : \(Moi.tiers) lui a envoyé le texte de \($0.nom) ; ajouter le numéro si c'est la même personne" }
                ?? "\(Moi.tiers) lui a envoyé le texte de plusieurs fiches : numéro absent de Pilote, rattacher ou créer la fiche"
        case "nom ambigu":
            ligne["alerte"] = "nom porté par plusieurs fiches : rattacher à la bonne"
        case "groupe suivi":
            ligne["alerte"] = "groupe suivi (entrants-groupes.txt)"
        default: break
        }
        if !via.isEmpty { ligne["via"] = via }
        if m.genre == "vocal" {
            ligne["vocal"] = true
            if m.duree > 0 { ligne["duree_s"] = m.duree }
            ligne["extrait"] = m.duree > 0
                ? "vocal \(m.duree / 60):\(String(format: "%02d", m.duree % 60)), à écouter" : "vocal, à écouter"
        } else {
            if !m.genre.isEmpty { ligne["piece_jointe"] = m.genre }
            ligne["extrait"] = EntNorm.extrait(m.texte, max: max)
        }
        if !m.objet.isEmpty { ligne["objet"] = EntNorm.extrait(m.objet, max: max) }
        return ligne
    }

    /// L'agent du contact (Ventes ou FREELANCE) l'apprend par le Facteur, comme pour une action de Sacha dans l'app.
    static func prevenirAgent(_ c: Contact, _ fait: String) {
        let nom = c.sousTitre.isEmpty ? c.titre : "\(c.titre) (\(c.sousTitre))"
        try? Decisions.noter(question: "Suivi de \(nom) (\(c.id))",
                             choix: "\(fait) La fiche porte déjà la trace au fil. À toi : vérifie l'étape, la prochaine action et la date, prends les dispositions, n'oublie rien.",
                             ref: "suivi:\(c.id):\(Int(Date().timeIntervalSince1970))",
                             liste: c.espace == "kryva" ? "Appels" : "Freelance", pour: c.espace == "kryva" ? "KRYVA · Ventes" : "FREELANCE")
    }

    /// T14 : un envoi de Sacha (WhatsApp, SMS) à un numéro absent de Pilote, dont le texte est celui d'une fiche (préparé ou envoyé
    /// depuis 30 jours) : le numéro devient « suivi », ses réponses vont à cette fiche (ou à PILOTE si plusieurs fiches avaient ce texte).
    /// Un message de Sacha à un proche ne ressemble à aucun texte de fiche : il reste perso.
    static func suiviPourEnvoi(_ m: EntMessage, _ annuaire: EntAnnuaire, _ stock: Stockage) -> (String, EntSuivi)? {
        guard annuaire.contactPilote(m) == nil, let cle = m.tels.first ?? m.mails.first, annuaire.suivis[cle] == nil,
              Sortants.normaliser(m.texte).count >= 30 else { return nil }
        let depuis = Dates.iso.string(from: Date().addingTimeInterval(-30 * 86400))
        let textes = ((try? stock.messages(statut: "envoye")) ?? []) + ((try? stock.messages(statut: "prepare")) ?? [])
        let fiches = Set(textes.filter { $0.0.le >= depuis && Sortants.correspond(envoye: m.texte, prepare: $0.0.texte) }.map(\.1))
        guard let premiere = fiches.first else { return nil }
        let c: Contact? = fiches.count == 1 ? premiere : nil
        return (cle, EntSuivi(contactId: c?.id ?? "", nom: c.map { $0.nom.isEmpty ? $0.entreprise : $0.nom } ?? "", le: Dates.iso.string(from: m.date)))
    }

    /// T47 : les messages écartés (ignore, perso) laissent une ligne dans entrants-ecartes.jsonl ; plus de 14 jours, elle s'efface.
    static var fichierEcartes: URL { dossier.appendingPathComponent("entrants-ecartes.jsonl") }

    static func ecrireEcartes(_ nouvelles: [[String: Any]]) {
        let chemin = fichierEcartes.path
        let anciennes = ((try? String(contentsOfFile: chemin, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
        let gardees = Ecartes.purger(anciennes)
        guard !nouvelles.isEmpty || gardees.count != anciennes.count else { return }
        let ajout = nouvelles.compactMap { (try? JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys, .withoutEscapingSlashes]))
            .map { String(decoding: $0, as: UTF8.self) } }
        let texte = (gardees + ajout).joined(separator: "\n") + "\n"
        let tmp = chemin + ".tmp"
        guard FileManager.default.createFile(atPath: tmp, contents: Data(texte.utf8), attributes: [.posixPermissions: 0o600]) else { return }
        if rename(tmp, chemin) != 0 { unlink(tmp) }            // remplacement d'un coup (jamais un fichier à moitié écrit)
    }

    /// Un message envoyé par Sacha (WhatsApp, SMS) à un contact connu : rapproché d'un message prêt (Stockage.captureSortante).
    static func traiterSortant(_ m: EntMessage, _ annuaire: EntAnnuaire, _ stock: Stockage) {
        guard let (c, via) = annuaire.contactPilote(m), via != "nom" else { return }   // téléphone ou e-mail seulement : un nom ne prouve pas le destinataire
        guard let r = try? stock.captureSortante(contactId: c.id, canal: m.canal, texte: m.texte, le: m.date, ref: m.ref) else { return }
        switch r {
        case .marqueEnvoye: prevenirAgent(c, "Message \(Sortants.libelleCanal(m.canal)) envoyé par \(Moi.tiers) (capté), passé à « envoyé ».")
        case .aVerifier: prevenirAgent(c, "Envoi possible (\(Sortants.libelleCanal(m.canal))) à vérifier : un message préparé attend toujours.")
        case .rien: break
        }
    }

    static func prefixeFil(_ canal: String) -> String { canal == "whatsapp" ? "WhatsApp : " : canal == "imessage" ? "iMessage : " : canal == "appel" ? "Appel : " : "" }

    static func libelleVocal(_ duree: Int) -> String { duree > 0 ? "vocal \(duree / 60):\(String(format: "%02d", duree % 60))" : "vocal" }

    /// Ajoute le message au fil du contact ; rend l'identifiant de l'événement (pour y mettre plus tard la transcription d'un vocal).
    @discardableResult
    static func ajouterAuFil(_ stock: Stockage, _ c: Contact, _ m: EntMessage, _ etat: inout EntEtat, enCours: Bool = false) -> String? {
        let prefixe = m.linkedin ? "LinkedIn : " : prefixeFil(m.canal)
        var corps: String
        if m.genre == "vocal" {
            corps = libelleVocal(m.duree) + (enCours ? ", transcription en cours" : ", à écouter")
        } else {
            corps = EntNorm.extrait(m.texte, max: 1500)
            if !m.genre.isEmpty { corps = corps.isEmpty ? "[\(m.genre)]" : corps + " [\(m.genre)]" }
        }
        var champs: [String: Any] = [
            "le": Dates.iso.string(from: m.date), "canal": m.linkedin ? "linkedin" : m.canal == "imessage" ? "sms" : m.canal == "mail" ? "mail" : "autre",
            "sens": "entrant", "type": m.signalSeul ? "note" : "reponse", "texte": prefixe + corps, "statut": "fait", "par": "Capteur Pilote",
            "source_ref": m.ref,
        ]
        if !m.objet.isEmpty { champs["objet"] = m.objet }
        do { return try stock.ajouterEvenement(contactId: c.id, champs).id }
        catch { etat.statuts["fil"] = EntStatut(ok: false, message: "\(error)", le: Dates.maintenant()); return nil }
    }

    // MARK: Transcription des vocaux (locale, après le tri : jamais un vocal perso)

    static func fichierPourEssai(_ m: EntMessage) -> String? {
        if !m.fichier.isEmpty, FileManager.default.fileExists(atPath: m.fichier) { return m.fichier }
        if let f = EntSource.fichierVocal(canal: m.canal, id: m.curseur), FileManager.default.fileExists(atPath: f) { return f }
        return nil
    }

    /// Complète la ligne d'un vocal. Travail : texte entier dans « transcription » (extrait = durée seule) ; inconnu : 120 caractères.
    static func conclureLigne(_ ligne: inout [String: Any], classe: String, duree: Int, texte: String?, note: String) {
        let v = libelleVocal(duree)
        if let t = texte?.trimmingCharacters(in: .whitespacesAndNewlines) {
            if t.isEmpty {
                ligne["extrait"] = "\(v), rien d'audible"
            } else if classe == "travail" {
                ligne["transcription"] = EntNorm.extrait(t, max: 8000)
                ligne["extrait"] = v
            } else {
                ligne["extrait"] = "\(v) : " + EntNorm.extrait(t, max: 120)
            }
            ligne["transcrit"] = true
        } else {
            ligne["extrait"] = "\(v), à écouter (\(note))"
        }
    }

    /// Transcrit les vocaux en attente, dans la limite d'un budget de temps par passe ; le reste attend la passe suivante.
    static func traiterAttente(_ etat: inout EntEtat, _ stock: Stockage?, budget: TimeInterval = 150) -> (faits: Int, echecs: Int) {
        guard let file = etat.attente, !file.isEmpty else { return (0, 0) }
        _ = setpriority(PRIO_PROCESS, 0, 10)                   // la transcription ne doit pas gêner le Mac
        let debut = Date()
        var reste: [EntAttente] = []
        var faits = 0, echecs = 0
        for i in file.indices {
            var a = file[i]
            if Date().timeIntervalSince(debut) > budget { reste.append(a); continue }
            var conclu = false
            var texte: String?
            var note = ""
            var chemin = FileManager.default.fileExists(atPath: a.fichier) ? a.fichier : ""
            if chemin.isEmpty, let f = EntSource.fichierVocal(canal: a.canal, id: a.sourceId), FileManager.default.fileExists(atPath: f) {
                chemin = f
                a.fichier = f
            }
            if chemin.isEmpty {
                a.essais += 1
                if a.essais >= 8 { conclu = true; note = "fichier audio introuvable" }       // ~8 passes : WhatsApp le télécharge en général tout de suite
            } else if a.duree > 1200 {
                conclu = true
                note = "trop long pour la transcription"
            } else {
                let tete = (try? JSONSerialization.jsonObject(with: Data(a.ligne.utf8))) as? [String: Any]
                let qui = tete?["qui"] as? String ?? ""
                let entreprise = (tete?["contact_id"] as? String).flatMap { id in (try? stock?.contact(id)).flatMap { $0 }?.entreprise } ?? ""
                let r = EntTranscription.transcrire(chemin, qui: qui, entreprise: entreprise, delai: TimeInterval(max(120, min(a.duree * 2, 900))))
                if let t = r.texte { texte = t; conclu = true }
                else {
                    a.essais += 1
                    note = r.erreur
                    if a.essais >= 3 { conclu = true }
                }
            }
            if conclu {
                var ligne = ((try? JSONSerialization.jsonObject(with: Data(a.ligne.utf8))) as? [String: Any]) ?? [:]
                conclureLigne(&ligne, classe: a.classe, duree: a.duree, texte: texte, note: note)
                ajouterLigne(ligne)
                if !a.evenementId.isEmpty, let stock {
                    let v = libelleVocal(a.duree)
                    var corps = "\(v), à écouter (\(note))"
                    if let t = texte?.trimmingCharacters(in: .whitespacesAndNewlines) {
                        corps = t.isEmpty ? "\(v), rien d'audible" : "\(v) : " + EntNorm.extrait(t, max: 6000)
                    }
                    do { try stock.modifierEvenement(a.evenementId, ["texte": prefixeFil(a.canal) + corps]) }
                    catch { etat.statuts["fil"] = EntStatut(ok: false, message: "\(error)", le: Dates.maintenant()) }
                }
                if texte != nil { faits += 1 } else { echecs += 1 }
                etat.statuts["transcription"] = EntStatut(ok: texte != nil, message: texte != nil ? "ok" : note, le: Dates.maintenant())
                etat.cumul[texte != nil ? "vocaux_transcrits" : "vocaux_non_transcrits", default: 0] += 1
            } else {
                reste.append(a)
            }
            etat.attente = reste + Array(file.dropFirst(i + 1))
            ecrireEtat(etat)                                   // si le processus s'arrête avant, au pire ce vocal est refait
        }
        etat.attente = reste
        ecrireEtat(etat)
        return (faits, echecs)
    }

    // MARK: Suivre, lire, état

    static func suivre(dernieres: Int) {
        let chemin = fichier.path
        var decalage: UInt64 = (try? FileManager.default.attributesOfItem(atPath: chemin)[.size] as? UInt64) ?? 0
        if dernieres > 0, let t = try? String(contentsOfFile: chemin, encoding: .utf8) {
            for l in t.split(separator: "\n").suffix(dernieres) { print(l); fflush(stdout) }
        }
        var reste = [UInt8]()
        while true {
            if let h = FileHandle(forReadingAtPath: chemin) {
                let taille = (try? h.seekToEnd()) ?? 0
                if taille < decalage { decalage = 0; reste = [] }                   // fichier remplacé
                if taille > decalage {
                    try? h.seek(toOffset: decalage)
                    reste += [UInt8](h.readData(ofLength: Int(taille - decalage)))
                    decalage = taille
                    while let i = reste.firstIndex(of: 0x0A) {
                        let ligne = String(decoding: reste[0..<i], as: UTF8.self)
                        reste.removeSubrange(0...i)
                        if !ligne.isEmpty { print(ligne); fflush(stdout) }
                    }
                }
                try? h.close()
            }
            Thread.sleep(forTimeInterval: 1)
        }
    }

    static func lire(_ n: Int) {
        guard let t = try? String(contentsOf: fichier, encoding: .utf8) else { return }
        for l in t.split(separator: "\n").suffix(n) { print(l) }
    }

    static func binaire() -> String {
        let a = CommandLine.arguments[0]
        let u = a.hasPrefix("/") ? URL(fileURLWithPath: a) : URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(a)
        return u.standardizedFileURL.path
    }

    static func etatCommande() {
        let e = lireEtat()
        var sortie: [String: Any] = [
            "derniere_passe": e.passe, "curseurs": e.curseurs, "cumul": e.cumul, "reperes_deja_vus": e.vus.count,
            "vocaux_en_attente": (e.attente ?? []).count, "moteur_transcription": EntTranscription.pret() ? "prêt (\(EntTranscription.modele))" : "absent",
            "tache_launchd": FileManager.default.fileExists(atPath: plist.path) ? etiquette : "non installée",
            "fichier": fichier.path,
            "lignes": ((try? String(contentsOf: fichier, encoding: .utf8)) ?? "").split(separator: "\n").count,
        ]
        sortie["sources"] = e.statuts.mapValues { ["ok": $0.ok, "message": $0.message, "le": $0.le] as [String: Any] }
        if let d = try? JSONSerialization.data(withJSONObject: sortie, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) {
            print(String(data: d, encoding: .utf8) ?? "")
        }
    }

    // MARK: launchd

    static func launchctl(_ args: [String]) -> (Int32, String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = args
        let s = Pipe()
        p.standardOutput = s
        p.standardError = s
        do { try p.run() } catch { return (1, "\(error)") }
        let out = String(data: s.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        p.waitUntilExit()
        return (p.terminationStatus, out.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func installer() {
        let bin = binaire()
        let journal = dossier.appendingPathComponent("entrants.log").path
        let contenu = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>Label</key><string>\(etiquette)</string>
          <key>ProgramArguments</key>
          <array><string>\(bin)</string><string>entrants</string><string>--capter</string></array>
          <key>StartInterval</key><integer>60</integer>
          <key>RunAtLoad</key><true/>
          <key>StandardOutPath</key><string>/dev/null</string>
          <key>StandardErrorPath</key><string>\(journal)</string>
        </dict>
        </plist>
        """
        do {
            try FileManager.default.createDirectory(at: plist.deletingLastPathComponent(), withIntermediateDirectories: true)
            try contenu.write(to: plist, atomically: true, encoding: .utf8)
        } catch { echouer("Écriture de \(plist.path) impossible : \(error)") }
        let domaine = "gui/\(getuid())"
        _ = launchctl(["bootout", "\(domaine)/\(etiquette)"])
        let (code, sortie) = launchctl(["bootstrap", domaine, plist.path])
        guard code == 0 else { echouer("launchctl bootstrap : \(sortie)") }
        print("{\"installe\": \"\(etiquette)\", \"binaire\": \"\(bin)\", \"toutes_les_secondes\": 60}")
    }

    static func desinstaller() {
        _ = launchctl(["bootout", "gui/\(getuid())/\(etiquette)"])
        try? FileManager.default.removeItem(at: plist)
        print("{\"desinstalle\": \"\(etiquette)\"}")
    }
}

// MARK: - Transcription locale (faster-whisper dans ~/Library/Application Support/io.github.pjksens.pilote/whisper, rien ne quitte le Mac)

enum EntTranscription {
    static var dossier: String {
        ProcessInfo.processInfo.environment["PILOTE_WHISPER_DIR"] ?? Demo.maison.path + "/Library/Application Support/\(Identite.app)/whisper"
    }
    static var python: String { dossier + "/venv/bin/python" }
    static var script: String { dossier + "/transcrire.py" }
    static let ffmpeg = "/opt/homebrew/bin/ffmpeg"
    static let modele = "small"

    static func pret() -> Bool {
        let f = FileManager.default
        return f.isExecutableFile(atPath: python) && f.fileExists(atPath: script) && f.isExecutableFile(atPath: ffmpeg)
    }

    /// Transcrit un fichier audio (opus WhatsApp, caf iMessage) en français. `texte` est nil si le moteur échoue ou dépasse `delai`.
    static func transcrire(_ fichier: String, qui: String, entreprise: String = "", delai: TimeInterval) -> (texte: String?, erreur: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: python)
        p.arguments = [script, fichier, modele, qui, entreprise]     // nom et entreprise du contact + vocabulaire.txt = noms propres mieux écrits
        var env = ProcessInfo.processInfo.environment
        env["HF_HUB_OFFLINE"] = "1"                            // le modèle est déjà en cache : aucun accès réseau
        p.environment = env
        let sortie = Pipe(), erreur = Pipe()
        p.standardOutput = sortie
        p.standardError = erreur
        p.standardInput = FileHandle.nullDevice
        let fin = DispatchSemaphore(value: 0)
        p.terminationHandler = { _ in fin.signal() }
        do { try p.run() } catch { return (nil, "moteur impossible à lancer") }
        var donnees = Data(), diagnostic = Data()
        let groupe = DispatchGroup()
        groupe.enter()
        DispatchQueue.global().async { donnees = sortie.fileHandleForReading.readDataToEndOfFile(); groupe.leave() }
        groupe.enter()
        DispatchQueue.global().async { diagnostic = erreur.fileHandleForReading.readDataToEndOfFile(); groupe.leave() }
        var expire = false
        if fin.wait(timeout: .now() + delai) == .timedOut {
            expire = true
            p.terminate()
            _ = fin.wait(timeout: .now() + 5)
        }
        groupe.wait()
        if expire { return (nil, "transcription trop longue") }
        guard p.terminationStatus == 0 else {
            let dernier = String(decoding: diagnostic, as: UTF8.self).split(separator: "\n").last.map(String.init) ?? ""
            FileHandle.standardError.write(Data("transcription : échec (\(p.terminationStatus)) \(dernier)\n".utf8))
            return (nil, "transcription impossible")
        }
        return (String(decoding: donnees, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines), "")
    }
}
