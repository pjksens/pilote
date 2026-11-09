// Même message déjà rangé au fil ? (04/11, doublon du mail de Julien Morel)
//
// Le capteur range un message entrant avec une `source_ref` (mail:198500). Une session qui avait déjà noté le même mail à la main
// (ajoute_au_fil, sans source_ref ni message_id) n'était pas reconnue : le fil avait deux entrées. Règle : même contact, sens
// entrant, texte de même début (hors majuscules, accents, ponctuation, retours à la ligne), moins de 10 minutes d'écart.

import Foundation

enum FilDoublon {
    static let ecartMax: TimeInterval = 10 * 60
    private static let longueurComparee = 40
    private static let longueurMini = 10        // en dessous, deux textes courts (« ok », « merci ») ne se confondent que s'ils sont identiques

    /// Début du texte réduit à des lettres et chiffres minuscules sans accent, sans le préfixe de canal du capteur.
    static func empreinte(_ texte: String) -> String {
        var t = texte
        for prefixe in ["WhatsApp : ", "iMessage : "] where t.hasPrefix(prefixe) { t.removeFirst(prefixe.count) }
        let plat = t.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
        return String(plat.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
    }

    static func memeMessage(texteA: String, leA: String, texteB: String, leB: String) -> Bool {
        guard let a = Dates.iso.date(from: leA), let b = Dates.iso.date(from: leB), abs(a.timeIntervalSince(b)) < ecartMax else { return false }
        let x = empreinte(texteA), y = empreinte(texteB)
        guard !x.isEmpty, !y.isEmpty else { return false }
        let n = min(longueurComparee, x.count, y.count)
        if n < longueurMini { return x == y }
        return x.prefix(n) == y.prefix(n)
    }
}
