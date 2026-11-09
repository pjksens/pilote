// Les invitations LinkedIn (04/11, Sacha : « j'ai pas d'option dans Pilote pour dire qu'une invitation n'a pas été
// acceptée, qu'il faut donc attendre ou faire autre chose »). Sur la ligne « Invitation acceptée ? » d'Aujourd'hui :
// « Acceptée » (l'agent prépare le message après acceptation), « Pas encore » (on revoit dans 3 jours ouvrés ; au 2e,
// l'agent prépare un mail ou un DM Insta à la place). « Reporter » vaut pour toutes les lignes.
import Foundation

enum Invitation {
    static let pasEncore = "Invitation pas encore acceptée"
    static let delai = 3          // jours ouvrés avant de revoir
    static let essais = 2         // au 2e « pas encore », on change de canal
    static let actionMessage = "Message après acceptation : préparé par l'agent, à valider"
    static let actionAutreCanal = "Invitation pas acceptée : passer par un mail ou Insta (message préparé par l'agent, à valider)"

    /// La prochaine action attend-elle qu'une invitation soit acceptée ? (posée par la routine ou écrite par un agent)
    static func attendue(_ action: String) -> Bool {
        let a = action.lowercased()
        return a.contains("invitation") && a.contains("accept") && !a.contains("pas accept")
    }

    /// Les « pas encore » notés depuis la dernière invitation (fil du plus récent au plus ancien).
    static func pasEncoreDepuisInvitation(_ fil: [Evenement]) -> Int {
        var n = 0
        for e in fil {
            if e.type == "invitation" { break }
            if e.texte.hasPrefix(pasEncore) { n += 1 }
        }
        return n
    }
}

extension Stockage {
    /// « Acceptée » : noté au fil ; la date se libère (l'envoi du message posera la relance de la routine).
    func invitationAcceptee(_ contactId: String) throws {
        try ajouterEvenement(contactId: contactId, ["canal": "linkedin", "sens": "interne", "type": "note",
                                                    "texte": "Invitation acceptée", "statut": "fait", "par": "\(Moi.nom)"])
        try enregistrer(["id": contactId, "prochaine_action": Invitation.actionMessage, "prochaine_date": ""])
    }

    /// « Pas encore » : noté au fil ; on revoit dans 3 jours ouvrés, ou, au 2e, on passe par un mail ou Insta.
    /// Renvoie vrai quand il faut changer de canal.
    @discardableResult
    func invitationPasEncore(_ contactId: String, maintenant: Date = Date()) throws -> Bool {
        let fois = Invitation.pasEncoreDepuisInvitation(try evenements(contactId)) + 1
        try ajouterEvenement(contactId: contactId, ["canal": "linkedin", "sens": "interne", "type": "note",
                                                    "texte": fois == 1 ? Invitation.pasEncore : "\(Invitation.pasEncore) (\(fois)e fois)",
                                                    "statut": "fait", "par": "\(Moi.nom)"])
        let changer = fois >= Invitation.essais
        if changer {
            try enregistrer(["id": contactId, "prochaine_action": Invitation.actionAutreCanal, "prochaine_date": ""])
        } else {
            try enregistrer(["id": contactId, "prochaine_date": Dates.ouvres(Invitation.delai, depuis: maintenant)])
        }
        return changer
    }

    /// « Reporter » : la même prochaine action, un autre jour (AAAA-MM-JJ).
    func reporterAction(_ contactId: String, au jour: String) throws {
        try enregistrer(["id": contactId, "prochaine_date": jour])
    }
}
