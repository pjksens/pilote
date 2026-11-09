// « Ma journée » (03/11, Sacha : « je dois avoir un brief chaque matin, tout ce que j'ai à faire » ; « je dois tout voir
// depuis Pilote »). La journée heure par heure, lue dans ce que Pilote a déjà : rendez-vous (Calendrier), tâches du jour
// (Rappels), vidéos à publier, à tourner et à valider, messages prêts, décisions ; plus le cadre de la semaine type
// (le plan de Sacha). Notification à 7 h, du lundi au samedi. Le brief de PILOTE (réveil
// « brief-matin ») reste : il dit en plus ce qui a glissé la veille.
import Foundation

struct ElementJournee: Identifiable, Hashable {
    enum Genre: Int { case decision, rendezVous, tache, video, prospects, cadre }
    let id: String
    let heure: String      // « 09:00 » ; vide = dans la journée, sans heure
    let titre: String
    var detail = ""
    let genre: Genre
    var lien = ""          // chemin ou adresse à ouvrir
    var cible = ""         // rendez-vous ou rappel visé par « Fait » et « Reporter » (identifiant EventKit)
    var fait = false       // en gris, barré : reste dans la journée
}

/// Un rendez-vous ou une tâche du jour, tels que l'app les a lus (sans EventKit, pour les tests).
struct EntreeJournee: Hashable {
    let titre: String
    let debut: Date
    var fin: Date?
    var avecHeure = true
    var source = ""        // calendrier ou liste de rappels
    var lien = ""
    var cible = ""
    var fait = false
}

/// Reporter un rendez-vous ou une tâche de Ma journée (03/11, Sacha : « au lendemain, date précise ») : même heure, autre jour.
/// Reporté, il quitte la journée.
enum Report: String, CaseIterable, Identifiable {
    case demain = "Demain", apresDemain = "Après-demain", lundi = "Lundi prochain"
    var id: String { rawValue }

    func jour(depuis maintenant: Date, cal: Calendar = .current) -> Date {
        let debut = cal.startOfDay(for: maintenant)
        switch self {
        case .demain: return cal.date(byAdding: .day, value: 1, to: debut)!
        case .apresDemain: return cal.date(byAdding: .day, value: 2, to: debut)!
        case .lundi: return cal.nextDate(after: debut, matching: DateComponents(weekday: 2), matchingPolicy: .nextTime)!
        }
    }

    /// La même heure qu'avant, le jour donné.
    static func memeHeure(_ debut: Date, le jour: Date, cal: Calendar = .current) -> Date {
        let h = cal.dateComponents([.hour, .minute], from: debut)
        return cal.date(bySettingHour: h.hour ?? 0, minute: h.minute ?? 0, second: 0, of: jour) ?? jour
    }
}

enum MaJournee {
    /// L'heure du brief (heure de Paris).
    static let heureBrief = 7

    /// La semaine type du CAP : les créneaux des jours ouvrés, et le bilan du samedi matin.
    static let cadreSemaine: [(heure: String, titre: String)] = [
        ("09:00", "Produire : freelance en cours, sinon tournage (jusqu'à 12 h)"),
        ("12:00", "Appeler les artisans, pause de midi (jusqu'à 13 h 30)"),
        ("14:00", "Publier + 5 messages de prospection freelance (jusqu'à 16 h)"),
        ("16:00", "Démos KRYVA, relances, devis freelance, papiers (jusqu'à 17 h 30)"),
        ("17:30", "Appeler les artisans, sortie de chantier (jusqu'à 19 h)"),
    ]
    static let cadreSamedi: [(heure: String, titre: String)] = [("09:00", "Bilan des 4 chiffres avec PILOTE (30 min)")]

    private static var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Paris")!
        return c
    }

    private static let hm: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Europe/Paris")
        f.dateFormat = "HH:mm"
        return f
    }()

    /// La clé de la notification du matin : du lundi au samedi, de 7 h à midi (le Mac ouvert plus tard la reçoit encore).
    static func cleNotification(_ maintenant: Date) -> String? {
        let h = cal.component(.hour, from: maintenant)
        guard h >= heureBrief, h < 12, cal.component(.weekday, from: maintenant) != 1 else { return nil }
        return "journee-\(Dates.jour.string(from: maintenant))"
    }

    /// L'heure d'une étape écrite dans les notes d'une vidéo : « Tournage 04/11 10:45, valider 18:30 ».
    static func heureDans(_ notes: String, apres mot: String) -> String? {
        // Jusqu'à la fin de la phrase : une virgule, ou un point suivi d'une majuscule (« mer. 04/11 » continue).
        let motif = mot + #"(?:[^,;.\n]|\.(?! [A-ZÀ-Ü]))*?(\d{1,2})[:h](\d{2})"#
        guard let r = notes.range(of: motif, options: [.regularExpression, .caseInsensitive]) else { return nil }
        let bout = String(notes[r])
        guard let h = bout.range(of: #"(\d{1,2})[:h](\d{2})$"#, options: .regularExpression) else { return nil }
        let p = bout[h].split(whereSeparator: { $0 == ":" || $0 == "h" })
        guard p.count == 2, let hh = Int(p[0]), let mm = Int(p[1]), hh < 24, mm < 60 else { return nil }
        return String(format: "%02d:%02d", hh, mm)
    }

    static func construire(aujourdhui: String, rendezVous: [EntreeJournee], taches: [EntreeJournee], videos: [Video],
                           messagesKryva: Int, messagesFreelance: Int, decisions: Int) -> [ElementJournee] {
        var e: [ElementJournee] = []
        let duJour = { (d: Date) in Dates.jour.string(from: d) == aujourdhui }

        for (i, r) in rendezVous.enumerated() where duJour(r.debut) {
            e.append(ElementJournee(id: "rdv-\(i)", heure: r.avecHeure ? hm.string(from: r.debut) : "", titre: r.titre,
                                    detail: [r.fin.map { r.avecHeure ? "jusqu'à \(hm.string(from: $0))" : "" } ?? "", r.source]
                                        .filter { !$0.isEmpty }.joined(separator: " · "),
                                    genre: .rendezVous, lien: r.lien, cible: r.cible, fait: r.fait))
        }
        for (i, t) in taches.enumerated() where duJour(t.debut) && !Decisions.estDecision(t.titre) {
            e.append(ElementJournee(id: "tache-\(i)", heure: t.avecHeure ? hm.string(from: t.debut) : "", titre: t.titre,
                                    detail: t.source, genre: .tache, lien: t.lien, cible: t.cible, fait: t.fait))
        }

        // Vidéos : publier celles du jour ; tourner (et valider) celles du jour ouvré suivant, la veille.
        // 05/11, Sacha : « les rappels en double, faut les enlever ». Un rappel du jour qui tourne, valide ou publie déjà
        // la vidéo d'un compte remplace la ligne calculée : une seule ligne par geste.
        let rappels = taches.filter { duJour($0.debut) }.map(\.titre)
        for (compte, libelle) in VideoVocabulaire.comptes {
            let nom = compte == "perso" ? "perso" : libelle
            if let v = videos.first(where: { $0.jour == aujourdhui && $0.compte == compte }), v.statut != "annulee",
               !rappelCouvre(rappels, compte: compte, action: "publier") {
                let publiee = v.statut == "publiee"
                let pasPrete = publiee || v.statut == "prete" ? "" : "pas encore prête (\(VideoVocabulaire.statut(v.statut).lowercased()))"
                e.append(ElementJournee(id: "publier-\(compte)", heure: v.heure,
                                        titre: v.sujet.isEmpty || v.statut == "a_choisir" ? "Publier la vidéo \(nom) : sujet à choisir"
                                            : "Publier la vidéo \(nom) : \(v.sujet)",
                                        detail: pasPrete, genre: .video, lien: v.fiche.isEmpty ? v.prompteur : v.fiche,
                                        cible: v.statut == "a_choisir" ? "" : VideoCalcul.cible(jour: aujourdhui, compte: compte, action: "publier"),
                                        fait: publiee))
            }
            guard VideoCalcul.estOuvre(aujourdhui) else { continue }
            let demain = VideoCalcul.lendemainOuvre(aujourdhui)
            let quand = DemainPret.libelleJour(demain)
            guard let v = videos.first(where: { $0.jour == demain && $0.compte == compte }) else {
                e.append(ElementJournee(id: "tourner-\(compte)", heure: "", titre: "Vidéo \(nom) de \(quand) : aucun sujet",
                                        detail: "Choisir un sujet (ou la réserve) avant de tourner", genre: .video))
                continue
            }
            // Tourner, puis valider le montage : cochables (« fait » = la vidéo avance d'un statut) ; une fois faits, ils restent en gris.
            let avancee = ["valide", "tournee", "prete", "publiee"].contains(v.statut)
            if v.statut == "a_choisir" {
                e.append(ElementJournee(id: "tourner-\(compte)", heure: "", titre: "Choisir le sujet de la vidéo \(nom) de \(quand)",
                                        detail: v.sujet, genre: .video, lien: v.fiche))
            } else if avancee, !rappelCouvre(rappels, compte: compte, action: "tourner") {
                e.append(ElementJournee(id: "tourner-\(compte)", heure: heureDans(v.notes, apres: "tournage") ?? "",
                                        titre: "Tourner la vidéo \(nom) de \(quand) : \(v.sujet)", genre: .video,
                                        lien: v.prompteur.isEmpty ? v.fiche : v.prompteur,
                                        cible: VideoCalcul.cible(jour: demain, compte: compte, action: "tourner"), fait: v.statut != "valide"))
            }
            if avancee, !rappelCouvre(rappels, compte: compte, action: "valider"), let h = heureDans(v.notes, apres: "valider") {
                e.append(ElementJournee(id: "valider-\(compte)", heure: h, titre: "Valider le montage de la vidéo \(nom) de \(quand)",
                                        detail: v.sujet, genre: .video, lien: v.fiche,
                                        cible: VideoCalcul.cible(jour: demain, compte: compte, action: "valider"),
                                        fait: ["prete", "publiee"].contains(v.statut)))
            }
        }

        let ouvre = VideoCalcul.estOuvre(aujourdhui)
        if messagesKryva > 0 {
            e.append(ElementJournee(id: "prospects-kryva", heure: ouvre ? "12:00" : "",
                                    titre: "Artisans KRYVA : \(messagesKryva) message\(messagesKryva > 1 ? "s" : "") prêt\(messagesKryva > 1 ? "s" : "") à envoyer",
                                    detail: "Aujourd'hui › Prospects du jour", genre: .prospects))
        }
        if messagesFreelance > 0 {
            e.append(ElementJournee(id: "prospects-freelance", heure: ouvre ? "14:00" : "",
                                    titre: "Freelance : \(messagesFreelance) message\(messagesFreelance > 1 ? "s" : "") prêt\(messagesFreelance > 1 ? "s" : "") à envoyer",
                                    detail: "Aujourd'hui › Prospects du jour", genre: .prospects))
        }
        if decisions > 0 {
            e.append(ElementJournee(id: "decisions", heure: "", titre: decisions == 1 ? "1 décision à prendre" : "\(decisions) décisions à prendre",
                                    detail: "Aujourd'hui › À décider", genre: .decision))
        }

        let cadre: [(heure: String, titre: String)]
        if ouvre { cadre = cadreSemaine } else if let d = Dates.jour.date(from: aujourdhui), cal.component(.weekday, from: d) == 7 {
            cadre = cadreSamedi
        } else { cadre = [] }
        e += cadre.enumerated().map { ElementJournee(id: "cadre-\($0.offset)", heure: $0.element.heure, titre: $0.element.titre,
                                                     detail: "Semaine type du CAP", genre: .cadre) }

        // Sans heure d'abord, puis dans l'ordre des heures ; à la même heure, le cadre passe après le reste.
        return e.sorted { a, b in
            if a.heure.isEmpty != b.heure.isEmpty { return a.heure.isEmpty }
            if a.heure != b.heure { return a.heure < b.heure }
            return a.genre.rawValue < b.genre.rawValue
        }
    }

    /// Un rappel fait déjà ce geste pour ce compte : « Tourner KRYVA « impayé » », « Valider le montage « Unslop » (perso) »,
    /// « Publier « J'améliore mon site » (@sachaprljk) ».
    static func rappelCouvre(_ titres: [String], compte: String, action: String) -> Bool {
        let verbes = action == "tourner" ? ["tourner"] : action == "valider" ? ["montage"] : ["publier"]
        let marques = compte == "perso" ? ["perso", "sachaprljk"] : ["kryva"]
        return titres.map { $0.lowercased() }.contains { t in
            verbes.contains { t.contains($0) } && marques.contains { t.contains($0) }
        }
    }

    /// Le texte de la notification : les 3 premières choses à faire, hors cadre.
    static func resume(_ elements: [ElementJournee]) -> String {
        elements.filter { $0.genre != .cadre && !$0.fait }.prefix(3)
            .map { $0.heure.isEmpty ? $0.titre : "\($0.heure) \($0.titre)" }.joined(separator: " · ")
    }
}
