// Tests du contrôle « Demain prêt ? » : vidéos, prospects, tâches, décisions, le dimanche et l'heure de la notification.
import XCTest

final class DemainPretTests: XCTestCase {
    private func video(_ jour: String, _ compte: String, _ statut: String, _ sujet: String = "Sujet") -> Video {
        Video(id: UUID().uuidString, jour: jour, compte: compte, sujet: sujet, statut: statut)
    }

    private func contact(_ espace: String, _ date: String, etape: String = "contacte", stop: Bool = false) -> Contact {
        Contact(id: UUID().uuidString, espace: espace, etape: etape, prochaineDate: date, nePlusContacter: stop)
    }

    private func point(_ b: BilanDemain, _ id: String) -> PointDemain? { b.points.first { $0.id == id } }

    private func bilan(aujourdhui: String = "2026-11-03", videos: [Video] = [], contacts: [Contact] = [],
                       messages: [MessageDemain] = [], taches: [TacheDemain]? = [], acces: Bool = true,
                       ouvertes: Int = 0, attente: Int = 0) -> BilanDemain {
        DemainPret.controler(aujourdhui: aujourdhui, videos: videos, contacts: contacts, messages: messages, taches: taches,
                             accesRappels: acces, decisionsOuvertes: ouvertes, reponsesEnAttente: attente)
    }

    // MARK: Vidéos

    /// Le soir du 03/11 : la vidéo KRYVA du 04/11 sans sujet validé, la perso validée mais pas tournée.
    func testVideosDu4Novembre() {
        let b = bilan(videos: [video("2026-11-04", "kryva", "a_choisir", "À choisir : poster « 2 ans » ou rien"),
                               video("2026-11-04", "perso", "valide", "Pub casque 3D")])
        XCTAssertEqual(b.jour, "2026-11-04")
        let k = point(b, "video-kryva")!
        XCTAssertFalse(k.ok)
        XCTAssertEqual(k.detail, "Aucun sujet validé (À choisir : poster « 2 ans » ou rien)")
        XCTAssertEqual(k.qui, Comble.reseaux)
        XCTAssertEqual(point(b, "video-perso")?.detail, "Sujet validé, pas encore tournée : Pub casque 3D")
        XCTAssertFalse(b.dimanche)
        XCTAssertNil(point(b, "semaine-sujets"))
    }

    func testVideoPreteAnnuleeTournee() {
        let b = bilan(videos: [video("2026-11-04", "kryva", "prete"), video("2026-11-04", "perso", "annulee")])
        XCTAssertEqual(point(b, "video-kryva")?.ok, true)
        XCTAssertEqual(point(b, "video-perso")?.ok, true)
        XCTAssertEqual(point(bilan(videos: [video("2026-11-04", "kryva", "tournee")]), "video-kryva")?.ok, false)
        // Rien dans la table : un trou.
        XCTAssertEqual(point(bilan(), "video-perso")?.detail, "Aucun sujet validé")
        // Le vendredi contrôle le lundi.
        XCTAssertEqual(bilan(aujourdhui: "2026-11-06").jour, "2026-11-09")
    }

    // MARK: Prospects

    func testProspects() {
        // Personne et rien de préparé.
        XCTAssertEqual(point(bilan(), "prospects-kryva")?.detail, "Aucune liste pour demain")
        // Des contacts prévus mais aucun message.
        let sansMessage = bilan(contacts: [contact("kryva", "2026-11-04"), contact("kryva", "2026-11-04")])
        XCTAssertEqual(point(sansMessage, "prospects-kryva")?.ok, false)
        XCTAssertEqual(point(sansMessage, "prospects-kryva")?.detail, "2 contacts prévus · aucun message préparé")
        // Un message préparé et un à valider : prêt.
        let pret = bilan(contacts: [contact("freelance", "2026-11-04"), contact("freelance", "2026-11-04", stop: true),
                                    contact("freelance", "2026-11-04", etape: "perdu"), contact("freelance", "2026-11-05")],
                         messages: [MessageDemain(espace: "freelance", jour: "2026-11-04", statut: "prepare"),
                                    MessageDemain(espace: "freelance", jour: "2026-11-04", statut: "a_valider"),
                                    MessageDemain(espace: "freelance", jour: "2026-11-05", statut: "prepare")])
        let f = point(pret, "prospects-freelance")!
        XCTAssertTrue(f.ok)
        XCTAssertEqual(f.detail, "1 contact prévu · 2 messages préparés (dont 1 à valider par vous)")
        XCTAssertEqual(f.qui, Comble.freelance)
        XCTAssertEqual(point(pret, "prospects-kryva")?.ok, false) // l'autre espace n'est pas compté
        // Un texte renvoyé à l'agent et pas refait : un trou, même avec des messages prêts.
        let refaire = bilan(contacts: [contact("kryva", "2026-11-04")],
                            messages: [MessageDemain(espace: "kryva", jour: "2026-11-04", statut: "prepare"),
                                       MessageDemain(espace: "kryva", jour: "2026-11-04", statut: "a_refaire", nom: "Jean-Marc")])
        XCTAssertEqual(point(refaire, "prospects-kryva")?.ok, false)
        XCTAssertTrue(point(refaire, "prospects-kryva")!.detail.hasSuffix("1 texte renvoyé pas encore refait (Jean-Marc)"))
        XCTAssertEqual(point(refaire, "prospects-kryva")?.qui, Comble.ventes)
    }

    // MARK: Tâches

    func testTaches() {
        let taches = [
            TacheDemain(titre: "Envoyer 3 mails aux vignerons · 30 min", liste: "Freelance", jour: "2026-11-04"),
            TacheDemain(titre: "Correctifs Sentry : dire « push »", liste: "KRYVA", jour: "2026-11-04"),
            TacheDemain(titre: "❓ Relancer qui d'abord ?", liste: "KRYVA", jour: "2026-11-04"),
            TacheDemain(titre: "Appeler 4 inscrits", liste: "Appels", jour: "2026-11-05"),
        ]
        let b = bilan(taches: taches)
        XCTAssertEqual(point(b, "taches-freelance")?.ok, true)
        XCTAssertEqual(point(b, "taches-freelance")?.detail, "Envoyer 3 mails aux vignerons · 30 min")
        // Sentry ne vend rien, la ❓ est une décision, l'appel tombe le 05/11.
        XCTAssertEqual(point(b, "taches-kryva")?.ok, false)
        XCTAssertEqual(point(b, "taches-kryva")?.qui, Comble.pilote)
        // Un appel de demain (liste Appels) compte pour KRYVA ; un « But : » commercial aussi.
        XCTAssertEqual(point(bilan(taches: [TacheDemain(titre: "Appeler Thomas", liste: "Appels", jour: "2026-11-04")]),
                             "taches-kryva")?.ok, true)
        XCTAssertTrue(DemainPret.faitAvancer(TacheDemain(titre: "Préparer la démo", notes: "But : 1er artisan payant", liste: "KRYVA",
                                                          jour: "2026-11-04")))
        XCTAssertFalse(DemainPret.faitAvancer(TacheDemain(titre: "Redémarrer le Mac", liste: "Papiers", jour: "2026-11-04")))
        // Rappels pas encore lus : bilan incomplet (pas de notification) ; accès refusé : complet, et un trou.
        XCTAssertFalse(bilan(taches: nil).complet)
        XCTAssertEqual(point(bilan(taches: nil), "taches-kryva")?.detail, "Lecture des Rappels…")
        XCTAssertTrue(bilan(taches: nil, acces: false).complet)
        XCTAssertEqual(point(bilan(taches: nil, acces: false), "taches-kryva")?.ok, false)
    }

    // MARK: Décisions

    func testDecisions() {
        XCTAssertEqual(point(bilan(), "decisions")?.ok, true)
        let d = point(bilan(ouvertes: 2, attente: 13), "decisions")!
        XCTAssertFalse(d.ok)
        XCTAssertEqual(d.detail, "2 décisions à prendre · 13 réponses pas envoyées")
        XCTAssertEqual(Comble.court(d.qui), "vous")
    }

    // MARK: Le dimanche : la semaine qui vient

    func testDimanche() {
        let semaine = VideoCalcul.semaine(de: "2026-11-09")
        var videos = semaine.flatMap { j in ["kryva", "perso"].map { video(j, $0, "valide") } }
        videos.append(video("", "kryva", "tournee", "Réserve KRYVA"))
        videos.append(video("", "perso", "valide", "Réserve perso"))
        let b = bilan(aujourdhui: "2026-11-08", videos: videos)
        XCTAssertTrue(b.dimanche)
        XCTAssertEqual(b.jour, "2026-11-09")
        XCTAssertEqual(point(b, "semaine-sujets")?.ok, true)
        XCTAssertEqual(point(b, "semaine-sujets")?.detail, "10 sur 10 validés")
        XCTAssertEqual(point(b, "semaine-reserve")?.ok, true)

        // Deux sujets KRYVA à choisir, plus de réserve perso.
        videos = videos.filter { !($0.compte == "perso" && $0.jour.isEmpty) }
        videos[0].statut = "a_choisir"
        videos[2].statut = "a_choisir"
        let trous = bilan(aujourdhui: "2026-11-08", videos: videos)
        XCTAssertEqual(point(trous, "semaine-sujets")?.ok, false)
        XCTAssertTrue(point(trous, "semaine-sujets")!.detail.hasPrefix("8 sur 10 validés. Manquent : KRYVA lun. 9, mar. 10"))
        XCTAssertEqual(point(trous, "semaine-reserve")?.detail, "KRYVA 1 · Perso 0. Manque : Perso")
    }

    // MARK: L'heure de la notification

    func testCleNotification() {
        let iso = ISO8601DateFormatter()
        XCTAssertNil(DemainPret.cleNotification(iso.date(from: "2026-11-03T18:59:00+01:00")!))
        XCTAssertEqual(DemainPret.cleNotification(iso.date(from: "2026-11-03T19:00:00+01:00")!), "demain-2026-11-03")
        XCTAssertEqual(DemainPret.cleNotification(iso.date(from: "2026-11-03T23:30:00+01:00")!), "demain-2026-11-03")
        XCTAssertNil(DemainPret.cleNotification(iso.date(from: "2026-11-07T20:00:00+01:00")!))   // samedi
        XCTAssertEqual(DemainPret.cleNotification(iso.date(from: "2026-11-08T19:05:00+01:00")!), "demain-2026-11-08") // dimanche
    }
}
