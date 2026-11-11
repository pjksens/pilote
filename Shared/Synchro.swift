// Synchro distante d'un espace (par exemple pour voir et marquer ses contacts depuis un téléphone) : deux tables d'une API
// REST (PostgREST, par exemple Supabase), `pilote_contacts` et `pilote_evenements` par défaut. COUPÉE par défaut : s'active
// dans reglages.json (`synchro`), avec une clé qui ne peut lire et écrire QUE ces deux tables (jamais service_role).
// On reprend d'abord ce qui a changé là-bas depuis la dernière lecture, puis on envoie ce qui a changé ici
// depuis le dernier envoi. La dernière écriture gagne (maj_le) ; une suppression est une marque (supprime_le).
import Foundation

struct BilanSynchro: Encodable {
    var contactsRecus = 0
    var evenementsRecus = 0
    var contactsEnvoyes = 0
    var evenementsEnvoyes = 0
    var ignores = 0
    var erreurs: [String] = []
    var secondes = 0.0
}

private final class Reponse: @unchecked Sendable {
    var code = 0
    var data = Data()
    var erreur: String?
}

final class Synchro {
    private let base: Base
    private let url: String
    private let cle: String
    private let tableContacts: String
    private let tableEvenements: String
    private let espace: String

    static let colonnesContact = ["id", "type", "nom", "entreprise", "ville", "departement", "telephone", "email",
                                  "linkedin", "facebook", "site", "source", "source_ref", "notes", "etape",
                                  "prochaine_action", "prochaine_date", "priorite", "ne_plus_contacter", "org_id",
                                  "cree_le", "maj_le", "supprime_le"]
    static let colonnesEvenement = ["id", "contact_id", "le", "canal", "sens", "type", "texte", "statut", "par",
                                    "source_ref", "objet", "reponse_a", "message_id", "maj_le", "supprime_le"]

    init(base: Base) throws {
        if Demo.actif { throw Demo.Refus() }
        guard let r = Reglages.courants.synchro, !r.url.isEmpty, !r.cle.isEmpty else { throw IntegrationCoupee(reglage: "synchro") }
        func nom(_ v: String?, _ defaut: String) -> String {
            let t = v?.trimmingCharacters(in: .whitespaces) ?? ""
            return t.isEmpty ? defaut : t
        }
        self.base = base
        self.url = r.url.hasSuffix("/") ? String(r.url.dropLast()) : r.url
        self.cle = r.cle
        self.tableContacts = nom(r.tableContacts, "pilote_contacts")
        self.tableEvenements = nom(r.tableEvenements, "pilote_evenements")
        self.espace = nom(r.espace, Libelles.espaces.first?.0 ?? "autre")
    }

    // MARK: Tour complet

    func lancer() throws -> BilanSynchro {
        let debut = Date()
        var bilan = BilanSynchro()
        let lecture = try etat("derniere_lecture")
        let envoi = try etat("dernier_envoi")
        let depart = Dates.iso.string(from: debut)

        // 1. Reprendre. 5 minutes de marge pour les écritures arrivées pendant la lecture précédente.
        var depuis = ""
        if let l = Dates.iso.date(from: lecture) { depuis = Dates.iso.string(from: l.addingTimeInterval(-300)) }
        var recus = Set<String>()
        var envoisRecus = Set<String>()   // contacts touchés par un envoi marqué ailleurs : à renvoyer quand même
        var plusRecent = lecture
        for ligne in try lire(tableContacts, depuis: depuis) {
            guard let id = ligne["id"] as? String else { continue }
            let maj = Synchro.horodatage(ligne["maj_le"]) ?? ""
            if maj > plusRecent { plusRecent = maj }
            do {
                if try appliquerContact(ligne) { bilan.contactsRecus += 1; recus.insert(id) }
            } catch { bilan.ignores += 1; let detail = "\(error)"; bilan.erreurs.append(L("contact \(id) : \(detail)")) }
        }
        for ligne in try lire(tableEvenements, depuis: depuis) {
            guard let id = ligne["id"] as? String else { continue }
            let maj = Synchro.horodatage(ligne["maj_le"]) ?? ""
            if maj > plusRecent { plusRecent = maj }
            do {
                if try appliquerEvenement(ligne, envoisRecus: &envoisRecus) { bilan.evenementsRecus += 1; recus.insert(id) }
            } catch { bilan.ignores += 1; let detail = "\(error)"; bilan.erreurs.append(L("événement \(id) : \(detail)")) }
        }
        recus.subtract(envoisRecus)
        if !plusRecent.isEmpty { try poserEtat("derniere_lecture", plusRecent) }

        // 2. Envoyer (les contacts d'abord : les événements pointent vers eux).
        let contacts = try base.lignes("SELECT * FROM contacts WHERE espace = ? AND maj_le >= ?", [espace, envoi])
            .filter { !recus.contains($0["id"] as? String ?? "") }
            .map(Synchro.versDistantContact)
        bilan.contactsEnvoyes = envoyer(tableContacts, contacts, &bilan.erreurs)
        let evenements = try base.lignes("""
            SELECT e.*, c.maj_le AS contact_maj FROM evenements e JOIN contacts c ON c.id = e.contact_id
            WHERE c.espace = ? AND e.maj_le >= ?
            """, [espace, envoi])
            .filter { !recus.contains($0["id"] as? String ?? "") }
            .map(Synchro.versDistantEvenement)
        bilan.evenementsEnvoyes = envoyer(tableEvenements, evenements, &bilan.erreurs)
        if bilan.erreurs.isEmpty || bilan.contactsEnvoyes + bilan.evenementsEnvoyes > 0 {
            try poserEtat("dernier_envoi", depart)
        }
        bilan.secondes = (Date().timeIntervalSince(debut) * 10).rounded() / 10
        return bilan
    }

    // MARK: Reprise

    /// Renvoie vrai si la ligne a changé quelque chose ici.
    private func appliquerContact(_ d: [String: Any]) throws -> Bool {
        guard let id = d["id"] as? String, let maj = Synchro.horodatage(d["maj_le"]) else { return false }
        var v = Synchro.versLocal(d, colonnes: Synchro.colonnesContact)
        v["maj_le"] = maj
        if let local = try base.lignes("SELECT espace, maj_le FROM contacts WHERE id = ?", [id]).first {
            guard local["espace"] as? String == espace, maj > (local["maj_le"] as? String ?? "") else { return false }
            let cols = Synchro.colonnesContact.filter { $0 != "id" }
            try base.executer("UPDATE contacts SET \(cols.map { "\($0) = ?" }.joined(separator: ", ")) WHERE id = ?",
                              cols.map { v[$0] } + [id])
        } else {
            let cols = Synchro.colonnesContact + ["espace"]
            v["espace"] = espace
            try base.executer("INSERT INTO contacts (\(cols.joined(separator: ", "))) VALUES (\(cols.map { _ in "?" }.joined(separator: ", ")))",
                              cols.map { v[$0] })
        }
        return true
    }

    private func appliquerEvenement(_ d: [String: Any], envoisRecus: inout Set<String>) throws -> Bool {
        guard let id = d["id"] as? String, let contact = d["contact_id"] as? String,
              let maj = Synchro.horodatage(d["maj_le"]) else { return false }
        guard try !base.lignes("SELECT 1 FROM contacts WHERE id = ? AND espace = ?", [contact, espace]).isEmpty else { return false }
        var v = Synchro.versLocal(d, colonnes: Synchro.colonnesEvenement)
        v["maj_le"] = maj
        if let local = try base.lignes("SELECT maj_le, statut FROM evenements WHERE id = ?", [id]).first {
            guard maj > (local["maj_le"] as? String ?? "") else { return false }
            let cols = Synchro.colonnesEvenement.filter { $0 != "id" }
            try base.executer("UPDATE evenements SET \(cols.map { "\($0) = ?" }.joined(separator: ", ")) WHERE id = ?",
                              cols.map { v[$0] } + [id])
            // Envoi marqué depuis le téléphone (prepare → envoye) : Pilote fait la suite, comme pour un envoi marqué ici.
            if local["statut"] as? String != "envoye", v["statut"] as? String == "envoye", v["sens"] as? String == "sortant",
               (v["supprime_le"] as? String ?? "").isEmpty,
               let ligne = try base.lignes("SELECT * FROM evenements WHERE id = ?", [id]).first {
                try Stockage(base: base).apresEnvoi(Stockage.evenement(ligne))
                envoisRecus.insert(contact)
            }
        } else {
            let cols = Synchro.colonnesEvenement
            try base.executer("INSERT INTO evenements (\(cols.joined(separator: ", "))) VALUES (\(cols.map { _ in "?" }.joined(separator: ", ")))",
                              cols.map { v[$0] })
        }
        return true
    }

    /// Valeurs distantes → colonnes locales : null → '' (sauf source/source_ref, où '' → NULL pour l'unicité locale).
    private static func versLocal(_ d: [String: Any], colonnes: [String]) -> [String: Any?] {
        var v: [String: Any?] = [:]
        for c in colonnes {
            let x = d[c]
            switch c {
            case "source", "source_ref":
                let s = x as? String ?? ""
                v[c] = s.isEmpty ? nil : s
            case "priorite": v[c] = (x as? NSNumber)?.intValue ?? 2
            case "ne_plus_contacter": v[c] = ((x as? NSNumber)?.boolValue ?? false) ? 1 : 0
            case "cree_le", "maj_le", "supprime_le", "le": v[c] = horodatage(x) ?? ""
            case "prochaine_date": v[c] = (x as? String).map { String($0.prefix(10)) } ?? ""
            default: v[c] = (x as? String) ?? ""
            }
        }
        return v
    }

    // MARK: Envoi

    private static func versDistantContact(_ l: [String: Any]) -> [String: Any] {
        var d: [String: Any] = [:]
        for c in colonnesContact {
            let s = l[c] as? String ?? ""
            switch c {
            case "priorite": d[c] = l[c] as? Int ?? 2
            case "ne_plus_contacter": d[c] = (l[c] as? Int ?? 0) != 0
            case "prochaine_date": d[c] = s.isEmpty ? NSNull() : String(s.prefix(10))
            case "org_id": d[c] = s.isEmpty ? NSNull() : s
            case "supprime_le": d[c] = horodatage(s) ?? NSNull()
            case "maj_le": d[c] = horodatage(s) ?? Dates.maintenant()
            case "cree_le": d[c] = horodatage(s) ?? horodatage(l["maj_le"]) ?? Dates.maintenant()
            default: d[c] = s
            }
        }
        return d
    }

    private static func versDistantEvenement(_ l: [String: Any]) -> [String: Any] {
        var d: [String: Any] = [:]
        for c in colonnesEvenement {
            let s = l[c] as? String ?? ""
            switch c {
            case "supprime_le": d[c] = horodatage(s) ?? NSNull()
            case "maj_le": d[c] = horodatage(s) ?? Dates.maintenant()
            // Quelques vieilles dates sont abîmées (« T18:00:00+02:00 ») : on prend alors celle du contact.
            case "le": d[c] = horodatage(s) ?? horodatage(l["contact_maj"]) ?? Dates.maintenant()
            default: d[c] = s
            }
        }
        return d
    }

    /// Envoie par paquets de 200 ; un paquet refusé est repris ligne à ligne pour isoler la fautive.
    private func envoyer(_ table: String, _ lignes: [[String: Any]], _ erreurs: inout [String]) -> Int {
        var envoyes = 0
        var i = 0
        while i < lignes.count {
            let paquet = Array(lignes[i..<min(i + 200, lignes.count)])
            i += 200
            if upsert(table, paquet) == nil { envoyes += paquet.count; continue }
            for l in paquet {
                if let e = upsert(table, [l]) { erreurs.append("\(table) \(l["id"] ?? "") : \(e)") } else { envoyes += 1 }
            }
        }
        return envoyes
    }

    private func upsert(_ table: String, _ lignes: [[String: Any]]) -> String? {
        guard let corps = try? JSONSerialization.data(withJSONObject: lignes) else { return L("JSON impossible") }
        let r = requete("POST", "\(table)?on_conflict=id", corps: corps,
                        entetes: ["Prefer": "resolution=merge-duplicates,return=minimal"])
        if let e = r.erreur { return e }
        return (200..<300).contains(r.code) ? nil : "HTTP \(r.code) \(String(data: r.data, encoding: .utf8)?.prefix(300) ?? "")"
    }

    // MARK: Réseau

    private func lire(_ table: String, depuis: String) throws -> [[String: Any]] {
        var out: [[String: Any]] = []
        var offset = 0
        while true {
            var chemin = "\(table)?select=*&order=maj_le.asc,id.asc&limit=1000&offset=\(offset)"
            if !depuis.isEmpty { chemin += "&maj_le=gt.\(depuis)" }
            let r = requete("GET", chemin)
            if let e = r.erreur { throw ErreurBase(description: L("Lecture \(table) : \(e)")) }
            guard r.code == 200, let page = try JSONSerialization.jsonObject(with: r.data) as? [[String: Any]] else {
                let code = "HTTP \(r.code) \(String(data: r.data, encoding: .utf8)?.prefix(300) ?? "")"
                throw ErreurBase(description: L("Lecture \(table) : \(code)"))
            }
            out += page
            if page.count < 1000 { return out }
            offset += 1000
        }
    }

    private func requete(_ methode: String, _ chemin: String, corps: Data? = nil, entetes: [String: String] = [:]) -> Reponse {
        let rep = Reponse()
        guard let u = URL(string: "\(url)/rest/v1/\(chemin)") else { rep.erreur = L("adresse invalide"); return rep }
        var req = URLRequest(url: u, timeoutInterval: 30)
        req.httpMethod = methode
        req.setValue(cle, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(cle)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (k, v) in entetes { req.setValue(v, forHTTPHeaderField: k) }
        req.httpBody = corps
        let fini = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: req) { data, reponse, erreur in
            rep.data = data ?? Data()
            rep.code = (reponse as? HTTPURLResponse)?.statusCode ?? 0
            rep.erreur = erreur?.localizedDescription
            fini.signal()
        }.resume()
        fini.wait()
        return rep
    }

    // MARK: Outils

    private func etat(_ c: String) throws -> String {
        try base.lignes("SELECT valeur FROM synchro WHERE cle = ?", [c]).first?["valeur"] as? String ?? ""
    }

    private func poserEtat(_ c: String, _ v: String) throws {
        try base.executer("INSERT INTO synchro (cle, valeur) VALUES (?, ?) ON CONFLICT(cle) DO UPDATE SET valeur = excluded.valeur", [c, v])
    }

    /// Ramène toute date ISO (avec ou sans fractions, Z ou +02:00) ou jour seul au format local « 2026-10-27T20:00:00Z ».
    static func horodatage(_ x: Any?) -> String? {
        guard let s = x as? String, !s.isEmpty else { return nil }
        let sansFraction = s.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        if let d = Dates.iso.date(from: sansFraction) { return Dates.iso.string(from: d) }
        if s.count == 10, let d = Dates.jour.date(from: s) { return Dates.iso.string(from: d) }
        return nil
    }
}
