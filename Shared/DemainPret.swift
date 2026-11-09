// « Demain prêt ? » (03/11, Sacha : chaque soir, le lendemain doit être parfaitement organisé ; ce qui se prépare à
// l'avance se fait le dimanche). Le contrôle du jour ouvré suivant : vidéos, prospects, tâches, décisions. Une ligne verte
// ou rouge par point, et pour chaque trou la session qui doit le combler. Le dimanche, en plus : les sujets de la semaine.
// Le contrôle garantit la préparation, pas le résultat.
import Foundation

/// Les objectifs que les tâches de demain doivent faire avancer (à adapter aux vôtres).
enum ObjectifsCap {
    static let kryva = "Des artisans payants sur KRYVA"
    static let freelance = "3 à 4 clients freelance signés par mois"
}

/// Qui comble un trou : le nom d'équipe (EQUIPE.md, `SESSIONS` de scripts/facteur.py) ; vide = Sacha lui-même.
enum Comble {
    static let reseaux = "KRYVA · Réseaux, image, événements"
    static let ventes = "KRYVA · Ventes"
    static let freelance = "FREELANCE"
    static let pilote = "PILOTE"
    static let sacha = ""

    static func court(_ qui: String) -> String {
        switch qui {
        case reseaux: return "Réseaux"
        case ventes: return "Ventes"
        case sacha: return "vous"
        default: return qui
        }
    }
}

struct PointDemain: Identifiable, Hashable {
    let id: String
    let titre: String
    let ok: Bool
    let detail: String
    /// Nom d'équipe de la session qui comble le trou (Comble), vide = Sacha.
    let qui: String
    /// Comment le point est compté (infobulle).
    var regle: String = ""
}

/// Un message préparé, vu par le contrôle : son espace, le jour où il part et son statut (prepare, a_valider, a_refaire).
struct MessageDemain: Hashable {
    let espace: String
    let jour: String
    let statut: String
    var nom: String = ""
}

/// Un rappel des listes du planning, vu par le contrôle : son jour d'échéance (AAAA-MM-JJ, heure de Paris).
struct TacheDemain: Hashable {
    let titre: String
    var notes: String = ""
    let liste: String
    let jour: String
}

struct BilanDemain: Hashable {
    /// Le jour contrôlé : le jour ouvré suivant (AAAA-MM-JJ).
    let jour: String
    let dimanche: Bool
    let points: [PointDemain]
    /// false tant que les Rappels ne sont pas lus : aucune notification sur un bilan incomplet.
    let complet: Bool
    var trous: [PointDemain] { points.filter { !$0.ok } }
}

enum DemainPret {
    /// L'heure du contrôle du soir (heure de Paris).
    static let heureControle = 19

    private static var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Paris")!
        return c
    }

    static func estDimanche(_ jour: String) -> Bool {
        guard let d = Dates.jour.date(from: jour) else { return false }
        return cal.component(.weekday, from: d) == 1
    }

    /// La clé de la notification du soir s'il est l'heure : du lundi au vendredi et le dimanche, à partir de 19 h.
    /// Le samedi, rien (le vendredi a déjà contrôlé lundi, le dimanche le refait avec la semaine).
    static func cleNotification(_ maintenant: Date) -> String? {
        let jour = Dates.jour.string(from: maintenant)
        guard cal.component(.hour, from: maintenant) >= heureControle,
              cal.component(.weekday, from: maintenant) != 7 else { return nil }
        return "demain-\(jour)"
    }

    /// « mer. 4 nov. »
    static func libelleJour(_ jour: String) -> String {
        guard let d = Dates.jour.date(from: jour) else { return jour }
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.timeZone = TimeZone(identifier: "Europe/Paris")
        f.dateFormat = "EEE d MMM"
        return f.string(from: d)
    }

    /// Le contrôle. `taches` nil = Rappels pas encore lus ; `accesRappels` false = Pilote n'a pas accès à Rappels.
    static func controler(aujourdhui: String, videos: [Video], contacts: [Contact], messages: [MessageDemain],
                          taches: [TacheDemain]?, accesRappels: Bool = true,
                          decisionsOuvertes: Int, reponsesEnAttente: Int) -> BilanDemain {
        let jour = VideoCalcul.lendemainOuvre(aujourdhui)
        let dimanche = estDimanche(aujourdhui)
        var points: [PointDemain] = VideoVocabulaire.comptes.map { pointVideo(videos, jour: jour, compte: $0.0, libelle: $0.1) }
        if dimanche { points += pointsSemaine(videos, jour: jour) }
        points.append(pointProspects(contacts, messages, jour: jour, espace: "kryva", titre: "Prospects KRYVA", qui: Comble.ventes))
        points.append(pointProspects(contacts, messages, jour: jour, espace: "freelance", titre: "Prospects freelance", qui: Comble.freelance))
        points += pointsTaches(taches, accesRappels: accesRappels, jour: jour)
        points.append(pointDecisions(ouvertes: decisionsOuvertes, enAttente: reponsesEnAttente))
        return BilanDemain(jour: jour, dimanche: dimanche, points: points, complet: taches != nil || !accesRappels)
    }

    // MARK: Vidéos : tournée et montée la veille, donc « Prête » le soir

    static func pointVideo(_ videos: [Video], jour: String, compte: String, libelle: String) -> PointDemain {
        let v = videos.first { $0.jour == jour && $0.compte == compte }
        let titre = "Vidéo \(compte == "perso" ? "perso" : libelle)"
        let regle = "Règle du 03/11 : tournée et montée la veille, donc « Prête » le soir. Annulée = décidé, rien à préparer."
        func point(_ ok: Bool, _ detail: String) -> PointDemain {
            PointDemain(id: "video-\(compte)", titre: titre, ok: ok, detail: detail, qui: Comble.reseaux, regle: regle)
        }
        guard let v, v.statut != "a_choisir", !v.sujet.isEmpty else {
            let note = v.map { $0.sujet.isEmpty ? "" : " (\($0.sujet))" } ?? ""
            return point(false, "Aucun sujet validé\(note)")
        }
        switch v.statut {
        case "prete", "publiee": return point(true, "Prête : \(v.sujet)")
        case "annulee": return point(true, "Annulée, rien à préparer")
        case "tournee": return point(false, "Tournée, montage pas fini : \(v.sujet)")
        default: return point(false, "Sujet validé, pas encore tournée : \(v.sujet)")
        }
    }

    /// Le dimanche : les 10 sujets de la semaine qui vient (5 KRYVA + 5 perso) et 1 sujet de réserve par compte.
    static func pointsSemaine(_ videos: [Video], jour: String) -> [PointDemain] {
        let semaine = VideoCalcul.semaine(de: jour)
        var manquent: [String] = []
        var valides = 0
        for (compte, libelle) in VideoVocabulaire.comptes {
            let jours = semaine.filter { j in
                guard let v = videos.first(where: { $0.jour == j && $0.compte == compte }) else { return true }
                return v.statut == "a_choisir" || v.sujet.isEmpty
            }
            valides += semaine.count - jours.count
            if !jours.isEmpty {
                manquent.append("\(libelle) " + jours.map { libelleJour($0).split(separator: " ").prefix(2).joined(separator: " ") }
                    .joined(separator: ", "))
            }
        }
        let total = semaine.count * VideoVocabulaire.comptes.count
        let sujets = PointDemain(
            id: "semaine-sujets", titre: "Sujets de la semaine", ok: manquent.isEmpty,
            detail: manquent.isEmpty ? "\(total) sur \(total) validés"
                : "\(valides) sur \(total) validés. Manquent : \(manquent.joined(separator: " · "))",
            qui: Comble.reseaux, regle: "Le dimanche : 5 sujets KRYVA + 5 perso validés pour la semaine du \(libelleJour(semaine.first ?? jour)).")
        let reserve = VideoVocabulaire.comptes.map { compte, libelle in
            (libelle, videos.filter { $0.jour.isEmpty && $0.compte == compte && !$0.sujet.isEmpty
                && ["valide", "tournee", "prete"].contains($0.statut) }.count)
        }
        let sansReserve = reserve.filter { $0.1 == 0 }.map(\.0)
        let pointReserve = PointDemain(
            id: "semaine-reserve", titre: "Sujets de réserve", ok: sansReserve.isEmpty,
            detail: reserve.map { "\($0.0) \($0.1)" }.joined(separator: " · ")
                + (sansReserve.isEmpty ? "" : ". Manque : \(sansReserve.joined(separator: ", "))"),
            qui: Comble.reseaux, regle: "Le dimanche : au moins 1 sujet de réserve validé par compte.")
        return [sujets, pointReserve]
    }

    // MARK: Prospects : les contacts dont la prochaine action tombe demain, avec leurs messages

    static func pointProspects(_ contacts: [Contact], _ messages: [MessageDemain], jour: String, espace: String,
                               titre: String, qui: String) -> PointDemain {
        let prevus = contacts.filter { $0.espace == espace && $0.prochaineDate == jour && !$0.nePlusContacter
            && $0.etape != "perdu" }.count      // un client « gagné » daté est suivi (05/11, T3)
        let duJour = messages.filter { $0.espace == espace && $0.jour == jour }
        let prets = duJour.filter { $0.statut == "prepare" }.count
        let aValider = duJour.filter { $0.statut == "a_valider" }.count
        let aRefaire = messages.filter { $0.espace == espace && $0.statut == "a_refaire" && !$0.jour.isEmpty && $0.jour <= jour }
        var morceaux: [String] = []
        morceaux.append(prevus == 1 ? "1 contact prévu" : "\(prevus) contacts prévus")
        if prets + aValider > 0 {
            morceaux.append((prets + aValider == 1 ? "1 message préparé" : "\(prets + aValider) messages préparés")
                + (aValider > 0 ? " (dont \(aValider) à valider par vous)" : ""))
        }
        var ok = true
        if prevus == 0 && prets + aValider == 0 {
            ok = false
            morceaux = ["Aucune liste pour demain"]
        } else if prets + aValider == 0 {
            ok = false
            morceaux.append("aucun message préparé")
        }
        if !aRefaire.isEmpty {
            ok = false
            let noms = aRefaire.map(\.nom).filter { !$0.isEmpty }.prefix(2).joined(separator: ", ")
            morceaux.append((aRefaire.count == 1 ? "1 texte renvoyé pas encore refait" : "\(aRefaire.count) textes renvoyés pas encore refaits")
                + (noms.isEmpty ? "" : " (\(noms))"))
        }
        return PointDemain(id: "prospects-\(espace)", titre: titre, ok: ok, detail: morceaux.joined(separator: " · "), qui: qui,
                           regle: "Les contacts dont la prochaine date est demain, et les messages prévus demain (préparés ou à valider). "
                               + "Un texte renvoyé à l'agent et pas refait est un trou.")
    }

    // MARK: Tâches : au moins une tâche de demain qui fait avancer chaque objectif

    /// Une tâche commerciale : appel, relance, envoi, mail, DM, devis, facture, client… (titre ou ligne « But : »).
    private static let motsCommerciaux = #"\b(appel|rappeler|relanc|envoi|envoy|e-?mail|mail|sms|dm\b|linkedin|insta|whatsapp|devis|factur|acompte|rdv|rendez-vous|visio|prospect|inscrit|client|artisan|propos|offre|demo|sign|contrat|vend|payant)"#

    static func faitAvancer(_ t: TacheDemain) -> Bool {
        guard !Decisions.estDecision(t.titre) else { return false }
        let texte = (t.titre + " " + (NotesPlanning.lire(t.notes).but ?? ""))
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr_FR"))
        return texte.range(of: motsCommerciaux, options: .regularExpression) != nil
    }

    static func pointsTaches(_ taches: [TacheDemain]?, accesRappels: Bool, jour: String) -> [PointDemain] {
        let objectifs: [(id: String, titre: String, listes: [String], objectif: String)] = [
            ("taches-freelance", "Tâche pour les clients freelance", ["Freelance"], ObjectifsCap.freelance),
            ("taches-kryva", "Tâche pour les clients KRYVA", ["KRYVA", "Appels"], ObjectifsCap.kryva),
        ]
        return objectifs.map { o in
            let regle = "Objectif : \(o.objectif). Compte : un rappel non coché de demain dans « \(o.listes.joined(separator: " » ou « ")) » "
                + "dont le titre ou le « But : » parle d'appel, relance, envoi, mail, DM, devis, facture, client…"
            guard accesRappels else {
                return PointDemain(id: o.id, titre: o.titre, ok: false, detail: "Pilote n'a pas accès à Rappels", qui: Comble.pilote, regle: regle)
            }
            guard let taches else {
                return PointDemain(id: o.id, titre: o.titre, ok: false, detail: "Lecture des Rappels…", qui: Comble.pilote, regle: regle)
            }
            let utiles = taches.filter { $0.jour == jour && o.listes.contains($0.liste) && faitAvancer($0) }
            let detail = utiles.isEmpty ? "Aucune tâche de demain ne fait avancer « \(o.objectif) »"
                : utiles.prefix(2).map(\.titre).joined(separator: " · ") + (utiles.count > 2 ? " · +\(utiles.count - 2)" : "")
            return PointDemain(id: o.id, titre: o.titre, ok: !utiles.isEmpty, detail: detail, qui: Comble.pilote, regle: regle)
        }
    }

    // MARK: Décisions du jour : toutes répondues et envoyées avant le soir

    static func pointDecisions(ouvertes: Int, enAttente: Int) -> PointDemain {
        var morceaux: [String] = []
        if ouvertes > 0 { morceaux.append(ouvertes == 1 ? "1 décision à prendre" : "\(ouvertes) décisions à prendre") }
        if enAttente > 0 { morceaux.append(enAttente == 1 ? "1 réponse pas envoyée" : "\(enAttente) réponses pas envoyées") }
        return PointDemain(id: "decisions", titre: "Décisions du jour", ok: morceaux.isEmpty,
                           detail: morceaux.isEmpty ? "Toutes répondues et envoyées" : morceaux.joined(separator: " · "),
                           qui: Comble.sacha,
                           regle: "Les ❓ du jour et les questions des sessions répondues, et « Vos réponses, prêtes à partir » vide.")
    }
}
