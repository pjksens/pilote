// Le parcours d'un prospect, dans l'ordre (04/11, Sacha : « tout chronologique, SUPER VISUEL : prospect entré en base →
// invitation envoyée → acceptée ? → message → réponse ? → relance… »). Calculé à partir du fil : aucune écriture, aucune
// nouvelle donnée ; ce que l'écran montre est ce qui s'est vraiment passé.
import Foundation

struct EtapeParcours: Identifiable, Equatable {
    enum Etat: Equatable {
        case fait        // arrivé : date au fil
        case courante    // là où en est le prospect
        case aVenir
        case saute       // pas nécessaire (déjà répondu avant la relance, etc.)
    }
    var cle: String
    var titre: String
    var etat: Etat
    /// Le jour (AAAA-MM-JJ) où c'est arrivé ; vide sinon.
    var date: String = ""
    /// Une ligne courte : « 2 fois », « à valider », « on attend depuis 3 j »…
    var detail: String = ""
    /// Étape courante qui attend l'autre (acceptation, réponse) plutôt qu'une action de Sacha.
    var attente: Bool = false
    var id: String { cle }
}

enum Parcours {
    static func etapes(contact c: Contact, fil: [Evenement], aujourdhui: String = Dates.aujourdhui()) -> [EtapeParcours] {
        let asc = fil.sorted { $0.le < $1.le }
        let envoyes = asc.filter { $0.sens == "sortant" && $0.statut == "envoye" }
        let invitations = envoyes.filter { $0.type == "invitation" }
        let messages = envoyes.filter { $0.type != "invitation" }
        let enCours = asc.filter { ["prepare", "a_valider", "a_refaire"].contains($0.statut) && $0.sens == "sortant" }
        let invitationPrete = enCours.first { $0.type == "invitation" }
        let messagePret = enCours.last { $0.type != "invitation" }
        let acceptee = asc.last { $0.texte.hasPrefix("Invitation acceptée") }
        let pasEncore = Invitation.pasEncoreDepuisInvitation(asc.reversed())
        let reponse = asc.first { $0.sens == "entrant" || $0.type == "reponse" }
        let rdv = asc.first { $0.type == "rdv" }
        let linkedin = !invitations.isEmpty || invitationPrete != nil || acceptee != nil || Invitation.attendue(c.prochaineAction)

        func jour(_ e: Evenement?) -> String { e.map { Dates.jourDe($0.le) } ?? "" }
        func depuis(_ j: String) -> String {
            guard let a = Dates.date(j), let b = Dates.date(aujourdhui) else { return "" }
            let n = Calendar.current.dateComponents([.day], from: a, to: b).day ?? 0
            return n <= 0 ? L("aujourd'hui") : L("depuis \(n) j")
        }

        var l: [EtapeParcours] = []
        l.append(EtapeParcours(cle: "base", titre: L("En base"), etat: .fait, date: Dates.jourDe(c.creeLe), detail: c.source))

        if linkedin {
            if let i = invitations.last {
                l.append(EtapeParcours(cle: "invitation", titre: L("Invitation"), etat: .fait, date: jour(i),
                                       detail: invitations.count > 1 ? L("\(invitations.count) fois") : ""))
            } else {
                l.append(EtapeParcours(cle: "invitation", titre: L("Invitation"), etat: .aVenir,
                                       detail: invitationPrete == nil ? L("à préparer") : L("prête, à envoyer")))
            }
            if let a = acceptee {
                l.append(EtapeParcours(cle: "acceptee", titre: L("Acceptée"), etat: .fait, date: jour(a)))
            } else if !invitations.isEmpty {
                let detail = pasEncore >= Invitation.essais ? L("pas encore ×\(pasEncore) : autre canal")
                    : (pasEncore > 0 ? L("pas encore ×\(pasEncore)") : depuis(jour(invitations.last)))
                l.append(EtapeParcours(cle: "acceptee", titre: L("Acceptée ?"), etat: .aVenir, detail: detail, attente: true))
            } else {
                l.append(EtapeParcours(cle: "acceptee", titre: L("Acceptée ?"), etat: .aVenir))
            }
        }

        if let m = messages.first {
            l.append(EtapeParcours(cle: "message", titre: L("Message"), etat: .fait, date: jour(m), detail: Libelles.canal(m.canal)))
        } else {
            let detail: String
            switch messagePret?.statut {
            case "a_valider": detail = L("à valider")
            case "a_refaire": detail = L("à refaire")
            case "prepare": detail = L("prêt, à envoyer")
            default: detail = L("à préparer")
            }
            l.append(EtapeParcours(cle: "message", titre: L("Message"), etat: .aVenir, detail: detail))
        }

        if let r = reponse {
            l.append(EtapeParcours(cle: "reponse", titre: L("Réponse"), etat: .fait, date: jour(r), detail: Libelles.canal(r.canal)))
        } else if let m = messages.last {
            l.append(EtapeParcours(cle: "reponse", titre: L("Réponse ?"), etat: .aVenir, detail: depuis(jour(m)), attente: true))
        } else {
            l.append(EtapeParcours(cle: "reponse", titre: L("Réponse ?"), etat: .aVenir))
        }

        // Relance : nécessaire seulement sans réponse ; un 2e envoi ou plus après le premier message en est une.
        if messages.count > 1 {
            l.append(EtapeParcours(cle: "relance", titre: L("Relance"), etat: .fait, date: jour(messages.last),
                                   detail: messages.count > 2 ? L("\(messages.count - 1) fois") : ""))
        } else if reponse != nil {
            l.append(EtapeParcours(cle: "relance", titre: L("Relance"), etat: .saute))
        } else {
            l.append(EtapeParcours(cle: "relance", titre: L("Relance"), etat: .aVenir,
                                   detail: messagePret != nil && !messages.isEmpty ? L("prête, à envoyer") : ""))
        }

        switch c.etape {
        case "gagne": l.append(EtapeParcours(cle: "fin", titre: L("Gagné"), etat: .fait))
        case "perdu": l.append(EtapeParcours(cle: "fin", titre: L("Perdu"), etat: .fait))
        default:
            if let r = rdv ?? (c.etape == "rdv" ? asc.last : nil) {
                l.append(EtapeParcours(cle: "fin", titre: L("Rendez-vous"), etat: .fait, date: jour(r)))
            } else {
                l.append(EtapeParcours(cle: "fin", titre: L("Rendez-vous"), etat: .aVenir))
            }
        }

        // La première étape non faite et non sautée est celle où en est le prospect.
        if !["gagne", "perdu"].contains(c.etape), let i = l.firstIndex(where: { $0.etat == .aVenir }) { l[i].etat = .courante }
        return l
    }
}
