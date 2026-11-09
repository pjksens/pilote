// Suivi des prospects (04/11, Sacha : « un suivi hors norme sur chaque prospect, on ne doit rien louper »).
// (a) rétablir la suite des fiches dont un envoi du jour ne les a pas fait avancer,
// (c) un message prêt ne se cache jamais derrière la date de la fiche,
// (b) le contrôle du matin : signale, ne corrige rien, ne rétrograde aucune étape.
import Foundation

extension Dates {
    /// Le jour (heure de Paris) d'un horodatage ISO ou d'une date AAAA-MM-JJ ; vide si illisible.
    static func jourDe(_ s: String) -> String {
        guard let d = date(s) else { return String(s.prefix(10)) }
        return jour.string(from: d)
    }
}

extension Libelles {
    /// Le jour où part un message prêt (« prepare »).
    /// 1. Le jour écrit en tête du message passe avant tout (« à envoyer par Sacha jeu. 05/11 »).
    /// 2. Sinon, un message prêt depuis un jour précédent part AUJOURD'HUI (chaîne vide) : il reste visible jusqu'à
    ///    l'envoi, quelle que soit la date de la fiche (04/11, Sacha : 2 mails prêts n'apparaissaient pas dans Aujourd'hui).
    /// 3. Sinon (préparé aujourd'hui), la date de la fiche : « c'est des trucs que j'envoie demain » (03/11).
    ///    Sauf une réponse dans un fil (`reponseA` rempli) : elle part le jour où elle est préparée (09/11 : la réponse validée
    ///    à Julien tombait au 11/11, date de la fiche fixée par l'appel du 11/11, pas par le mail).
    /// 4. 08/11 (Sacha voyait des messages du 16/11) : une condition EN ATTENTE qui cite une date (« Ventes a relu le 16/11 »)
    ///    ne peut pas être remplie avant : le message attend la première de ces dates qui n'est pas passée si elle est après aujourd'hui et
    ///    après le jour trouvé plus haut. `condition` est vide quand il n'y en a pas ou qu'elle est cochée.
    static func jourDuMessage(texte: String, le: String, dateFiche: String, aujourdhui: String, condition: String = "",
                              reponseA: String = "") -> String {
        let base: String
        if let j = jourPrevu(texte, aujourdhui: aujourdhui) { base = j }
        else if !le.isEmpty, Dates.jourDe(le) < aujourdhui { base = "" }
        else if !reponseA.trimmingCharacters(in: .whitespaces).isEmpty { base = "" }
        else { base = dateFiche }
        if let c = dateDansCondition(condition, aujourdhui: aujourdhui), c > aujourdhui, c > base { return c }
        return base
    }

    /// La première date citée (JJ/MM) dans une condition qui n'est pas passée, au format AAAA-MM-JJ ; nil s'il n'y en a pas, ou
    /// si c'est aujourd'hui. « Lundi 09/11 avant envoi… annuler la relance du 16/11 » attend le 09/11 ; « relu le 16/11 : aucune
    /// réponse depuis le SMS du 07/11 » attend le 16/11 (le 07/11 est passé).
    static func dateDansCondition(_ condition: String, aujourdhui: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: #"(?<![\d/])(\d{1,2})/(\d{1,2})(?![\d/])"#) else { return nil }
        let ns = condition as NSString
        let jours = re.matches(in: condition, range: NSRange(location: 0, length: ns.length)).compactMap {
            jourISO(ns.substring(with: $0.range), aujourdhui: aujourdhui)
        }
        return jours.first { $0 >= aujourdhui }
    }

    /// Une condition qui écrit un jour de semaine devant une date (« Dim. 16/11 ») doit tomber juste ; renvoie le défaut, sinon nil.
    static func incoherenceJourSemaine(_ condition: String, aujourdhui: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: #"\b(lun|mar|mer|jeu|ven|sam|dim)[a-zé]*\.?\s+(?:le\s+)?(\d{1,2}/\d{1,2})\b"#, options: .caseInsensitive) else { return nil }
        let ns = condition as NSString
        let noms = ["dim": 1, "lun": 2, "mar": 3, "mer": 4, "jeu": 5, "ven": 6, "sam": 7]
        let long = [1: "dimanche", 2: "lundi", 3: "mardi", 4: "mercredi", 5: "jeudi", 6: "vendredi", 7: "samedi"]
        let cal = Calendar(identifier: .gregorian)
        for m in re.matches(in: condition, range: NSRange(location: 0, length: ns.length)) {
            let nom = ns.substring(with: m.range(at: 1)).lowercased(), jm = ns.substring(with: m.range(at: 2))
            guard let attendu = noms[nom], let iso = jourISO(jm, aujourdhui: aujourdhui), let d = Dates.jour.date(from: iso) else { continue }
            let reel = cal.component(.weekday, from: d)
            if reel != attendu { return "« \(ns.substring(with: m.range)) » : le \(jm) tombe un \(long[reel] ?? "?") (\(iso)), pas un \(long[attendu] ?? nom)" }
        }
        return nil
    }
}

extension Libelles {
    /// L'action de la fiche est-elle un envoi (relance, mail, SMS, DM, invitation…) ? On regarde le DÉBUT du texte seulement :
    /// « Taux tranché par Sacha le 03/11 : … (réponse 75…) » n'en est pas un, même s'il cite un mail plus loin.
    /// L'action est la « Relance unique… » (texte seulement, début de ligne) : après son envoi, la suite est la dernière étape, jamais une autre relance.
    static func estRelanceUnique(_ action: String) -> Bool {
        action.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("relance unique")
    }

    /// La dernière étape de la routine, « Sans réponse au JJ/MM : classer sans suite, plus aucune relance. » (Stockage.suiteApresEnvoi).
    static func estSansSuite(_ action: String) -> Bool {
        let a = action.trimmingCharacters(in: .whitespaces).lowercased()
        return a.hasPrefix("sans réponse au") && a.contains("classer sans suite")
    }

    /// 05/11 (T3) : « Répondre à X » (posée par le capteur) est un envoi : la réponse partie, la suite se pose, la fiche ne reste
    /// pas due le jour même.
    static func actionEstUnEnvoi(_ action: String) -> Bool {
        let debut = action.prefix(45).lowercased()
        if ["relance", "sms", "dm ", "mail", "message", "écrire", "ecrire", "envoi", "envoy", "whatsapp", "invit", "répondre", "repondre"]
            .contains(where: { debut.contains($0) }) { return true }
        // 05/11 : « Jeudi 05/11 : texte VALIDÉ tel quel par Sacha (04/11, statut prepare) : « Envoyer depuis Gmail »… » et
        // « Texte validé par Sacha (prepare, 04/11 soir)… » sont l'envoi du texte prêt, même si le mot vient après 45 caractères
        // (25 fiches restées « dues » après leur envoi du 05/11, dont Sophie MARTIN).
        let tout = action.lowercased()
        return ["statut prepare", "(prepare", "envoyer depuis gmail", "texte validé", "texte revalidé"].contains { tout.contains($0) }
    }
}

/// Une fiche dont un envoi du jour n'a pas posé la suite.
struct SuiteARetablir: Codable, Equatable {
    var contactId: String
    var nom: String
    var ancienneAction: String
    var ancienneDate: String
    var nouvelleAction: String
    var nouvelleDate: String
}

/// Le contrôle du matin. Il signale, il ne corrige rien et ne fait reculer aucune étape.
struct Controle: Codable, Equatable {
    struct Ligne: Codable, Equatable {
        var contactId: String
        var nom: String
        var espace: String
        var detail: String
    }
    var jour: String
    /// Envoi du jour (ou d'avant l'échéance) et fiche encore due : la suite n'a pas été posée.
    var envoyesEncoreDus: [Ligne] = []
    /// Action due, aucun texte prêt, à valider ou à refaire, aucun envoi depuis (une invitation à vérifier n'a pas besoin de texte).
    var dusSansTexte: [Ligne] = []
    /// R1 : étape « a répondu » ou « rendez-vous » sans aucune réponse, appel ou rendez-vous au fil.
    var etapesSansFait: [Ligne] = []
    /// R2 : une date de suivi sans action, ou sans événement ni source.
    var datesSansSource: [Ligne] = []
    /// R3 (04/11, PILOTE) : un prospect actif (ni gagné, ni perdu, ni « ne plus contacter ») sans prochaine date : il sort du suivi.
    var sansDate: [Ligne] = []
    /// Stock « À contacter » sans date : listé à part et PAS compté (04/11 : 338 fiches jamais contactées ; les compter donnerait
    /// « 344 trous » chaque matin et noierait les vraies fuites). Pour le compter : mettre ces lignes dans `sansDate` (une condition dans `controle`).
    var sansDateAContacter: [Ligne] = []
    /// Piste 2 (04/11, PILOTE) : mails partis d'une adresse kryva.fr ces 48 dernières heures (règle : jamais depuis kryva.fr).
    var envoyesDepuisKryva: [Ligne] = []
    /// La vérification de Mail n'a pas tourné depuis plus de 6 h (ou jamais) : on le dit, on ne se tait pas.
    var verifKryvaPerimee: Bool = false
    /// 04/11 (GO de PILOTE) : capteur ou veille arrêtés (voir AlerteArret). Listé à part, PAS compté dans les trous du suivi.
    var arrets: [String] = []
    /// 05/11 (T39) : lignes d'information (dernier message WhatsApp reçu), jamais comptées.
    var infos: [String] = []

    var total: Int { envoyesEncoreDus.count + dusSansTexte.count + etapesSansFait.count + datesSansSource.count + sansDate.count + envoyesDepuisKryva.count }

    func texte() -> String {
        func bloc(_ titre: String, _ l: [Ligne]) -> String {
            guard !l.isEmpty else { return "\(titre) : aucun" }
            return "\(titre) (\(l.count)) :\n" + l.map { "  - \($0.nom) [\($0.espace)] : \($0.detail)" }.joined(separator: "\n")
        }
        return ["Contrôle du \(jour) : \(total) trou\(total > 1 ? "s" : "")",
                bloc("Envoyés mais encore dus (anomalie)", envoyesEncoreDus),
                bloc("Dus sans texte", dusSansTexte),
                bloc("Étapes sans fait au fil (R1)", etapesSansFait),
                bloc("Dates sans source (R2)", datesSansSource),
                bloc("Actifs sans prochaine date (R3)", sansDate),
                "Stock à contacter : \(sansDateAContacter.count)" + (sansDateAContacter.isEmpty ? "" : " (sans date, non compté dans les trous ; liste : --json)"),
                bloc("Mails partis d'un domaine interdit (48 h)", envoyesDepuisKryva)
                + (verifKryvaPerimee ? "\nVérification « envoyé depuis un domaine interdit » : pas à jour (capteur arrêté ou Mail illisible)" : ""),
                arrets.isEmpty ? "Arrêts (capteur, veille) : aucun" : "ARRÊTS (capteur, veille) :\n" + arrets.map { "  - \($0)" }.joined(separator: "\n")]
            .joined(separator: "\n") + (infos.isEmpty ? "" : "\n" + infos.joined(separator: "\n"))
    }
}

extension Stockage {
    /// Contacts dont le DERNIER envoi du `jour` (heure de Paris) n'a pas fait avancer la fiche : leur date est ≤ au jour.
    /// On ne touche pas à un contact qui a un texte en cours (prepare, a_valider, a_refaire) ni à un « ne plus contacter ».
    func suitesARetablir(jour: String = Dates.aujourdhui()) throws -> [SuiteARetablir] {
        let envois = try base.lignes("SELECT * FROM evenements WHERE sens = 'sortant' AND statut = 'envoye' AND supprime_le = '' ORDER BY le")
            .map(Self.evenement).filter { Dates.jourDe($0.le) == jour }
        var dernier: [String: Evenement] = [:]
        for e in envois { dernier[e.contactId] = e }
        var r: [SuiteARetablir] = []
        for (id, e) in dernier {
            guard let c = try contact(id), !c.nePlusContacter, c.etape != "perdu",
                  !c.prochaineDate.isEmpty, c.prochaineDate <= jour, Self.suiteAPoser(c, jour: jour) else { continue }
            let enCours = try base.lignes("SELECT 1 FROM evenements WHERE contact_id = ? AND statut IN ('prepare', 'a_valider', 'a_refaire') AND supprime_le = '' LIMIT 1", [id])
            guard enCours.isEmpty else { continue }
            let (action, date) = Self.suiteApresEnvoi(e, actionFaite: c.prochaineAction, etape: c.etape)
            r.append(SuiteARetablir(contactId: id, nom: c.nom.isEmpty ? c.entreprise : c.nom, ancienneAction: c.prochaineAction,
                                    ancienneDate: c.prochaineDate, nouvelleAction: action, nouvelleDate: date))
        }
        return r.sorted { $0.nom < $1.nom }
    }

    /// Pose la suite. À appeler APRÈS une sauvegarde de la base.
    /// Une note au fil par fiche (04/11, PILOTE : « en notant chaque correction au fil »).
    func retablirSuites(_ liste: [SuiteARetablir]) throws {
        for s in liste {
            try base.executer("UPDATE contacts SET prochaine_action = ?, prochaine_date = ?, maj_le = ? WHERE id = ?",
                              [s.nouvelleAction, s.nouvelleDate, Dates.maintenant(), s.contactId])
            let avant = s.ancienneAction.isEmpty ? "aucune action" : "« \(s.ancienneAction.prefix(70)) »"
            try ajouterEvenement(contactId: s.contactId, ["canal": "autre", "sens": "interne", "type": "note", "statut": "fait", "par": "Pilote",
                "texte": "Suite posée par Pilote (un envoi du jour n'avait pas fait avancer la fiche) : « \(s.nouvelleAction.prefix(70)) » le \(Dates.court(s.nouvelleDate)). Avant : \(avant) du \(Dates.court(s.ancienneDate))."])
        }
    }

    /// Un fait au fil : une réponse reçue, un appel, un rendez-vous, une visite.
    static func estUnFait(_ e: Evenement) -> Bool {
        e.sens == "entrant" || ["reponse", "rdv", "appel", "visite", "visio"].contains(e.type)
    }

    /// `envoisKryva` : l'état relevé par le capteur (`EnvoisKryva.lire()`). Par défaut rien : les tests ne lisent pas le vrai fichier.
    func controle(jour: String = Dates.aujourdhui(), envoisKryva: EtatEnvoisKryva? = nil, verifierKryva: Bool = false,
                  arrets: [String] = [], maintenant: Date = Date()) throws -> Controle {
        let contacts = try base.lignes("SELECT * FROM contacts WHERE supprime_le = '' AND ne_plus_contacter = 0 AND etape NOT IN ('gagne', 'perdu') ORDER BY priorite, prochaine_date")
            .map(Self.contact)
        let fils = Dictionary(grouping: try base.lignes("SELECT * FROM evenements WHERE supprime_le = ''").map(Self.evenement), by: \.contactId)
        var r = Controle(jour: jour)
        r.arrets = arrets
        if verifierKryva {
            r.envoyesDepuisKryva = EnvoisKryva.lignes(envoisKryva, maintenant: maintenant)
            r.verifKryvaPerimee = EnvoisKryva.perimee(envoisKryva, maintenant: maintenant)
        }
        for c in contacts {
            let fil = fils[c.id] ?? []
            let nom = c.nom.isEmpty ? c.entreprise : c.nom
            func ligne(_ d: String) -> Controle.Ligne { Controle.Ligne(contactId: c.id, nom: nom, espace: c.espace, detail: d) }
            // R1 : une étape ne repose pas sur du vide.
            if c.etape == "repondu" || c.etape == "rdv", !fil.contains(where: Self.estUnFait) {
                r.etapesSansFait.append(ligne("étape « \(c.etape) » sans réponse, appel ni rendez-vous au fil"))
            }
            // R3 : un prospect actif a toujours une date, même pour une dernière étape (« classer sans suite »).
            if c.prochaineDate.isEmpty {
                let l = ligne(c.prochaineAction.isEmpty ? "aucune action ni date (étape « \(Libelles.etape(c.etape)) »)"
                                                        : "action « \(c.prochaineAction.prefix(60)) » sans date")
                if c.etape == "a_contacter" { r.sansDateAContacter.append(l) } else { r.sansDate.append(l) }
                continue
            }
            // R2 : rien de daté sans source.
            if c.prochaineAction.isEmpty {
                r.datesSansSource.append(ligne("date \(c.prochaineDate) sans action"))
            } else if fil.isEmpty && c.source.isEmpty && c.sourceRef.isEmpty {
                r.datesSansSource.append(ligne("date \(c.prochaineDate) sans événement ni source : \(c.prochaineAction.prefix(60))"))
            }
            guard c.prochaineDate <= jour else { continue }
            if fil.contains(where: { ["prepare", "a_valider", "a_refaire"].contains($0.statut) }) { continue }
            if let envoi = fil.filter({ $0.sens == "sortant" && $0.statut == "envoye" && Dates.jourDe($0.le) >= c.prochaineDate })
                .max(by: { $0.le < $1.le }) {
                r.envoyesEncoreDus.append(ligne("envoyé le \(Dates.jourDe(envoi.le)), action toujours due au \(c.prochaineDate) : \(c.prochaineAction.prefix(60))"))
                continue
            }
            if Invitation.attendue(c.prochaineAction) { continue }   // un clic « Acceptée / Pas encore », pas un texte
            r.dusSansTexte.append(ligne(String(c.prochaineAction.prefix(80))))
        }
        return r
    }
}

// MARK: « Pas envoyé » / « Pas fait » avec une raison (04/11, Sacha : « je ne peux pas donner de raison quand je n'envoie
// pas un message dans Prospects du jour, alors qu'il faudrait pour le suivi »).

/// Pourquoi un message ou une action du jour ne part pas. La raison reste au fil du contact et remonte à l'agent.
enum RaisonPasEnvoye: String, CaseIterable, Identifiable {
    /// Le message reste prêt, la fiche est reportée : il revient au jour choisi.
    case pasLeMoment = "Pas le moment"
    /// Le texte repart à l'agent avec la consigne de Sacha (message seulement).
    case texteAChanger = "Texte à changer"
    /// Le message est annulé ; la fiche ne bouge pas, la ligne du jour continue de poser la question.
    case plusDActualite = "Plus d'actualité"

    var id: String { rawValue }

    static let pourMessage: [RaisonPasEnvoye] = [.pasLeMoment, .texteAChanger, .plusDActualite]
    static let pourSuivi: [RaisonPasEnvoye] = [.pasLeMoment, .plusDActualite]
}

extension Stockage {
    private static func precisionNettoyee(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }

    func noterAuFil(_ contactId: String, _ texte: String) throws {
        _ = try ajouterEvenement(contactId: contactId, ["canal": "autre", "sens": "interne", "type": "note",
                                                        "texte": texte, "statut": "fait", "par": "\(Moi.nom)"])
    }

    /// Un message prêt qui ne part pas. Écrit la raison au fil, applique l'effet, renvoie la ligne écrite.
    /// « Pas le moment » : le message reste prêt (marquer remet l'horodatage à maintenant : il compte comme préparé aujourd'hui
    /// et attend la date de la fiche, règle Libelles.jourDuMessage) et la fiche est reportée au `jour`.
    @discardableResult
    func pasEnvoye(evenementId: String, raison: RaisonPasEnvoye, precision: String = "", au jour: String? = nil) throws -> String {
        guard let ligne = try base.lignes("SELECT * FROM evenements WHERE id = ? AND supprime_le = ''", [evenementId]).first else { return "" }
        let e = Self.evenement(ligne)
        let p = Self.precisionNettoyee(precision)
        var note = "Pas envoyé (\(Libelles.canal(e.canal))) : \(raison.rawValue.lowercased())"
        switch raison {
        case .pasLeMoment:
            let j = jour ?? Dates.ouvres(1)
            try marquer(evenementId: evenementId, statut: "prepare")
            try reporterAction(e.contactId, au: j)
            note += ", revu le \(Dates.court(j))"
        case .texteAChanger:
            try marquer(evenementId: evenementId, statut: "a_refaire")
        case .plusDActualite:
            try marquer(evenementId: evenementId, statut: "annule")
        }
        if !p.isEmpty { note += " — " + p }
        try noterAuFil(e.contactId, note)
        return note
    }

    /// Une action du jour (sans texte prêt) qui n'est pas faite. « Pas le moment » : même action, autre jour.
    /// « Plus d'actualité » : l'action est abandonnée, la fiche se libère ; la raison reste au fil.
    @discardableResult
    func pasFait(contactId: String, raison: RaisonPasEnvoye, precision: String = "", au jour: String? = nil) throws -> String {
        guard let c = try contact(contactId) else { return "" }
        let p = Self.precisionNettoyee(precision)
        let action = c.prochaineAction.isEmpty ? "action prévue" : "« \(c.prochaineAction.prefix(70)) »"
        var note: String
        switch raison {
        case .plusDActualite:
            note = "Abandonné (plus d'actualité) : \(action)"
            try enregistrer(["id": contactId, "prochaine_action": "", "prochaine_date": ""])
        default:
            let j = jour ?? Dates.ouvres(1)
            note = "Pas fait (pas le moment), revu le \(Dates.court(j)) : \(action)"
            try reporterAction(contactId, au: j)
        }
        if !p.isEmpty { note += " — " + p }
        try noterAuFil(contactId, note)
        return note
    }
}

// MARK: Chaque modification de Sacha laisse une trace au fil (04/11, Sacha : « chaque modif doit être notée dans la fiche d'un
// prospect, son statut mis à jour et toutes les dispositions prises »).

enum Changements {
    /// Ce qui a changé sur la fiche entre deux états : étape, prochaine action, date, « ne plus contacter ». Vide = rien de suivi.
    static func resume(avant: Contact, apres: Contact) -> String {
        var l: [String] = []
        if avant.etape != apres.etape { l.append("étape : \(Libelles.etape(avant.etape)) → \(Libelles.etape(apres.etape))") }
        if avant.prochaineAction != apres.prochaineAction {
            func q(_ s: String) -> String { s.isEmpty ? "aucune" : "« \(s.prefix(80)) »" }
            l.append("prochaine action : \(q(avant.prochaineAction)) → \(q(apres.prochaineAction))")
        }
        if avant.prochaineDate != apres.prochaineDate {
            func d(_ s: String) -> String { s.isEmpty ? "aucune" : Dates.court(s) }
            l.append("date : \(d(avant.prochaineDate)) → \(d(apres.prochaineDate))")
        }
        if avant.nePlusContacter != apres.nePlusContacter { l.append(apres.nePlusContacter ? "ne plus contacter" : "recontact autorisé") }
        return l.isEmpty ? "" : "Fiche modifiée par \(Moi.nom) : " + l.joined(separator: " · ")
    }
}

extension Stockage {
    /// Écrit au fil ce que Sacha a changé sur la fiche. nil si rien de suivi n'a bougé.
    func consignerChangements(avant: Contact, apres: Contact) throws -> String? {
        let note = Changements.resume(avant: avant, apres: apres)
        guard !note.isEmpty else { return nil }
        try noterAuFil(apres.id, note)
        return note
    }

    /// « Reporter » : la même action, un autre jour, et la trace au fil. Renvoie la ligne écrite.
    @discardableResult
    func reporterEtNoter(_ contactId: String, au jour: String) throws -> String {
        guard let c = try contact(contactId) else { return "" }
        let avant = c.prochaineDate.isEmpty ? "sans date" : Dates.court(c.prochaineDate)
        let note = "Reporté : \(c.prochaineAction.isEmpty ? "action prévue" : "« \(c.prochaineAction.prefix(70)) »") du \(avant) au \(Dates.court(jour))"
        try reporterAction(contactId, au: jour)
        try noterAuFil(contactId, note)
        return note
    }
}

// MARK: « C'est fait » sur la prochaine action (04/11, PILOTE : « sur une action d'envoi, pose la suite comme un envoi au lieu
// de vider la date » : une fiche sans date sort du suivi, c'était la cause des fiches orphelines).

extension Stockage {
    /// La prochaine action est faite. Une action d'ENVOI (relance, mail, DM, invitation…) vaut un envoi : étape « contacté » au
    /// moins, suite de la routine à J+5 ouvrés, même si la date de la fiche est plus tard. Les autres actions libèrent la date,
    /// comme avant. « Invitation acceptée ? » garde ses boutons « Acceptée / Pas encore » : « Fait » ne la traite pas en envoi.
    /// 05/11 (T27) : sur la dernière étape « Sans réponse au … : classer sans suite », « C'est fait » classe la fiche « Perdu »
    /// (vider la date la laissait orpheline, hors de tout suivi). Jamais un client « gagné » : lui garde son étape.
    /// Écrit la trace au fil et renvoie la ligne écrite.
    @discardableResult
    func actionFaite(contactId: String) throws -> String {
        guard let c = try contact(contactId) else { return "" }
        let action = c.prochaineAction.isEmpty ? "Action prévue" : c.prochaineAction
        var note = "Fait : \(action)"
        if Libelles.estSansSuite(action), c.etape != "gagne", c.etape != "perdu" {
            try enregistrer(["id": c.id, "etape": "perdu", "prochaine_action": "", "prochaine_date": ""])
            note += " · classée sans suite : étape « \(Libelles.etape(c.etape)) » → « Perdu », plus aucune relance"
            try noterAuFil(c.id, note)
            return note
        }
        let estUnEnvoi = Libelles.actionEstUnEnvoi(action) && !Invitation.attendue(action)
            && !c.nePlusContacter && c.etape != "perdu"
        if estUnEnvoi {
            let debut = action.prefix(45).lowercased()
            var e = Evenement(id: "", contactId: c.id, le: Dates.maintenant())
            e.type = debut.contains("invit") && !debut.contains("pas accept") ? "invitation" : "message"
            let (suite, date) = Self.suiteApresEnvoi(e, actionFaite: action, etape: c.etape)
            let etape = Libelles.rang("contacte") > Libelles.rang(c.etape) ? "contacte" : c.etape
            try enregistrer(["id": c.id, "etape": etape, "prochaine_action": suite, "prochaine_date": date])
            note += " · suite posée : « \(suite.prefix(70)) » le \(Dates.court(date))"
        } else {
            try enregistrer(["id": c.id, "prochaine_action": "", "prochaine_date": ""])
        }
        try noterAuFil(c.id, note)
        return note
    }
}
