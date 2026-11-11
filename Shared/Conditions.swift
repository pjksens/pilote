// Condition d'un message préparé et rappel lié (05/11, T7 du rapport TROUS-PILOTE). Cas réel : le SMS à Marc Lefèvre du
// 04/11 13:47 est parti AVANT le test de l'acompte qui en était la condition (écrite seulement dans l'en-tête du texte), et le
// rappel « Tester l'acompte avant d'écrire à Frédéric » est resté ouvert, sans lien avec la fiche.
// Règles : la condition est portée par l'événement « prepare » ; tant qu'elle n'est pas cochée, l'app bloque l'envoi et
// `marquer(… envoye)` refuse (sauf message déjà parti). Le rappel lié (`rappel_id`) est coché par l'app quand la condition
// l'est, ou à l'envoi d'un message sans condition ; il reste ouvert si le message part sans que la condition soit remplie.
import Foundation

extension Libelles {
    /// L'identifiant d'un rappel tel qu'EventKit le connaît : « x-apple-reminder://ABC » (AppleScript) → « ABC ».
    static func refRappel(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.hasPrefix("x-apple-reminder://") ? String(t.dropFirst("x-apple-reminder://".count)) : t
    }
}

/// Un rappel lié que l'app doit cocher (puis noter au fil).
struct RappelAFermer: Equatable {
    var evenementId: String
    var contactId: String
    var rappel: String
    /// « condition remplie » ou « message envoyé ».
    var raison: String
}

extension Stockage {
    /// La condition d'un message préparé est remplie : la date est notée, l'envoi se débloque, une ligne va au fil.
    /// Renvoie la ligne écrite ; vide s'il n'y a pas de condition ou si elle était déjà cochée.
    @discardableResult
    func conditionRemplie(evenementId: String, par: String = "\(Moi.nom)") throws -> String {
        guard let e = try evenement(evenementId) else { throw ErreurBase(description: L("Événement introuvable : \(evenementId)")) }
        guard e.conditionEnAttente else { return "" }
        let maintenant = Dates.maintenant()
        try base.executer("UPDATE evenements SET condition_ok_le = ?, maj_le = ? WHERE id = ?", [maintenant, maintenant, evenementId])
        let apres = e.statut == "envoye" ? " (après l'envoi)" : ", le message peut partir"
        let note = "Condition remplie, cochée par \(par)\(apres) : « \(e.condition.trimmingCharacters(in: .whitespacesAndNewlines)) »."
        try ajouterEvenement(contactId: e.contactId, ["canal": e.canal, "sens": "interne", "type": "note", "statut": "fait",
                                                      "par": par, "texte": note])
        return note
    }

    /// Les rappels liés à cocher : condition cochée, ou message sans condition parti. Jamais un message parti sans sa condition.
    func rappelsAFermer() throws -> [RappelAFermer] {
        try base.lignes("""
            SELECT * FROM evenements WHERE rappel_id != '' AND rappel_ferme_le = '' AND supprime_le = ''
              AND (condition_ok_le != '' OR (trim(condition) = '' AND statut = 'envoye'))
            ORDER BY le
            """).map(Self.evenement).map {
            RappelAFermer(evenementId: $0.id, contactId: $0.contactId, rappel: Libelles.refRappel($0.rappelId),
                          raison: $0.conditionOkLe.isEmpty ? "message envoyé" : "condition remplie")
        }
    }

    /// L'app a coché le rappel lié (`titre`), ou ne l'a pas trouvé (`titre` nil) : on ne le cherche plus, la trace va au fil.
    func rappelFerme(_ r: RappelAFermer, titre: String?) throws {
        let maintenant = Dates.maintenant()
        try base.executer("UPDATE evenements SET rappel_ferme_le = ?, maj_le = ? WHERE id = ?", [maintenant, maintenant, r.evenementId])
        let note = titre.map { "Rappel lié « \($0) » coché par Pilote (\(r.raison))." }
            ?? "Rappel lié « \(r.rappel) » introuvable dans Rappels (\(r.raison)) : à cocher à la main s'il existe."
        try ajouterEvenement(contactId: r.contactId, ["canal": "autre", "sens": "interne", "type": "note", "statut": "fait",
                                                      "par": "Pilote", "texte": note])
    }
}
