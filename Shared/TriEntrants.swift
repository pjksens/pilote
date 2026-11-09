// Tri des messages entrants : les règles pures du capteur (CLI/Entrants.swift lit les bases des autres apps, ici on décide).
// Déplacé de CLI/Entrants.swift le 05/11 (chantier A « ne rien cacher ») pour être testé : Tests/TriEntrantsTests.swift.
//
// Ordre du tri (classer) :
//   0. rebond (mailer-daemon, « undeliverable »)                       → inconnu, via « rebond », fiche retrouvée par l'adresse citée
//   1. contact de Pilote : téléphone, e-mail, nom (« X via LinkedIn » compris), domaine d'entreprise d'une seule fiche → travail
//   2. numéro ou adresse à qui Sacha a envoyé le texte d'une fiche (T14) → travail (cette fiche) ou inconnu, via « envoi »
//   3. groupe : suivi (entrants-groupes.txt) → inconnu, via « groupe suivi » ; sinon ignore
//   4. automatique (List-Id, noreply en tête), sauf plateforme suivie ou réponse à un envoi de Sacha → ignore ; entrants-ignorer.txt → ignore
//   5. Contacts du Mac → perso ; sinon inconnu (un mail automatique probable y porte "auto": true, voir TriMail.masquer)
import CryptoKit
import Foundation

// MARK: - Normalisation

enum EntNorm {
    /// 9 derniers chiffres d'un numéro (+33 6 12 34 56 78 et 06 12 34 56 78 donnent la même clé).
    static func tel(_ s: String) -> String? {
        let d = s.filter { $0 >= "0" && $0 <= "9" }
        return d.count >= 9 ? String(d.suffix(9)) : nil
    }

    /// Tous les numéros d'un champ libre (un contact peut en avoir plusieurs).
    static func tels(_ s: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: #"\+?\d[\d .\-()]{7,}\d"#) else { return [] }
        let ns = s as NSString
        return re.matches(in: s, range: NSRange(location: 0, length: ns.length)).compactMap { tel(ns.substring(with: $0.range)) }
    }

    static func emails(_ s: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: #"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}"#) else { return [] }
        let ns = s as NSString
        return re.matches(in: s, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range).lowercased() }
    }

    /// Domaine d'une adresse, en minuscules (« contact@pdp-exemple.tech » → « pdp-exemple.tech »).
    static func domaine(_ email: String) -> String? {
        let a = email.lowercased().trimmingCharacters(in: .whitespaces)
        guard let i = a.lastIndex(of: "@") else { return nil }
        let d = String(a[a.index(after: i)...])
        return d.contains(".") ? d : nil
    }

    /// Nom sans accents ni casse, mots triés : « Leblanc Alice » = « alice leblanc ». Au moins 2 mots, sinon pas de clé
    /// (un prénom seul ne suffit pas à reconnaître quelqu'un).
    static func nom(_ s: String) -> String? {
        let plie = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
        let mots = plie.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        return mots.count >= 2 ? mots.sorted().joined(separator: " ") : nil
    }

    /// Retire les marques invisibles que WhatsApp met autour des numéros.
    static func propre(_ s: String) -> String {
        String(s.unicodeScalars.filter { !($0.value >= 0x200B && $0.value <= 0x200F) && !($0.value >= 0x202A && $0.value <= 0x202E) })
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func empreinte(_ s: String) -> String {
        SHA256.hash(data: Data(s.utf8)).prefix(6).map { String(format: "%02x", $0) }.joined()
    }

    static func extrait(_ s: String, max: Int) -> String {
        let plat = s.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        return plat.count > max ? String(plat.prefix(max - 1)) + "…" : plat
    }

    /// Minuscules sans accents (pour chercher des mots).
    static func plier(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
    }
}

// MARK: - Message

struct EntMessage {
    var canal: String                 // whatsapp | imessage | mail
    var ref: String                   // identifiant stable : whatsapp:30305
    var date: Date
    var adresse = ""                  // numéro ou e-mail de l'expéditeur
    var affiche = ""                  // nom affiché par l'app (« via LinkedIn » retiré)
    var tels: [String] = []
    var mails: [String] = []
    var noms: [String] = []
    var texte = ""
    var objet = ""
    var genre = ""                    // vocal | image | video | document | …
    var duree = 0
    var fichier = ""                  // vocal : chemin du fichier audio sur le disque (à transcrire)
    var groupe = false
    var nomGroupe = ""                // WhatsApp : nom du groupe (comparé à entrants-groupes.txt)
    var automatique = false
    var indesirable = false           // mail rangé dans Indésirables / Spam (T13) : montré seulement pour un contact connu ou une plateforme suivie
    var boite = ""                    // diagnostic seulement : URL de la boîte Mail et drapeau « supprimé »
    /// Mail d'un expéditeur automatique probable (ExpediteurAuto) : la ligne porte « auto », la veille ne la transmet pas.
    var autoProbable = false
    /// Mail d'une plateforme suivie (Google Play Console, Stripe, LinkedIn message…) : jamais masqué, montré en ligne courte.
    var plateforme = ""
    var linkedin = false              // mail « X via LinkedIn » : rangé au fil sous LinkedIn
    var signalSeul = false            // LinkedIn hors message (invitation acceptée…) : note au fil, pas d'action « Répondre à »
    var rebond = false                // mail non remis (mailer-daemon, « undeliverable ») : signalé, jamais ignoré
    var rebondPour: [String] = []     // adresses citées dans le rebond, pour retrouver la fiche
    var sortant = false               // envoyé par Sacha (WhatsApp, SMS) : jamais classé ni émis, seulement rapproché d'un message prêt
    var envoisAdresse = ""            // diagnostic : mes envois (90 j) à cette adresse, « date objet » séparés par « ¦ »
    var reponseEnvoi = ""             // mail : réponse à un mail envoyé par Sacha (ReponseAEnvoi) : « fil », « sujet » ou « adresse »
    var curseur = 0                   // identifiant source (pour avancer le curseur)
}

/// T14 : un numéro (ou une adresse) absent de Pilote à qui Sacha a envoyé le texte d'une fiche. Ses réponses ne sont plus « perso ».
struct EntSuivi: Codable, Equatable {
    var contactId: String             // la fiche dont le texte est parti ("" si plusieurs fiches avaient ce texte)
    var nom: String
    var le: String                    // ISO : quand Sacha a écrit
}

// MARK: - Annuaire et tri

struct EntAnnuaire {
    var piloteTel: [String: Contact] = [:]
    var piloteMail: [String: Contact] = [:]
    var piloteNom: [String: Contact] = [:]
    var piloteNomAmbigu = Set<String>()                          // nom porté par plusieurs fiches : connu, mais à rattacher à la main
    var piloteDomaine: [String: Contact] = [:]                   // domaine d'entreprise porté par une seule fiche (T40)
    var parId: [String: Contact] = [:]
    var macTel = Set<String>()
    var macMail = Set<String>()
    var macNom = Set<String>()
    var lid: [String: (tels: [String], noms: [String])] = [:]   // WhatsApp : identifiant masqué → numéro et nom du carnet
    var ignorer: [String] = []                                   // morceaux d'adresses à ignorer (entrants-ignorer.txt)
    var groupesSuivis: [String] = []                             // morceaux de noms de groupes suivis (entrants-groupes.txt), pliés
    var suivis: [String: EntSuivi] = [:]                         // clé EntNorm.tel ou adresse mail → envoi de Sacha (T14)
    var avertissements: [String] = []

    /// Messageries et fournisseurs grand public : un domaine partagé par tout le monde ne désigne pas une entreprise.
    static let domainesGeneriques: Set<String> = [
        "gmail.com", "googlemail.com", "outlook.com", "outlook.fr", "hotmail.com", "hotmail.fr", "live.com", "live.fr", "msn.com",
        "yahoo.com", "yahoo.fr", "ymail.com", "icloud.com", "me.com", "mac.com", "free.fr", "orange.fr", "wanadoo.fr", "sfr.fr",
        "neuf.fr", "bbox.fr", "laposte.net", "numericable.fr", "aliceadsl.fr", "club-internet.fr", "gmx.fr", "gmx.com", "gmx.de",
        "aol.com", "aol.fr", "protonmail.com", "proton.me", "pm.me", "yandex.com", "mail.com", "zoho.com", "tutanota.com",
        "privaterelay.appleid.com",
    ]

    init(contacts: [Contact]) {
        var noms: [String: [Contact]] = [:]
        var domaines: [String: [String: Contact]] = [:]
        // Vos propres domaines (domaines_interdits) ne désignent pas non plus une entreprise.
        let propres = Set((Reglages.courants.domainesInterdits ?? []).map { $0.lowercased() })
        for c in contacts {
            parId[c.id] = c
            for t in EntNorm.tels(c.telephone) { piloteTel[t] = piloteTel[t] ?? c }
            for e in EntNorm.emails(c.email) {
                piloteMail[e] = piloteMail[e] ?? c
                if let d = EntNorm.domaine(e), !Self.domainesGeneriques.contains(d), !propres.contains(d) { domaines[d, default: [:]][c.id] = c }
            }
            if let n = EntNorm.nom(c.nom) { noms[n, default: []].append(c) }
        }
        for (n, liste) in noms {                                    // un nom partagé par deux contacts ne prouve rien
            if liste.count == 1 { piloteNom[n] = liste[0] } else { piloteNomAmbigu.insert(n) }
        }
        for (d, fiches) in domaines where fiches.count == 1 { piloteDomaine[d] = fiches.values.first }
    }

    /// Une ligne par morceau, « # » pour un commentaire.
    static func lireListe(_ fichier: URL) -> [String] {
        let t = (try? String(contentsOf: fichier, encoding: .utf8)) ?? ""
        return t.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    func chargerIgnorer(_ dossier: URL) -> [String] { Self.lireListe(dossier.appendingPathComponent("entrants-ignorer.txt")) }
    func chargerGroupes(_ dossier: URL) -> [String] { Self.lireListe(dossier.appendingPathComponent("entrants-groupes.txt")).map(EntNorm.plier) }

    func contactPilote(_ m: EntMessage) -> (Contact, String)? {
        for t in m.tels { if let c = piloteTel[t] { return (c, "telephone") } }
        for e in m.mails { if let c = piloteMail[e] { return (c, "email") } }
        for n in m.noms { if let c = piloteNom[n] { return (c, "nom") } }
        // T40 : une réponse depuis une autre adresse de la même entreprise. Jamais pour un envoi automatique (newsletter de l'entreprise).
        if m.canal == "mail", !m.automatique, !m.rebond, m.plateforme.isEmpty, !ExpediteurAuto.probable(m.adresse),
           let d = EntNorm.domaine(m.adresse), let c = piloteDomaine[d] {
            return (c, "domaine")
        }
        return nil
    }

    /// La fiche d'une des adresses (rebond : l'adresse à qui le mail de Sacha n'a pas été remis).
    func contactParAdresses(_ adresses: [String]) -> Contact? {
        for a in adresses { if let c = piloteMail[a.lowercased()] { return c } }
        return nil
    }

    func suivi(_ m: EntMessage) -> EntSuivi? {
        for t in m.tels { if let s = suivis[t] { return s } }
        for e in m.mails { if let s = suivis[e] { return s } }
        return nil
    }

    func dansContactsMac(_ m: EntMessage) -> Bool {
        m.tels.contains(where: macTel.contains) || m.mails.contains(where: macMail.contains) || m.noms.contains(where: macNom.contains)
    }

    func groupeSuivi(_ m: EntMessage) -> Bool {
        let nom = EntNorm.plier(m.nomGroupe)
        return !nom.isEmpty && groupesSuivis.contains(where: { nom.contains($0) })
    }

    func classer(_ m: EntMessage) -> (classe: String, contact: Contact?, via: String) {
        if m.rebond { return ("inconnu", contactParAdresses(m.rebondPour), "rebond") }
        if let (c, via) = contactPilote(m) { return ("travail", c, via) }
        if let s = suivi(m) {
            if let c = parId[s.contactId] { return ("travail", c, "envoi") }
            return ("inconnu", nil, "envoi")
        }
        if m.groupe { return groupeSuivi(m) ? ("inconnu", nil, "groupe suivi") : ("ignore", nil, "groupe") }
        if m.automatique && m.plateforme.isEmpty && m.reponseEnvoi.isEmpty { return ("ignore", nil, "automatique") }
        let a = (m.adresse + " " + m.mails.joined(separator: " ")).lowercased()
        if ignorer.contains(where: { a.contains($0) }) { return ("ignore", nil, "liste") }
        if m.canal == "mail", m.noms.contains(where: piloteNomAmbigu.contains) { return ("inconnu", nil, "nom ambigu") }
        if dansContactsMac(m) { return ("perso", nil, "contacts") }
        return ("inconnu", nil, "")
    }
}

// MARK: - Mails

enum TriMail {
    /// Partie locale d'un envoi automatique (en tête d'adresse) : ignoré, sauf plateforme suivie.
    static let motifsAutomatiques = try! NSRegularExpression(
        pattern: #"^(no[-_.]?reply|do[-_.]?not[-_.]?reply|donotreply|noreply|notifications?|notify|mailer-daemon|postmaster|bounces?|newsletter|news|alerts?|automated|auto|system|billing|invoices?|receipts?|updates?|digest|marketing|mailing|campaign)([-_.+0-9]|$)"#,
        options: [.caseInsensitive])

    /// Objet d'un mail non remis (T26).
    static let objetRebond = try! NSRegularExpression(
        pattern: #"undeliverable|undelivered|non distribuable|non remis|delivery status notification|echec de (la )?(remise|distribution|livraison)|returned mail|mail delivery (failed|failure|subsystem)|message not delivered|delivery (has )?failed|delivery failure|impossible de (remettre|distribuer)|address not found|adresse introuvable"#,
        options: [.caseInsensitive])

    static func trouve(_ re: NSRegularExpression, _ s: String) -> Bool {
        re.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length)) != nil
    }

    static func estRebond(adresse: String, objet: String) -> Bool {
        let local = adresse.lowercased().split(separator: "@").first.map(String.init) ?? ""
        return local.hasPrefix("mailer-daemon") || trouve(objetRebond, EntNorm.plier(objet))
    }

    /// Complète un mail lu dans l'Envelope Index (adresse, objet, texte et reponseEnvoi déjà posés) : nom affiché sans « via LinkedIn »,
    /// plateforme suivie, automatique, rebond, auto probable.
    static func preparer(_ m: inout EntMessage, commentaire: String, listeId: Bool) {
        let viaLinkedIn = ExpediteurAuto.nomViaLinkedIn(commentaire)
        let nom = viaLinkedIn ?? commentaire
        m.affiche = nom.isEmpty ? m.adresse : nom
        m.noms = EntNorm.nom(nom).map { [$0] } ?? []
        let local = m.adresse.split(separator: "@").first.map(String.init) ?? ""
        m.automatique = listeId || trouve(motifsAutomatiques, local)
        m.rebond = estRebond(adresse: m.adresse, objet: m.objet)
        let domaine = EntNorm.domaine(m.adresse) ?? ""
        let surLinkedIn = viaLinkedIn != nil || domaine == "linkedin.com" || domaine.hasSuffix(".linkedin.com")
        m.plateforme = ""
        if m.rebond {
            m.rebondPour = EntNorm.emails(m.objet + " " + m.texte).filter { $0 != m.adresse }
        } else if surLinkedIn || m.automatique || ExpediteurAuto.probable(m.adresse) {
            // Plateforme : seulement pour un envoi automatique. Un humain (support Supabase, conseiller d'un service public)
            // garde sa ligne ENTRANT complète, jamais la ligne courte.
            m.plateforme = ExpediteurAuto.plateforme(adresse: m.adresse, nom: commentaire, objet: m.objet, texte: m.texte) ?? ""
        }
        if surLinkedIn {
            m.linkedin = true
            m.signalSeul = m.plateforme != "LinkedIn"           // invitation, invitation acceptée… : pas un message à qui répondre
        }
        m.autoProbable = ExpediteurAuto.probable(m.adresse) && m.plateforme.isEmpty && !m.rebond && m.reponseEnvoi.isEmpty
    }

    /// T13 : un mail en Indésirables n'est montré que s'il vient d'un contact connu de Pilote ou d'une plateforme de la liste blanche.
    static func garderIndesirable(_ m: EntMessage, contact: Contact?) -> Bool {
        !m.indesirable || contact != nil || !m.plateforme.isEmpty
    }

    /// La ligne de entrants.jsonl porte-t-elle "auto": true (la veille ne la transmet pas, elle est comptée au tri de 7 h) ?
    /// Seulement un inconnu pur : ni fiche, ni nom connu, ni plateforme suivie, ni réponse à un envoi de Sacha, ni rebond.
    static func masquer(_ m: EntMessage, classe: String, via: String) -> Bool {
        m.canal == "mail" && m.autoProbable && classe == "inconnu" && via.isEmpty && m.plateforme.isEmpty && m.reponseEnvoi.isEmpty && !m.rebond
    }
}

// MARK: - Messages écartés (T47) : entrants-ecartes.jsonl, gardés 14 jours, pour pouvoir vérifier ce que le tri a mis de côté

enum Ecartes {
    static let jours = 14
    static let heure: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.timeZone = TimeZone(identifier: "Europe/Paris")
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func ligne(_ m: EntMessage, classe: String, via: String) -> [String: Any] {
        let corps = m.canal == "mail" ? [m.objet, m.texte].filter { !$0.isEmpty }.joined(separator: " · ")
            : (m.genre.isEmpty ? m.texte : "[\(m.genre)] " + m.texte)
        var l: [String: Any] = ["ref": m.ref, "canal": m.canal, "classe": classe, "via": via, "adresse": m.adresse,
                                "qui": m.affiche, "heure": heure.string(from: m.date), "extrait": EntNorm.extrait(corps, max: 60)]
        if !m.nomGroupe.isEmpty { l["groupe"] = m.nomGroupe }
        return l
    }

    /// Les lignes de moins de 14 jours (une ligne illisible est gardée : on n'efface pas ce qu'on ne comprend pas).
    static func purger(_ lignes: [String], maintenant: Date = Date()) -> [String] {
        let limite = maintenant.addingTimeInterval(-Double(jours) * 86400)
        return lignes.filter { l in
            guard let d = l.data(using: .utf8), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                  let h = o["heure"] as? String, let quand = heure.date(from: h) else { return !l.isEmpty }
            return quand >= limite
        }
    }
}
