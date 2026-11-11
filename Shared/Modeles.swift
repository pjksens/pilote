// Ce que Pilote suit : des contacts (KRYVA, freelance, autre) et le fil de ce qui s'est passé avec chacun.
import Foundation

struct Contact: Identifiable, Hashable, Codable {
    var id: String
    var espace: String = "kryva"          // kryva | freelance | autre
    var type: String = "autre"            // artisan | comptable | partenaire | negoce | syndicat | client | autre
    var nom: String = ""
    var entreprise: String = ""
    var ville: String = ""
    var departement: String = ""
    var telephone: String = ""
    var email: String = ""
    var linkedin: String = ""
    var facebook: String = ""
    var site: String = ""
    var etape: String = "a_contacter"     // a_contacter | contacte | repondu | rdv | gagne | perdu
    var prochaineAction: String = ""
    var prochaineDate: String = ""        // AAAA-MM-JJ, vide si aucune
    var priorite: Int = 2                 // 1 haute, 2 normale, 3 basse
    var nePlusContacter: Bool = false
    var orgId: String = ""                // entreprise inscrite sur KRYVA
    var source: String = ""
    var sourceRef: String = ""
    var notes: String = ""
    var creeLe: String = ""
    var majLe: String = ""

    /// 09/11 (Organisation) : le nom montré sur une ligne, jamais vide. Sans nom : l'entreprise, sinon le téléphone,
    /// l'e-mail ou le site.
    var nomAffiche: String {
        [nom, entreprise, telephone, email, site].lazy.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? L("Contact sans nom")
    }

    /// Ordre par défaut de la liste : d'abord ce qui demande une action, puis les échanges en cours,
    /// les inscrits KRYVA, les prochaines actions sans date, les priorités hautes, le reste.
    var importance: Int {
        if nePlusContacter || etape == "perdu" { return 9 }
        if !prochaineDate.isEmpty { return 0 }          // un client « gagné » daté est suivi comme les autres (05/11, T3)
        if etape == "rdv" || etape == "repondu" { return 1 }
        if !orgId.isEmpty { return 2 }
        if !prochaineAction.isEmpty { return 3 }
        if priorite == 1 { return 4 }
        if etape == "contacte" { return 5 }
        return 6
    }

    /// Le profil LinkedIn s'il est connu, sinon une recherche LinkedIn sur le nom (Sacha cherche et clique lui-même).
    var lienLinkedIn: URL? {
        if !linkedin.isEmpty { return URL(string: linkedin) }
        return Self.recherche("https://www.linkedin.com/search/results/people/", nom.isEmpty ? [entrepriseCourte, ville] : [nom, entrepriseCourte])
    }

    /// Le site de la fiche comme adresse web ouvrable (« exemple.fr/page » → https://exemple.fr/page) ; nil si vide ou pas une adresse web.
    var lienSite: URL? {
        let t = site.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !t.contains(" ") else { return nil }
        let avecSchema = t.range(of: #"^[a-zA-Z][a-zA-Z0-9+.-]*://"#, options: .regularExpression) != nil ? t : "https://" + t
        guard let u = URL(string: avecSchema), ["http", "https"].contains(u.scheme?.lowercased() ?? ""),
              let h = u.host, h.contains(".") else { return nil }
        return u
    }

    var lienFacebook: URL? {
        if !facebook.isEmpty { return URL(string: facebook) }
        return Self.recherche("https://www.facebook.com/search/people/", [nom, ville])
    }

    /// L'entreprise sans les précisions entre parenthèses (« CABINET (avec Partenaire…) » → « CABINET »).
    var entrepriseCourte: String {
        entreprise.replacingOccurrences(of: #"\s*[\(«].*$"#, with: "", options: .regularExpression)
    }

    private static func recherche(_ base: String, _ mots: [String]) -> URL? {
        let q = mots.filter { !$0.isEmpty }.joined(separator: " ")
        guard !q.isEmpty, var c = URLComponents(string: base) else { return nil }
        c.queryItems = [URLQueryItem(name: base.contains("linkedin") ? "keywords" : "q", value: q)]
        return c.url
    }

    /// Nom à afficher : la personne, sinon l'entreprise.
    var titre: String { nom.isEmpty ? (entreprise.isEmpty ? L("Sans nom") : entreprise) : nom }
    var sousTitre: String { nom.isEmpty ? "" : entreprise }
}

struct Evenement: Identifiable, Hashable, Codable {
    var id: String
    var contactId: String
    var le: String                        // ISO 8601
    var canal: String = "autre"           // linkedin | facebook | sms | mail | appel | visite | visio | autre
    var sens: String = "interne"          // sortant | entrant | interne
    var type: String = "note"             // invitation | message | reponse | appel | visite | rdv | note
    var texte: String = ""
    var statut: String = "fait"           // a_valider | a_refaire | prepare | envoye | echec | annule | fait
    var par: String = "\(Moi.nom)"
    var objet: String = ""                // mails : l'objet ; DM : le pseudo du destinataire (« @… »)
    var reponseA: String = ""             // mails : Message-ID du mail auquel on répond (même fil)
    var messageId: String = ""            // mails : Message-ID du mail parti
    /// Message préparé (05/11, T7) : ce qui doit être vrai avant l'envoi (« après le test de l'acompte sur un vrai devis »).
    var condition: String = ""
    var conditionOkLe: String = ""        // ISO 8601 : quand la condition a été cochée ; vide = pas encore
    /// Le rappel (Rappels) lié : identifiant, ou titre exact. Pilote le coche quand la condition l'est, ou à l'envoi s'il n'y en a pas.
    var rappelId: String = ""
    var rappelFermeLe: String = ""        // ISO 8601 : quand Pilote a coché (ou cherché en vain) le rappel lié

    /// Une condition posée et pas encore cochée : l'envoi est bloqué.
    /// La condition à regarder pour dater le message : vide si aucune ou déjà cochée (Libelles.jourDuMessage).
    var conditionPourJour: String { conditionEnAttente ? condition : "" }
    var conditionEnAttente: Bool { !condition.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && conditionOkLe.isEmpty }
}

enum Libelles {
    // 10/11 (langues) : les libellés se lisent à l'appel (var calculées), pas une fois pour toutes ; les clés (« kryva »,
    // « a_contacter »…) sont les valeurs stockées et ne changent jamais.
    static var espaces: [(String, String)] { Reglages.nommer([("kryva", "KRYVA"), ("freelance", "Freelance"), ("autre", L("Autre"))]) }
    static var types: [(String, String)] { [
        ("artisan", L("Artisan")), ("comptable", L("Comptable")), ("partenaire", L("Partenaire")),
        ("negoce", L("Négoce")), ("syndicat", L("Syndicat")), ("client", L("Client")), ("autre", L("Autre")),
    ] }
    static var etapes: [(String, String)] { [
        ("a_contacter", L("À contacter")), ("contacte", L("Contacté")), ("repondu", L("A répondu")),
        ("rdv", L("Rendez-vous")), ("gagne", L("Gagné")), ("perdu", L("Perdu")),
    ] }
    static var canaux: [(String, String)] { [
        ("linkedin", "LinkedIn"), ("facebook", "Facebook"), ("instagram", "Instagram"), ("sms", "SMS"), ("mail", "Mail"),
        ("appel", L("Appel")), ("visite", L("Visite")), ("visio", L("Visio")), ("autre", L("Autre")),
    ] }
    static var typesEvenement: [(String, String)] { [
        ("invitation", L("Invitation")), ("message", L("Message")), ("reponse", L("Réponse")), ("appel", L("Appel")),
        ("visite", L("Visite")), ("rdv", L("Rendez-vous")), ("note", L("Note")),
    ] }

    // Les mêmes libellés, toujours en français : pour ce qu'on écrit dans la base (notes du fil) ou qu'on envoie à une
    // session (les équipes d'agents travaillent en français). Jamais pour l'écran.
    private static let etapesFr: [(String, String)] = [
        ("a_contacter", "À contacter"), ("contacte", "Contacté"), ("repondu", "A répondu"),
        ("rdv", "Rendez-vous"), ("gagne", "Gagné"), ("perdu", "Perdu"),
    ]
    private static let canauxFr: [(String, String)] = [
        ("linkedin", "LinkedIn"), ("facebook", "Facebook"), ("instagram", "Instagram"), ("sms", "SMS"), ("mail", "Mail"),
        ("appel", "Appel"), ("visite", "Visite"), ("visio", "Visio"), ("autre", "Autre"),
    ]
    private static let typesEvenementFr: [(String, String)] = [
        ("invitation", "Invitation"), ("message", "Message"), ("reponse", "Réponse"), ("appel", "Appel"),
        ("visite", "Visite"), ("rdv", "Rendez-vous"), ("note", "Note"),
    ]
    static func etapeFr(_ c: String) -> String { libelle(etapesFr, c) }
    static func canalFr(_ c: String) -> String { libelle(canauxFr, c) }
    static func typeEvenementFr(_ c: String) -> String { libelle(typesEvenementFr, c) }

    static func libelle(_ liste: [(String, String)], _ cle: String) -> String {
        liste.first { $0.0 == cle }?.1 ?? cle
    }
    static func espace(_ c: String) -> String { libelle(espaces, c) }
    static func type(_ c: String) -> String { libelle(types, c) }
    static func etape(_ c: String) -> String { libelle(etapes, c) }
    static func canal(_ c: String) -> String { libelle(canaux, c) }

    /// « @annemariepiombo » → son profil Instagram (le pseudo d'un DM est rangé dans l'objet).
    static func lienInstagram(_ pseudo: String) -> URL? {
        let p = pseudo.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "@", with: "").replacingOccurrences(of: "＠", with: "")
        return p.isEmpty ? nil : URL(string: "https://www.instagram.com/\(p)/")
    }
    static func typeEvenement(_ c: String) -> String { libelle(typesEvenement, c) }

    /// Le jour d'envoi écrit par l'agent en tête d'un message prêt (« WhatsApp à envoyer par Sacha mer. 04/11 à 09:45 ») :
    /// il passe avant la date de la fiche, qui suit parfois une autre action du contact. nil sinon.
    static func jourPrevu(_ texte: String, aujourdhui: String) -> String? {
        let tete = texte.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        guard tete.lowercased().contains("envoyer"),
              let r = tete.range(of: #"\b(\d{2})/(\d{2})\b"#, options: .regularExpression) else { return nil }
        return jourISO(String(tete[r]), aujourdhui: aujourdhui)
    }

    /// « 16/11 » → « 2026-11-16 » (un mois passé de plus de six mois veut dire l'an prochain). nil si ce n'est pas une date.
    static func jourISO(_ jjmm: String, aujourdhui: String) -> String? {
        let jm = jjmm.split(separator: "/")
        guard jm.count == 2, let j = Int(jm[0]), let m = Int(jm[1]), (1...31).contains(j), (1...12).contains(m),
              let annee = Int(aujourdhui.prefix(4)) else { return nil }
        let moisCourant = Int(aujourdhui.dropFirst(5).prefix(2)) ?? m
        let a = m < moisCourant - 6 ? annee + 1 : annee
        return String(format: "%04d-%02d-%02d", a, m, j)
    }

    /// Ordre des étapes : on ne fait jamais reculer un contact automatiquement.
    static func rang(_ etape: String) -> Int { etapesFr.firstIndex { $0.0 == etape } ?? 0 }
}

enum Dates {
    static let jour: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Europe/Paris")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    static let iso = ISO8601DateFormatter()

    static func aujourdhui() -> String { jour.string(from: Date()) }
    static func maintenant() -> String { iso.string(from: Date()) }
    /// Dans n jours ouvrés (samedi, dimanche et jours fériés français sautés : 04/11, le 11/11 tombait un férié).
    static func ouvres(_ n: Int, depuis: Date = Date()) -> String {
        var d = depuis, reste = n
        while reste > 0 {
            d = Calendar.current.date(byAdding: .day, value: 1, to: d)!
            if !Calendar.current.isDateInWeekend(d) && !estFerie(d) { reste -= 1 }
        }
        return jour.string(from: d)
    }

    private static let calendrierParis: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Paris")!
        return c
    }()

    /// Dimanche de Pâques (calcul de Meeus/Jones/Butcher).
    static func paques(_ annee: Int) -> Date {
        let a = annee % 19, b = annee / 100, c = annee % 100
        let d = b / 4, e = b % 4, f = (b + 8) / 25, g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4, k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let mois = (h + l - 7 * m + 114) / 31, jourDuMois = (h + l - 7 * m + 114) % 31 + 1
        return calendrierParis.date(from: DateComponents(year: annee, month: mois, day: jourDuMois, hour: 12))!
    }

    /// Les 11 jours fériés de l'année, en AAAA-MM-JJ : 1er janvier, lundi de Pâques, 1er mai, 8 mai, Ascension, lundi de
    /// Pentecôte, 14 juillet, 15 août, 1er novembre, 11 novembre, 25 décembre.
    static func feries(_ annee: Int) -> Set<String> {
        let fixes = [(1, 1), (5, 1), (5, 8), (7, 14), (8, 15), (11, 1), (11, 11), (12, 25)].map { String(format: "%04d-%02d-%02d", annee, $0.0, $0.1) }
        let paques = paques(annee)
        let mobiles = [1, 39, 50].map { jour.string(from: calendrierParis.date(byAdding: .day, value: $0, to: paques)!) }
        return Set(fixes + mobiles)
    }

    static func estFerie(_ d: Date) -> Bool {
        feries(calendrierParis.component(.year, from: d)).contains(jour.string(from: d))
    }

    static func dans(_ jours: Int) -> String {
        jour.string(from: Calendar.current.date(byAdding: .day, value: jours, to: Date())!)
    }

    /// « 27 oct. » ou « 27 oct. 2025 » si ce n'est pas l'année en cours.
    /// « 2026-11-12 » → « 12/11 » (les actions écrites à la main disent « au 12/11 »).
    static func jjmm(_ s: String) -> String {
        let p = s.prefix(10).split(separator: "-")
        return p.count == 3 ? "\(p[2])/\(p[1])" : s
    }

    /// `francais` : pour une note écrite dans la base (toujours en français) ; sinon la langue de l'app.
    static func court(_ s: String, francais: Bool = false) -> String {
        guard let d = date(s) else { return s }
        let f = DateFormatter()
        f.locale = (francais || Loc.estFrancais) ? Locale(identifier: "fr_FR") : Loc.locale
        f.timeZone = TimeZone(identifier: "Europe/Paris")
        let memeAnnee = Calendar.current.component(.year, from: d) == Calendar.current.component(.year, from: Date())
        f.setLocalizedDateFormatFromTemplate(memeAnnee ? "d MMM" : "d MMM y")
        return f.string(from: d)
    }

    static func date(_ s: String) -> Date? {
        if s.isEmpty { return nil }
        return iso.date(from: s) ?? jour.date(from: String(s.prefix(10)))
    }
}

extension DernierEchange {
    /// Le dernier échange en une phrase, dans la langue de l'app (`resume`, dans Videos.swift, reste en français).
    /// Une phrase entière par cas : l'ordre des mots change d'une langue à l'autre.
    var resumeAffiche: String {
        let quand = Dates.court(le)
        let canal = Libelles.canal(self.canal)
        switch sens {
        case "entrant": return L("A répondu (\(canal)) le \(quand)")
        case "sortant":
            if self.canal == "autre" { return L("\(Libelles.typeEvenement(type)) envoyé le \(quand)") }
            return L("\(canal) envoyé le \(quand)")
        default: return L("\(Libelles.typeEvenement(type)) le \(quand)")
        }
    }
}
