// Messages et Mail : ouvrent un brouillon déjà rempli. Rien ne part : Sacha relit et envoie lui-même.
import AppKit

enum Brouillon {
    /// Numéro au format international : « 06 12 34 56 78 » → « +33612345678 ». Vide si la fiche n'en a pas.
    static func numero(_ telephone: String) -> String {
        var n = telephone.filter { $0.isNumber || $0 == "+" }
        if n.hasPrefix("00") { n = "+" + n.dropFirst(2) }
        if n.hasPrefix("0"), n.count == 10 { n = "+33" + n.dropFirst() }
        return n
    }

    /// Messages : nouveau message au numéro de la fiche (destinataire vide sans numéro), texte rempli.
    /// Forme « sms:numéro&body=texte » vérifiée sur macOS 26 : numéro, texte, retours à la ligne, accents et « & » repris.
    static func messages(telephone: String, texte: String) {
        ouvrir("sms:\(numero(telephone))&body=\(encode(texte))", app: "com.apple.MobileSMS")
    }

    // Mail : voir `Mail.brouillon` (expéditeur Gmail forcé). Plus de « mailto: », qui partait du compte par défaut de Mail (kryva.fr possible).

    /// Encode tout sauf les lettres et chiffres ASCII et « -._~ » : espaces, retours à la ligne, « & », « ? », accents.
    private static func encode(_ texte: String, garder: String = "") -> String {
        let permis = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~" + garder)
        return texte.addingPercentEncoding(withAllowedCharacters: permis) ?? ""
    }

    /// Ouvre dans l'app voulue, quelle que soit l'app par défaut pour ces liens.
    private static func ouvrir(_ adresse: String, app: String) {
        guard let url = URL(string: adresse) else { return }
        guard let appli = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app) else {
            NSWorkspace.shared.open(url)
            return
        }
        NSWorkspace.shared.open([url], withApplicationAt: appli, configuration: NSWorkspace.OpenConfiguration())
    }
}
