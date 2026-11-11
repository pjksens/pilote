// Liaison Pilote ↔ Pip (10/11, demande de Sacha du 04/11 et du 10/11). Pip est l'app Mac d'encoche qui suit les réunions
// (github.com/pjksens/heypip, MIT). Tout ce qui se décide ici est pur, pour être testé (Tests/PipTests.swift) :
//
// Aller : Pilote ouvre Pip 2 min avant une visio de l'agenda, ou au clic, par un lien `heypip://meeting?name=…&ref=…&open=1`.
//   Un lien ne fait que préparer la réunion (nom rempli, bandeau dans l'encoche) : l'enregistrement reste le clic de Sacha
//   sur « Start » dans Pip, qui lui rappelle de prévenir les participants.
// Retour : Pip écrit `meeting.json` (nom, ref, heure) dans le dossier de la réunion quand elle est lancée par ce lien ;
//   quand `summary.md` (écrit par Claude, ligne finale « Prochaine action : … ») est là et ne bouge plus, il entre dans le
//   fil du contact lié. Pilote ne lit que les réunions qu'il a lancées (ref commençant par `pilote:`).
//
// Facultatif : sans Pip installé, rien ne s'affiche et rien ne se lance. Aucun chemin ni nom propre à Sacha ici : le dossier
// des réunions est celui que Pip déclare (réglage `meetingsFolder` de Pip), sinon `~/Documents/Pip`.
import Foundation

struct ParticipantPip: Hashable {
    let nom: String
    let email: String
}

/// Une réunion de l'agenda, réduite à ce que la liaison lit.
struct ReunionPip: Identifiable, Hashable {
    let id: String
    let titre: String
    let debut: Date
    let fin: Date
    let journee: Bool
    let lien: URL?
    let participants: [ParticipantPip]
}

enum Pip {
    static let schema = "heypip"
    static let identifiant = "com.sachapraljak.heypip"
    /// Pilote ouvre Pip 2 minutes avant la visio.
    static let avance: TimeInterval = 120
    /// Une visio commencée depuis plus de 5 minutes n'ouvre plus Pip tout seul (Pilote vient de démarrer, ou Sacha est déjà dedans).
    static let retard: TimeInterval = 300

    // MARK: Le lien

    /// `heypip://meeting?name=…&ref=…&open=1` ; `ouvrir` ouvre l'encoche sur le formulaire (clic de Sacha), sinon un bandeau.
    static func lien(titre: String, ref: String, ouvrir: Bool) -> URL {
        var champs = ["name=\(encoder(titre))"]
        if !ref.isEmpty { champs.append("ref=\(encoder(ref))") }
        if ouvrir { champs.append("open=1") }
        return URL(string: "\(schema)://meeting?" + champs.joined(separator: "&"))!
    }

    /// Tout sauf les lettres, chiffres et - . _ ~ est encodé : « & », « = », « + » et les espaces ne cassent jamais le lien.
    private static func encoder(_ texte: String) -> String {
        let permis = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        return texte.addingPercentEncoding(withAllowedCharacters: permis) ?? ""
    }

    // MARK: Quelles réunions

    private static let hotesVisio = ["meet.google.com", "zoom.us", "teams.microsoft.com", "teams.live.com", "whereby.com",
                                     "webex.com", "facetime.apple.com"]

    /// Un lien de visio (Meet, Zoom, Teams, Whereby, Webex, FaceTime). Un lien d'une autre sorte (une page Notion dans la
    /// fiche de l'événement) n'ouvre pas Pip tout seul.
    static func estVisio(_ url: URL?) -> Bool {
        guard let hote = url?.host?.lowercased() else { return false }
        return hotesVisio.contains { hote == $0 || hote.hasSuffix("." + $0) }
    }

    /// Le lien de visio écrit dans les notes ou le lieu d'un événement.
    static func lienVisio(dans texte: String) -> URL? {
        guard let r = texte.range(of: #"https://(meet\.google\.com|[a-z0-9.]*zoom\.us|teams\.microsoft\.com)/[^\s>]+"#, options: .regularExpression)
        else { return nil }
        return URL(string: String(texte[r]))
    }

    /// Clé d'une réunion déjà ouverte : une réunion déplacée à une autre heure rouvre Pip une fois de plus.
    static func cle(_ r: ReunionPip) -> String { "\(r.id)|\(Int(r.debut.timeIntervalSince1970))" }

    /// Faut-il ouvrir Pip tout seul maintenant ? Une visio (pas un événement « journée »), de 2 min avant à 5 min après le
    /// début, pas déjà ouverte.
    static func aLancer(_ r: ReunionPip, a maintenant: Date, dejaLancees: Set<String>) -> Bool {
        !r.journee && estVisio(r.lien) && !dejaLancees.contains(cle(r))
            && maintenant >= r.debut.addingTimeInterval(-avance) && maintenant <= r.debut.addingTimeInterval(retard)
    }

    // MARK: Le contact lié

    private static func normaliser(_ texte: String) -> String {
        texte.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    /// Le contact de Pilote qui est dans la réunion, s'il n'y en a qu'un. Trois règles, dans cet ordre, la première qui
    /// trouve quelqu'un décide : (1) l'e-mail d'un invité, (2) le nom complet (2 mots ou plus) d'un invité ou dans le titre,
    /// (3) l'entreprise (4 lettres ou plus) dans le titre. Plusieurs contacts à une même règle : aucun (on ne devine pas).
    static func contactLie(a r: ReunionPip, parmi contacts: [Contact]) -> Contact? {
        let vivants = contacts.filter { !$0.nePlusContacter }
        let emails = Set(r.participants.map { $0.email.lowercased() }.filter { !$0.isEmpty })
        let parEmail = vivants.filter { !$0.email.isEmpty && emails.contains($0.email.lowercased()) }
        if !parEmail.isEmpty { return parEmail.count == 1 ? parEmail[0] : nil }

        let titre = " " + normaliser(r.titre) + " "
        let noms = Set(r.participants.map { normaliser($0.nom) }.filter { $0.contains(" ") })
        let parNom = vivants.filter { c in
            let n = normaliser(c.nom)
            return n.contains(" ") && (noms.contains(n) || titre.contains(" " + n + " "))
        }
        if !parNom.isEmpty { return parNom.count == 1 ? parNom[0] : nil }

        let parEntreprise = vivants.filter { c in
            let e = normaliser(c.entreprise)
            return e.count >= 4 && titre.contains(" " + e + " ")
        }
        return parEntreprise.count == 1 ? parEntreprise[0] : nil
    }

    // MARK: La référence portée par la réunion

    /// `pilote:contact:<id>` quand le contact est connu, sinon `pilote:rdv:<id de l'événement>`.
    static func ref(contact: Contact?, reunion: ReunionPip) -> String {
        if let contact { return "pilote:contact:\(contact.id)" }
        return "pilote:rdv:\(reunion.id)"
    }

    static func estDePilote(_ ref: String) -> Bool { ref.hasPrefix("pilote:") }

    static func contactId(deRef ref: String) -> String? {
        let prefixe = "pilote:contact:"
        guard ref.hasPrefix(prefixe) else { return nil }
        let id = String(ref.dropFirst(prefixe.count))
        return id.isEmpty ? nil : id
    }
}

// MARK: - Le retour : le résumé de la réunion

/// Une réunion lancée par Pilote dont le résumé est prêt à entrer dans le fil.
struct ResumePip: Hashable {
    /// Le nom du dossier de la réunion chez Pip (jamais le chemin) : identifie la réunion, sert de `source_ref` (pas de doublon).
    let dossier: String
    let nom: String
    let ref: String
    let debut: Date?
    let resume: String
    let prochaineAction: String?
}

enum PipRetour {
    /// Un résumé encore modifié depuis moins de 90 s n'est pas importé : Claude peut être en train de l'écrire.
    static let calme: TimeInterval = 90
    /// Au-delà de 4 000 caractères, le résumé est coupé dans le fil (le fichier complet reste chez Pip).
    static let longueurMax = 4000

    /// Le dossier des réunions de Pip : le réglage `meetingsFolder` de Pip, sinon `~/Documents/Pip` (défaut de Pip).
    static func racine(reglagePip: String?, maison: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        if let r = reglagePip?.trimmingCharacters(in: .whitespaces), !r.isEmpty {
            return URL(fileURLWithPath: (r as NSString).expandingTildeInPath)
        }
        return maison.appendingPathComponent("Documents/Pip")
    }

    private struct Fiche: Decodable {
        let name: String
        let ref: String
        let startedAt: String
    }

    /// Les résumés prêts : dossiers de la racine avec `meeting.json` (ref de Pilote) et `summary.md` non vide, stable
    /// depuis `calme` secondes. Ne lit rien d'autre (ni transcription, ni son).
    static func aImporter(racine: URL, a maintenant: Date = Date()) -> [ResumePip] {
        let fm = FileManager.default
        guard let dossiers = try? fm.contentsOfDirectory(at: racine, includingPropertiesForKeys: nil) else { return [] }
        var trouves: [ResumePip] = []
        for d in dossiers.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) where d.lastPathComponent != "current" {
            guard let data = try? Data(contentsOf: d.appendingPathComponent("meeting.json")),
                  let fiche = try? JSONDecoder().decode(Fiche.self, from: data), Pip.estDePilote(fiche.ref) else { continue }
            let fichier = d.appendingPathComponent("summary.md")
            guard let attributs = try? fm.attributesOfItem(atPath: fichier.path),
                  let modifie = attributs[.modificationDate] as? Date, maintenant.timeIntervalSince(modifie) >= calme,
                  let texte = try? String(contentsOf: fichier, encoding: .utf8),
                  !texte.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let (corps, action) = separer(texte)
            trouves.append(ResumePip(dossier: d.lastPathComponent, nom: fiche.name, ref: fiche.ref,
                                     debut: Dates.iso.date(from: fiche.startedAt), resume: corps, prochaineAction: action))
        }
        return trouves
    }

    /// Le résumé sans sa ligne « Prochaine action : … » (la dernière du fichier qui commence ainsi), et cette action.
    /// Reconnaît « Next action », « Prochaine action » et « Próxima acción », avec ou sans gras, tiret ou citation.
    static func separer(_ texte: String) -> (corps: String, action: String?) {
        var lignes = texte.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        let regle = try! NSRegularExpression(
            pattern: #"^[\s>*_\-#]*(?:prochaine action|next action|pr[oó]xima acci[oó]n)[\s*_]*:[\s*_]*(.+?)[\s*_]*$"#,
            options: [.caseInsensitive])
        for i in lignes.indices.reversed() {
            let l = lignes[i]
            guard let m = regle.firstMatch(in: l, range: NSRange(l.startIndex..., in: l)), let p = Range(m.range(at: 1), in: l) else { continue }
            let action = String(l[p]).trimmingCharacters(in: .whitespaces)
            lignes.remove(at: i)
            return (lignes.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines), action.isEmpty ? nil : action)
        }
        return (texte.trimmingCharacters(in: .whitespacesAndNewlines), nil)
    }

    /// Le texte qui entre dans le fil (donnée de la base : en français, jamais traduit).
    static func texteDuFil(_ r: ResumePip) -> String {
        var corps = r.resume
        if corps.count > longueurMax {
            let coupe = corps.prefix(longueurMax)
            let propre = coupe.range(of: "\n", options: .backwards).map { String(coupe[..<$0.lowerBound]) } ?? String(coupe)
            corps = propre.trimmingCharacters(in: .whitespacesAndNewlines) + "\n…"
        }
        var lignes = ["Résumé de la réunion « \(r.nom) » (Pip, dossier \(r.dossier))", "", corps]
        if let a = r.prochaineAction { lignes += ["", "Prochaine action : \(a)"] }
        return lignes.joined(separator: "\n")
    }
}

extension Stockage {
    /// Fait entrer dans le fil les résumés prêts. Une réunion déjà importée est reconnue à sa `source_ref` (pas de doublon,
    /// même relancé cent fois). Sans contact lié (inconnu, ou fiche supprimée) : une entrée du journal, pour ne rien perdre.
    /// Ne touche ni à l'étape ni à la prochaine action de la fiche. Renvoie ce qui est nouveau : (nom de la réunion, contact).
    @discardableResult
    func importerResumesPip(_ resumes: [ResumePip]) throws -> [(reunion: String, contact: Contact?)] {
        var nouveaux: [(String, Contact?)] = []
        for r in resumes {
            let ref = "pip:" + r.dossier
            let texte = PipRetour.texteDuFil(r)
            let le = r.debut.map { Dates.iso.string(from: $0) } ?? Dates.maintenant()
            if let id = Pip.contactId(deRef: r.ref), let c = try contact(id) {
                let deja = !(try base.lignes("SELECT 1 FROM evenements WHERE contact_id = ? AND source_ref = ?", [id, ref]).isEmpty)
                try ajouterEvenement(contactId: id, ["canal": "visio", "sens": "interne", "type": "rdv", "texte": texte,
                                                      "statut": "fait", "par": "Pip", "le": le, "source_ref": ref])
                if !deja { nouveaux.append((r.nom, c)) }
            } else {
                let deja = !(try base.lignes("SELECT 1 FROM journal WHERE source_ref = ?", [ref]).isEmpty)
                try ajouterJournal(["type": "pip", "titre_session": "Pip", "demande": "Réunion « \(r.nom) » (aucun contact lié)",
                                    "texte": texte, "le": le, "source_ref": ref])
                if !deja { nouveaux.append((r.nom, nil)) }
            }
        }
        return nouveaux
    }
}
