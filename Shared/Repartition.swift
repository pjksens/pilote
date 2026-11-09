// Qui traite la prochaine action d'une fiche (05/11, Sacha : « les fiches où il faut attendre reviennent à l'agent concerné
// (FREELANCE, Ventes…), inutile de me les mettre… mais elles doivent être traitées automatiquement… Personne ne doit passer
// entre les mailles du filet »).
// Sacha ne voit que SES gestes (appeler, visio, rendez-vous, décider…) ; tout le reste (attendre, vérifier, préparer un texte,
// relancer, classer) est la liste du jour de l'agent de l'espace : kryva → Ventes, freelance → FREELANCE, autre → PILOTE.
// La veille la lui envoie chaque matin et relance ce qui reste dû à 11 h et 16 h (16 h : PILOTE est prévenu).
import Foundation

enum Responsable: String, Codable, CaseIterable {
    case sacha, ventes, freelance, pilote

    /// Le nom de la session (celui de `scripts/facteur.py`).
    var session: String {
        switch self {
        case .sacha: return "\(Moi.nom)"
        case .ventes: return "KRYVA · Ventes"
        case .freelance: return "FREELANCE"
        case .pilote: return "PILOTE"
        }
    }
}

extension Libelles {
    /// Les gestes que seul Sacha fait. Une action est pour lui si elle COMMENCE (après une date en tête) par l'un d'eux.
    /// Convention pour les agents : un geste de Sacha s'écrit « Sacha : … ».
    static var gestesDeSacha: [String] { [Moi.nom.lowercased(), "appeler", "rappeler", "téléphoner", "appel ", "visio", "rendez-vous", "rdv",
                                "rencontrer", "passer voir", "aller voir", "décider", "choisir"] }

    /// « Jeu. 05/11 : … », « Lun. 09/11 (choix de Sacha, 05/11) : … », « ⚠ … » → le texte après.
    static func sansDateEnTete(_ action: String) -> String {
        var s = action.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("⚠") { s = String(s.dropFirst()).trimmingCharacters(in: .whitespaces) }
        let motif = #"^(lun|mar|mer|jeu|ven|sam|dim)[a-zé]*\.?\s+\d{1,2}/\d{1,2}(\s*(à|a)\s*\d{1,2}\s*[h:]\s*\d{0,2})?\s*(\([^)]*\))?\s*:\s*"#
        if let r = s.range(of: motif, options: [.regularExpression, .caseInsensitive]) { s.removeSubrange(r) }
        return s
    }

    /// L'action est-elle un geste de Sacha ? Sinon elle revient à l'agent de l'espace.
    static func pourSacha(_ action: String) -> Bool {
        let debut = sansDateEnTete(action).lowercased()
        return gestesDeSacha.contains { debut.hasPrefix($0) }
    }

    static func agent(espace: String) -> Responsable {
        switch espace {
        case "kryva": return .ventes
        case "freelance": return .freelance
        default: return .pilote
        }
    }

    static func responsable(_ c: Contact) -> Responsable {
        pourSacha(c.prochaineAction) ? .sacha : agent(espace: c.espace)
    }
}

/// La liste du jour d'un agent : ce qu'il doit traiter, sans rien laisser derrière.
struct ListeAgent: Encodable {
    let date: String
    let pour: String
    let session: String
    let consigne: String
    /// Action due (aujourd'hui ou en retard) qui n'est pas un geste de Sacha, sans texte qui l'attend déjà chez Sacha.
    let dus: [Contact]
    /// Fiches engagées (contactée ou au-delà) sans prochaine date : invisibles partout, à dater ou à classer.
    let sansDate: [Contact]
    /// « À contacter » sans date : le stock de prospects, pas un oubli. Compté seulement.
    let reservoir: Int
}

extension Stockage {
    static let consigneAgent = """
    Avant 9 h, pour chaque fiche due : vérifier (réponse dans Gmail, Mail, Messages ; activité KRYVA), puis UNE suite : \
    (1) la vraie prochaine action et sa date ; (2) ou un texte rangé « a_valider » pour \(Moi.nom) ; (3) ou un geste pour \(Moi.nom), \
    action commençant par « \(Moi.nom) : » (appel, visio, rendez-vous, décision) ; (4) ou classer (perdu, gagné, ne plus contacter \
    sur demande). Chaque fiche « sans date » : la dater ou la classer. Jamais « attendre » à une date passée : rien ne reste dû le soir. \
    Fait connu = ajoute_au_fil. Compte rendu à PILOTE en 3 lignes.
    """

    /// Les contacts dont un texte attend Sacha (à valider ou prêt à envoyer) : ils sont chez lui, pas chez l'agent.
    func contactsChezSacha() throws -> Set<String> {
        Set(try messages(statut: "prepare").map(\.1.id) + messages(statut: "a_valider").map(\.1.id))
    }

    /// Ce qui est dû à Sacha : ses gestes seulement (les textes à envoyer et à valider ont leurs propres listes).
    func dusSacha(au jour: String = Dates.aujourdhui()) throws -> [Contact] {
        try dus(au: jour).filter { Libelles.pourSacha($0.prochaineAction) }
    }

    func listeAgent(_ r: Responsable, au jour: String = Dates.aujourdhui()) throws -> ListeAgent {
        let chezSacha = try contactsChezSacha()
        let siens = { (c: Contact) in Libelles.agent(espace: c.espace) == r }
        let dus = try dus(au: jour).filter { siens($0) && !Libelles.pourSacha($0.prochaineAction) && !chezSacha.contains($0.id) }
        let actifs = try contacts().filter {
            siens($0) && $0.prochaineDate.isEmpty && !$0.nePlusContacter && !["gagne", "perdu"].contains($0.etape)
        }
        let sansDate = actifs.filter { $0.etape != "a_contacter" && !chezSacha.contains($0.id) }
        return ListeAgent(date: jour, pour: r.rawValue, session: r.session, consigne: Self.consigneAgent,
                          dus: dus, sansDate: sansDate, reservoir: actifs.count - actifs.filter { $0.etape != "a_contacter" }.count)
    }
}

// MARK: Ce que chaque agent a fait de sa liste (05/11, Sacha : « toutes les fiches traitées, j'aimerais bien les voir
// quelque part dans Pilote… si elles l'ont pas été, que je puisse les relancer »).
// La liste du jour est gardée dans `listes_agents` dès qu'elle est lue (veille 7 h 05, 11 h 13, 16 h 13, app) : une fiche
// y reste toute la journée. Elle est « traitée » quand elle a quitté la liste vivante (nouvelle date, classée, passée
// chez Sacha) ; sinon elle « reste ».

/// Une fiche de la liste du jour d'un agent, et ce qu'elle est devenue.
struct FicheAgent: Identifiable, Hashable, Encodable {
    var id: String { contact.id }
    let contact: Contact
    /// « du » (action due) ou « sans_date » (fiche engagée sans prochaine date).
    let motif: String
    let actionAvant: String
    let dateAvant: String
    let traitee: Bool
    /// 05/11 (T5) : ce qui prouve la traitée. « faite » : un fait au fil depuis la liste du matin, ou classée / passée à Sacha ;
    /// « reportee » : seulement une nouvelle date, rien au fil ; « sans_trace » : sortie de la liste sans rien ; « reste » : pas traitée.
    let preuve: String
    /// En clair : « suite le jeu. 12/11 », « classée perdue », « texte pour vous »… ou ce qui reste à faire.
    let devenue: String
}

struct JourneeAgent: Identifiable, Hashable, Encodable {
    var id: String { pour }
    let date: String
    let pour: String
    let session: String
    let traitees: [FicheAgent]
    let restantes: [FicheAgent]
    /// T42 : « à contacter » sans date de cet agent (stock de prospection, hors liste du jour), pour que le volume reste visible.
    let reservoir: Int

    var faites: [FicheAgent] { traitees.filter { $0.preuve == "faite" } }
    var reportees: [FicheAgent] { traitees.filter { $0.preuve == "reportee" } }
    var sansTrace: [FicheAgent] { traitees.filter { $0.preuve == "sans_trace" } }
}

extension Stockage {
    /// Garde la liste vivante dans `listes_agents` : la première entrée du jour d'une fiche reste (INSERT OR IGNORE).
    func noterListe(_ l: ListeAgent, le: Date = Date()) throws {
        let h = Dates.iso.string(from: le)
        // Seulement les nouvelles : pas d'écriture vide (l'app relit tout à chaque écriture d'une autre connexion).
        let deja = Set(try base.lignes("SELECT contact_id FROM listes_agents WHERE jour = ? AND pour = ?", [l.date, l.pour])
            .compactMap { $0["contact_id"] as? String })
        let fiches = (l.dus.map { ($0, "du") } + l.sansDate.map { ($0, "sans_date") }).filter { !deja.contains($0.0.id) }
        guard !fiches.isEmpty else { return }
        try base.transaction {
            for (c, motif) in fiches {
                try base.executer("""
                    INSERT OR IGNORE INTO listes_agents (jour, pour, contact_id, motif, action_avant, date_avant, note_le)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """, [l.date, l.pour, c.id, motif, c.prochaineAction, c.prochaineDate, h])
            }
        }
    }

    /// La journée d'un agent : sa liste du jour (gardée) partagée entre traitées et restantes.
    func journeeAgent(_ r: Responsable, au jour: String = Dates.aujourdhui()) throws -> JourneeAgent {
        let vivante = try listeAgent(r, au: jour)
        try noterListe(vivante)
        let restent = Set(vivante.dus.map(\.id) + vivante.sansDate.map(\.id))
        let chezSacha = try contactsChezSacha()
        var traitees: [FicheAgent] = [], restantes: [FicheAgent] = []
        for l in try base.lignes("SELECT * FROM listes_agents WHERE jour = ? AND pour = ? ORDER BY note_le, rowid",
                                 [jour, r.rawValue]) {
            guard let id = l["contact_id"] as? String, let c = try contact(id) else { continue }
            let reste = restent.contains(id)
            let devenue = Self.devenue(c, reste: reste, chezSacha: chezSacha.contains(id), jour: jour)
            let depuis = l["note_le"] as? String ?? ""
            let faitAuFil = try base.lignes("SELECT 1 FROM evenements WHERE contact_id = ? AND supprime_le = '' AND (le >= ? OR maj_le >= ?) LIMIT 1",
                                            [id, depuis, depuis]).isEmpty == false
            let f = FicheAgent(contact: c, motif: l["motif"] as? String ?? "du", actionAvant: l["action_avant"] as? String ?? "",
                               dateAvant: l["date_avant"] as? String ?? "", traitee: !reste,
                               preuve: Self.preuve(reste: reste, devenue: devenue, faitAuFil: faitAuFil), devenue: devenue)
            if reste { restantes.append(f) } else { traitees.append(f) }
        }
        return JourneeAgent(date: jour, pour: r.rawValue, session: r.session, traitees: traitees, restantes: restantes,
                             reservoir: vivante.reservoir)
    }

    /// Les trois agents qui ont une liste du jour.
    func journeesAgents(au jour: String = Dates.aujourdhui()) throws -> [JourneeAgent] {
        try [Responsable.ventes, .freelance, .pilote].map { try journeeAgent($0, au: jour) }
    }

    /// T5 : classe une fiche sortie de la liste. Un fait au fil, un classement ou un passage chez Sacha = faite ;
    /// une nouvelle date seule = reportée ; rien d'autre = sans trace.
    static func preuve(reste: Bool, devenue: String, faitAuFil: Bool) -> String {
        if reste { return "reste" }
        if faitAuFil { return "faite" }
        if devenue.hasPrefix("suite le") { return "reportee" }
        if devenue == "traitée" { return "sans_trace" }
        return "faite"
    }

    static func devenue(_ c: Contact, reste: Bool, chezSacha: Bool, jour: String) -> String {
        if reste {
            if c.prochaineDate.isEmpty { return "sans date : à dater ou à classer" }
            return c.prochaineDate < jour ? "en retard depuis le \(Dates.jjmm(c.prochaineDate))" : "due aujourd'hui"
        }
        if c.nePlusContacter { return "ne plus contacter" }
        if c.etape == "gagne" { return "classée gagnée" }
        if c.etape == "perdu" { return "classée perdue" }
        if chezSacha { return "texte pour vous" }
        if Libelles.pourSacha(c.prochaineAction) { return "passée à vous" }
        if !c.prochaineDate.isEmpty { return "suite le \(Dates.jjmm(c.prochaineDate))" }
        return "traitée"
    }

    /// Le message « Relancer » : les fiches qui restent, puis la consigne du matin.
    static func relance(_ j: JourneeAgent, heure: Date = Date()) -> String {
        let h = heure.formatted(date: .omitted, time: .shortened)
        let lignes = j.restantes.map { f in
            let action = Libelles.sansDateEnTete(f.contact.prochaineAction).replacingOccurrences(of: "\n", with: " ")
            let court = action.count > 90 ? String(action.prefix(90)) + "…" : action
            return "- \(f.contact.nom) (\(f.devenue)) : \(court.isEmpty ? "aucune action" : court)"
        }
        return """
        Relance de \(Moi.nom) (\(h)) : \(j.restantes.count) fiche\(j.restantes.count > 1 ? "s" : "") de ta liste du jour \
        pas encore traitée\(j.restantes.count > 1 ? "s" : "") (\(j.traitees.count) déjà faite\(j.traitees.count > 1 ? "s" : "")). \
        Traite-les maintenant, sans rien laisser dû.
        \(lignes.joined(separator: "\n"))
        Consigne : \(consigneAgent)
        """
    }
}
