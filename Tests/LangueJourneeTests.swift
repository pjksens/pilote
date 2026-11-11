// La langue de la journée (10/11) : les textes que produisent Shared/MaJournee.swift, DemainPret.swift, SeanceDimanche.swift et
// ATOI.swift sortent en anglais et en espagnol sans un mot de français ; le français reste celui d'avant ; ce qui part vers
// une session ou s'écrit en base reste en français quelle que soit la langue de l'app.
import XCTest

final class LangueJourneeTests: XCTestCase {
    override func setUp() { Loc.dossierBundle = Bundle(for: Self.self).bundleURL }
    override func tearDown() { Loc.dossierBundle = nil; Loc.langue = "fr" }

    /// Lundi 9 novembre 2026, 14 h (heure de Paris).
    private let maintenant: Date = {
        var c = DateComponents(); c.year = 2026; c.month = 11; c.day = 9; c.hour = 14
        c.timeZone = TimeZone(identifier: "Europe/Paris")
        return Calendar(identifier: .gregorian).date(from: c)!
    }()
    private let heure: TimeInterval = 3600
    private let aujourdhui = "2026-11-09"
    private let langues = ["en", "es"]

    private func date(_ s: String) -> Date {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Europe/Paris")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.date(from: s)!
    }

    /// Les mots français d'une série de sorties, donnée d'exemple volontairement française mise à part.
    private func francais(_ sorties: [String], _ langue: String, ignorer: [String] = []) -> [String] {
        sorties.flatMap { s in ContientDuFrancais(s, langue: langue, donnees: ignorer).map { "\($0) <- \(s)" } }
    }

    // MARK: Ma journée

    private func sortiesJournee() -> [String] {
        let videos = [
            Video(id: "1", jour: "2026-11-03", compte: "kryva", sujet: "2 ans", statut: "prete", heure: "18:00"),
            Video(id: "2", jour: "2026-11-04", compte: "perso", sujet: "Casque 3D", statut: "valide",
                  notes: "Tournage 03/11 10:45, valider 18:30."),
            Video(id: "3", jour: "2026-11-04", compte: "kryva", statut: "a_choisir"),
            Video(id: "4", jour: "2026-11-03", compte: "perso", sujet: "Casque 3D", statut: "tournee"),
        ]
        func jour(_ aujourdhui: String, messagesKryva: Int, messagesFreelance: Int, decisions: Int) -> [ElementJournee] {
            MaJournee.construire(aujourdhui: aujourdhui,
                                 rendezVous: [EntreeJournee(titre: "Salle", debut: date("2026-11-03 08:00"), fin: date("2026-11-03 09:00"))],
                                 taches: [EntreeJournee(titre: "Poster la story", debut: date("2026-11-03 10:00"))],
                                 videos: videos, messagesKryva: messagesKryva, messagesFreelance: messagesFreelance, decisions: decisions)
        }
        var sorties: [String] = []
        for (k, f, d) in [(2, 1, 1), (1, 0, 3), (0, 0, 0)] {
            let e = jour("2026-11-03", messagesKryva: k, messagesFreelance: f, decisions: d)
            sorties += e.filter { $0.genre != .rendezVous && $0.genre != .tache }.map(\.titre)
            sorties.append(MaJournee.resume(e))
        }
        sorties += jour("2026-11-07", messagesKryva: 0, messagesFreelance: 0, decisions: 0).map(\.titre)
        sorties += MaJournee.cadreSemaine.map(\.titre) + MaJournee.cadreSamedi.map(\.titre)
        sorties += Report.allCases.map(\.libelle)
        return sorties
    }

    func testLaJourneeSortSansFrancais() {
        for langue in langues {
            Loc.langue = langue
            let sorties = sortiesJournee()
            XCTAssertGreaterThan(sorties.count, 15)
            // « Casque 3D » et « 2 ans » sont des données ; le sujet d'une vidéo n'a pas de mot français de toute façon.
            XCTAssertEqual(francais(sorties, langue, ignorer: ["Poster la story"]), [], langue)
        }
    }

    func testUnSeulMessageOuUnePluriel() {
        let cas = [(1, 0, 0), (2, 0, 0), (0, 1, 0), (0, 3, 0), (0, 0, 1), (0, 0, 4)]
        func titres(_ langue: String) -> [String] {
            Loc.langue = langue
            return cas.map { k, f, d in
                let e = MaJournee.construire(aujourdhui: "2026-11-03", rendezVous: [], taches: [], videos: [],
                                             messagesKryva: k, messagesFreelance: f, decisions: d)
                return e.first { $0.id == (k > 0 ? "prospects-kryva" : f > 0 ? "prospects-freelance" : "decisions") }?.titre ?? ""
            }
        }
        XCTAssertEqual(titres("en"), ["KRYVA tradespeople: 1 message ready to send", "KRYVA tradespeople: 2 messages ready to send",
                                      "Freelance: 1 message ready to send", "Freelance: 3 messages ready to send",
                                      "1 decision to make", "4 decisions to make"])
        let es = titres("es")
        XCTAssertEqual(Set(es).count, 6)
        XCTAssertTrue(es[0].contains("1 mensaje ") && es[1].contains("2 mensajes "), es.joined(separator: " | "))
        // Le français ne change pas.
        XCTAssertEqual(titres("fr"), ["Artisans KRYVA : 1 message prêt à envoyer", "Artisans KRYVA : 2 messages prêts à envoyer",
                                      "Freelance : 1 message prêt à envoyer", "Freelance : 3 messages prêts à envoyer",
                                      "1 décision à prendre", "4 décisions à prendre"])
    }

    // MARK: Demain prêt ?

    private func sortiesDemain() -> [String] {
        func video(_ jour: String, _ compte: String, _ statut: String, _ sujet: String = "Sujet") -> Video {
            Video(id: UUID().uuidString, jour: jour, compte: compte, sujet: sujet, statut: statut)
        }
        func contact(_ espace: String, _ date: String) -> Contact {
            Contact(id: UUID().uuidString, espace: espace, etape: "contacte", prochaineDate: date)
        }
        func bilan(_ aujourdhui: String, videos: [Video] = [], contacts: [Contact] = [], messages: [MessageDemain] = [],
                   taches: [TacheDemain]? = [], acces: Bool = true, ouvertes: Int = 0, attente: Int = 0) -> BilanDemain {
            DemainPret.controler(aujourdhui: aujourdhui, videos: videos, contacts: contacts, messages: messages, taches: taches,
                                 accesRappels: acces, decisionsOuvertes: ouvertes, reponsesEnAttente: attente)
        }
        var bilans: [BilanDemain] = []
        // Un soir de semaine : tout manque, puis tout va bien, puis les pluriels et les cas limites.
        bilans.append(bilan("2026-11-03", ouvertes: 1, attente: 1))
        bilans.append(bilan("2026-11-03", videos: [video("2026-11-04", "kryva", "tournee"), video("2026-11-04", "perso", "annulee")],
                            contacts: [contact("kryva", "2026-11-04")], taches: nil, acces: false))
        bilans.append(bilan("2026-11-03", videos: [video("2026-11-04", "kryva", "prete"), video("2026-11-04", "perso", "valide")],
                            contacts: [contact("kryva", "2026-11-04"), contact("freelance", "2026-11-04"), contact("freelance", "2026-11-04")],
                            messages: [MessageDemain(espace: "kryva", jour: "2026-11-04", statut: "prepare"),
                                       MessageDemain(espace: "kryva", jour: "2026-11-04", statut: "a_valider"),
                                       MessageDemain(espace: "freelance", jour: "2026-11-04", statut: "a_refaire", nom: "Jean-Marc")],
                            taches: [TacheDemain(titre: "Envoyer 3 mails aux vignerons", liste: "Freelance", jour: "2026-11-04"),
                                     TacheDemain(titre: "Appeler 4 inscrits", liste: "Appels", jour: "2026-11-04"),
                                     TacheDemain(titre: "Relancer le plombier", liste: "KRYVA", jour: "2026-11-04"),
                                     TacheDemain(titre: "Facturer le garage", liste: "KRYVA", jour: "2026-11-04")],
                            ouvertes: 2, attente: 13))
        bilans.append(bilan("2026-11-03", messages: [MessageDemain(espace: "kryva", jour: "2026-11-04", statut: "prepare")],
                            taches: [], ouvertes: 0, attente: 1))
        // Le dimanche : la semaine qui vient.
        let semaine = VideoCalcul.semaine(de: "2026-11-09")
        var videos = semaine.flatMap { j in ["kryva", "perso"].map { video(j, $0, "valide") } }
        videos.append(video("", "kryva", "tournee", "Réserve KRYVA"))
        videos.append(video("", "perso", "valide", "Réserve perso"))
        bilans.append(bilan("2026-11-08", videos: videos))
        videos = videos.filter { !($0.compte == "perso" && $0.jour.isEmpty) }
        videos[0].statut = "a_choisir"; videos[2].statut = "a_choisir"
        bilans.append(bilan("2026-11-08", videos: videos))

        var sorties: [String] = []
        for b in bilans {
            for p in b.points {
                sorties += [p.titre, p.detail, p.regle, Comble.court(p.qui)]
            }
        }
        sorties += ["2026-11-09", "2026-11-10"].flatMap { [DemainPret.libelleJour($0), DemainPret.libelleJourCourt($0)] }
        sorties += [ObjectifsCap.kryva, ObjectifsCap.freelance]
        return sorties
    }

    func testDemainPretSortSansFrancais() {
        // Les sujets, titres de rappels et noms des exemples sont des données françaises : ils ne se traduisent pas.
        let donnees = ["Sujet", "Réserve KRYVA", "Réserve perso", "Envoyer 3 mails aux vignerons", "Appeler 4 inscrits",
                       "Relancer le plombier", "Facturer le garage", "Jean-Marc"]
        for langue in langues {
            Loc.langue = langue
            let sorties = sortiesDemain()
            XCTAssertGreaterThan(sorties.count, 40)
            XCTAssertEqual(francais(sorties, langue, ignorer: donnees), [], langue)
        }
    }

    func testLesJoursSEcriventDansLaLangue() {
        Loc.langue = "fr"
        XCTAssertEqual(DemainPret.libelleJour("2026-11-09"), "lun. 9 nov.")
        XCTAssertEqual(DemainPret.libelleJourCourt("2026-11-09"), "lun. 9")
        Loc.langue = "en"
        XCTAssertTrue(DemainPret.libelleJour("2026-11-09").hasPrefix("Mon"), DemainPret.libelleJour("2026-11-09"))
        XCTAssertTrue(DemainPret.libelleJour("2026-11-09").contains("Nov"), DemainPret.libelleJour("2026-11-09"))
        Loc.langue = "es"
        XCTAssertTrue(DemainPret.libelleJour("2026-11-09").hasPrefix("lun"), DemainPret.libelleJour("2026-11-09"))
        XCTAssertTrue(DemainPret.libelleJour("2026-11-09").contains("nov"), DemainPret.libelleJour("2026-11-09"))
    }

    func testLesPluriels() {
        func detail(_ langue: String, _ prevus: Int, _ prets: Int, refaire: Int = 0) -> String {
            Loc.langue = langue
            let contacts = (0..<prevus).map { _ in Contact(id: UUID().uuidString, espace: "freelance", etape: "contacte", prochaineDate: "2026-11-04") }
            var messages = (0..<prets).map { _ in MessageDemain(espace: "freelance", jour: "2026-11-04", statut: "prepare") }
            messages += (0..<refaire).map { _ in MessageDemain(espace: "freelance", jour: "2026-11-04", statut: "a_refaire") }
            let b = DemainPret.controler(aujourdhui: "2026-11-03", videos: [], contacts: contacts, messages: messages, taches: [],
                                         accesRappels: true, decisionsOuvertes: 0, reponsesEnAttente: 0)
            return b.points.first { $0.id == "prospects-freelance" }!.detail
        }
        XCTAssertEqual(detail("en", 1, 1), "1 contact scheduled · 1 message prepared")
        XCTAssertEqual(detail("en", 2, 2), "2 contacts scheduled · 2 messages prepared")
        XCTAssertEqual(detail("en", 1, 1, refaire: 1), "1 contact scheduled · 1 message prepared · 1 text sent back, not redone yet")
        XCTAssertEqual(detail("fr", 1, 1), "1 contact prévu · 1 message préparé")
        XCTAssertEqual(detail("fr", 2, 2), "2 contacts prévus · 2 messages préparés")
        XCTAssertTrue(detail("es", 1, 1).contains("1 contacto "), detail("es", 1, 1))
        XCTAssertTrue(detail("es", 3, 3).contains("3 contactos "), detail("es", 3, 3))
    }

    // MARK: Séance du dimanche

    func testLaSeanceSortSansFrancais() {
        let videos = [
            Video(id: "1", jour: "2026-11-09", compte: "kryva", sujet: "À choisir", statut: "a_choisir",
                  notes: "Réseaux, 07/11.\nA : Acompte 7 jours\nB : TVA 20 % chaudière"),
            Video(id: "2", jour: "", compte: "perso", sujet: "Unslop", statut: "valide"),
        ]
        for langue in langues {
            Loc.langue = langue
            var sorties = SeanceDimanche.creneaux(videos, aujourdhui: "2026-11-08").map { SeanceDimanche.libelleCreneau(jour: $0.jour, compte: $0.compte) }
            sorties += SeanceDimanche.choixIdee.map(SeanceDimanche.libelleChoixIdee)
            sorties.append(SeanceDimanche.libelleChoixIdee("Autre"))
            XCTAssertEqual(sorties.count, 12 + 3 + 1)
            XCTAssertEqual(francais(sorties, langue, ignorer: ["Autre"]), [], langue)
            XCTAssertTrue(sorties[0].contains("9"), sorties[0])
        }
    }

    func testCeQuiPartVersUneSessionResteEnFrancais() {
        let videos = [Video(id: "1", jour: "2026-11-09", compte: "kryva", sujet: "À choisir", statut: "a_choisir")]
        let c = SeanceDimanche.creneaux(videos, aujourdhui: "2026-11-08")[0]
        Loc.langue = "fr"
        let attendu = SeanceDimanche.question(c)
        XCTAssertTrue(attendu.hasPrefix("Séance du dimanche, sujet de la vidéo lun. 9 nov."), attendu)
        for langue in langues {
            Loc.langue = langue
            XCTAssertEqual(SeanceDimanche.question(c), attendu, langue)          // écrit en base : jamais traduit
            XCTAssertEqual(Loc.langue, langue)                                   // et la langue de l'app est rendue intacte
        }
        // Les réponses envoyées à PILOTE restent les valeurs françaises de la base.
        XCTAssertEqual(SeanceDimanche.choixIdee, ["À faire cette semaine", "Au parking (relu le samedi)", "Non"])
    }

    // MARK: À toi

    private func contact(_ id: String, _ nom: String, action: String = "", date: String = "") -> Contact {
        Contact(id: id, nom: nom, prochaineAction: action, prochaineDate: date)
    }

    private func message(_ id: String, canal: String = "sms", objet: String = "", condition: String = "",
                         statut: String = "prepare", date: String = "") -> MessageAEnvoyer {
        let e = Evenement(id: id, contactId: "c-\(id)", le: "2026-11-09T08:00:00+01:00", canal: canal, sens: "sortant",
                          type: "message", texte: "Bonjour,\nOn revient vers vous.\nSacha, de l'équipe KRYVA", statut: statut, objet: objet,
                          condition: condition)
        return MessageAEnvoyer(evenement: e, contact: contact("c-\(id)", "Contact \(id)", date: date), aujourdhui: aujourdhui)
    }

    private func rappel(_ id: String, _ titre: String, liste: String, dans h: Double = 2, retard: Bool = false, notes: String = "") -> Rappel {
        Rappel(id: id, titre: titre, notes: notes, liste: liste, echeance: maintenant.addingTimeInterval(h * heure),
               enRetard: retard, priorite: 0, avecHeure: true)
    }

    private func pub(_ id: String, _ compte: String, _ etat: String, phase: String = "", titre: String = "", fichier: String = "",
                     dans h: Double = 3) -> Publication {
        Publication(id: id, compte: compte, source: "", fichier: fichier, titre: titre, texte: "",
                    prevuLe: Dates.iso.string(from: maintenant.addingTimeInterval(h * heure)), etat: etat, phase: phase,
                    raison: "", empreinte: "e-\(id)", empreinteFichier: "", taille: 0, ia: false, proposePar: "", validePar: "",
                    valideLe: "", ref: "", lien: "", conteneur: "", session: "", tentatives: 0, verifieLe: "", creeLe: "",
                    majLe: "", faitLe: "")
    }

    private func rdv(_ id: String, dans h: Double, journee: Bool = false, lieu: String = "", url: URL? = nil) -> RendezVous {
        let d = maintenant.addingTimeInterval(h * heure)
        return RendezVous(id: id, titre: "RDV \(id)", debut: d, fin: d.addingTimeInterval(heure), calendrier: "Rendez-vous",
                          journee: journee, lieu: lieu, url: url)
    }

    private func reponse(_ rang: Int, _ question: String, _ choix: String, pour: String) -> Decisions.Envoyee {
        Decisions.Envoyee(id: rang, question: question, choix: choix, pour: pour, heure: "13:10", transmise: false, enAttente: true)
    }

    /// Les données françaises de l'exemple (titres de rappels, noms, questions) : jamais traduites.
    private let donneesATOI = [
        "❓ On garde le prix à 29 € ?", "Taper push dans la session App", "Publier la release 2.2", "Relire la note de version",
        "Répondre au support", "Vérifier le paiement", "Préparer la démo", "Déclarer l'URSSAF d'octobre", "Appeler le conseiller",
        "❓ Quel sujet jeudi ?", "Le devis en 30 s", "repo-github-v3", "On part sur quelle version ?", "Release ce soir ?",
        "Sujet jeudi ?", "Prix à 29 € ?", "le devis", "la facture", "non, 39 €", "Le devis", "Le repo", "Hôpital",
        "12 rue de la Paix", "Appeler Arthur", "Vérifier le site", "Poster les stories", "Session q1", "Version A", "Version B",
        "Réseaux", "Contact", "Salle 11", "Tâche", "On garde le prix à 29 € ?", "Quel sujet jeudi ?", "Votre devis",
        "Bonjour,\nOn revient vers vous.\nSacha, de l'équipe KRYVA", "Bonjour, On revient vers vous. Sacha, de l'équipe KRYVA",
    ]

    private func sourcesATOI() -> SourcesATOI {
        let mailOk = message("m1", canal: "mail", objet: "Votre devis")
        let mailBloque = message("m2", canal: "mail", objet: "")
        var s = SourcesATOI(maintenant: maintenant)
        s.aValider = [message("t1", statut: "a_valider"), message("t2", statut: "a_valider")]
        s.aEnvoyer = [mailOk, mailBloque, message("m3"), message("m4", condition: "après le test"), message("m5", date: "2026-11-12")]
        s.candidatsFile = [CandidatFile(evenement: mailOk.evenement, contact: mailOk.contact, jour: mailOk.jour, refus: [], aujourdhui: aujourdhui),
                           CandidatFile(evenement: mailBloque.evenement, contact: mailBloque.contact, jour: mailBloque.jour,
                                        refus: ["objet vide"], aujourdhui: aujourdhui)]
        var a = ActiviteSession(id: "q1")
        a.question = "On part sur quelle version ?"; a.questionRef = "session:q1:1"; a.choix = ["Version A", "Version B"]
        a.depuis = maintenant.addingTimeInterval(-heure)
        s.questions = [QuestionATOI(activite: a, nom: "Session q1")]
        s.rappels = [
            rappel("d1", "❓ On garde le prix à 29 € ?", liste: "KRYVA", notes: "Option 1 : oui\nOption 2 : non, 39 €"),
            rappel("d3", "❓ Quel sujet jeudi ?", liste: "KRYVA"),
            rappel("k1", "Sacha : taper push dans la session App", liste: "KRYVA", dans: -0.5),
            rappel("k2", "Publier la release 2.2", liste: "KRYVA", dans: -30, retard: true),
            rappel("k3", "Relire la note de version", liste: "KRYVA", dans: 3),
            rappel("k4", "Répondre au support", liste: "KRYVA", dans: 4),
            rappel("k5", "Vérifier le paiement", liste: "KRYVA", dans: 5),
            rappel("k6", "Préparer la démo", liste: "KRYVA", dans: 6),
            rappel("p1", "Déclarer l'URSSAF d'octobre", liste: "Papiers", dans: -50, retard: true),
        ]
        s.decisionsAVenir = [rappel("d2", "❓ Quel sujet jeudi ?", liste: "Contenu", dans: 72, notes: "A : le devis\nB : la facture")]
        s.rappelsDemain = [rappel("j1", "Appeler le conseiller", liste: "Papiers", dans: 20)]
        s.dus = [contact("c1", "Arthur", action: "Sacha : appeler Arthur", date: "2026-11-08")]
        s.publications = [pub("v1", "yt-kryva", "a_valider", titre: "Le devis en 30 s"),
                          pub("v2", "tt-perso", "envoye", phase: "boite", fichier: "/x/repo-github-v3.mp4"),
                          pub("v3", "ig-perso", "planifie")]
        s.rendezVous = [rdv("r1", dans: 1, url: URL(string: "https://meet.google.com/abc")), rdv("r2", dans: 3, lieu: "Hôpital\n12 rue de la Paix")]
        s.videos = [Video(id: "a", jour: "2026-11-10", compte: "kryva", sujet: "Le devis", statut: "valide"),
                    Video(id: "b", jour: aujourdhui, compte: "perso", sujet: "Le repo", statut: "prete")]
        s.reponses = [reponse(41, "Release ce soir ?", "Oui", pour: "App"), reponse(42, "Sujet jeudi ?", "Le devis", pour: "Réseaux"),
                      reponse(44, "Prix à 29 € ?", "Oui", pour: "App")]
        return s
    }

    private func textes(_ lignes: [GesteSacha]) -> [String] {
        lignes.flatMap { g -> [String] in
            let propres = [g.verbe, g.objet, g.contexte, g.bouton] + g.choix
            if case .groupe(let l) = g.genre { return propres + textes(l) }
            return propres
        }
    }

    func testAToiSortSansFrancais() {
        for langue in langues {
            Loc.langue = langue
            let s = sourcesATOI()
            let lignes = GesteSacha.grouper(GesteSacha.du(s))
            var sorties = textes(lignes)
            XCTAssertGreaterThan(sorties.count, 40)
            // Une ligne oubliée : l'alerte dit ce qui manque (1 chose, puis 3), dans la langue de l'app.
            let sans = lignes.filter { $0.id != "rappel:p1" }
            let manque = ControleATOI.manquants(s, lignes: sans)
            XCTAssertEqual(manque.count, 1)
            sorties += manque
            sorties.append(ControleATOI.alerte(manque) ?? "")
            sorties.append(ControleATOI.alerte(manque + manque + manque) ?? "")
            // Les horaires et les dates viennent d'aides partagées (Libelles, Dates) : on ne juge ici que les phrases de la journée.
            let instants = (s.rappels + s.decisionsAVenir + s.rappelsDemain).compactMap(\.echeance) + [maintenant.addingTimeInterval(3 * heure)]
            let aides = instants.flatMap { [Libelles.quand($0, maintenant: maintenant), Libelles.jourHeure($0)] }
                + ["2026-11-10", "2026-11-12"].map { Dates.court($0) }
            let trouves = francais(sorties, langue, ignorer: donneesATOI + aides)
            XCTAssertEqual(trouves, [], langue)
        }
    }

    func testAToiPetitsPluriels() {
        var s = SourcesATOI(maintenant: maintenant)
        s.rappelsDemain = [rappel("j1", "Appeler le conseiller", liste: "Papiers", dans: 20)]
        func demain(_ langue: String) -> String? { Loc.langue = langue; return GesteSacha.du(s).last?.objet }
        XCTAssertEqual([demain("fr"), demain("en")], ["1 tâche", "1 task"])
        s.rappelsDemain.append(rappel("j2", "Payer la cantine", liste: "Papiers", dans: 21))
        XCTAssertEqual([demain("fr"), demain("en")], ["2 tâches", "2 tasks"])
        XCTAssertNotEqual(demain("es"), demain("en"))

        // Les réponses à envoyer : « ta réponse » / « tes 3 réponses », et le bouton qui les envoie toutes.
        let un = [reponse(41, "Release ce soir ?", "Oui", pour: "App")]
        let trois = un + [reponse(42, "Sujet jeudi ?", "Le devis", pour: "Réseaux"), reponse(44, "Prix à 29 € ?", "Oui", pour: "App")]
        Loc.langue = "en"
        XCTAssertEqual([GesteSacha.reponses(un).objet, GesteSacha.reponses(trois).objet], ["your reply", "your 3 replies"])
        XCTAssertEqual(GesteSacha.reponses(trois).bouton, "Send All (3)")
        Loc.langue = "fr"
        XCTAssertEqual([GesteSacha.reponses(un).objet, GesteSacha.reponses(trois).objet], ["ta réponse", "tes 3 réponses"])
        XCTAssertEqual(GesteSacha.reponses(trois).bouton, "Tout envoyer (3)")

        // L'alerte d'un oubli : 1 chose, puis plusieurs.
        XCTAssertEqual(ControleATOI.alerte(["tâche « X »"]), "À toi : 1 chose ne s'affiche pas (tâche « X »). PILOTE est à prévenir.")
        XCTAssertEqual(ControleATOI.alerte(["a", "b"]), "À toi : 2 choses ne s'affichent pas (a, b). PILOTE est à prévenir.")
        Loc.langue = "en"
        XCTAssertEqual(ControleATOI.alerte(["a", "b"]), "For you: 2 things aren't showing (a, b). PILOTE needs to be notified.")
    }

    /// Les étiquettes « But / Docs / Fini quand » s'affichent dans la langue de l'app : ce qu'on tape dans les notes d'un
    /// rappel avec l'étiquette lue à l'écran doit se relire, en français comme en anglais ou en espagnol.
    func testLesNotesSeLisentAvecLesEtiquettesDeChaqueLangue() {
        let fr = NotesPlanning.lire("But : 3 démos prises\nDocs : https://exemple.fr/a\nFini quand : les 9 ont été appelés")
        let en = NotesPlanning.lire("Goal: 3 demos booked\nDocs: https://exemple.fr/a\nDone when: all 9 were called")
        let es = NotesPlanning.lire("Objetivo: 3 demos reservadas\nDocumentos: https://exemple.fr/a\nHecho cuando: se llamó a los 9")
        XCTAssertEqual([fr.but, en.but, es.but], ["3 démos prises", "3 demos booked", "3 demos reservadas"])
        XCTAssertEqual([fr.finiQuand, en.finiQuand, es.finiQuand], ["les 9 ont été appelés", "all 9 were called", "se llamó a los 9"])
        XCTAssertEqual([fr.docs.count, en.docs.count, es.docs.count], [1, 1, 1])
        // Un mot qui commence comme une étiquette n'en est pas une.
        XCTAssertNil(NotesPlanning.lire("Butter : du beurre\nGoalie: x").but)
    }

    /// Les boutons se reconnaissent par leur action, jamais par leur texte : une décision sans option se règle en une langue
    /// comme en une autre.
    func testLesActionsNeDependentPasDuTexteDesBoutons() {
        var s = SourcesATOI(maintenant: maintenant)
        s.rappels = [rappel("d9", "❓ Que faire ?", liste: "KRYVA")]
        var actions: [String] = []
        for langue in ["fr", "en", "es"] {
            Loc.langue = langue
            let g = GesteSacha.du(s).first { $0.id == "decision:d9" }!
            XCTAssertTrue(g.reglable, langue)
            XCTAssertFalse(g.bouton.isEmpty, langue)
            actions.append("\(g.action)")
        }
        XCTAssertEqual(Set(actions).count, 1)
    }
}
