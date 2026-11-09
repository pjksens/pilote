// Tests de « Ma journée » (brief de 7 h), de la séance du dimanche et de la boîte à idées (03/11).
import XCTest

final class JourneeTests: XCTestCase {
    private func date(_ s: String) -> Date {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Europe/Paris")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.date(from: s)!
    }

    func testHeureDansLesNotes() {
        XCTAssertEqual(MaJournee.heureDans("Tournage 04/11 10:45, valider 18:30.", apres: "tournage"), "10:45")
        XCTAssertEqual(MaJournee.heureDans("Tournage 04/11 10:45, valider 18:30.", apres: "valider"), "18:30")
        XCTAssertEqual(MaJournee.heureDans("Tournage mer. 04/11 9h05", apres: "tournage"), "09:05")
        XCTAssertNil(MaJournee.heureDans("Rushes absents.", apres: "tournage"))
        XCTAssertNil(MaJournee.heureDans("Tournage fait. Valider 18:30", apres: "tournage"))
    }

    func testJourneeDUnMardi() {
        let videos = [
            Video(id: "1", jour: "2026-11-03", compte: "kryva", sujet: "2 ans", statut: "prete", heure: "18:00"),
            Video(id: "2", jour: "2026-11-04", compte: "perso", sujet: "Casque 3D", statut: "valide",
                  notes: "Tournage 03/11 10:45, valider 18:30."),
            Video(id: "3", jour: "2026-11-04", compte: "kryva", statut: "a_choisir"),
        ]
        let e = MaJournee.construire(aujourdhui: "2026-11-03",
                                     rendezVous: [EntreeJournee(titre: "Salle", debut: date("2026-11-03 08:00"), fin: date("2026-11-03 09:00")),
                                                  EntreeJournee(titre: "Demain", debut: date("2026-11-04 08:00"))],
                                     taches: [EntreeJournee(titre: "❓ Poster ?", debut: date("2026-11-03 10:00"))],
                                     videos: videos, messagesKryva: 2, messagesFreelance: 0, decisions: 1)
        let ids = e.map(\.id)
        XCTAssertEqual(ids.first, "decisions")                       // sans heure d'abord
        XCTAssertFalse(ids.contains("tache-0"))                      // une décision n'est pas une tâche
        XCTAssertFalse(ids.contains("rdv-1"))                        // pas du jour
        XCTAssertEqual(e.first { $0.id == "rdv-0" }?.heure, "08:00")
        XCTAssertEqual(e.first { $0.id == "tourner-perso" }?.heure, "10:45")
        XCTAssertEqual(e.first { $0.id == "valider-perso" }?.heure, "18:30")
        XCTAssertEqual(e.first { $0.id == "publier-kryva" }?.heure, "18:00")
        XCTAssertEqual(e.first { $0.id == "prospects-kryva" }?.heure, "12:00")
        XCTAssertTrue(e.first { $0.id == "tourner-kryva" }?.titre.hasPrefix("Choisir le sujet") ?? false)
        XCTAssertEqual(e.filter { $0.genre == .cadre }.count, MaJournee.cadreSemaine.count)
        XCTAssertEqual(e.map(\.heure).filter { !$0.isEmpty }, e.map(\.heure).filter { !$0.isEmpty }.sorted())
    }

    func testSamediEtDimanche() {
        let samedi = MaJournee.construire(aujourdhui: "2026-11-07", rendezVous: [], taches: [], videos: [],
                                          messagesKryva: 0, messagesFreelance: 0, decisions: 0)
        XCTAssertEqual(samedi.map(\.id), ["cadre-0"])                // le bilan, rien à tourner le week-end
        XCTAssertTrue(MaJournee.construire(aujourdhui: "2026-11-08", rendezVous: [], taches: [], videos: [],
                                           messagesKryva: 0, messagesFreelance: 0, decisions: 0).isEmpty)
    }

    func testNotificationDuMatin() {
        XCTAssertEqual(MaJournee.cleNotification(date("2026-11-03 07:05")), "journee-2026-11-03")
        XCTAssertNil(MaJournee.cleNotification(date("2026-11-03 06:59")))
        XCTAssertNil(MaJournee.cleNotification(date("2026-11-03 12:00")))
        XCTAssertNil(MaJournee.cleNotification(date("2026-11-08 08:00")))   // dimanche
        XCTAssertNotNil(MaJournee.cleNotification(date("2026-11-07 08:00"))) // samedi
    }

    func testSeanceDuDimanche() {
        let videos = [
            Video(id: "1", jour: "2026-11-09", compte: "kryva", sujet: "À choisir", statut: "a_choisir",
                  notes: "Réseaux, 07/11.\nA : Acompte 7 jours\nB : TVA 20 % chaudière"),
            Video(id: "2", jour: "", compte: "perso", sujet: "Unslop", statut: "valide"),
        ]
        let c = SeanceDimanche.creneaux(videos, aujourdhui: "2026-11-08")
        XCTAssertEqual(c.count, 12)
        XCTAssertEqual(c.first?.id, "2026-11-09-kryva")
        XCTAssertEqual(c.first?.options, ["Acompte 7 jours", "TVA 20 % chaudière"])
        XCTAssertEqual(c.first?.choisi, false)
        XCTAssertEqual(c.first { $0.id == "reserve-perso" }?.choisi, true)
        XCTAssertEqual(SeanceDimanche.creneaux(videos, aujourdhui: "2026-11-07").first?.id, "2026-11-09-kryva") // samedi aussi

        let avec = SeanceDimanche.champs(c[0], sujet: "Acompte 7 jours")
        XCTAssertEqual(avec["id"] as? String, "1")
        XCTAssertEqual(avec["statut"] as? String, "valide")
        let sans = SeanceDimanche.champs(c[1], sujet: "Pilote en vrai")
        XCTAssertEqual(sans["jour"] as? String, "2026-11-09")
        XCTAssertEqual(sans["compte"] as? String, "perso")
        XCTAssertNil(SeanceDimanche.champs(c.first { $0.id == "reserve-kryva" }!, sujet: "X")["jour"])
    }

    func testNotificationEtAffichageDuDimanche() {
        XCTAssertEqual(SeanceDimanche.cleNotification(date("2026-11-08 10:00")), "seance-2026-11-08")
        XCTAssertNil(SeanceDimanche.cleNotification(date("2026-11-08 09:59")))
        XCTAssertNil(SeanceDimanche.cleNotification(date("2026-11-07 11:00")))
        XCTAssertTrue(SeanceDimanche.affichee("2026-11-07"))
        XCTAssertFalse(SeanceDimanche.affichee("2026-11-06"))
    }

    func testBoiteAIdees() {
        let i = SeanceDimanche.idees("# Boîte à idées\n\nUne ligne par idée.\n\n- 03/11 · Sacha · Louer un Mac Studio\n-  \n- 03/11 (App) : avis")
        XCTAssertEqual(i.map(\.texte), ["03/11 · Sacha · Louer un Mac Studio", "03/11 (App) : avis"])
        XCTAssertTrue(i[0].ref.hasPrefix("idee:"))
        XCTAssertEqual(i[0].ref, SeanceDimanche.idees("- 03/11 · Sacha · Louer un Mac Studio")[0].ref)
        XCTAssertNotEqual(i[0].ref, i[1].ref)
    }

    func testFaitResteEnGris() {
        let e = MaJournee.construire(aujourdhui: "2026-11-03",
                                     rendezVous: [EntreeJournee(titre: "Salle", debut: date("2026-11-03 07:45"), cible: "evt1", fait: true)],
                                     taches: [EntreeJournee(titre: "Prise de sang", debut: date("2026-11-03 06:45"), cible: "rap1")],
                                     videos: [], messagesKryva: 0, messagesFreelance: 0, decisions: 0)
        XCTAssertEqual(e.first { $0.id == "rdv-0" }?.fait, true)            // fait : toujours là, en gris
        XCTAssertEqual(e.first { $0.id == "rdv-0" }?.cible, "evt1")
        XCTAssertEqual(e.first { $0.id == "tache-0" }?.fait, false)
        XCTAssertTrue(MaJournee.resume(e).contains("06:45 Prise de sang"))
        XCTAssertFalse(MaJournee.resume(e).contains("Salle"))                // la notification ne cite pas ce qui est fait
    }

    func testReport() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Paris")!
        let mardi = date("2026-11-03 22:50")
        XCTAssertEqual(Report.demain.jour(depuis: mardi, cal: cal), date("2026-11-04 00:00"))
        XCTAssertEqual(Report.apresDemain.jour(depuis: mardi, cal: cal), date("2026-11-05 00:00"))
        XCTAssertEqual(Report.lundi.jour(depuis: mardi, cal: cal), date("2026-11-09 00:00"))
        XCTAssertEqual(Report.lundi.jour(depuis: date("2026-11-09 08:00"), cal: cal), date("2026-11-16 00:00")) // un lundi : le suivant
        XCTAssertEqual(Report.memeHeure(date("2026-11-03 07:45"), le: date("2026-11-09 00:00"), cal: cal), date("2026-11-09 07:45"))
    }

    func testRouvrirUnTermine() throws {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let tt = TachesTerminees(dossier: d)
        let t = TachePlanning(genre: .evenement, ref: "ext1", idLocal: "loc1", titre: "Salle", debut: date("2026-11-03 07:45"),
                              fin: date("2026-11-03 10:15"), calendrier: "Perso", journee: false, url: nil, notes: NotesPlanning.lire(""))
        XCTAssertTrue(try tt.terminer(t))
        XCTAssertNotNil(tt.lire()[t.id])
        try tt.rouvrir(t)
        XCTAssertNil(tt.lire()[t.id])
        let lignes = try String(contentsOf: tt.fichierEntrants, encoding: .utf8).split(separator: "\n")
        XCTAssertEqual(lignes.count, 2)
        XCTAssertTrue(lignes[1].contains("\"classe\":\"tache_rouverte\""))
    }

    func testIdeesRepondues() throws {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        try Decisions.noter(question: "Idée : x", choix: "Non", ref: "idee:abc", liste: "KRYVA", pour: "PILOTE", dossier: d)
        try Decisions.noter(question: "Q", choix: "C", ref: "session:s:u", liste: "Sessions", dossier: d)
        XCTAssertEqual(Decisions.refsRepondues(prefixe: "idee:", dossier: d), ["idee:abc"])
        XCTAssertEqual(Decisions.questionsRepondues(dossier: d), ["session:s:u"])
    }

    // MARK: les étapes de vidéo se cochent (04/11)

    func testTournerSeCocheEtResteEnGris() {
        func journee(_ statut: String) -> [ElementJournee] {
            MaJournee.construire(aujourdhui: "2026-11-04", rendezVous: [], taches: [],
                                 videos: [Video(id: "p", jour: "2026-11-05", compte: "perso", sujet: "J'améliore mon site", statut: statut,
                                                notes: "Tournage 04/11 10:45, valider 18:30.")],
                                 messagesKryva: 0, messagesFreelance: 0, decisions: 0)
        }
        let avant = journee("valide")
        XCTAssertEqual(avant.first { $0.id == "tourner-perso" }?.fait, false)
        XCTAssertEqual(avant.first { $0.id == "tourner-perso" }?.cible, "video:2026-11-05:perso:tourner")
        let tournee = journee("tournee")
        XCTAssertEqual(tournee.first { $0.id == "tourner-perso" }?.fait, true)       // reste là, en gris
        XCTAssertEqual(tournee.first { $0.id == "valider-perso" }?.fait, false)
        let prete = journee("prete")
        XCTAssertEqual(prete.first { $0.id == "valider-perso" }?.fait, true)
        XCTAssertEqual(prete.first { $0.id == "tourner-perso" }?.fait, true)
        XCTAssertEqual(MaJournee.resume(tournee).contains("Tourner"), false)          // le brief ne le redit pas
        XCTAssertEqual(VideoCalcul.statutApres(action: "tourner", fait: true), "tournee")
        XCTAssertEqual(VideoCalcul.statutApres(action: "tourner", fait: false), "valide")
        XCTAssertEqual(VideoCalcul.statutApres(action: "valider", fait: true), "prete")
        XCTAssertEqual(VideoCalcul.statutApres(action: "publier", fait: true), "publiee")
        XCTAssertNil(VideoCalcul.statutApres(action: "autre", fait: true))
    }

    // 05/11 : un rappel « Tourner… », « Valider le montage… » ou « Publier… » remplace la ligne calculée de la vidéo.
    func testRappelVideoPasEnDouble() {
        let d = { (h: String) in self.date("2026-11-05 \(h)") }
        let e = MaJournee.construire(aujourdhui: "2026-11-05", rendezVous: [],
                                     taches: [EntreeJournee(titre: "Tourner KRYVA « impayé » (priorité du matin)", debut: d("11:30")),
                                              EntreeJournee(titre: "Valider le montage « Unslop » (perso)", debut: d("17:15")),
                                              EntreeJournee(titre: "Publier « J'améliore mon site » (@sachaprljk)", debut: d("20:00"))],
                                     videos: [Video(id: "k", jour: "2026-11-06", compte: "kryva", sujet: "Impayé", statut: "valide", notes: ""),
                                              Video(id: "p", jour: "2026-11-06", compte: "perso", sujet: "Unslop", statut: "valide",
                                                    notes: "valider 17:15"),
                                              Video(id: "q", jour: "2026-11-05", compte: "perso", sujet: "J'améliore mon site", statut: "prete", notes: "")],
                                     messagesKryva: 0, messagesFreelance: 0, decisions: 0)
        let ids = Set(e.map(\.id))
        XCTAssertFalse(ids.contains("tourner-kryva"))       // le rappel suffit
        XCTAssertTrue(ids.contains("tourner-perso"))        // aucun rappel « Tourner » perso : la ligne reste
        XCTAssertFalse(ids.contains("valider-perso"))
        XCTAssertFalse(ids.contains("publier-perso"))
        XCTAssertEqual(e.filter { $0.genre == .tache }.count, 3)
        XCTAssertFalse(MaJournee.rappelCouvre(["Valider les textes de demain"], compte: "kryva", action: "valider"))
    }

    func testPublierSeCocheEtUneVideoPublieeResteEnGris() {
        let j = MaJournee.construire(aujourdhui: "2026-11-04", rendezVous: [], taches: [],
                                     videos: [Video(id: "k", jour: "2026-11-04", compte: "kryva", sujet: "2 ans", statut: "publiee", heure: "18:00")],
                                     messagesKryva: 0, messagesFreelance: 0, decisions: 0)
        let p = j.first { $0.id == "publier-kryva" }
        XCTAssertEqual(p?.fait, true)
        XCTAssertEqual(p?.cible, "video:2026-11-04:kryva:publier")
    }
}
