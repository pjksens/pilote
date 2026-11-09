// L'utilisateur de Pilote, tel que Pilote l'écrit : le réglage `prenom` de reglages.json.
// `nom` sert aux libellés de l'app (« Camille : appeler… », « Vous » sans réglage) ;
// `tiers` aux textes lus par les sessions Claude Code (« l'utilisateur » sans réglage : « envoyé par l'utilisateur »).
import Foundation

enum Moi {
    /// Le prénom réglé, ou nil.
    static var prenom: String? {
        let p = Reglages.courants.prenom?.trimmingCharacters(in: .whitespaces) ?? ""
        return p.isEmpty ? nil : p
    }
    static var nom: String { prenom ?? "Vous" }
    static var tiers: String { prenom ?? "l'utilisateur" }
}
