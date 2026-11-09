// Le planning de Sacha (règle commune : docs/PLANNING-CONTRAT.md) : les tâches dans Rappels, les événements dans le Calendrier,
// les notes « But / Docs / Fini quand », la semaine du lundi, les colonnes de ce qui se chevauche,
// et « Terminé » : l'état gardé par Pilote et la ligne ajoutée à entrants.jsonl pour prévenir PILOTE.
import Foundation

enum CalendriersPlanning {
    /// « Une tâche = un reminder apple. Un évènement = event apple » (Sacha, 02/11) : les listes de Rappels des tâches…
    static let listesTaches: [(nom: String, couleur: UInt32)] = [
        ("Appels", 0x34C759), ("KRYVA", 0x0A84FF), ("Freelance", 0xFF9500), ("Contenu", 0xAF52DE), ("Papiers", 0xFF3B30),
    ]
    /// … et les calendriers des événements. Couleurs fixes du contrat ; les autres listes et calendriers ne s'affichent pas.
    static let calendriersEvenements: [(nom: String, couleur: UInt32)] = [
        ("Salle", 0x8E8E93), ("Rendez-vous", 0x30B0C7), ("Perso", 0xFFCC00),
    ]
    /// Dans l'ordre de la légende.
    static var tous: [(nom: String, couleur: UInt32)] { listesTaches + calendriersEvenements }
    static func tache(_ liste: String) -> Bool { listesTaches.contains { $0.nom == liste } }
    static func evenement(_ calendrier: String) -> Bool { calendriersEvenements.contains { $0.nom == calendrier } }
    static func couleur(_ nom: String) -> UInt32 { tous.first { $0.nom == nom }?.couleur ?? 0x8E8E93 }
}

struct LienDoc: Hashable {
    let libelle: String
    let url: URL
}

/// Les notes d'un événement, dans l'ordre du contrat : « But : … », « Docs : » puis un lien par ligne, « Fini quand : … ».
struct NotesPlanning: Hashable {
    var but: String?
    var docs: [LienDoc] = []
    var finiQuand: String?

    static func lire(_ texte: String) -> NotesPlanning {
        var n = NotesPlanning()
        var dansDocs = false
        let propre = texte.replacingOccurrences(of: "\u{00A0}", with: " ").replacingOccurrences(of: "\u{202F}", with: " ")
        for brute in propre.components(separatedBy: .newlines) {
            let ligne = brute.trimmingCharacters(in: .whitespaces)
            if let reste = champ(ligne, #"but"#) {
                n.but = reste.isEmpty ? nil : reste
                dansDocs = false
            } else if let reste = champ(ligne, #"docs?"#) {
                dansDocs = true
                if let l = lien(reste) { n.docs.append(l) }
            } else if let reste = champ(ligne, #"fini\s+quand"#) {
                n.finiQuand = reste.isEmpty ? nil : reste
                dansDocs = false
            } else if dansDocs, let l = lien(ligne) {
                n.docs.append(l)
            }
        }
        return n
    }

    /// « Nom : reste » (casse et espaces indifférents) → le reste.
    private static func champ(_ ligne: String, _ nom: String) -> String? {
        guard let r = ligne.range(of: "^" + nom + #"\s*:\s*"#, options: [.regularExpression, .caseInsensitive]) else { return nil }
        return String(ligne[r.upperBound...]).trimmingCharacters(in: .whitespaces)
    }

    /// Une ligne de « Docs » : « [libellé :] https://… », « file:///… » ou un chemin (/Users/…, ~/…). Le libellé est facultatif.
    static func lien(_ ligne: String) -> LienDoc? {
        let l = ligne.trimmingCharacters(in: CharacterSet(charactersIn: "-•* ").union(.whitespaces))
        var avant = ""
        var url: URL?
        if let r = l.range(of: #"https?://"#, options: [.regularExpression, .caseInsensitive]) {
            avant = String(l[..<r.lowerBound])
            let adresse = String(l[r.lowerBound...]).split(separator: " ").first.map(String.init) ?? ""
            url = URL(string: adresse)
        } else if let r = l.range(of: "file://", options: .caseInsensitive) {
            avant = String(l[..<r.lowerBound])
            // Un chemin de fichier peut contenir des espaces : tout le reste de la ligne.
            let adresse = String(l[r.lowerBound...]).trimmingCharacters(in: .whitespaces)
            url = URL(string: adresse) ?? URL(string: adresse.replacingOccurrences(of: " ", with: "%20"))
        } else if let r = l.range(of: #"(^|\s)(~/|/)"#, options: .regularExpression) {
            avant = String(l[..<r.lowerBound])
            let chemin = String(l[r.lowerBound...]).trimmingCharacters(in: .whitespaces)
            url = URL(fileURLWithPath: Chemins.complet(chemin))
        }
        guard let url else { return nil }
        var libelle = avant.trimmingCharacters(in: .whitespaces)
        while libelle.hasSuffix(":") { libelle = String(libelle.dropLast()).trimmingCharacters(in: .whitespaces) }
        if libelle.isEmpty {
            libelle = url.isFileURL ? url.lastPathComponent : (url.host ?? url.absoluteString)
        }
        return LienDoc(libelle: libelle, url: url)
    }
}

/// Un élément du planning : une tâche (un rappel, placé à son échéance) ou un événement du Calendrier (lecture seule).
struct TachePlanning: Identifiable, Hashable {
    enum Genre: Hashable { case tache, evenement }
    /// Une tâche à heure précise occupe 30 min dans la grille (un rappel n'a pas de fin).
    static let dureeTache: TimeInterval = 30 * 60

    let genre: Genre
    /// Identifiant transmis à PILOTE (identifiant iCloud, le même pour toutes les occurrences d'un élément répété).
    let ref: String
    /// Identifiant local d'EventKit, pour cocher le rappel.
    let idLocal: String
    let titre: String
    /// Événement : début. Tâche : échéance.
    let debut: Date
    let fin: Date
    /// Liste de Rappels ou calendrier.
    let calendrier: String
    /// Événement « journée » ou tâche sans heure : en haut de la journée, à part.
    let journee: Bool
    let url: URL?
    let notes: NotesPlanning
    /// Rappel coché dans Rappels (ici, sur l'iPhone ou ailleurs).
    var faite = false
    /// La clé de l'état « Terminé » : identifiant + date de début (échéance pour une tâche).
    var id: String { TachesTerminees.cle(ref: ref, debut: debut) }
    /// Le document ouvert d'un clic : l'URL, sinon le premier lien de « Docs ».
    var document: URL? { url ?? notes.docs.first?.url }
}

enum Semaine {
    /// Calendrier grégorien, semaine du lundi, dans le fuseau donné (celui du Mac par défaut).
    static func calendrier(_ fuseau: TimeZone = .current) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2
        c.minimumDaysInFirstWeek = 4
        c.timeZone = fuseau
        return c
    }

    /// Le lundi 0 h de la semaine qui contient `date`.
    static func lundi(de date: Date, fuseau: TimeZone = .current) -> Date {
        let c = calendrier(fuseau)
        return c.dateInterval(of: .weekOfYear, for: date)?.start ?? c.startOfDay(for: date)
    }

    /// Les 7 jours (0 h) du lundi au dimanche.
    static func jours(de date: Date, fuseau: TimeZone = .current) -> [Date] {
        let c = calendrier(fuseau)
        let l = lundi(de: date, fuseau: fuseau)
        return (0..<7).compactMap { c.date(byAdding: .day, value: $0, to: l) }
    }
}

enum Disposition {
    /// Les tâches qui se chevauchent se partagent la largeur : pour chaque plage (dans l'ordre donné),
    /// sa colonne et le nombre de colonnes de son groupe. Une tâche de moins de 15 min compte pour 15 min.
    static func colonnes(_ plages: [(debut: Date, fin: Date)]) -> [(colonne: Int, sur: Int)] {
        var res = Array(repeating: (colonne: 0, sur: 1), count: plages.count)
        let ordre = plages.indices.sorted { (plages[$0].debut, $0) < (plages[$1].debut, $1) }
        var groupe: [Int] = []
        var finsColonnes: [Date] = []
        var finGroupe = Date.distantPast
        func clore() {
            for i in groupe { res[i].sur = finsColonnes.count }
            groupe = []
            finsColonnes = []
        }
        for i in ordre {
            let d = plages[i].debut
            let f = max(plages[i].fin, d.addingTimeInterval(15 * 60))
            if !groupe.isEmpty && d >= finGroupe { clore() }
            if let c = finsColonnes.firstIndex(where: { $0 <= d }) {
                finsColonnes[c] = f
                res[i].colonne = c
            } else {
                finsColonnes.append(f)
                res[i].colonne = finsColonnes.count - 1
            }
            groupe.append(i)
            finGroupe = groupe.count == 1 ? f : max(finGroupe, f)
        }
        clore()
        return res
    }
}

/// « Terminé » : Pilote garde l'état (planning-termine.json, clé → heure du clic) et ajoute UNE ligne à entrants.jsonl,
/// que PILOTE suit en continu. Ajout en fin de fichier seulement, jamais de réécriture. Rien n'est écrit dans le Calendrier.
struct TachesTerminees {
    let dossier: URL
    var fichierEtat: URL { dossier.appendingPathComponent("planning-termine.json") }
    var fichierEntrants: URL { dossier.appendingPathComponent("entrants.jsonl") }

    /// Le dossier de entrants.jsonl (PILOTE_ENTRANTS_DIR pour les essais, comme le capteur).
    static var dossierParDefaut: URL {
        if let d = ProcessInfo.processInfo.environment["PILOTE_ENTRANTS_DIR"], !d.isEmpty {
            return URL(fileURLWithPath: d, isDirectory: true)
        }
        // Instance d'essai sur une copie de la base : ses lignes restent à côté de la copie.
        if let autre = ProcessInfo.processInfo.environment["PILOTE_BASE"], !autre.isEmpty {
            return URL(fileURLWithPath: autre).deletingLastPathComponent()
        }
        return Base.dossier
    }

    /// Heure ISO avec décalage de Paris, comme les autres lignes de entrants.jsonl.
    static let iso: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Europe/Paris")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXX"
        return f
    }()

    static func cle(ref: String, debut: Date) -> String { ref + "|" + iso.string(from: debut) }

    /// Depuis quand Pilote surveille les rappels cochés ailleurs (posé au premier passage) : rien d'avant n'est signalé.
    func depuis(_ maintenant: Date = Date()) throws -> Date {
        var etat = lire()
        if let d = etat[Self.cleDepuis].flatMap({ Self.iso.date(from: $0) }) { return d }
        etat[Self.cleDepuis] = Self.iso.string(from: maintenant)
        try ecrireEtat(etat)
        return Self.iso.date(from: etat[Self.cleDepuis]!) ?? maintenant
    }
    static let cleDepuis = "_depuis"

    /// Les rappels cochés ailleurs (iPhone, Rappels) depuis `depuis` et pas encore signalés, avec l'heure où ils l'ont été.
    static func nouvellesCoches(_ cochees: [(tache: TachePlanning, le: Date)], etat: [String: String], depuis: Date)
        -> [(tache: TachePlanning, le: Date)] {
        cochees.filter { $0.tache.genre == .tache && $0.le >= depuis && etat[$0.tache.id] == nil }
    }

    /// L'état gardé : clé → heure du clic.
    func lire() -> [String: String] {
        guard let d = try? Data(contentsOf: fichierEtat),
              let e = try? JSONSerialization.jsonObject(with: d) as? [String: String] else { return [:] }
        return e
    }

    /// Ajoute la ligne puis garde l'état. Renvoie false (et n'écrit rien) si la tâche est déjà terminée.
    @discardableResult
    func terminer(_ t: TachePlanning, a heure: Date = Date()) throws -> Bool {
        var etat = lire()
        guard etat[t.id] == nil else { return false }
        try ajouter(Self.ligne(t, heure: heure))
        etat[t.id] = Self.iso.string(from: heure)
        try ecrireEtat(etat)
        return true
    }

    /// Annule un « Terminé » donné par erreur : la clé est retirée, PILOTE reçoit une ligne tache_rouverte.
    func rouvrir(_ t: TachePlanning, a heure: Date = Date()) throws {
        var etat = lire()
        guard etat[t.id] != nil else { return }
        try ajouter(Self.ligne(t, heure: heure, classe: "tache_rouverte"))
        etat[t.id] = nil
        try ecrireEtat(etat)
    }

    private func ecrireEtat(_ etat: [String: String]) throws {
        try FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
        let d = try JSONSerialization.data(withJSONObject: etat, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try d.write(to: fichierEtat, options: .atomic)
    }

    /// La ligne du contrat, champs dans son ordre :
    /// {"canal":"pilote","classe":"tache_terminee","extrait":…,"heure":…,"qui":"Sacha","ref":…,"calendrier":…,"debut":…}
    /// tache_terminee (tâche cochée ; événement marqué terminé : « genre »: « evenement » en plus) ou tache_supprimee.
    static func ligne(_ t: TachePlanning, heure: Date, classe: String = "tache_terminee") -> String {
        var champs: [(String, String)] = [
            ("canal", "pilote"), ("classe", classe), ("extrait", t.titre), ("heure", iso.string(from: heure)),
            ("qui", "\(Moi.nom)"), ("ref", t.ref), ("calendrier", t.calendrier), ("debut", iso.string(from: t.debut)),
        ]
        if t.genre == .evenement { champs.append(("genre", "evenement")) }
        return "{" + champs.map { json($0.0) + ":" + json($0.1) }.joined(separator: ",") + "}"
    }

    static func json(_ s: String) -> String {
        guard let d = try? JSONSerialization.data(withJSONObject: s, options: [.fragmentsAllowed, .withoutEscapingSlashes]) else { return "\"\"" }
        return String(decoding: d, as: UTF8.self)
    }

    /// O_APPEND : l'écriture va toujours en fin de fichier, même si le capteur écrit en même temps.
    func ajouter(_ ligne: String) throws {
        try FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
        let fd = open(fichierEntrants.path, O_WRONLY | O_APPEND | O_CREAT, 0o600)
        guard fd >= 0 else { throw CocoaError(.fileWriteNoPermission) }
        defer { close(fd) }
        let d = Data((ligne + "\n").utf8)
        let ecrit = d.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        guard ecrit == d.count else { throw CocoaError(.fileWriteUnknown) }
    }
}
