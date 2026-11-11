// Langue de l'app (10/11) : français = langue source (les clés du catalogue App/Localizable.xcstrings sont les phrases
// françaises), anglais = repli pour toute autre langue, espagnol en plus. L'app suit la langue du Mac ; l'outil en ligne
// de commande (aucun catalogue embarqué) reste en français. Les données de la base ne se traduisent jamais.
import Foundation

enum Loc {
    /// Les langues que l'app parle (dossiers .lproj du catalogue).
    static let langues = ["fr", "en", "es"]

    /// La langue de l'app : celle que le bundle retient pour les préférences du Mac (repli : l'anglais, région de
    /// développement). Sans catalogue embarqué (outil, tests) : le français, langue des clés.
    static func langueDuBundle(_ bundle: Bundle = .main) -> String {
        // Le catalogue embarqué le prouve (l'espagnol n'existe qu'ici) : le bundle d'un outil ou d'un test, lui, a des
        // localisations « en » héritées d'ailleurs, mais pas nos textes.
        guard bundle.url(forResource: "Localizable", withExtension: "strings", subdirectory: nil, localization: "es") != nil
        else { return "fr" }
        let choisie = bundle.preferredLocalizations.first.map { Locale(identifier: $0).language.languageCode?.identifier ?? $0 }
        return choisie.flatMap { langues.contains($0) ? $0 : nil } ?? "en"
    }

    /// Langue réglée pour toute l'app (les tests y posent « en » ou « es »).
    nonisolated(unsafe) private static var langueDeLApp: String = langueDuBundle()
    /// Langue imposée le temps d'un `enFrancais { }` (propre à la tâche en cours : ne gêne pas les autres).
    @TaskLocal static var surcharge: String? = nil
    /// La langue en cours : celle de l'app, sauf dans un `enFrancais { }`.
    static var langue: String {
        get { surcharge ?? langueDeLApp }
        set { langueDeLApp = newValue }
    }

    /// Fait tourner `travail` avec les textes en FRANÇAIS, quelle que soit la langue de l'app. Pour ce qui part vers un
    /// autre programme ou une personne (consigne à une session, note du fil, journal) : les équipes d'agents travaillent
    /// en français, et un libellé traduit y mélangerait deux langues. Ne traverse pas un `Task.detached`.
    static func enFrancais<T>(_ travail: () throws -> T) rethrows -> T {
        try $surcharge.withValue("fr", operation: travail)
    }
    /// Les tests y posent le dossier du bundle qui porte le catalogue (le bundle principal d'un test n'en a pas).
    nonisolated(unsafe) static var dossierBundle: URL? = nil

    /// Pour les dates, nombres et accords : la langue de l'app, jamais un mélange avec la région du Mac.
    static var locale: Locale { Locale(identifier: langue) }
    static var estFrancais: Bool { langue == "fr" }

    /// Une plage horaire (« 14:00 à 15:00 »). Pas passée par le catalogue : la clé « %@ à %@ » sert aussi à « jour à heure »
    /// (« at » / « a las »), qui ne convient pas à une plage. Hors français, un tiret demi-cadratin suffit dans toutes les langues.
    static func plage(_ debut: String, _ fin: String) -> String {
        estFrancais ? "\(debut) à \(fin)" : "\(debut) – \(fin)"
    }
}

extension Loc {
    private static var formats: [String: DateFormatter] = [:]
    private static let verrou = NSLock()

    /// Une date écrite selon un gabarit de composants, dans la langue de l'app : « EEEEdMMMM » donne « lundi 10 novembre »,
    /// « Monday, November 10 » ou « lunes, 10 de noviembre » (composants : EEEE jour, d jour du mois, MMMM mois, yyyy année…).
    /// À préférer à un `dateFormat` fixe, qui garde l'ordre français. L'heure reste « HH:mm » partout (24 h), sans gabarit.
    static func date(_ d: Date, _ gabarit: String) -> String {
        verrou.lock(); defer { verrou.unlock() }
        let cle = langue + "|" + gabarit
        let f: DateFormatter
        if let connu = formats[cle] { f = connu } else {
            f = DateFormatter(); f.locale = locale; f.setLocalizedDateFormatFromTemplate(gabarit)
            formats[cle] = f
        }
        return f.string(from: d)
    }
}

/// Un texte de l'écran qui n'est pas un littéral SwiftUI (ceux de `Text("…")`, `Button("…")`, `.help("…")` se traduisent
/// tout seuls). La clé est la phrase française ; une phrase avec un nombre prend ses pluriels dans le catalogue.
func L(_ ressource: LocalizedStringResource) -> String {
    guard let dossier = Loc.dossierBundle else {
        var r = ressource
        r.locale = Loc.locale
        return Loc.prenomRegle(String(localized: r))
    }
    return Loc.prenomRegle(String(localized: LocalizedStringResource(ressource.defaultValue, table: ressource.table, locale: Loc.locale,
                                                      bundle: .atURL(dossier), comment: nil)))
}

extension Loc {
    /// Copie publique : les phrases du catalogue disent « Sacha » (celui qui a écrit Pilote). Chez vous, elles disent le prénom
    /// de reglages.json, sinon « Vous » / « You » / « Tú » selon la langue. Sans effet quand le prénom réglé est « Sacha »
    /// (les tests).
    static func prenomRegle(_ texte: String) -> String {
        guard texte.contains("Sacha") else { return texte }
        let moi = Moi.prenom ?? L("Vous")
        return moi == "Sacha" ? texte : texte.replacingOccurrences(of: "Sacha", with: moi)
    }
}
