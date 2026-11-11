// L'écran unique et les agents en anglais et en espagnol (10/11) : les fonctions de Shared/Domaines.swift, Sessions, AlerteArret
// tournent sur les données d'exemple de DomainesTests ; aucune sortie ne garde de mot français, hors les données d'exemple
// volontairement françaises (noms, titres de cartes, textes écrits par une session). Les vues SwiftUI (App/Vues) ne sont pas dans
// la cible de test : leurs textes calculés passent par les mêmes fonctions de Shared.
import XCTest

final class LangueDomainesTests: XCTestCase {
    override func setUp() {
        Loc.dossierBundle = Bundle(for: Self.self).bundleURL
        // Copie publique : le dépôt suivi vient de reglages.json, pas d'un chemin écrit en dur.
        Reglages.remplacement = { var r = EssaiPrincipal.reglages; r.depotSuivi = "/Users/x/Projects/app"; return r }()
    }
    override func tearDown() { Loc.dossierBundle = nil; Loc.langue = "fr"; Reglages.remplacement = EssaiPrincipal.reglages }

    /// Lundi 9 novembre 2026, 10 h (heure de Paris), comme DomainesTests.
    let maintenant: Date = {
        var c = DateComponents(); c.year = 2026; c.month = 11; c.day = 9; c.hour = 10
        c.timeZone = TimeZone(identifier: "Europe/Paris")
        return Calendar(identifier: .gregorian).date(from: c)!
    }()
    let jour: TimeInterval = 86_400
    let langues = ["en", "es"]

    private func heure(_ h: Int, _ m: Int = 0, jour j: Int = 9) -> Date {
        var c = DateComponents(); c.year = 2026; c.month = 11; c.day = j; c.hour = h; c.minute = m
        c.timeZone = TimeZone(identifier: "Europe/Paris")
        return Calendar(identifier: .gregorian).date(from: c)!
    }

    /// Les morceaux d'exemple volontairement français : ce que les sessions et Sacha ont écrit (titres de cartes, de tâches,
    /// « pourquoi »), les noms de personnes ; l'écran ne les traduit pas.
    private let donneesFrancaises = [
        "Appeler Arthur", "Vérifier le site", "Une tâche courte n'est plus coupée", "Barre du bas au choix", "Compte déconnecté, il faut le relier",
        "Publier la vidéo TikTok", "Ranger les passations", "Relever les vues", "Écrire la légende", "Préparer la miniature",
        "Monter la vidéo de demain", "Trier les rushs", "Vérifier le 1er paiement de Yanis", "Relancer Yanis", "Préparer le webhook Stripe",
        "Prod Supabase pas lue", "Pas urgent : PILOTE la lit quand Chrome sera reconnecté", "Trier la liste", "Relire les réponses",
        "Liste du jour triée", "Mutuelle résiliée", "Payer la CFE", "Déclarer l'URSSAF", "Mot de passe du compte de test Apple",
        "Version iPhone 2.0.2 : build chez Apple", "Pub (option A) : lien montré", "Dossier d'inscription", "On attend l'académie",
        "l'académie", "SMS à Pascal validé", "Devis Lucie relu", "Fiche Yanis", "Classification d'âge Apple : on répond 4+ ?",
        "Envoyer la convention ?", "Relire la fiche App Store", "Pas à moi", "Carte ",
    ]

    private func publication(_ id: String, _ compte: String, _ etat: String, phase: String = "", dans heures: Double) -> Publication {
        Publication(id: id, compte: compte, source: "", fichier: "", titre: "Vidéo \(id)", texte: "",
                    prevuLe: Dates.iso.string(from: maintenant.addingTimeInterval(heures * 3600)), etat: etat, phase: phase,
                    raison: "", empreinte: "", empreinteFichier: "", taille: 0, ia: false, proposePar: "", validePar: "", valideLe: "",
                    ref: "", lien: "", conteneur: "", session: "", tentatives: 0, verifieLe: "", creeLe: "", majLe: "", faitLe: "")
    }

    /// Les données de Tests/DomainesTests.swift, une situation par source : de quoi passer par chaque phrase de l'écran unique.
    private func scenarios() -> [SourcesDomaines] {
        let il = Dates.iso.string(from: maintenant.addingTimeInterval(-3600))
        let commits = [
            CommitKryva(hash: "a", sujet: "fix(planning): une tâche courte n'est plus coupée", le: maintenant.addingTimeInterval(-2 * jour), enLigne: true),
            CommitKryva(hash: "b", sujet: "feat: barre du bas au choix", le: maintenant.addingTimeInterval(-jour), enLigne: false, branche: "feat/x"),
        ]
        let pushDemain = TacheDomaine(id: "P", titre: "Sacha : push KRYVA", echeance: heure(13, 35, jour: 10), faite: false, faiteLe: nil)
        let pushPasse = TacheDomaine(id: "P", titre: "Sacha : push KRYVA", echeance: heure(9), faite: false, faiteLe: nil)
        let commitsMain = [CommitKryva(hash: "a", sujet: "feat: x", le: maintenant, enLigne: false),
                           CommitKryva(hash: "b", sujet: "fix: y", le: maintenant, enLigne: false)]
        let rappel = TacheDomaine(id: "BE8CC75D-EEF0-439B-8AE1-95C1B3F4410C", titre: "Mot de passe du compte de test Apple",
                                  echeance: maintenant.addingTimeInterval(8 * 3600 + 25 * 60), faite: false, faiteLe: nil)
        var rappelFait = rappel; rappelFait.faite = true; rappelFait.faiteLe = maintenant
        let titreQ = "❓ Classification d'âge Apple : on répond 4+ ?"
        let question = TacheDomaine(id: "Q1", titre: titreQ, echeance: nil, faite: false, faiteLe: nil, domaine: .app, decision: true)
        let carteApp = CarteDomaine(id: "v202", domaine: .app, etat: .enCours, texte: "Version iPhone 2.0.2 : build chez Apple", auteur: "App",
                                    majLe: il, attend: "Sacha", rappel: "BE8CC75D")
        let cartesQuiAttendent = [
            carteApp,
            CarteDomaine(id: "pub", domaine: .app, etat: .enCours, texte: "Pub (option A) : lien montré", auteur: "App", majLe: il, attend: "PILOTE"),
            CarteDomaine(id: "bts", domaine: .papiers, etat: .pasPuFaire, texte: "Dossier d'inscription", pourquoi: "On attend l'académie",
                         auteur: "Papiers", majLe: il, attend: "l'académie"),
        ]
        func pret(_ id: String, _ texte: String, attend: String) -> CarteDomaine {
            CarteDomaine(id: id, domaine: .ventes, etat: .prepare, texte: texte, auteur: "Ventes", majLe: il, attend: attend)
        }
        let ventesSession = SessionDomaine(id: "v", titre: "KRYVA · Ventes", etat: "idle", depuis: maintenant.addingTimeInterval(-7200))
        let futur = TravailAgent(id: "f", titre: "Vérifier le 1er paiement de Yanis", domaine: .ventes, prevu: heure(16, 30, jour: 12),
                                 faite: false, faiteLe: nil)
        let enRetard = TravailAgent(id: "r", titre: "Relancer Yanis", domaine: .ventes, prevu: heure(8, 30), faite: false, faiteLe: nil)
        let lucie = ResumeContact(id: "k3", nom: "Lucie", espace: "kryva", dernierLe: "2026-11-09T08:12:00Z", dernierSens: "entrant",
                                  dernierCanal: "mail", recus: 1)
        func travail(_ id: String, _ titre: String, prevu: Date?, faite: Bool = false, faiteLe: Date? = nil, d: Domaine = .reseaux) -> TravailAgent {
            TravailAgent(id: id, titre: titre, domaine: d, prevu: prevu, faite: faite, faiteLe: faiteLe)
        }
        func carte(_ id: String, _ etat: CaseDomaine, auteur: String) -> CarteDomaine {
            CarteDomaine(id: id, domaine: .reseaux, etat: etat, texte: "Carte \(id)", auteur: auteur,
                         majLe: Dates.iso.string(from: maintenant.addingTimeInterval(-3600)))
        }
        return [
            // App : en ligne, prêt sur une branche
            SourcesDomaines(maintenant: maintenant, commits: commits),
            // App : le push de demain, celui dont l'heure est passée, le dépôt illisible
            SourcesDomaines(maintenant: maintenant, commits: commitsMain, push: pushDemain),
            SourcesDomaines(maintenant: maintenant, commits: commitsMain, push: pushPasse),
            SourcesDomaines(maintenant: maintenant, commits: nil),
            // Ventes et Freelance : une phrase par personne
            SourcesDomaines(maintenant: maintenant, contacts: [
                ResumeContact(id: "k1", nom: "Jean", entreprise: "Moreau", espace: "kryva",
                              prochaineAction: "Lun. 16/11 : Ventes relit Gmail (14b05237). Sans réponse : relance", prochaineDate: "2026-11-16",
                              dernierLe: "2026-11-09T08:00:00Z", dernierSens: "sortant", dernierCanal: "sms", partis: 2),
                ResumeContact(id: "k3", nom: "Lucie", espace: "kryva", dernierLe: "2026-11-08T09:00:00Z", dernierSens: "entrant",
                              dernierCanal: "mail", recus: 1),
                ResumeContact(id: "k4", nom: "Arthur", espace: "kryva", prochaineAction: "Sacha : appeler Arthur. Ensuite classer",
                              prochaineDate: "2026-11-06"),
                ResumeContact(id: "k5", nom: "Karl", espace: "kryva", partis: 1, aPartir: 1),
                ResumeContact(id: "k6", nom: "Omar", espace: "kryva", echecs: 1),
                ResumeContact(id: "f1", nom: "Julien", espace: "freelance", aPartir: 1, prets: 1, envoiLe: "2026-11-16",
                              envoiSousCondition: true),
                ResumeContact(id: "f2", nom: "Nadia", espace: "freelance", aPartir: 2, prets: 2, envoiLe: "2026-11-10"),
            ]),
            // Réseaux : ce qui part tout seul, la boîte TikTok
            SourcesDomaines(maintenant: maintenant, publications: [
                publication("a", "yt-kryva", "envoye", dans: 8),
                publication("b", "ig-perso", "planifie", dans: 25),
                publication("c", "tt-perso", "envoye", phase: "boite", dans: 2),
            ]),
            // Papiers : échéances, puis Rappels inaccessibles
            SourcesDomaines(maintenant: maintenant, taches: [
                TacheDomaine(id: "1", titre: "Déclarer l'URSSAF", echeance: maintenant.addingTimeInterval(3 * jour), faite: false, faiteLe: nil),
                TacheDomaine(id: "2", titre: "Payer la CFE", echeance: maintenant.addingTimeInterval(-jour), faite: false, faiteLe: nil),
                TacheDomaine(id: "3", titre: "Kbis", echeance: nil, faite: true, faiteLe: maintenant.addingTimeInterval(-2 * jour)),
            ]),
            SourcesDomaines(maintenant: maintenant, taches: nil, rappelsSacha: nil),
            // Qui tient chaque domaine
            SourcesDomaines(maintenant: maintenant, sessions: [
                SessionDomaine(id: "s1", titre: "KRYVA · App et interface", etat: "busy", depuis: maintenant.addingTimeInterval(-7200), etape: "Tests", k: 3, n: 5),
                SessionDomaine(id: "s1b", titre: "Correctif planning", dossier: "/Users/x/Projects/app", etat: "busy"),
                SessionDomaine(id: "s2", titre: "KRYVA · Réseaux, image, événements", etat: "waiting", question: "Quelle musique ?"),
                SessionDomaine(id: "s3", titre: "FREELANCE", etat: "idle", depuis: maintenant.addingTimeInterval(-7200)),
                SessionDomaine(id: "s4", titre: "KRYVA · Ventes", etat: "waiting"),
            ]),
            // Le travail d'agent : fait, prévu, en retard, sans heure
            SourcesDomaines(maintenant: maintenant, travaux: [
                travail("1", "Monter la vidéo de demain", prevu: heure(8), faite: true, faiteLe: heure(9, 12)),
                travail("2", "Écrire la légende", prevu: heure(18)),
                travail("3", "Préparer la miniature", prevu: heure(12, 30)),
                travail("4", "Relever les vues", prevu: heure(7)),
                travail("5", "Trier les rushs", prevu: nil),
                travail("7", "Pas à moi", prevu: heure(11), d: .ventes),
                travail("8", "Ranger les passations", prevu: heure(12), d: .pilote),
            ]),
            // Les cartes : fait par, à faire, en cours, préparé, pas pu faire avec son pourquoi
            SourcesDomaines(maintenant: maintenant, cartes: [
                carte("f", .fait, auteur: "KRYVA · Réseaux, image, événements"), carte("a", .aFaire, auteur: ""),
                carte("c", .enCours, auteur: "Réseaux"), carte("p", .prepare, auteur: "session"),
                CarteDomaine(id: "pp", domaine: .reseaux, etat: .pasPuFaire, texte: "Publier la vidéo TikTok",
                             pourquoi: "Compte déconnecté, il faut le relier", auteur: "Réseaux", majLe: Dates.iso.string(from: maintenant)),
            ]),
            // Ce qui attend passe avant la reprise ; la pause dit pourquoi
            SourcesDomaines(maintenant: maintenant, contacts: [lucie], sessions: [ventesSession], travaux: [futur, enRetard]),
            SourcesDomaines(maintenant: maintenant, sessions: [ventesSession], travaux: [futur]),
            SourcesDomaines(maintenant: maintenant, cartes: [
                CarteDomaine(id: "a", domaine: .ventes, etat: .aFaire, texte: "Trier la liste", auteur: "Ventes"),
                CarteDomaine(id: "b", domaine: .ventes, etat: .aFaire, texte: "Relire les réponses", auteur: "Ventes"),
            ], sessions: [ventesSession]),
            SourcesDomaines(maintenant: maintenant, cartes: [
                CarteDomaine(id: "p", domaine: .app, etat: .pasPuFaire, texte: "Prod Supabase pas lue",
                             pourquoi: "Pas urgent : PILOTE la lit quand Chrome sera reconnecté", auteur: "App"),
            ], sessions: [SessionDomaine(id: "a", titre: "App et interface", etat: "idle", depuis: maintenant.addingTimeInterval(-3000))],
               travaux: [TravailAgent(id: "w", titre: "Préparer le webhook Stripe", domaine: .app, prevu: heure(9, jour: 11), faite: false, faiteLe: nil)]),
            SourcesDomaines(maintenant: maintenant, sessions: [
                SessionDomaine(id: "p", titre: "PILOTE", etat: "idle", depuis: maintenant.addingTimeInterval(-3600)),
            ], travaux: [TravailAgent(id: "1", titre: "Ranger les passations", domaine: .pilote, prevu: heure(12), faite: false, faiteLe: nil)]),
            // Une carte qui attend Sacha, PILOTE ou un tiers ; le rappel manque ou est fait ; une décision ; ce qui est prêt
            SourcesDomaines(maintenant: maintenant, cartes: cartesQuiAttendent, commits: [], taches: [], rappelsSacha: [rappel]),
            SourcesDomaines(maintenant: maintenant, cartes: [carteApp], commits: [], taches: [], rappelsSacha: []),
            SourcesDomaines(maintenant: maintenant, cartes: [carteApp], commits: [], taches: [], rappelsSacha: [rappelFait]),
            SourcesDomaines(maintenant: maintenant, cartes: [], commits: [], taches: [], rappelsSacha: [question]),
            SourcesDomaines(maintenant: maintenant, cartes: [
                pret("a", "SMS à Pascal validé", attend: "Ventes"), pret("b", "Devis Lucie relu", attend: "PILOTE"), pret("c", "Fiche Yanis", attend: ""),
            ]),
        ]
    }

    /// Tout ce qu'une ligne de domaine montre, texte par texte (titres de lignes compris : « Décider : … » vient de l'app).
    private func textes(_ e: EtatDomaine) -> [String] {
        var r = [e.domaine.titre, e.domaine.agent, e.domaine.motRouge, e.qui, e.resume, e.bilanTexte]
        if let x = e.erreur { r.append(x) }
        r += e.pastilles.map(\.texte) + e.bilan.map(\.texte)
        for s in e.sections { r.append(s.titre); r += s.elements.flatMap { [$0.titre, $0.detail] } }
        for (c, els) in e.cases { r.append(c.titre); r += els.flatMap { [$0.titre, $0.detail] } }
        return r.filter { !$0.isEmpty }
    }

    // MARK: Dates, heures, durées

    func testDatesEtDureesEnAnglais() {
        Loc.langue = "en"
        XCTAssertEqual(Libelles.quand(heure(12), maintenant: maintenant), "today at 12:00")
        XCTAssertEqual(Libelles.quand(heure(11, jour: 10), maintenant: maintenant), "tomorrow at 11:00")
        XCTAssertEqual(Libelles.quand(heure(17, jour: 12), maintenant: maintenant), "Thu 12/11 at 17:00")
        XCTAssertEqual(Libelles.quand(heure(0, jour: 23), maintenant: maintenant), "Mon 23/11")
        XCTAssertEqual(Libelles.depuisLe(heure(18, 40, jour: 8), maintenant: maintenant), "yesterday 18:40")
        XCTAssertEqual(Libelles.depuisLe(heure(9, jour: 5), maintenant: maintenant), "Thu 05/11")
        XCTAssertEqual(Libelles.depuisLe(heure(0), maintenant: maintenant), "today")
        XCTAssertEqual(Libelles.depuisLe(heure(14, 12), maintenant: maintenant), "14:12")
        XCTAssertEqual(Libelles.heureCourte(heure(13, 35)), "13:35")
        XCTAssertEqual(Libelles.heureCourte(heure(18)), "18:00")
        XCTAssertEqual(Libelles.jourCourt(heure(18, jour: 10)), "10/11")
        XCTAssertEqual(Libelles.jourHeure(heure(14, 5, jour: 10)), "10/11 at 14:05")
        XCTAssertEqual(Libelles.depuis(maintenant.addingTimeInterval(-50 * 60), maintenant: maintenant), "50 min")
        XCTAssertEqual(Libelles.depuis(maintenant.addingTimeInterval(-7200), maintenant: maintenant), "2 h")
        XCTAssertEqual(Libelles.depuis(maintenant.addingTimeInterval(-3 * jour), maintenant: maintenant), "3 d")
    }

    func testDatesEtDureesEnEspagnol() {
        Loc.langue = "es"
        XCTAssertEqual(Libelles.quand(heure(12), maintenant: maintenant), "hoy a las 12:00")
        XCTAssertEqual(Libelles.quand(heure(11, jour: 10), maintenant: maintenant), "mañana a las 11:00")
        XCTAssertTrue(Libelles.quand(heure(17, jour: 12), maintenant: maintenant).hasPrefix("el "), "le jour de la semaine, en espagnol")
        XCTAssertTrue(Libelles.quand(heure(17, jour: 12), maintenant: maintenant).hasSuffix("12/11 a las 17:00"))
        XCTAssertEqual(Libelles.depuisLe(heure(18, 40, jour: 8), maintenant: maintenant), "ayer 18:40")
        XCTAssertEqual(Libelles.depuisLe(heure(0), maintenant: maintenant), "hoy")
        XCTAssertEqual(Libelles.heureCourte(heure(13, 35)), "13:35")
        XCTAssertEqual(Libelles.jourHeure(heure(14, 5, jour: 10)), "10/11 a las 14:05")
        XCTAssertEqual(Libelles.depuis(maintenant.addingTimeInterval(-3 * jour), maintenant: maintenant), "3 d")
    }

    func testAucunMotFrancaisDansLesDatesEtLesDurees() {
        for langue in langues {
            Loc.langue = langue
            var sorties: [String] = []
            for j in 5...12 {
                for (h, m) in [(0, 0), (9, 12), (13, 35), (18, 0)] {
                    let d = heure(h, m, jour: j)
                    sorties += [Libelles.quand(d, maintenant: maintenant), Libelles.depuisLe(d, maintenant: maintenant),
                                Libelles.heureCourte(d), Libelles.jourSemaine(d), Libelles.jourHeure(d),
                                Libelles.depuis(d, maintenant: maintenant)]
                }
            }
            for s: TimeInterval in [30, 3000, 7200, 4 * 86_400, 40 * 86_400] {
                sorties.append(Libelles.depuis(maintenant.addingTimeInterval(-s), maintenant: maintenant))
                sorties.append(AlerteArret.ecoule(s))
            }
            XCTAssertSansFrancais(sorties, "[\(langue)]")
        }
    }

    // MARK: Titres, mots des domaines, « prêt, … »

    func testTitresEtMotsDesDomaines() {
        Loc.langue = "en"
        XCTAssertEqual(Domaine.allCases.map(\.titre), ["KRYVA App", "Social", "KRYVA Sales", "Freelance", "Paperwork", "Pilote"])
        XCTAssertEqual(Domaine.allCases.map(\.motRouge), ["to fix", "to prepare", "overdue", "overdue", "to do", "to do"])
        XCTAssertEqual(CaseDomaine.allCases.map(\.titre), ["Done", "In progress", "Couldn’t do", "Prepared", "To do"])
        Loc.langue = "es"
        XCTAssertEqual(Domaine.allCases.map(\.titre), ["App KRYVA", "Redes", "Ventas KRYVA", "Freelance", "Papeleo", "Pilote"])
        for langue in langues {
            Loc.langue = langue
            var sorties = Domaine.allCases.flatMap { [$0.titre, $0.agent, $0.motRouge] }
            sorties += CaseDomaine.allCases.map(\.titre)
            sorties += [Domaines.titreProbleme, Domaines.titreEnCours, Domaines.titreFaitAujourdhui, Domaines.titreFait7Jours, Domaines.pourToi]
            XCTAssertSansFrancais(sorties, "[\(langue)]")
            // L'identifiant d'un domaine et son nom d'équipe ne changent jamais (comparés au titre réel des sessions).
            XCTAssertEqual(Domaine.reseaux.equipe, "KRYVA · Réseaux, image, événements")
            XCTAssertEqual(Domaine.reseaux.agentFrancais, "Réseaux")
            XCTAssertEqual(Domaine.reseaux.rawValue, "reseaux")
        }
    }

    func testSuitePretDansToutesLesLangues() {
        let suites: [SuitePret] = [.aucune, .attendPush, .fusionner, .partALHeure, .envoyerLeJour, .preciser("Sales"),
                                   .fairePartir("Sales"), .attend("PILOTE")]
        Loc.langue = "en"
        XCTAssertEqual(SuitePret.attendPush.titre, "Ready, waiting for your push")
        XCTAssertEqual(SuitePret.attendPush.pastille(n: 1), "1 ready, waiting for your push")
        XCTAssertEqual(SuitePret.partALHeure.pastille(n: 3), "3 ready, going out at the scheduled time")
        for langue in langues {
            Loc.langue = langue
            XCTAssertSansFrancais(suites.flatMap { [$0.titre, $0.texte(), $0.texte(pluriel: true), $0.pastille(n: 1), $0.pastille(n: 4)] },
                                  "[\(langue)]")
        }
    }

    // MARK: L'écran unique sur les données des tests existants

    func testEcranUniqueEnAnglais() {
        Loc.langue = "en"
        let s = scenarios()
        func domaine(_ d: Domaine, _ i: Int) -> EtatDomaine { Domaines.regrouper(s[i]).first { $0.domaine == d }! }
        XCTAssertEqual(domaine(.app, 0).pastilles.map(\.texte), ["Nothing for you to do"])
        XCTAssertEqual(domaine(.app, 0).bilanTexte, "1 ready, to be merged by App")
        XCTAssertEqual(domaine(.app, 1).pastilles.first?.texte, "For you: Type “push” in App (2 changes)")
        XCTAssertEqual(domaine(.app, 1).bilanTexte, "2 ready, waiting for your push")
        XCTAssertEqual(domaine(.app, 1).elements(.prepare).first?.detail, "Ready in main, goes out with your push tomorrow at 13:35")
        XCTAssertEqual(domaine(.app, 2).sections.first?.elements.first?.detail, "Overdue · scheduled today at 09:00")
        XCTAssertNotNil(domaine(.app, 3).erreur)
        XCTAssertEqual(domaine(.ventes, 4).pastilles.map(\.texte), ["For you: Appeler Arthur (scheduled for 06/11)"])
        XCTAssertEqual(domaine(.freelance, 4).bilanTexte, "2 ready, to send on the scheduled day")
        XCTAssertEqual(domaine(.reseaux, 5).bilanTexte, "2 ready, going out at the scheduled time")
        XCTAssertEqual(domaine(.reseaux, 5).elements(.prepare).first?.detail, "In your TikTok inbox, for you to post · scheduled today at 12:00")
        XCTAssertEqual(domaine(.papiers, 6).pastilles.map(\.texte), ["2 for you, 1 overdue"])
        XCTAssertEqual(domaine(.papiers, 6).elements(.aFaire).first?.detail, "For you · overdue, due 08/11")
        XCTAssertNotNil(domaine(.papiers, 7).erreur)
        XCTAssertEqual(domaine(.app, 8).qui, "App working: Tests (step 3/5) · 1 other session working")
        XCTAssertEqual(domaine(.reseaux, 8).qui, "Social is waiting for your reply, in For you")
        XCTAssertEqual(domaine(.freelance, 8).qui, "FREELANCE paused for 2 h")
        XCTAssertEqual(domaine(.papiers, 8).qui, "Paperwork isn’t running")
        XCTAssertEqual(domaine(.reseaux, 9).bilanTexte, "1 problem · 3 to do by Social, 2 of them by 18:00 · 1 done today")
        XCTAssertEqual(domaine(.reseaux, 9).elements(.fait).map(\.detail), ["Done by Social today at 09:12"])
        XCTAssertEqual(domaine(.pilote, 15).qui, "PILOTE paused for 1 h · resumes today at 12:00: “Ranger les passations”")
    }

    func testEcranUniqueEnEspagnol() {
        Loc.langue = "es"
        let s = scenarios()
        func domaine(_ d: Domaine, _ i: Int) -> EtatDomaine { Domaines.regrouper(s[i]).first { $0.domaine == d }! }
        XCTAssertEqual(domaine(.app, 0).pastilles.map(\.texte), ["Nada que hacer para ti"])
        XCTAssertEqual(domaine(.app, 0).bilanTexte, "1 listo, para que lo fusione App")
        XCTAssertEqual(domaine(.app, 1).pastilles.first?.texte, "Para ti: Escribe «push» en App (2 cambios)")
        XCTAssertEqual(domaine(.papiers, 6).pastilles.map(\.texte), ["2 para ti, 1 atrasados"])
        XCTAssertEqual(domaine(.papiers, 8).qui, "Papeleo no está en marcha")
    }

    func testAucunMotFrancaisDansLEcranUnique() {
        for langue in langues {
            Loc.langue = langue
            for (i, s) in scenarios().enumerated() {
                for e in Domaines.regrouper(s) {
                    XCTAssertSansFrancais(textes(e), hors: donneesFrancaises, "[\(langue) scénario \(i) \(e.domaine.rawValue)]")
                }
            }
        }
    }

    /// Les textes écrits aux agents (boutons « Relancer ») restent en français : les sessions travaillent en français.
    func testLesConsignesAuxAgentsRestentEnFrancais() {
        func relances() -> [String] {
            scenarios().flatMap { Domaines.regrouper($0) }.flatMap { [$0.relance, $0.relancePilote] }.compactMap { $0 }
        }
        Loc.langue = "fr"
        let enFrancais = relances()
        XCTAssertFalse(enFrancais.isEmpty)
        for langue in langues {
            Loc.langue = langue
            XCTAssertEqual(relances(), enFrancais, "[\(langue)] une consigne envoyée à une session ne se traduit pas")
        }
    }

    /// « Sacha » est écrit tel quel dans les cartes (les sessions l'écrivent en français) : hors du français, pas de « toi ».
    func testTutoyerNeToucheQueLeFrancais() {
        for langue in langues {
            Loc.langue = langue
            XCTAssertEqual(Libelles.tutoyer("Sacha : appeler Arthur"), "Sacha : appeler Arthur")
            XCTAssertEqual(Libelles.tutoyer("Attend le feu vert de Sacha"), "Attend le feu vert de Sacha")
        }
        Loc.langue = "fr"
        XCTAssertEqual(Libelles.tutoyer("Sacha : appeler Arthur"), "Toi : appeler Arthur")
    }

    // MARK: Choix des sessions, alerte d'arrêt

    func testChoixDesSessionsSeTraduisentSeulementPourAffichage() {
        let choix = ["Oui", "Non", "Ouvrir la PR", "Fusionner", "Réparer la CI", "Traiter les commentaires", "Résoudre les conflits",
                     "Vérifier", "Archiver", "Nouvelle session"]
        Loc.langue = "en"
        XCTAssertEqual(choix.map(Sessions.libelleChoix), ["Yes", "No", "Open the PR", "Merge", "Fix the CI", "Address Comments",
                                                          "Resolve Conflicts", "Verify", "Archive", "New Session"])
        XCTAssertEqual(Sessions.libelleChoix("Plutôt la 2"), "Plutôt la 2")          // un libellé écrit par la session reste tel quel
        for langue in langues {
            Loc.langue = langue
            XCTAssertSansFrancais(choix.map(Sessions.libelleChoix), "[\(langue)]")
        }
    }

    func testAlerteArretEnAnglaisEtEspagnol() {
        var paris = Calendar(identifier: .gregorian)
        paris.timeZone = TimeZone(identifier: "Europe/Paris")!
        func date(_ jour: Int, _ h: Int, _ m: Int) -> Date {
            paris.date(from: DateComponents(year: 2026, month: 11, day: jour, hour: h, minute: m))!
        }
        func lignes() -> [String] {
            AlerteArret.lignes(capteur: date(4, 10, 0), veille: nil, maintenant: date(4, 13, 0), calendrier: paris)
            + AlerteArret.lignesAnnexes(facteur: date(4, 9, 0), inscrits: nil, inscritsStatut: "CLOSED", inscritsDepuis: date(4, 9, 0),
                                        disqueLibre: 9_100_000_000, whatsapp: date(2, 9, 0), maintenant: date(4, 13, 0), calendrier: paris)
            + [AlerteArret.ligneWhatsApp(nil), AlerteArret.ligneWhatsApp(date(4, 9, 0), maintenant: date(4, 13, 0))]
        }
        Loc.langue = "en"
        let en = lignes()
        XCTAssertTrue(en.contains { $0.hasPrefix("Inbound sensor (launchd, 60 s): nothing written since 04/11 at 10:00") }, "\(en)")
        XCTAssertTrue(en.contains("Disk: 9.1 GB free on /System/Volumes/Data (threshold 10 GB)"), "\(en)")
        XCTAssertTrue(en.contains { $0.hasPrefix("Sign-ups service (inscrits-battement.json, every minute): no trace") }, "\(en)")
        Loc.langue = "es"
        let es = lignes()
        XCTAssertTrue(es.contains("Disco: 9,1 GB libres en /System/Volumes/Data (umbral: 10 GB)"), "\(es)")
        for langue in langues {
            Loc.langue = langue
            XCTAssertSansFrancais(lignes(), "[\(langue)]")
        }
    }

    // MARK: L'aide elle-même

    func testLAideReperEffectivementLeFrancais() {
        XCTAssertEqual(MotsFrancais.mots(dans: "Rien à faire pour toi, en retard depuis hier"),
                       ["rien", "à", "faire", "pour", "toi", "retard", "depuis", "hier"])
        XCTAssertEqual(MotsFrancais.mots(dans: "Aujourd'hui, l'heure n'est pas bonne"), ["aujourd", "hui", "heure", "est", "pas"])
        XCTAssertTrue(MotsFrancais.mots(dans: "Nothing for you to do, overdue since yesterday").isEmpty)
        XCTAssertTrue(MotsFrancais.mots(dans: "Nada que hacer para ti, atrasado desde ayer en la lista").isEmpty)
        XCTAssertTrue(MotsFrancais.mots(dans: "For you: Appeler Arthur", hors: ["Appeler Arthur"]).isEmpty)
        XCTAssertEqual(MotsFrancais.mots(dans: "Pilote’s database isn’t open"), [])
    }
}
