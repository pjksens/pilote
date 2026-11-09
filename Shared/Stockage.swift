// Lecture et écriture des contacts et du fil. Utilisé tel quel par l'app et par l'outil `pilote`.
import Foundation

final class Stockage: @unchecked Sendable {
    let base: Base

    init(base: Base) { self.base = base }

    static let colonnesContact = [
        "espace", "type", "nom", "entreprise", "ville", "departement", "telephone", "email", "linkedin",
        "facebook", "site", "etape", "prochaine_action", "prochaine_date", "priorite", "ne_plus_contacter",
        "org_id", "source", "source_ref", "notes",
    ]
    static let colonnesEvenement = ["le", "canal", "sens", "type", "texte", "statut", "par", "source_ref", "objet", "reponse_a", "message_id",
                                    "condition", "rappel_id"]

    // MARK: Contacts

    func contacts() throws -> [Contact] {
        try base.lignes("SELECT * FROM contacts WHERE supprime_le = '' ORDER BY maj_le DESC").map(Self.contact)
    }

    func contact(_ id: String) throws -> Contact? {
        try base.lignes("SELECT * FROM contacts WHERE id = ? AND supprime_le = ''", [id]).first.map(Self.contact)
    }

    /// Recherche libre (nom, entreprise, ville, e-mail, téléphone), pour l'outil en ligne de commande.
    func chercher(_ texte: String) throws -> [Contact] {
        let motif = "%\(texte)%"
        return try base.lignes("""
            SELECT * FROM contacts WHERE supprime_le = '' AND (nom LIKE ?1 OR entreprise LIKE ?1 OR ville LIKE ?1
              OR email LIKE ?1 OR telephone LIKE ?1 OR linkedin LIKE ?1 OR id = ?2)
            ORDER BY maj_le DESC
            """, [motif, texte]).map(Self.contact)
    }

    /// Le contact déjà présent pour ces champs (même supprimé) : même `id`, sinon même `source` + `source_ref`.
    func existant(_ champs: [String: Any]) throws -> Contact? {
        if let id = champs["id"] as? String, !id.isEmpty,
           let c = try base.lignes("SELECT * FROM contacts WHERE id = ?", [id]).first.map(Self.contact) { return c }
        if let s = champs["source"] as? String, let r = Self.texte(champs["source_ref"]), !s.isEmpty, !r.isEmpty {
            return try base.lignes("SELECT * FROM contacts WHERE source = ? AND source_ref = ?", [s, r]).first.map(Self.contact)
        }
        return nil
    }

    /// Crée ou met à jour un contact à partir de champs partiels (clés en snake_case).
    /// Retrouve le contact par `id`, sinon par le couple `source` + `source_ref`. Seuls les champs fournis changent.
    @discardableResult
    func enregistrer(_ champs: [String: Any]) throws -> Contact {
        let existant = try self.existant(champs)
        let maintenant = Dates.maintenant()
        let fournis = Self.colonnesContact.filter { champs[$0] != nil }
        let valeurs: [Any?] = fournis.map { Self.valeurColonne($0, champs[$0]) }

        if let existant {
            guard !fournis.isEmpty else { return existant }
            let sets = fournis.map { "\($0) = ?" }.joined(separator: ", ")
            // Réenregistrer un contact supprimé le fait revenir.
            try base.executer("UPDATE contacts SET \(sets), maj_le = ?, supprime_le = '' WHERE id = ?", valeurs + [maintenant, existant.id])
            return try contact(existant.id)!
        }
        let id = (champs["id"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? UUID().uuidString.lowercased()
        let cols = ["id"] + fournis + ["cree_le", "maj_le"]
        let marques = Array(repeating: "?", count: cols.count).joined(separator: ", ")
        try base.executer("INSERT INTO contacts (\(cols.joined(separator: ", "))) VALUES (\(marques))",
                          [id] + valeurs + [maintenant, maintenant])
        return try contact(id)!
    }

    /// Enregistre la fiche complète telle qu'éditée dans l'app.
    func enregistrer(_ c: Contact) throws {
        try enregistrer(Self.champs(c))
    }

    /// KRYVA : la suppression devient une marque, pour que la synchro la transmette à l'admin.
    func supprimer(_ id: String) throws {
        let maintenant = Dates.maintenant()
        try base.executer("UPDATE contacts SET supprime_le = ?, maj_le = ? WHERE id = ? AND espace = 'kryva'", [maintenant, maintenant, id])
        try base.executer("DELETE FROM contacts WHERE id = ? AND espace != 'kryva'", [id])
    }

    // MARK: Fil

    func evenements(_ contactId: String) throws -> [Evenement] {
        try base.lignes("SELECT * FROM evenements WHERE contact_id = ? AND supprime_le = '' ORDER BY le DESC", [contactId]).map(Self.evenement)
    }

    /// Ajoute un événement au fil. Fait avancer l'étape du contact sans jamais la faire reculer :
    /// un envoi passe « À contacter » à « Contacté », une réponse reçue passe à « A répondu ».
    @discardableResult
    func ajouterEvenement(contactId: String, _ champs: [String: Any]) throws -> Evenement {
        guard let c = try contact(contactId) else { throw ErreurBase(description: "Contact introuvable : \(contactId)") }
        var champs = champs
        if champs["le"] == nil { champs["le"] = Dates.maintenant() }
        if let ref = Self.texte(champs["source_ref"]), !ref.isEmpty,
           let deja = try base.lignes("SELECT * FROM evenements WHERE contact_id = ? AND source_ref = ?", [contactId, ref]).first {
            return Self.evenement(deja)
        }
        // Un message du capteur (source_ref) déjà noté à la main pour le même mail : pas de deuxième entrée (FilDoublon).
        if let ref = Self.texte(champs["source_ref"]), !ref.isEmpty, (champs["sens"] as? String) == "entrant",
           let texte = champs["texte"] as? String, let le = champs["le"] as? String,
           let deja = try base.lignes("SELECT * FROM evenements WHERE contact_id = ? AND sens = 'entrant' AND supprime_le = ''", [contactId])
            .first(where: { FilDoublon.memeMessage(texteA: texte, leA: le, texteB: Self.texte($0["texte"]) ?? "", leB: Self.texte($0["le"]) ?? "") }) {
            return Self.evenement(deja)
        }
        try Self.verifierCondition(champs["condition"] as? String, statut: champs["statut"] as? String ?? "fait")
        let id = UUID().uuidString.lowercased()
        let fournis = Self.colonnesEvenement.filter { champs[$0] != nil }
        let cols = ["id", "contact_id"] + fournis + ["maj_le"]
        let marques = Array(repeating: "?", count: cols.count).joined(separator: ", ")
        try base.executer("INSERT INTO evenements (\(cols.joined(separator: ", "))) VALUES (\(marques))",
                          [id, contactId] + fournis.map { Self.texte(champs[$0]) } + [Dates.maintenant()])

        let sens = champs["sens"] as? String ?? "interne"
        let statut = champs["statut"] as? String ?? "fait"
        var cible: String?
        if sens == "sortant" && (statut == "envoye" || statut == "fait") { cible = "contacte" }
        if sens == "entrant" { cible = "repondu" }
        if let cible, Libelles.rang(cible) > Libelles.rang(c.etape), c.etape != "perdu" {
            try base.executer("UPDATE contacts SET etape = ?, maj_le = ? WHERE id = ?", [cible, Dates.maintenant(), contactId])
        } else {
            try base.executer("UPDATE contacts SET maj_le = ? WHERE id = ?", [Dates.maintenant(), contactId])
        }
        let e = Self.evenement(try base.lignes("SELECT * FROM evenements WHERE id = ?", [id]).first!)
        // Un envoi noté directement (envoyé ailleurs que depuis Pilote) pose la même suite qu'un « Envoyé ».
        if sens == "sortant" && statut == "envoye" { try poserSuite(e) }
        return e
    }

    /// Corrige un événement (texte, objet, mail auquel il répond…) avant envoi.
    /// 05/11 (T7) : `condition` (une nouvelle condition est à recocher), `rappel_id`, et `condition_remplie: true` (avec `par`).
    func modifierEvenement(_ id: String, _ champs: [String: Any]) throws {
        let modifiables = ["texte", "objet", "reponse_a", "canal", "type", "le", "condition", "rappel_id"]
        let fournis = modifiables.filter { champs[$0] != nil }
        if let c = Self.texte(champs["condition"]), let e = try evenement(id) { try Self.verifierCondition(c, statut: e.statut) }
        if !fournis.isEmpty {
            var sets = fournis.map { "\($0) = ?" }
            if fournis.contains("condition") { sets.append("condition_ok_le = ''") }
            if fournis.contains("rappel_id") { sets.append("rappel_ferme_le = ''") }
            try base.executer("UPDATE evenements SET \(sets.joined(separator: ", ")), maj_le = ? WHERE id = ?",
                              fournis.map { Self.texte(champs[$0])?.trimmingCharacters(in: .whitespacesAndNewlines) } + [Dates.maintenant(), id])
        }
        let remplie = champs["condition_remplie"]
        if (remplie as? Bool) == true || ["1", "true", "oui"].contains(Self.texte(remplie) ?? "") {
            try conditionRemplie(evenementId: id, par: champs["par"] as? String ?? "Claude")
        }
    }

    /// Garde-fou du 08/11 : un message « prepare » dont la condition écrit un jour de semaine faux (« Dim. 16/11 », un lundi)
    /// est refusé. Sa date, elle, n'a pas besoin de garde : une condition qui cite une date fait attendre le message
    /// jusqu'à ce jour, sans date de message à poser (Libelles.jourDuMessage).
    static func verifierCondition(_ condition: String?, statut: String) throws {
        guard statut == "prepare", let condition, !condition.isEmpty,
              let defaut = Libelles.incoherenceJourSemaine(condition, aujourdhui: Dates.aujourdhui()) else { return }
        throw ErreurBase(description: "Condition refusée, jour de semaine faux : \(defaut). Corriger la condition (rien n'a été écrit).")
    }

    func evenement(_ id: String) throws -> Evenement? {
        try base.lignes("SELECT * FROM evenements WHERE id = ? AND supprime_le = ''", [id]).first.map(Self.evenement)
    }

    /// Passe un message préparé à « envoyé » (ou « échec »), à l'heure où Sacha l'a envoyé.
    /// 05/11 (T7) : un message dont la condition n'est pas cochée ne passe pas à « envoyé » (erreur), sauf `malgreCondition` :
    /// le message est DÉJÀ parti (capteur, mail parti de Gmail, Sacha le dit) ; le fil le note et le rappel lié reste ouvert.
    func marquer(evenementId: String, statut: String, messageId: String = "", malgreCondition: Bool = false) throws {
        guard let ligne = try base.lignes("SELECT * FROM evenements WHERE id = ?", [evenementId]).first else { return }
        var e = Self.evenement(ligne)
        let sansCondition = statut == "envoye" && e.statut != "envoye" && e.conditionEnAttente
        if sansCondition && !malgreCondition { throw ErreurBase(description: Self.refusCondition(e)) }
        if !messageId.isEmpty {
            try base.executer("UPDATE evenements SET message_id = ?, maj_le = ? WHERE id = ?", [messageId, Dates.maintenant(), evenementId])
        }
        let maintenant = Dates.maintenant()
        try base.executer("UPDATE evenements SET statut = ?, le = ?, maj_le = ? WHERE id = ?",
                          [statut, maintenant, maintenant, evenementId])
        if sansCondition {
            try ajouterEvenement(contactId: e.contactId, ["canal": e.canal, "sens": "interne", "type": "note", "statut": "fait", "par": "Pilote",
                "texte": "Parti alors que la condition n'était pas cochée : « \(e.condition) »." + (e.rappelId.isEmpty ? "" : " Le rappel lié reste ouvert.")])
        }
        guard statut == "envoye", e.sens == "sortant" else { return }
        e.le = maintenant
        try apresEnvoi(e)
    }

    static func refusCondition(_ e: Evenement) -> String {
        "Pas envoyé : la condition n'est pas cochée (« \(e.condition) »). La cocher d'abord (« Condition remplie » dans l'app, "
            + "ou modifie_evenement avec condition_remplie), ou, si le message est déjà parti, le marquer avec malgre_condition."
    }

    /// Effets d'un envoi sur le contact : étape « contacté » au moins, puis la suite de la routine (J+5 ouvrés après e.le).
    /// Appelé par marquer et par la synchro quand un envoi a été marqué ailleurs (téléphone) ; ne touche pas à `le`.
    func apresEnvoi(_ e: Evenement) throws {
        guard let c = try contact(e.contactId) else { return }
        if Libelles.rang("contacte") > Libelles.rang(c.etape) {
            try base.executer("UPDATE contacts SET etape = 'contacte', maj_le = ? WHERE id = ?", [Dates.maintenant(), c.id])
        }
        try poserSuite(e)
    }

    /// La suite de la routine après un envoi : l'action et son jour (J+5 ouvrés après l'envoi).
    /// `actionFaite` : l'action que la fiche portait quand l'envoi a eu lieu. Si c'était la « Relance unique… », la suite est la
    /// dernière étape « Sans réponse au JJ/MM : classer sans suite » (04/11, PILOTE) : jamais une deuxième relance, jamais une boucle.
    /// `etape` « gagne » (05/11, T3) : un client n'est jamais classé sans suite ; après sa relance unique, l'agent le remonte à PILOTE.
    static func suiteApresEnvoi(_ e: Evenement, actionFaite: String = "", etape: String = "") -> (action: String, date: String) {
        let date = Dates.ouvres(5, depuis: Dates.date(e.le) ?? Date())
        if e.type != "invitation", Libelles.estRelanceUnique(actionFaite) {
            if etape == "gagne" {
                return ("Client sans réponse au \(Dates.jjmm(date)) : le remonter à PILOTE, pas de nouvelle relance.", date)
            }
            return ("Sans réponse au \(Dates.jjmm(date)) : classer sans suite, plus aucune relance.", date)
        }
        let action = e.type == "invitation"
            ? "Invitation acceptée ? Si oui, message après acceptation (modèle de la routine)"
            : "Relance unique si pas de réponse"
        return (action, date)
    }

    /// Faut-il poser la suite après un envoi ? Oui si la fiche n'a pas de date, si sa date est passée, ou si elle est
    /// d'aujourd'hui ET que l'action est un envoi (c'est celle qu'on vient de faire). Une autre action du jour (un appel,
    /// « Taux tranché par Sacha… ») reste : le contrôle du matin la signale « envoyé mais encore dû ».
    static func suiteAPoser(_ c: Contact, jour: String) -> Bool {
        c.prochaineDate.isEmpty || c.prochaineDate < jour || (c.prochaineDate == jour && Libelles.actionEstUnEnvoi(c.prochaineAction))
    }

    /// Prochaine étape de la routine, à J+5 ouvrés après l'envoi, sauf si une action est déjà prévue PLUS TARD.
    /// 04/11 : une date égale à aujourd'hui est l'échéance de l'action qu'on vient de faire, pas une action à garder
    /// (avec `<`, tout envoi fait le jour de l'échéance laissait la fiche « due » : 15 fiches le 04/11).
    /// 05/11 (T3) : un client « gagné » reste suivi : un envoi pose aussi sa suite (sinon « Répondre à… » restait dû après la réponse).
    func poserSuite(_ e: Evenement) throws {
        guard let c = try contact(e.contactId), !c.nePlusContacter, c.etape != "perdu" else { return }
        guard Self.suiteAPoser(c, jour: Dates.aujourdhui()) else { return }
        let (suite, date) = Self.suiteApresEnvoi(e, actionFaite: c.prochaineAction, etape: c.etape)
        try base.executer("UPDATE contacts SET prochaine_action = ?, prochaine_date = ?, maj_le = ? WHERE id = ?",
                          [suite, date, Dates.maintenant(), c.id])
    }

    /// KRYVA : marque de suppression (transmise par la synchro) ; ailleurs, suppression réelle.
    func supprimerEvenement(_ id: String) throws {
        let maintenant = Dates.maintenant()
        let kryva = "contact_id IN (SELECT id FROM contacts WHERE espace = 'kryva')"
        try base.executer("UPDATE evenements SET supprime_le = ?, maj_le = ? WHERE id = ? AND \(kryva)", [maintenant, maintenant, id])
        try base.executer("DELETE FROM evenements WHERE id = ? AND NOT \(kryva)", [id])
    }

    // MARK: Aujourd'hui

    /// Contacts dont la prochaine action est due aujourd'hui ou en retard. Les clients « gagné » en font partie (05/11, T3 :
    /// Julien Morel, client freelance en production, sortait de tout suivi) ; « perdu » et « ne plus contacter » non.
    func dus(au jour: String = Dates.aujourdhui()) throws -> [Contact] {
        try base.lignes("""
            SELECT * FROM contacts
            WHERE supprime_le = '' AND prochaine_date != '' AND prochaine_date <= ? AND ne_plus_contacter = 0 AND etape != 'perdu'
            ORDER BY prochaine_date, priorite
            """, [jour]).map(Self.contact)
    }

    /// Messages préparés par Claude qui attendent d'être envoyés par Sacha.
    func aEnvoyer() throws -> [(Evenement, Contact)] { try messages(statut: "prepare") }

    /// Messages d'un statut donné : « prepare » (validés, à envoyer), « a_valider » (texte à lire par Sacha),
    /// « a_refaire » (renvoyés à l'agent avec une consigne).
    func messages(statut: String) throws -> [(Evenement, Contact)] {
        try base.lignes("SELECT * FROM evenements WHERE statut = ? AND supprime_le = '' ORDER BY le", [statut]).compactMap { l in
            let e = Self.evenement(l)
            guard let c = try contact(e.contactId) else { return nil }
            return (e, c)
        }
    }

    // MARK: Sauvegarde

    func exporter() throws -> Data {
        let contacts = try base.lignes("SELECT * FROM contacts ORDER BY cree_le")
        let evenements = try base.lignes("SELECT * FROM evenements ORDER BY le")
        let projets = try base.lignes("SELECT * FROM projets ORDER BY espace, ordre")
        let journal = try base.lignes("SELECT * FROM journal ORDER BY le")
        let objet: [String: Any] = ["exporte_le": Dates.maintenant(), "contacts": contacts, "evenements": evenements,
                                    "projets": projets, "journal": journal]
        return try JSONSerialization.data(withJSONObject: objet, options: [.prettyPrinted, .sortedKeys])
    }

    /// Une copie par jour dans iCloud Drive (dossier « Pilote open source », Identite.sauvegardes), on garde les 14 dernières.
    func sauvegardeDuJour() throws -> URL? {
        let icloud = Demo.maison
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        guard FileManager.default.fileExists(atPath: icloud.path) else { return nil }
        let dossier = icloud.appendingPathComponent(Identite.sauvegardes, isDirectory: true)
        try FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
        let fichier = dossier.appendingPathComponent("pilote-\(Dates.aujourdhui()).json")
        try exporter().write(to: fichier, options: .atomic)
        let anciens = try FileManager.default.contentsOfDirectory(atPath: dossier.path)
            .filter { $0.hasPrefix("pilote-") && $0.hasSuffix(".json") }.sorted().dropLast(14)
        for nom in anciens { try? FileManager.default.removeItem(at: dossier.appendingPathComponent(nom)) }
        return fichier
    }

    // MARK: Conversions

    static func texte(_ v: Any?) -> String? {
        switch v {
        case nil, is NSNull: return nil
        case let s as String: return s
        case let b as Bool: return b ? "1" : "0"
        default: return "\(v!)"
        }
    }

    private static func valeurColonne(_ col: String, _ v: Any?) -> Any? {
        switch col {
        case "priorite": return (v as? Int) ?? Int(texte(v) ?? "") ?? 2
        case "ne_plus_contacter":
            if let b = v as? Bool { return b ? 1 : 0 }
            return ((v as? Int) ?? Int(texte(v) ?? "") ?? 0) != 0 ? 1 : 0
        case "source", "source_ref":
            let s = texte(v) ?? ""
            return s.isEmpty ? nil : s
        default: return texte(v) ?? ""
        }
    }

    static func champs(_ c: Contact) -> [String: Any] {
        [
            "id": c.id, "espace": c.espace, "type": c.type, "nom": c.nom, "entreprise": c.entreprise,
            "ville": c.ville, "departement": c.departement, "telephone": c.telephone, "email": c.email,
            "linkedin": c.linkedin, "facebook": c.facebook, "site": c.site, "etape": c.etape,
            "prochaine_action": c.prochaineAction, "prochaine_date": c.prochaineDate, "priorite": c.priorite,
            "ne_plus_contacter": c.nePlusContacter, "org_id": c.orgId, "source": c.source,
            "source_ref": c.sourceRef, "notes": c.notes,
        ]
    }

    static func contact(_ l: [String: Any]) -> Contact {
        func s(_ k: String) -> String { l[k] as? String ?? "" }
        return Contact(
            id: s("id"), espace: s("espace"), type: s("type"), nom: s("nom"), entreprise: s("entreprise"),
            ville: s("ville"), departement: s("departement"), telephone: s("telephone"), email: s("email"),
            linkedin: s("linkedin"), facebook: s("facebook"), site: s("site"), etape: s("etape"),
            prochaineAction: s("prochaine_action"), prochaineDate: s("prochaine_date"),
            priorite: l["priorite"] as? Int ?? 2, nePlusContacter: (l["ne_plus_contacter"] as? Int ?? 0) != 0,
            orgId: s("org_id"), source: s("source"), sourceRef: s("source_ref"), notes: s("notes"),
            creeLe: s("cree_le"), majLe: s("maj_le"))
    }

    static func evenement(_ l: [String: Any]) -> Evenement {
        func s(_ k: String) -> String { l[k] as? String ?? "" }
        return Evenement(id: s("id"), contactId: s("contact_id"), le: s("le"), canal: s("canal"), sens: s("sens"),
                         type: s("type"), texte: s("texte"), statut: s("statut"), par: s("par"),
                         objet: s("objet"), reponseA: s("reponse_a"), messageId: s("message_id"),
                         condition: s("condition"), conditionOkLe: s("condition_ok_le"), rappelId: s("rappel_id"),
                         rappelFermeLe: s("rappel_ferme_le"))
    }
}
