// Le capteur de messages (04/11, GO de PILOTE) :
// (a) une réponse reçue d'un contact connu crée l'action « Répondre à X » du jour ;
// (c) un message envoyé par Sacha hors de Pilote (WhatsApp, SMS) ne passe un message « prepare » à « envoye » que si le contact, le
//     canal ET le texte correspondent ; sinon, une note au fil « envoi possible, à vérifier », sans changer aucun statut.
import Foundation

enum Sortants {
    /// Minuscules, sans accents ni ponctuation, espaces réduits : « Bonjour Léa ! » et « bonjour lea » se valent.
    static func normaliser(_ s: String) -> String {
        let plie = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
        let signes = plie.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        return String(signes).split(separator: " ").joined(separator: " ")
    }

    /// Le texte à envoyer d'un message prêt : sans la ligne d'en-tête de l'agent (« WhatsApp à envoyer par Sacha mer. 04/11 »).
    static func corps(_ prepare: String) -> String {
        var lignes = prepare.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        while let l = lignes.first, l.trimmingCharacters(in: .whitespaces).isEmpty { lignes.removeFirst() }
        if lignes.count > 1, lignes[0].lowercased().contains("envoyer") { lignes.removeFirst() }
        return lignes.joined(separator: "\n")
    }

    /// Le texte parti est-il le texte prêt ? Égalité, ou l'un contient l'autre et couvre au moins 90 % de sa longueur.
    /// Moins de 10 caractères : jamais (« ok » ne prouve rien).
    static func correspond(envoye: String, prepare: String) -> Bool {
        let a = normaliser(envoye), b = normaliser(corps(prepare))
        guard a.count >= 10, b.count >= 10 else { return false }
        if a == b { return true }
        let (court, long) = a.count <= b.count ? (a, b) : (b, a)
        return Double(court.count) >= 0.9 * Double(long.count) && long.contains(court)
    }

    /// Le canal du message prêt est-il celui où le message est parti ? « imessage » (SMS compris) ↔ canal « sms » ;
    /// « whatsapp » ↔ canal « sms » ou « autre » ET WhatsApp écrit dans l'en-tête du texte prêt.
    static func canalCompatible(_ canal: String, prepare: Evenement) -> Bool {
        let entete = (prepare.texte.split(separator: "\n").first.map(String.init) ?? "").lowercased()
        switch canal {
        case "imessage": return prepare.canal == "sms" && !entete.contains("whatsapp")
        case "whatsapp": return ["sms", "autre"].contains(prepare.canal) && entete.contains("whatsapp")
        default: return false
        }
    }

    static func libelleCanal(_ canal: String) -> String { canal == "whatsapp" ? "WhatsApp" : "SMS" }
}

enum CaptureSortante: Equatable {
    case marqueEnvoye(String)      // id de l'événement passé à « envoye »
    case aVerifier
    case rien
}

extension Stockage {
    private static let heureParis: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.timeZone = TimeZone(identifier: "Europe/Paris")
        f.dateFormat = "HH:mm"
        return f
    }()

    /// Un message envoyé par Sacha (WhatsApp ou iMessage/SMS) à un contact connu. `ref` : « whatsapp:123 », pour ne jamais noter deux fois.
    @discardableResult
    func captureSortante(contactId: String, canal: String, texte: String, le: Date, ref: String) throws -> CaptureSortante {
        guard let c = try contact(contactId), !c.nePlusContacter else { return .rien }
        let prepares = try messages(statut: "prepare").filter { $0.1.id == contactId }.map(\.0)
        guard !prepares.isEmpty else { return .rien }              // rien n'attend d'être envoyé : on ne note pas chaque message
        let heure = Self.heureParis.string(from: le), nom = Sortants.libelleCanal(canal)
        let champs = { (note: String) -> [String: Any] in
            ["canal": canal == "whatsapp" ? "autre" : "sms", "sens": "interne", "type": "note", "texte": note, "statut": "fait",
             "par": "Capteur Pilote", "source_ref": ref + ":sortant"]
        }
        if let p = prepares.first(where: { Sortants.canalCompatible(canal, prepare: $0) && Sortants.correspond(envoye: texte, prepare: $0.texte) }) {
            try marquer(evenementId: p.id, statut: "envoye", malgreCondition: true)   // il est parti : le fil note une condition non cochée
            try ajouterEvenement(contactId: contactId, champs("Envoi capté (\(nom), \(heure)) : le message préparé est parti, passé à « envoyé » (contact, canal et texte correspondent)."))
            return .marqueEnvoye(p.id)
        }
        let extrait = EntExtrait.court(texte, 120)
        try ajouterEvenement(contactId: contactId, champs("Envoi possible (\(nom), \(heure)), à vérifier : « \(extrait) ». Un message préparé attend toujours ; rien n'a été changé."))
        return .aVerifier
    }

    /// Une réponse reçue d'un contact connu : l'action du jour devient « Répondre à X ». On n'écrase qu'une action vide, une action
    /// d'envoi (la relance prévue n'a plus de sens) ou une action passée. Ni « perdu », ni « ne plus contacter ». Un client « gagné »
    /// oui (05/11, T3) : sa réponse devient l'action du jour de l'agent de l'espace.
    /// Renvoie la ligne écrite au fil, ou nil si rien n'a changé.
    @discardableResult
    func actionRepondre(contactId: String, jour: String = Dates.aujourdhui()) throws -> String? {
        guard let c = try contact(contactId), !c.nePlusContacter, c.etape != "perdu" else { return nil }
        let nom = c.nom.isEmpty ? c.entreprise : c.nom
        let action = "Répondre à \(nom)"
        if c.prochaineAction == action, !c.prochaineDate.isEmpty, c.prochaineDate <= jour { return nil }   // déjà posée
        let ecrasable = c.prochaineAction.isEmpty || Libelles.actionEstUnEnvoi(c.prochaineAction)
            || c.prochaineAction == action || (!c.prochaineDate.isEmpty && c.prochaineDate < jour)
        guard ecrasable else { return nil }
        try enregistrer(["id": c.id, "prochaine_action": action, "prochaine_date": jour])
        let avant = c.prochaineAction.isEmpty ? "aucune action" : "« \(c.prochaineAction.prefix(70)) »"
        let note = "Réponse reçue : action du jour « \(action) ». Avant : \(avant)\(c.prochaineDate.isEmpty ? "" : " du \(Dates.court(c.prochaineDate))")."
        try ajouterEvenement(contactId: c.id, ["canal": "autre", "sens": "interne", "type": "note", "texte": note, "statut": "fait", "par": "Capteur Pilote"])
        return note
    }
}

enum EntExtrait {
    /// Une ligne, au plus `max` caractères.
    static func court(_ s: String, _ max: Int) -> String {
        let une = s.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return une.count <= max ? une : String(une.prefix(max)) + "…"
    }
}
