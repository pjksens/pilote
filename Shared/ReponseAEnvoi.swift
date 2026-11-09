// Un mail « inconnu » qui répond à un mail envoyé par Sacha (04/11, cas de Paul DURAND / Exemple)
//
// Paul a répondu à Sacha, mais sans fiche Pilote son mail est resté « inconnu » : ligne noyée parmi les autres, aucun agent prévenu.
// Le capteur ne crée pas de fiche tout seul. Il marque la ligne (`reponse_a_envoi`) et la veille la signale en tête à PILOTE.
//
// Attention (vérifié dans l'Envelope Index) : Mail range l'objet SANS son préfixe « RE: » (colonne `subject_prefix` à part).
// Une règle fondée sur « l'objet commence par RE: » ne verrait donc jamais le préfixe dans `subjects.subject`.
//
// Une réponse = un message entrant qui, dans les 90 jours après un envoi de Sacha :
//   « fil »     appartient à la même conversation (conversation_id) qu'un mail envoyé par Sacha ;
//   « sujet »   porte un préfixe de réponse (RE, TR…) et le même objet qu'un mail envoyé par Sacha à cette adresse ;
//   « adresse » porte un préfixe de réponse et vient d'une adresse à qui Sacha a écrit.
// Une adresse à qui Sacha a écrit, mais qui écrit sur un autre sujet sans préfixe, n'est pas marquée (trop de faux positifs).

import Foundation

struct EnvoiDeSacha: Equatable {
    var adresse: String         // destinataire (minuscules)
    var sujet: String           // objet du mail envoyé
    var conversation: Int       // conversation_id de Mail (0 = inconnu)
    var le: Date
}

enum ReponseAEnvoi {
    static let fenetre: TimeInterval = 90 * 86400
    private static let prefixesDeReponse: Set<String> = ["re", "tr", "rep", "aw", "sv", "fw", "fwd"]

    /// Retire les préfixes « RE: », « Re : », « TR: », « Fwd: » en tête (accents et casse ignorés). Renvoie leur nombre et le reste.
    static func decouper(_ s: String) -> (prefixes: Int, reste: String) {
        var reste = Substring(s.trimmingCharacters(in: .whitespacesAndNewlines))
        var n = 0
        while let deuxPoints = reste.firstIndex(of: ":") {
            let mot = String(reste[..<deuxPoints]).trimmingCharacters(in: .whitespaces)
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
            guard mot.count <= 3, prefixesDeReponse.contains(mot) else { break }
            n += 1
            reste = reste[reste.index(after: deuxPoints)...].drop(while: { $0.isWhitespace })
        }
        return (n, String(reste))
    }

    /// `prefixe` = colonne subject_prefix de Mail ; `objet` peut lui-même commencer par « RE: » selon le compte.
    static func aPrefixeDeReponse(prefixe: String, objet: String) -> Bool {
        decouper(prefixe).prefixes > 0 || decouper(objet).prefixes > 0
    }

    /// Réponses d'absence et accusés automatiques : le message d'un humain absent n'est pas une réponse à traiter.
    static func estReponseAutomatique(_ objet: String) -> Bool {
        let o = objet.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
        return ["reponse automatique", "automatic reply", "autoreply", "auto-reply", "out of office", "absence du bureau", "absent du bureau",
                "accuse de reception", "undeliverable", "delivery status notification"].contains(where: { o.hasPrefix($0) })
    }

    private static func sujetComparable(_ s: String) -> String { FilDoublon.empreinte(decouper(s).reste) }

    /// nil si ce n'est pas une réponse à un envoi de Sacha ; sinon « fil », « sujet » ou « adresse ».
    static func raison(prefixe: String, objet: String, adresses: [String], conversation: Int, recu: Date, envois: [EnvoiDeSacha]) -> String? {
        guard !estReponseAutomatique(objet) else { return nil }
        let pertinents = envois.filter { $0.le <= recu && recu.timeIntervalSince($0.le) <= fenetre }
        guard !pertinents.isEmpty else { return nil }
        if conversation != 0, pertinents.contains(where: { $0.conversation == conversation }) { return "fil" }
        guard aPrefixeDeReponse(prefixe: prefixe, objet: objet) else { return nil }
        let adr = Set(adresses.map { $0.lowercased() })
        let ecrits = pertinents.filter { adr.contains($0.adresse) }
        guard !ecrits.isEmpty else { return nil }
        let sujet = sujetComparable(objet)
        if !sujet.isEmpty, ecrits.contains(where: { sujetComparable($0.sujet) == sujet }) { return "sujet" }
        return "adresse"
    }

    /// Les mails envoyés par Sacha depuis `depuis`, un enregistrement par destinataire. Boîtes d'envoi : « Sent », « Sent Messages »,
    /// « Messages envoyés » (Gmail FR), « Éléments envoyés » (adresses encodées dans l'URL : on cherche « /sent » et « envoy »).
    static func requete(avecConversation: Bool, avecSupprime: Bool) -> String {
        """
        SELECT lower(a.address) AS adresse, s.subject AS sujet, \(avecConversation ? "m.conversation_id" : "0") AS conv, m.date_received AS d
        FROM recipients r
        JOIN messages m ON m.ROWID = r.message
        JOIN mailboxes mb ON mb.ROWID = m.mailbox
        JOIN addresses a ON a.ROWID = r.address
        LEFT JOIN subjects s ON s.ROWID = m.subject
        WHERE (lower(mb.url) LIKE '%/sent%' OR lower(mb.url) LIKE '%envoy%') AND m.date_received >= ?\(avecSupprime ? " AND m.deleted = 0" : "")
        """
    }
}
