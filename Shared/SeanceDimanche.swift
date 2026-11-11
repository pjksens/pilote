// La séance du dimanche (règle de Sacha du 03/11 : « les sujets sont validés une seule fois par semaine, le dimanche :
// 10 sujets, 5 KRYVA + 5 perso, + 1 sujet de réserve par compte »). Le samedi, Réseaux propose 2 ou 3 sujets par créneau
// (vidéo « a_choisir », une ligne « A : … » par sujet dans les notes, réveil « seance-dimanche » de la veille) ; le
// dimanche, Sacha choisit dans Pilote d'un clic. Le choix valide la vidéo tout de suite et part à Réseaux avec ses envois.
import Foundation

struct CreneauSeance: Identifiable, Hashable {
    let id: String          // « 2026-11-09-kryva », « reserve-kryva »
    let jour: String        // vide = sujet de réserve
    let compte: String
    let libelle: String     // « lun. 9 nov. · KRYVA », « Réserve · Perso »
    let video: Video?
    let options: [String]

    /// Un sujet est choisi : validé (ou plus loin), ou la vidéo annulée.
    var choisi: Bool {
        guard let v = video, !v.sujet.isEmpty else { return false }
        return v.statut != "a_choisir"
    }
}

enum SeanceDimanche {
    /// L'heure de la notification du dimanche (heure de Paris).
    static let heureNotification = 10

    private static var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Paris")!
        return c
    }

    private static func jourSemaine(_ jour: String) -> Int? {
        Dates.jour.date(from: jour).map { cal.component(.weekday, from: $0) }
    }

    /// La carte s'affiche le samedi (pour voir les propositions arriver) et le dimanche.
    static func affichee(_ aujourdhui: String) -> Bool { [1, 7].contains(jourSemaine(aujourdhui) ?? 0) }

    /// La clé de la notification : le dimanche, à partir de 10 h.
    static func cleNotification(_ maintenant: Date) -> String? {
        guard cal.component(.weekday, from: maintenant) == 1, cal.component(.hour, from: maintenant) >= heureNotification
        else { return nil }
        return "seance-\(Dates.jour.string(from: maintenant))"
    }

    /// Les 5 jours de la semaine qui vient (du samedi ou du dimanche, c'est la semaine du lundi suivant).
    static func semaine(_ aujourdhui: String) -> [String] { VideoCalcul.semaine(de: VideoCalcul.lendemainOuvre(aujourdhui)) }

    /// « lun. 9 nov. · KRYVA », « Réserve · Perso » (jour vide), dans la langue de l'app.
    static func libelleCreneau(jour: String, compte: String) -> String {
        let nom = VideoVocabulaire.compte(compte)
        return jour.isEmpty ? L("Réserve · \(nom)") : "\(DemainPret.libelleJour(jour)) · \(nom)"
    }

    /// Les 10 créneaux de la semaine, puis 1 sujet de réserve par compte.
    static func creneaux(_ videos: [Video], aujourdhui: String) -> [CreneauSeance] {
        var c: [CreneauSeance] = []
        for j in semaine(aujourdhui) {
            for (compte, _) in VideoVocabulaire.comptes {
                let v = videos.first { $0.jour == j && $0.compte == compte }
                c.append(CreneauSeance(id: "\(j)-\(compte)", jour: j, compte: compte, libelle: libelleCreneau(jour: j, compte: compte),
                                       video: v, options: v.map { Decisions.options($0.notes) } ?? []))
            }
        }
        for (compte, _) in VideoVocabulaire.comptes {
            let reserve = videos.filter { $0.jour.isEmpty && $0.compte == compte }
            // Une réserve validée suffit ; sinon la proposition de Réseaux, s'il y en a une.
            let v = reserve.first { !$0.sujet.isEmpty && ["valide", "tournee", "prete"].contains($0.statut) }
                ?? reserve.first { $0.statut == "a_choisir" }
            c.append(CreneauSeance(id: "reserve-\(compte)", jour: "", compte: compte, libelle: libelleCreneau(jour: "", compte: compte),
                                   video: v, options: v.map { Decisions.options($0.notes) } ?? []))
        }
        return c
    }

    /// Les champs à enregistrer pour un choix : la vidéo existante, sinon une nouvelle (jour vide = réserve).
    static func champs(_ c: CreneauSeance, sujet: String) -> [String: Any] {
        var champs: [String: Any] = ["sujet": sujet, "statut": "valide"]
        if let v = c.video { champs["id"] = v.id } else {
            champs["compte"] = c.compte
            if !c.jour.isEmpty { champs["jour"] = c.jour }
        }
        return champs
    }

    // MARK: La boîte à idées (IDEES.md, « revue le dimanche avec les sujets »)

    /// Les réponses possibles, telles qu'elles partent à PILOTE (en français : valeurs de la base, jamais traduites).
    static let choixIdee = ["À faire cette semaine", "Au parking (relu le samedi)", "Non"]

    /// Le même choix, écrit pour l'écran dans la langue de l'app.
    static func libelleChoixIdee(_ choix: String) -> String {
        switch choix {
        case "À faire cette semaine": return L("À faire cette semaine")
        case "Au parking (relu le samedi)": return L("Au parking (relu le samedi)")
        case "Non": return L("Non")
        default: return choix
        }
    }

    /// Les idées de IDEES.md : une ligne « - … » chacune ; la ref ne change pas tant que la ligne ne change pas.
    static func idees(_ texte: String) -> [(ref: String, texte: String)] {
        texte.split(whereSeparator: \.isNewline).compactMap { brut in
            let l = brut.trimmingCharacters(in: .whitespaces)
            guard l.hasPrefix("- ") else { return nil }
            let idee = String(l.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            return idee.isEmpty ? nil : (ref: "idee:" + empreinte(idee), texte: idee)
        }
    }

    /// Une empreinte stable d'un texte (FNV-1a 64 bits, en hexadécimal) : la même d'un lancement à l'autre.
    static func empreinte(_ s: String) -> String {
        var h: UInt64 = 0xcbf29ce484222325
        for b in s.utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        return String(h, radix: 16)
    }

    /// La question telle qu'elle part à Réseaux avec la réponse (écrite en base : toujours en français).
    static func question(_ c: CreneauSeance) -> String {
        DemainPret.enFrancais { "Séance du dimanche, sujet de la vidéo \(libelleCreneau(jour: c.jour, compte: c.compte))" }
    }
}
