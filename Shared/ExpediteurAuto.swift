// Expéditeur automatique probable (04/11, GO de PILOTE, point b) : noreply, notifications, alertes, newsletters.
// Le capteur marque la ligne de entrants.jsonl `"auto": true` (elle reste en base) ; la veille ne la transmet plus à PILOTE.
// Un humain inconnu n'est jamais marqué : seuls les motifs ci-dessous comptent, rien d'autre.
//
// Limite connue : l'en-tête List-Unsubscribe n'est pas dans l'Envelope Index de Mail (seul List-Id l'est, déjà traité en
// amont par le capteur). On juge donc sur l'adresse seulement.
//
// 05/11 (chantier A, trou 1 : un message LinkedIn de Nathalie DUPRÉ et deux mails Google Play « Action requise » étaient
// masqués) : `probable` reste un jugement sur l'adresse, mais la décision de masquer est dans TriMail.masquer. Jamais masqué :
// une fiche (adresse, nom, nom « X via LinkedIn »), une plateforme suivie (`plateforme` : montrée en ligne courte), une réponse
// à un envoi de Sacha, un rebond.

import Foundation

enum ExpediteurAuto {
    /// Morceaux d'une partie locale (sans - _ . +) qui disent « envoi automatique », où qu'ils soient.
    private static let morceauxLocal = ["noreply", "donotreply", "nepasrepondre", "nepasrepond", "nietbeantwoorden", "noanswer",
                                        "jobalert", "notification", "newsletter", "mailerdaemon", "bounce", "unsubscribe", "dmarc"]
    /// Mots entiers (la partie locale coupée sur - _ . + et les chiffres).
    private static let motsLocal: Set<String> = ["alert", "alerts", "alerte", "alertes", "digest", "notify", "notif", "notifs",
                                                 "automated", "mailer", "autoresponder", "invitations", "rua", "ruf"]
    /// Sous-domaines d'envoi en masse : info.vercel.com, emails.boutique-exemple.fr, notif.kryva.fr…
    private static let sousDomaines: Set<String> = ["notif", "notifs", "notification", "notifications", "email", "emails", "mail", "mailing",
                                                    "news", "newsletter", "newsletters", "info", "infos", "marketing", "actu", "actus",
                                                    "send", "bounce", "bounces", "updates", "campaign", "campaigns", "alerts"]

    static func probable(_ adresse: String) -> Bool {
        let a = adresse.lowercased().trimmingCharacters(in: .whitespaces)
        guard let arobase = a.lastIndex(of: "@") else { return false }
        let local = String(a[..<arobase])
        let domaine = String(a[a.index(after: arobase)...])
        let colle = local.filter { !"-_.+".contains($0) }
        if morceauxLocal.contains(where: { colle.contains($0) }) { return true }
        let mots = local.split(whereSeparator: { "-_.+0123456789".contains($0) }).map(String.init)
        if mots.contains(where: motsLocal.contains) { return true }
        let labels = domaine.split(separator: ".").map(String.init)
        guard labels.count >= 3 else { return false }
        return labels.dropLast(2).contains(where: sousDomaines.contains)
    }

    // MARK: Plateformes suivies et LinkedIn (05/11)

    /// « Nathalie DUPRÉ via LinkedIn » → « Nathalie DUPRÉ ». nil si le nom ne finit pas par « via LinkedIn ».
    static func nomViaLinkedIn(_ nom: String) -> String? {
        let n = nom.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let r = n.range(of: #"\s*\(?\s*via\s+linkedin\s*\)?$"#, options: [.regularExpression, .caseInsensitive]) else { return nil }
        let reste = n[..<r.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        return reste.isEmpty ? nil : reste
    }

    private static let objetMessage = try! NSRegularExpression(
        pattern: #"(vous a envoye|vient de vous envoyer) (un|des) (nouveaux? )?messages?|nouveaux? messages?|sent you (a |an )?(new )?(message|inmail)|new messages?|inmail"#)
    private static let objetPasMessage = try! NSRegularExpression(
        pattern: #"connaissez peut-etre|you may know|consulte votre profil|ont consulte|viewed your profile|recrute|is hiring|offres? d.emploi|job alert"#)

    static func trouve(_ re: NSRegularExpression, _ s: String) -> Bool {
        re.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length)) != nil
    }

    /// Un mail LinkedIn qui porte un message d'une personne. Pas les alertes emploi, les invitations, « vous connaissez peut-être »,
    /// les vues du profil (messages-noreply sert aussi à ça : on exige alors « X via LinkedIn » ou un objet de message).
    static func messageLinkedIn(adresse: String, nom: String, objet: String) -> Bool {
        let a = adresse.lowercased()
        guard let arobase = a.lastIndex(of: "@") else { return false }
        let domaine = String(a[a.index(after: arobase)...])
        guard domaine == "linkedin.com" || domaine.hasSuffix(".linkedin.com") else { return false }
        let colle = String(a[..<arobase]).filter { !"-_.+".contains($0) }
        if ["jobalert", "jobs", "invitation"].contains(where: colle.contains) { return false }
        let o = EntNorm.plier(objet)
        if trouve(objetPasMessage, o) { return false }
        if colle.contains("messaging") || colle.contains("inmail") { return true }
        if colle.contains("messages") && nomViaLinkedIn(nom) != nil { return true }
        return trouve(objetMessage, o)
    }

    /// Domaines administratifs et santé : jamais masqués.
    private static let administratifs = ["gouv.fr", "francetravail.fr", "pole-emploi.fr", "ameli.fr", "urssaf.fr", "caf.fr",
                                         "service-public.fr", "msa.fr", "lassuranceretraite.fr"]
    private static let sante = ["monespacesante.fr", "mesanalyses.fr", "doctolib.fr", "doctolib.com"]
    /// Mots d'une action à faire (objet ou début du texte), pour tout expéditeur automatique.
    private static let motsAction = try! NSRegularExpression(
        pattern: #"\b(action (requise|required|needed|advised|necessaire)|date limite|dernier delai|deadline|finalisation|(compte|transactions?|carte|paiement|acces) (est |sont |a ete |ont ete )?(bloquee?s?|suspendue?s?|desactivee?s?)|(account|transactions?|card|payment) (is |are |has been |have been )?(blocked|suspended|disabled)|impaye|echec (du|de) (paiement|prelevement)|payment failed|nouvelle connexion|new login|nouveau message)\b"#)

    /// La plateforme suivie d'un mail automatique, montrée en ligne COURTE à PILOTE au lieu d'être masquée ; nil sinon.
    /// Google Play Console, App Store Connect, Stripe, Resend, Supabase, Sentry, LinkedIn (messages), Administratif, Santé,
    /// et « Action requise » pour tout envoi dont l'objet ou le texte demande une action.
    static func plateforme(adresse: String, nom: String = "", objet: String = "", texte: String = "") -> String? {
        let a = adresse.lowercased().trimmingCharacters(in: .whitespaces)
        guard let arobase = a.lastIndex(of: "@") else { return nil }
        let colle = String(a[..<arobase]).filter { !"-_.+".contains($0) }
        let domaine = String(a[a.index(after: arobase)...])
        func sous(_ d: String) -> Bool { domaine == d || domaine.hasSuffix("." + d) }
        let titre = EntNorm.plier(nom + " " + objet)
        if sous("linkedin.com") { return messageLinkedIn(adresse: a, nom: nom, objet: objet) ? "LinkedIn" : nil }
        if sous("google.com"), colle.contains("play") { return "Google Play Console" }
        if sous("apple.com"), colle.contains("testflight") || titre.contains("app store connect") || titre.contains("testflight")
            || titre.contains("app review") { return "App Store Connect" }
        if sous("stripe.com") { return "Stripe" }
        if sous("resend.com") || sous("resend.dev") { return "Resend" }
        if sous("supabase.com") || sous("supabase.io") { return "Supabase" }
        if sous("sentry.io") || sous("getsentry.com") { return "Sentry" }
        if administratifs.contains(where: sous) { return "Administratif" }
        if sante.contains(where: sous) { return "Santé" }
        if trouve(motsAction, EntNorm.plier(objet + " " + String(texte.prefix(300)))) { return "Action requise" }
        return nil
    }
}
