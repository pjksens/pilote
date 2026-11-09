// L'écran unique (09/11) : le regroupement par domaine (pur, sources construites à la main) et les règles de l'outil des
// cartes (plafonds, « pourquoi », longueur, tiret long, journal) sur une base temporaire. Ni dépôt git, ni Rappels, ni réseau.
import XCTest

final class DomainesTests: XCTestCase {
    /// Lundi 9 novembre 2026, 10 h (heure de Paris).
    let maintenant: Date = {
        var c = DateComponents(); c.year = 2026; c.month = 11; c.day = 9; c.hour = 10
        c.timeZone = TimeZone(identifier: "Europe/Paris")
        return Calendar(identifier: .gregorian).date(from: c)!
    }()
    let jour: TimeInterval = 86_400

    private func domaine(_ d: Domaine, _ s: SourcesDomaines) -> EtatDomaine {
        Domaines.regrouper(s).first { $0.domaine == d }!
    }

    // MARK: Regroupement

    func testSixDomainesDansLOrdre() {
        let r = Domaines.regrouper(SourcesDomaines(maintenant: maintenant))
        XCTAssertEqual(r.map(\.domaine), [.app, .reseaux, .ventes, .freelance, .papiers, .pilote])
    }

    func testAppEnLigneEtPasEnLigne() {
        let s = SourcesDomaines(maintenant: maintenant, commits: [
            CommitKryva(hash: "a", sujet: "fix(planning): une tâche courte n'est plus coupée", le: maintenant.addingTimeInterval(-2 * jour), enLigne: true),
            CommitKryva(hash: "b", sujet: "feat: barre du bas au choix", le: maintenant.addingTimeInterval(-jour), enLigne: false, branche: "feat/x"),
            CommitKryva(hash: "c", sujet: "fix: trop vieux", le: maintenant.addingTimeInterval(-9 * jour), enLigne: true),
            CommitKryva(hash: "d", sujet: "chore: .npm-cache sort de git", le: maintenant, enLigne: true),
        ])
        let e = domaine(.app, s)
        XCTAssertEqual(e.elements(.fait).map(\.titre), ["Une tâche courte n'est plus coupée"])   // préfixe retiré, « chore » écarté, > 7 j écarté
        XCTAssertEqual(e.elements(.prepare).map(\.titre), ["Barre du bas au choix"])
        XCTAssertEqual(e.elements(.prepare).first?.detail, "Prêt sur la branche feat/x, à fusionner par App")
        XCTAssertEqual(e.pastilles.map(\.texte), ["Rien à faire pour toi"])          // une branche ne part pas avec le push
        XCTAssertEqual(e.bilanTexte, "1 prêt, à fusionner par App")                    // le même mot que la section dépliée
        XCTAssertEqual(e.sections.map(\.titre), ["Prêt, à fusionner par App", "Fait ces 7 derniers jours"])
        XCTAssertFalse(e.rienDeNeuf)
    }

    func testAppIllisibleDonneUneErreur() {
        let e = domaine(.app, SourcesDomaines(maintenant: maintenant, commits: nil))
        XCTAssertNotNil(e.erreur)
        XCTAssertFalse(e.rienDeNeuf)
    }

    func testTitreCommit() {
        XCTAssertEqual(Domaines.titreCommit("fix(relances): au moins 3 jours"), "Au moins 3 jours")
        XCTAssertEqual(Domaines.titreCommit("feat!: refonte"), "Refonte")
        XCTAssertEqual(Domaines.titreCommit("Corrige le planning"), "Corrige le planning")
        XCTAssertEqual(Domaines.titreCommit("fix(ios): iPhone, la page de secours"), "iPhone, la page de secours")
        XCTAssertEqual(Domaines.nomEtEntreprise("Jean Moreau", "Moreau"), "Jean Moreau")
        XCTAssertEqual(Domaines.nomEtEntreprise("Lucas Petit", "Lucas Petit — Projet en cours"), "Lucas Petit, Projet en cours")
        XCTAssertEqual(Domaines.nomEtEntreprise("Arnaud Girard", "Girard electricite"), "Arnaud Girard, Girard electricite")
        XCTAssertNil(Domaines.titreCommit("docs: ETAT à jour"))
        XCTAssertNil(Domaines.titreCommit("test(cartes): plafonds"))
    }

    func testCaseDUnePersonneParPriorite() {
        let auj = "2026-11-09"
        var c = ResumeContact(id: "1", nom: "A", espace: "kryva", prochaineAction: "Relancer par SMS", prochaineDate: "2026-11-08",
                              partis: 2, aPartir: 1, echecs: 1)
        XCTAssertEqual(Domaines.caseDe(c, aujourdhui: auj), .pasPuFaire)     // l'échec passe avant tout
        c.echecs = 0
        XCTAssertEqual(Domaines.caseDe(c, aujourdhui: auj), .prepare)        // puis ce qui attend de partir
        c.aPartir = 0
        XCTAssertEqual(Domaines.caseDe(c, aujourdhui: auj), .fait)           // une action d'agent, même passée, n'est pas à Sacha
        c.prochaineAction = "Sacha : appeler A pour le devis"
        XCTAssertEqual(Domaines.caseDe(c, aujourdhui: auj), .aFaire)         // son geste à lui, oui
        c.etape = "perdu"
        XCTAssertEqual(Domaines.caseDe(c, aujourdhui: auj), .fait)           // perdu : plus de geste
        c.partis = 0
        XCTAssertNil(Domaines.caseDe(c, aujourdhui: auj))                    // rien en 7 jours : pas à l'écran
        c.recus = 1
        XCTAssertEqual(Domaines.caseDe(c, aujourdhui: auj), .fait)
    }

    func testGesteDeSachaSansJargon() {
        func g(_ action: String) -> String? {
            Domaines.gesteSacha(ResumeContact(id: "1", nom: "A", espace: "kryva", prochaineAction: action))
        }
        XCTAssertEqual(g("Sacha : visio avec Arthur mardi 10/11 (heure à confirmer). Sans réponse d'ici mardi : relance unique"),
                       "Visio avec Arthur mardi 10/11 (heure à confirmer)")
        XCTAssertEqual(g("Sacha : visio avec Julien mer. 11/11 12h30, Google Meet. Offre = film complet"),
                       "Visio avec Julien mer. 11/11 12h30, Google Meet")       // « mer. 11/11 » ne coupe pas la phrase
        XCTAssertEqual(g("Sacha : envoyer le SMS rangé 1391fc94 à Karl"), "Envoyer le SMS rangé à Karl")
        XCTAssertEqual(g("Jeu. 12/11 : appeler Yanis"), "Appeler Yanis")
        XCTAssertNil(g("Lun. 16/11 : Ventes relit Gmail. Sans réponse : classer"))     // travail d'agent : jamais montré
        XCTAssertNil(g(""))
        XCTAssertEqual(Domaines.sansIdentifiants("Rappel (rid A2D7EEDF) posé"), "Rappel posé")
        XCTAssertEqual(Domaines.sansIdentifiants("décision du 08/11"), "décision du 08/11")
        XCTAssertEqual(Domaines.court("un deux trois, quatre cinq six", 20), "un deux trois")
        XCTAssertEqual(Domaines.court("un, deux, trois quatre cinq six", 20), "un, deux, trois quat…")
    }

    func testVentesEtFreelanceUnePhraseParPersonne() {
        let s = SourcesDomaines(maintenant: maintenant, contacts: [
            ResumeContact(id: "k1", nom: "Jean", entreprise: "Moreau", espace: "kryva",
                          prochaineAction: "Lun. 16/11 : Ventes relit Gmail (14b05237). Sans réponse : relance", prochaineDate: "2026-11-16",
                          dernierLe: "2026-11-09T08:00:00Z", dernierSens: "sortant", dernierCanal: "sms", partis: 2),
            ResumeContact(id: "k2", nom: "Yanis", espace: "kryva", prochaineAction: "Vérifier le site", prochaineDate: "2026-11-02"),
            ResumeContact(id: "k3", nom: "Lucie", espace: "kryva", dernierLe: "2026-11-08T09:00:00Z", dernierSens: "entrant",
                          dernierCanal: "mail", recus: 1),
            ResumeContact(id: "k4", nom: "Arthur", espace: "kryva", prochaineAction: "Sacha : appeler Arthur. Ensuite classer",
                          prochaineDate: "2026-11-06"),
            ResumeContact(id: "f1", nom: "Julien", espace: "freelance", aPartir: 1, prets: 1, envoiLe: "2026-11-16",
                          envoiSousCondition: true),
            ResumeContact(id: "f2", nom: "Nadia", espace: "freelance", aPartir: 2, prets: 2, envoiLe: "2026-11-10"),
        ])
        let v = domaine(.ventes, s)
        XCTAssertEqual(v.elements(.fait).map(\.contactId), ["k3", "k1"])                 // la réponse reçue d'abord, puis le plus récent
        XCTAssertEqual(v.elements(.fait).first?.detail, "A répondu le 08/11 (Mail)")
        XCTAssertEqual(v.elements(.fait).last?.detail, "Message parti le 09/11 (SMS), attend sa réponse")
        XCTAssertEqual(v.elements(.aFaire).map(\.contactId), ["k4"])                    // Yanis : tâche d'agent, pas à l'écran
        XCTAssertEqual(v.elements(.aFaire).first?.detail, "Pour toi : Appeler Arthur (prévu le 06/11)")
        for e in v.cases.values.flatMap({ $0 }) {
            XCTAssertFalse(e.detail.contains("14b05237") || e.detail.contains("Ventes relit"), e.detail)
        }
        XCTAssertEqual(v.pastilles.map(\.texte), ["Pour toi : Appeler Arthur (prévu le 06/11)"])
        XCTAssertEqual(v.pastilles.map(\.ton), [.rouge])                                 // en retard
        XCTAssertEqual(v.pastilles.map(\.geste), ["prospect:k4"])                      // le retard renvoie à sa ligne de « À toi »
        XCTAssertEqual(v.sections.map(\.titre), ["Pour toi", "Réponse reçue, à traiter par Ventes", "Fait aujourd'hui"])
        XCTAssertEqual(v.bilanTexte, "1 réponse reçue, à traiter par Ventes · 1 fait aujourd'hui")
        XCTAssertEqual(v.resume, "")
        let f = domaine(.freelance, s)
        XCTAssertEqual(f.elements(.prepare).map(\.contactId), ["f2", "f1"])              // le premier à partir d'abord
        XCTAssertEqual(f.elements(.prepare).last?.detail, "Message prêt, à envoyer le lun. 16/11, sous condition")
        XCTAssertEqual(f.pastilles.map(\.texte), ["Rien à faire pour toi"])
        XCTAssertEqual(f.bilanTexte, "2 prêts, à envoyer le jour prévu")                 // des personnes, comme la section
        XCTAssertEqual(f.sections.map { "\($0.titre) \($0.elements.count)" }, ["Prêt, à envoyer le jour prévu 2"])
    }

    private func pub(_ id: String, _ compte: String, _ etat: String, phase: String = "", dans heures: Double) -> Publication {
        Publication(id: id, compte: compte, source: "", fichier: "", titre: "Vidéo \(id)", texte: "",
                    prevuLe: Dates.iso.string(from: maintenant.addingTimeInterval(heures * 3600)), etat: etat, phase: phase,
                    raison: "", empreinte: "", empreinteFichier: "", taille: 0, ia: false, proposePar: "", validePar: "", valideLe: "",
                    ref: "", lien: "", conteneur: "", session: "", tentatives: 0, verifieLe: "", creeLe: "", majLe: "", faitLe: "")
    }

    func testReseauxDitCeQuiPartToutSeul() {
        let s = SourcesDomaines(maintenant: maintenant, publications: [
            pub("a", "yt-kryva", "envoye", dans: 8),            // aujourd'hui 18:00
            pub("b", "ig-perso", "planifie", dans: 25),         // demain 11:00
            pub("c", "tt-perso", "envoye", phase: "boite", dans: 2),
        ])
        let e = domaine(.reseaux, s)
        XCTAssertEqual(e.elements(.prepare).map(\.detail), [
            "Dans ta boîte TikTok, à publier par toi · prévue aujourd'hui à 12:00",
            "Part toute seule aujourd'hui à 18:00 · YouTube KRYVA",
            "Part toute seule demain à 11:00 · Instagram perso",
        ])
        XCTAssertEqual(e.pastilles.map(\.texte), ["Pour toi : Publier sur TikTok « Vidéo c »"])
        XCTAssertEqual(e.pastilles.first?.geste, "tiktok:c")
        XCTAssertEqual(e.bilanTexte, "2 prêts, partent à l'heure prévue")
        XCTAssertEqual(e.sections.map(\.titre), ["Pour toi", "Prêt, part à l'heure prévue"])
    }

    func testPapiersEcheancesEtRappelsInaccessibles() {
        let s = SourcesDomaines(maintenant: maintenant, taches: [
            TacheDomaine(id: "1", titre: "Déclarer l'URSSAF", echeance: maintenant.addingTimeInterval(3 * jour), faite: false, faiteLe: nil),
            TacheDomaine(id: "2", titre: "Payer la CFE", echeance: maintenant.addingTimeInterval(-jour), faite: false, faiteLe: nil),
            TacheDomaine(id: "3", titre: "Kbis", echeance: nil, faite: true, faiteLe: maintenant.addingTimeInterval(-2 * jour)),
            TacheDomaine(id: "4", titre: "Vieux", echeance: nil, faite: true, faiteLe: maintenant.addingTimeInterval(-10 * jour)),
        ])
        let e = domaine(.papiers, s)
        XCTAssertEqual(e.elements(.aFaire).map(\.titre), ["Payer la CFE", "Déclarer l'URSSAF"])   // la plus proche d'abord
        XCTAssertEqual(e.elements(.aFaire).first?.detail, "Pour toi · en retard, échéance 08/11")   // qui, puis quand
        XCTAssertEqual(e.elements(.fait).map(\.titre), ["Kbis"])
        XCTAssertEqual(e.pastilles.map(\.texte), ["2 pour toi, dont 1 en retard"])
        XCTAssertEqual(e.pastilles.first?.ton, .rouge)
        XCTAssertEqual(e.pastilles.first?.geste, "rappel:2")
        XCTAssertEqual(e.resume, "")                                                   // plus de « Prochaine échéance » à part
        XCTAssertEqual(e.bilan, [])
        XCTAssertNotNil(domaine(.papiers, SourcesDomaines(maintenant: maintenant, taches: nil)).erreur)
    }

    func testQuiTientChaqueDomaine() {
        // 09/11 : la session n'est plus une ligne « en cours » ; elle dit qui tient le domaine et ce qu'il fait.
        Reglages.remplacement = { var r = EssaiPrincipal.reglages; r.depotSuivi = "/Users/x/Projects/app"; return r }()
        defer { Reglages.remplacement = EssaiPrincipal.reglages }
        let s = SourcesDomaines(maintenant: maintenant, sessions: [
            SessionDomaine(id: "s1", titre: "KRYVA · App et interface", etat: "busy", depuis: maintenant.addingTimeInterval(-7200), etape: "Tests", k: 3, n: 5),
            SessionDomaine(id: "s1b", titre: "Correctif planning", dossier: "/Users/x/Projects/app", etat: "busy"),
            SessionDomaine(id: "s2", titre: "KRYVA · Réseaux, image, événements", etat: "waiting", question: "Quelle musique ?"),
            SessionDomaine(id: "s3", titre: "FREELANCE", etat: "idle", depuis: maintenant.addingTimeInterval(-7200)),
            SessionDomaine(id: "s4", titre: "KRYVA · Ventes", etat: "waiting"),
        ])
        XCTAssertTrue(domaine(.app, s).elements(.enCours).isEmpty)
        XCTAssertEqual(domaine(.app, s).qui, "App au travail : Tests (étape 3/5) · 1 autre session au travail")
        XCTAssertEqual(domaine(.app, s).quiTon, .vert)
        XCTAssertEqual(domaine(.reseaux, s).qui, "Réseaux attend ta réponse, dans À toi")
        XCTAssertEqual(domaine(.reseaux, s).quiTon, .ambre)
        XCTAssertEqual(domaine(.ventes, s).qui, "Ventes attend un message de toi")
        XCTAssertEqual(domaine(.freelance, s).qui, "FREELANCE en pause depuis 2 h")
        XCTAssertEqual(domaine(.freelance, s).quiTon, .gris)
        XCTAssertEqual(domaine(.papiers, s).qui, "Papiers n'est pas lancé")
        XCTAssertEqual(Domaine.deSession(titre: "Chantier", dossier: "/Users/x/Documents/kryva"), .papiers)
        XCTAssertEqual(Domaine.deSession(titre: "PILOTE", dossier: "/Users/x/Projects/pilote"), .pilote)
    }

    // MARK: Travail d'agent (liste Rappels « Agents »)

    private func heure(_ h: Int, _ m: Int = 0, jour j: Int = 9) -> Date {
        var c = DateComponents(); c.year = 2026; c.month = 11; c.day = j; c.hour = h; c.minute = m
        c.timeZone = TimeZone(identifier: "Europe/Paris")
        return Calendar(identifier: .gregorian).date(from: c)!
    }

    func testNoteDuTravailDAgentLesDeuxFormats() {
        let tri = "Préparer la légende.\n\nTri du 09/11 : travail d'agent, pour Réseaux. Échéance d'origine : 2026-11-09T18:00 (liste Contenu)."
        XCTAssertEqual(TravailAgents.note(tri).0, .reseaux)
        XCTAssertEqual(TravailAgents.note(tri).1, heure(18))
        let nouveau = "Relancer Jean si pas de réponse.\nPour : Ventes · Prévu : 2026-11-10T09:30"
        XCTAssertEqual(TravailAgents.note(nouveau).0, .ventes)
        XCTAssertEqual(TravailAgents.note(nouveau).1, heure(9, 30, jour: 10))
        // Le domaine par la liste d'origine quand le nom ne se lit pas ; la dernière mention gagne (une replanification).
        let liste = "Tri du 09/11 : travail d'agent, pour quelqu'un. Échéance d'origine : 2026-11-09T08:00 (liste Papiers)."
        XCTAssertEqual(TravailAgents.note(liste).0, .papiers)
        XCTAssertEqual(TravailAgents.note(tri + "\nPour : App et interface · Prévu : 2026-11-09T21:00").0, .app)
        XCTAssertEqual(TravailAgents.note(tri + "\nPour : App et interface · Prévu : 2026-11-09T21:00").1, heure(21))
        XCTAssertEqual(TravailAgents.note("Pour : FREELANCE · Prévu : 2026-11-11T14:00").0, .freelance)
        XCTAssertNil(TravailAgents.note("Une note sans rien").0)
        XCTAssertEqual(TravailAgents.note("Pour : PILOTE · Prévu : 2026-11-09T18:00").0, .pilote)   // 09/11 : PILOTE a sa ligne
    }

    func testTravailDAgentFaitPrevuEnRetard() {
        func t(_ id: String, _ titre: String, prevu: Date?, faite: Bool = false, faiteLe: Date? = nil, d: Domaine = .reseaux) -> TravailAgent {
            TravailAgent(id: id, titre: titre, domaine: d, prevu: prevu, faite: faite, faiteLe: faiteLe)
        }
        let s = SourcesDomaines(maintenant: maintenant, travaux: [
            t("1", "Monter la vidéo de demain", prevu: heure(8), faite: true, faiteLe: heure(9, 12)),
            t("2", "Écrire la légende", prevu: heure(18)),
            t("3", "Préparer la miniature", prevu: heure(12, 30)),
            t("4", "Relever les vues", prevu: heure(7)),                       // 7 h passé, pas fait : problème
            t("5", "Trier les rushs", prevu: nil),
            t("6", "Vieux", prevu: nil, faite: true, faiteLe: heure(9, jour: 1)),  // fait il y a 8 jours : sort
            t("7", "Pas à moi", prevu: heure(11), d: .ventes),
        ])
        let e = domaine(.reseaux, s)
        XCTAssertEqual(e.elements(.fait).map(\.detail), ["Fait par Réseaux aujourd'hui à 09:12"])
        XCTAssertEqual(e.elements(.aFaire).map(\.titre), ["Préparer la miniature", "Écrire la légende", "Trier les rushs"])  // par heure prévue
        XCTAssertEqual(e.elements(.aFaire).map(\.detail), ["Réseaux · prévu aujourd'hui à 12:30", "Réseaux · prévu aujourd'hui à 18:00",
                                                           "Réseaux · sans heure prévue"])
        XCTAssertEqual(e.elements(.pasPuFaire).map(\.detail), ["Réseaux · prévu aujourd'hui à 07:00, pas encore fait"])
        XCTAssertEqual(e.elements(.pasPuFaire).first?.ton, .rouge)
        XCTAssertTrue(e.cases.values.flatMap { $0 }.allSatisfy { $0.agent == "KRYVA · Réseaux, image, événements" })  // « Écrire à Réseaux »
        XCTAssertEqual(e.bilanTexte, "1 problème · 3 à faire par Réseaux, dont 2 d'ici 18 h · 1 fait aujourd'hui")
        XCTAssertEqual(e.bilan.map(\.ton), [.rouge, .ambre, .vert])
        XCTAssertEqual(e.sections.map { "\($0.titre) \($0.elements.count)" }, ["Problème 1", "À faire par Réseaux 3", "Fait aujourd'hui 1"])
        XCTAssertEqual(e.pastilles.map(\.texte), ["Rien à faire pour toi"])
        XCTAssertEqual(e.qui, "Réseaux n'est pas lancé · 1 problème attend depuis 07:00")   // pas lancé, et ce qui attend depuis quand
        XCTAssertEqual(e.relance?.hasPrefix("1 problème attend depuis 07:00 : « Relever les vues »"), true)
        XCTAssertEqual(domaine(.ventes, s).elements(.aFaire).map(\.titre), ["Pas à moi"])
        XCTAssertEqual(domaine(.ventes, s).bilanTexte, "1 à faire par Ventes, dont 1 d'ici 11 h")
    }

    func testBilanSepareReponsesEtFaits() {
        // Une réponse reçue aujourd'hui n'est pas un fait d'agent : elle a sa section ; une carte « fait » l'est.
        let s = SourcesDomaines(maintenant: maintenant, cartes: [
            CarteDomaine(id: "c", domaine: .ventes, etat: .fait, texte: "Liste du jour triée", auteur: "Ventes",
                         majLe: Dates.iso.string(from: heure(8, 30))),
        ], contacts: [
            ResumeContact(id: "k1", nom: "Lucie", espace: "kryva", dernierLe: "2026-11-09T08:00:00Z", dernierSens: "entrant", recus: 1),
        ])
        XCTAssertEqual(domaine(.ventes, s).bilanTexte, "1 réponse reçue, à traiter par Ventes · 1 fait aujourd'hui")
        XCTAssertEqual(domaine(.papiers, s).bilanTexte, "")
    }

    func testPushDeSachaDitQuandEtRenvoieAATOI() {
        let commits = [
            CommitKryva(hash: "a", sujet: "feat: x", le: maintenant, enLigne: false),
            CommitKryva(hash: "b", sujet: "fix: y", le: maintenant, enLigne: false),
        ]
        let demain = TacheDomaine(id: "P", titre: "Sacha : push KRYVA", echeance: heure(13, 35, jour: 10), faite: false, faiteLe: nil)
        let e = domaine(.app, SourcesDomaines(maintenant: maintenant, commits: commits, push: demain))
        XCTAssertEqual(e.pastilles.first?.texte, "Pour toi : Taper « push » dans App (2 changements)")
        XCTAssertEqual(e.pastilles.first?.ton, .ambre)
        XCTAssertNil(e.pastilles.first?.geste)                                     // demain : pas encore dans « À toi »
        XCTAssertEqual(e.elements(.prepare).first?.detail, "Prêt dans main, part avec ton push demain à 13:35")
        XCTAssertEqual(e.sections.map { "\($0.titre) \($0.elements.count)" }, ["Pour toi 1", "Prêt, attend ton push 2"])
        XCTAssertEqual(e.bilanTexte, "2 prêts, attendent ton push")
        XCTAssertEqual(e.sections.first?.elements.first?.detail, "Prévu demain à 13:35")
        let ajd = TacheDomaine(id: "P", titre: "Sacha : push KRYVA", echeance: heure(13, 35), faite: false, faiteLe: nil)
        let f = domaine(.app, SourcesDomaines(maintenant: maintenant, commits: commits, push: ajd))
        XCTAssertEqual(f.pastilles.first?.geste, "rappel:P")                      // aujourd'hui : un clic l'ouvre dans « À toi »
        let passe = TacheDomaine(id: "P", titre: "Sacha : push KRYVA", echeance: heure(9), faite: false, faiteLe: nil)
        let g = domaine(.app, SourcesDomaines(maintenant: maintenant, commits: commits, push: passe))
        XCTAssertEqual(g.pastilles.first?.ton, .rouge)                            // l'heure est passée : en retard
        XCTAssertEqual(g.sections.first?.elements.first?.detail, "En retard · prévu aujourd'hui à 09:00")
    }

    func testCarteFaitSortApresSeptJoursEtRienDeNeuf() {
        let recente = CarteDomaine(id: "r", domaine: .papiers, etat: .fait, texte: "Mutuelle résiliée",
                                   majLe: Dates.iso.string(from: maintenant.addingTimeInterval(-2 * jour)))
        let vieille = CarteDomaine(id: "v", domaine: .papiers, etat: .fait, texte: "Ancienne",
                                   majLe: Dates.iso.string(from: maintenant.addingTimeInterval(-8 * jour)))
        let e = domaine(.papiers, SourcesDomaines(maintenant: maintenant, cartes: [recente, vieille]))
        XCTAssertEqual(e.elements(.fait).map(\.titre), ["Mutuelle résiliée"])
        XCTAssertTrue(e.rienDeNeuf)                                                    // un « fait » de 2 jours n'est pas du neuf
        let hier = CarteDomaine(id: "h", domaine: .papiers, etat: .fait, texte: "Assurance envoyée",
                                majLe: Dates.iso.string(from: maintenant.addingTimeInterval(-3600)))
        XCTAssertFalse(domaine(.papiers, SourcesDomaines(maintenant: maintenant, cartes: [hier])).rienDeNeuf)
    }

    func testPasPuFaireMontreLePourquoi() {
        let c = CarteDomaine(id: "p", domaine: .reseaux, etat: .pasPuFaire, texte: "Publier la vidéo TikTok",
                             pourquoi: "Compte déconnecté, il faut le relier", auteur: "Réseaux", majLe: Dates.iso.string(from: maintenant))
        let e = domaine(.reseaux, SourcesDomaines(maintenant: maintenant, cartes: [c]))
        XCTAssertEqual(e.elements(.pasPuFaire).first?.detail, "Compte déconnecté, il faut le relier · Réseaux, aujourd'hui à 10:00")
        XCTAssertEqual(e.bilan, [PastilleStatut(texte: "1 problème", ton: .rouge)])
        XCTAssertEqual(e.qui, "Réseaux n'est pas lancé · 1 problème attend depuis 10:00")   // le pourquoi reste dans le détail
    }

    func testCarteDitQuiEtQuand() {
        func carte(_ id: String, _ etat: CaseDomaine, auteur: String) -> CarteDomaine {
            CarteDomaine(id: id, domaine: .reseaux, etat: etat, texte: "Carte \(id)", auteur: auteur,
                         majLe: Dates.iso.string(from: maintenant.addingTimeInterval(-3600)))
        }
        let e = domaine(.reseaux, SourcesDomaines(maintenant: maintenant, cartes: [
            carte("f", .fait, auteur: "KRYVA · Réseaux, image, événements"), carte("a", .aFaire, auteur: ""),
            carte("c", .enCours, auteur: "Réseaux"), carte("p", .prepare, auteur: "session"),
        ]))
        XCTAssertEqual(e.elements(.fait).first?.detail, "Fait par Réseaux aujourd'hui à 09:00")       // le nom court, jamais le titre de session
        XCTAssertEqual(e.elements(.aFaire).first?.detail, "Réseaux · sans heure prévue, noté le 09/11 à 09:00")
        XCTAssertEqual(e.elements(.aFaire).first?.ton, .ambre)                                         // pas en retard : pas rouge
        XCTAssertNil(e.elements(.aFaire).first?.quand)
        XCTAssertEqual(e.elements(.enCours).first?.detail, "Réseaux y travaille depuis 1 h")
        XCTAssertEqual(e.elements(.prepare).first?.detail, "Préparé par Réseaux aujourd'hui à 09:00")    // « session » = l'agent du domaine
        XCTAssertEqual(e.pastilles.map(\.texte), ["Rien à faire pour toi"])
        XCTAssertEqual(e.bilanTexte, "1 en cours · 1 à faire par Réseaux · 1 prêt, suite à préciser par Réseaux · 1 fait aujourd'hui")
    }

    func testUnePastillePourSacha() {
        let s = SourcesDomaines(maintenant: maintenant, contacts: [
            ResumeContact(id: "1", nom: "A", espace: "kryva", partis: 1, aPartir: 1),
            ResumeContact(id: "2", nom: "B", espace: "kryva", echecs: 1),
            ResumeContact(id: "3", nom: "C", espace: "kryva", prochaineAction: "Sacha : appeler", prochaineDate: "2026-11-01"),
            ResumeContact(id: "4", nom: "D", espace: "kryva", dernierSens: "entrant", recus: 1),
        ])
        for e in Domaines.regrouper(s) { XCTAssertEqual(e.pastilles.count, 1) }
    }

    // MARK: Une chose = une ligne, le « tu », PILOTE, la pause expliquée (09/11)

    func testUneChoseUneLigne() {
        // Les vrais doublons du 09/11 : un commit de branche, la carte qui le dit, le rappel « Agents » qui le demande.
        let s = SourcesDomaines(maintenant: maintenant, cartes: [
            CarteDomaine(id: "c1", domaine: .app, etat: .prepare,
                         texte: "TVA de chaque ligne sur téléphone : codée et testée, pas vue à l'écran. Hors 2.2, part dans la version suivante.",
                         auteur: "App", majLe: Dates.iso.string(from: heure(9))),
            CarteDomaine(id: "c2", domaine: .app, etat: .prepare,
                         texte: "Envoi bloqué sans réponse TVA : codé. Part au push suivant la 2.2, quand Sacha dit « push ».",
                         auteur: "App", majLe: Dates.iso.string(from: heure(9))),
            // Une carte qui parle des deux : elle ne doit pas faire disparaître un des deux commits.
            CarteDomaine(id: "c3", domaine: .app, etat: .prepare,
                         texte: "TVA : envoi bloqué sans réponse et taux de chaque ligne sur téléphone, codés",
                         auteur: "App", majLe: Dates.iso.string(from: heure(9))),
        ], commits: [
            CommitKryva(hash: "aaa", sujet: "fix: phrase d'aide du mobile facultatif validée par Sacha", le: heure(7), enLigne: true),
            CommitKryva(hash: "6138583", sujet: "feat(devis): le taux de TVA de chaque ligne se voit aussi sur téléphone (éditeur)",
                        le: heure(8), enLigne: false, branche: "feat/tva-par-ligne-telephone"),
            CommitKryva(hash: "443fbaa", sujet: "feat: ni devis ni facture ne partent tant que l'artisan n'a pas dit s'il facture la TVA",
                        le: heure(8), enLigne: false, branche: "feat/envoi-bloque-tva-micro"),
        ], travaux: [
            TravailAgent(id: "t1", titre: "App : afficher le taux de TVA de chaque ligne du devis sur téléphone", domaine: .app,
                         prevu: heure(9, jour: 10), faite: false, faiteLe: nil),
            TravailAgent(id: "t2", titre: "Idée App : avis « Relance non reçue » aussi sur l'envoi initial devis/facture", domaine: .app,
                         prevu: nil, faite: true, faiteLe: heure(8)),
            TravailAgent(id: "t3", titre: "Avis « Relance non reçue » aussi sur l'envoi initial devis/facture", domaine: .app,
                         prevu: nil, faite: true, faiteLe: heure(9)),
            // Une tâche qui revient : faite cette semaine, à refaire lundi. Les deux restent.
            TravailAgent(id: "t4", titre: "Relever les vues des vidéos de la semaine", domaine: .app, prevu: nil, faite: true, faiteLe: heure(8)),
            TravailAgent(id: "t5", titre: "Relever les vues des vidéos de la semaine", domaine: .app, prevu: heure(9, jour: 16),
                         faite: false, faiteLe: nil),
        ])
        let e = domaine(.app, s)
        XCTAssertEqual(e.elements(.prepare).map(\.id), ["git:6138583", "git:443fbaa"])   // le commit, lu dans le dépôt, l'emporte
        XCTAssertEqual(e.elements(.aFaire).map(\.id), ["agent:t5"])
        XCTAssertEqual(e.elements(.fait).map(\.id).sorted(), ["agent:t2", "agent:t4", "git:aaa"].sorted())   // l'avis : une fois
        XCTAssertEqual(e.elements(.fait).first { $0.id == "git:aaa" }?.titre, "Phrase d'aide du mobile facultatif validée par toi")
        XCTAssertFalse(e.cases.values.flatMap { $0 }.contains { $0.detail.contains("push") })    // une branche ne dit jamais « push »
        XCTAssertEqual(e.bilanTexte, "1 à faire par App · 2 prêts, à fusionner par App · 3 faits aujourd'hui")
        XCTAssertFalse(Domaines.memeChose(Domaines.mots("Envoi bloqué sans réponse TVA"), Domaines.mots("Avis Relance non reçue sur l'envoi initial")))
    }

    func testLEcranTutoieSacha() {
        // Les vraies cartes du 09/11 qui parlaient de Sacha à la 3e personne.
        XCTAssertEqual(Libelles.tutoyer("Créer 3 aperçus de site (10/11) et les montrer à Sacha avant tout déploiement"),
                       "Créer 3 aperçus de site (10/11) et te les montrer avant tout déploiement")
        XCTAssertEqual(Libelles.tutoyer("3 pièces reçues par l'académie (d'après Sacha, 09/11)"),
                       "3 pièces reçues par l'académie (d'après toi, 09/11)")
        XCTAssertEqual(Libelles.tutoyer("PDP Exemple retenue par Sacha le 09/11 : plan du bac à sable prêt, compte à créer par Sacha (rappel 23/11)"),
                       "PDP Exemple retenue par toi le 09/11 : plan du bac à sable prêt, compte à créer par toi (rappel 23/11)")
        XCTAssertEqual(Libelles.tutoyer("Version iPhone qui corrige le blocage de Victor : après le push de mardi 13 h 35 et le feu vert de Sacha."),
                       "Version iPhone qui corrige le blocage de Victor : après le push de mardi 13 h 35 et ton feu vert.")
        XCTAssertEqual(Libelles.tutoyer("Envoi bloqué sans réponse TVA : codé. Part au push suivant la 2.2, quand Sacha dit « push »."),
                       "Envoi bloqué sans réponse TVA : codé. Part au push suivant la 2.2, quand tu dis « push ».")
        XCTAssertEqual(Libelles.tutoyer("Texte vidéo dépannage écrit et validé par Sacha, prêt pour le tournage de jeudi 13:30"),
                       "Texte vidéo dépannage écrit et validé par toi, prêt pour le tournage de jeudi 13:30")
        XCTAssertEqual(Libelles.tutoyer("Sacha a validé la légende. Sacha valide le prix."), "Tu as validé la légende. Tu valides le prix.")
        XCTAssertEqual(Libelles.tutoyer("Sacha : appeler Arthur"), "Toi : appeler Arthur")
        XCTAssertEqual(Libelles.tutoyer("« BoisCave » (lu dans ses DM ; Sacha avait dicté « Bois Cave »)"),
                       "« BoisCave » (lu dans ses DM ; tu avais dicté « Bois Cave »)")
        XCTAssertEqual(Libelles.tutoyer("reçues (d’après Sacha)"), "reçues (d’après toi)")
        XCTAssertEqual(Libelles.tutoyer("Rien à changer"), "Rien à changer")
        // Une carte arrive à l'écran tutoyée.
        let c = CarteDomaine(id: "x", domaine: .app, etat: .aFaire, texte: "Attend le feu vert de Sacha", auteur: "App")
        XCTAssertEqual(domaine(.app, SourcesDomaines(maintenant: maintenant, cartes: [c])).elements(.aFaire).first?.titre,
                       "Attend ton feu vert")
    }

    func testPiloteASaLigne() {
        let s = SourcesDomaines(maintenant: maintenant, sessions: [
            SessionDomaine(id: "p", titre: "PILOTE", etat: "idle", depuis: maintenant.addingTimeInterval(-3600)),
        ], travaux: [
            TravailAgent(id: "1", titre: "Ranger les passations", domaine: .pilote, prevu: heure(12), faite: false, faiteLe: nil),
        ])
        let e = domaine(.pilote, s)
        XCTAssertEqual(e.elements(.aFaire).map(\.detail), ["PILOTE · prévu aujourd'hui à 12:00"])
        XCTAssertEqual(e.qui, "PILOTE en pause depuis 1 h · reprend aujourd'hui à 12:00 : « Ranger les passations »")
        XCTAssertEqual(e.bilanTexte, "1 à faire par PILOTE, dont 1 d'ici 12 h")
        XCTAssertEqual(Domaine.pilote.equipe, "PILOTE")
    }

    func testLaPauseDitPourquoi() {
        let s = SourcesDomaines(maintenant: maintenant, cartes: [
            CarteDomaine(id: "a", domaine: .ventes, etat: .aFaire, texte: "Trier la liste", auteur: "Ventes"),
            CarteDomaine(id: "b", domaine: .ventes, etat: .aFaire, texte: "Relire les réponses", auteur: "Ventes"),
        ], sessions: [SessionDomaine(id: "v", titre: "KRYVA · Ventes", etat: "idle", depuis: maintenant.addingTimeInterval(-7200))])
        XCTAssertEqual(domaine(.ventes, s).qui, "Ventes en pause depuis 2 h · 2 à faire sans heure prévue, écris-lui")
        XCTAssertNil(domaine(.ventes, s).relance)                                           // rien n'attend : pas de « Relancer »
        XCTAssertEqual(domaine(.freelance, s).qui, "FREELANCE n'est pas lancé")              // rien en attente : rien à expliquer
        // Un problème et un travail prévu : le problème attend, il passe avant « reprend le … » (09/11, Organisation).
        let t = SourcesDomaines(maintenant: maintenant, cartes: [
            CarteDomaine(id: "p", domaine: .app, etat: .pasPuFaire, texte: "Prod Supabase pas lue",
                         pourquoi: "Pas urgent : PILOTE la lit quand Chrome sera reconnecté", auteur: "App"),
        ], sessions: [SessionDomaine(id: "a", titre: "App et interface", etat: "idle", depuis: maintenant.addingTimeInterval(-3000))],
           travaux: [TravailAgent(id: "w", titre: "Préparer le webhook Stripe", domaine: .app, prevu: heure(9, jour: 11),
                                  faite: false, faiteLe: nil)])
        let a = domaine(.app, t)
        XCTAssertEqual(a.qui, "App en pause depuis 50 min · 1 problème attend")               // carte sans date : pas de « depuis »
        XCTAssertEqual(a.quiTon, .ambre)
        XCTAssertEqual(a.bilan.first, PastilleStatut(texte: "1 problème", ton: .rouge))
        XCTAssertEqual(Libelles.quand(heure(0, jour: 23), maintenant: maintenant), "le lun. 23/11")   // sans « à 00:00 »
    }

    /// 09/11 (Organisation : « reprend le jeu. 12/11 » alors qu'une réponse attend) : ce qui attend passe avant la reprise,
    /// avec l'heure du plus ancien et le bouton « Relancer » ; « reprend le … » seulement quand plus rien n'attend.
    func testCeQuiAttendPasseAvantLaReprise() {
        let ventes = SessionDomaine(id: "v", titre: "KRYVA · Ventes", etat: "idle", depuis: maintenant.addingTimeInterval(-7200))
        let futur = TravailAgent(id: "f", titre: "Vérifier le 1er paiement de Yanis", domaine: .ventes, prevu: heure(16, 30, jour: 12),
                                 faite: false, faiteLe: nil)
        let enRetard = TravailAgent(id: "r", titre: "Relancer Yanis", domaine: .ventes, prevu: heure(8, 30), faite: false, faiteLe: nil)
        let lucie = ResumeContact(id: "k3", nom: "Lucie", espace: "kryva", dernierLe: "2026-11-09T08:12:00Z", dernierSens: "entrant",
                                  dernierCanal: "mail", recus: 1)                         // 09:12 à Paris
        let s = SourcesDomaines(maintenant: maintenant, contacts: [lucie], sessions: [ventes], travaux: [futur, enRetard])
        let v = domaine(.ventes, s)
        XCTAssertEqual(v.qui, "Ventes en pause depuis 2 h · 1 réponse reçue et 1 problème attendent depuis 08:30")
        XCTAssertEqual(v.quiTon, .ambre)
        XCTAssertEqual(v.relance, "1 réponse reçue et 1 problème attendent depuis 08:30 : « Lucie », « Relancer Yanis ». "
                                  + "À traiter maintenant, puis dis-moi en une ligne où tu en es.")
        XCTAssertTrue(v.bilanTexte.contains("1 réponse reçue, à traiter par Ventes"), v.bilanTexte)   // mêmes mots que le bilan
        // Une seule réponse : « attend », à son heure.
        let r = domaine(.ventes, SourcesDomaines(maintenant: maintenant, contacts: [lucie], sessions: [ventes], travaux: [futur]))
        XCTAssertEqual(r.qui, "Ventes en pause depuis 2 h · 1 réponse reçue attend depuis 09:12")
        // L'agent travaille : pas de « Relancer ».
        var auTravail = ventes; auTravail.etat = "busy"
        XCTAssertNil(domaine(.ventes, SourcesDomaines(maintenant: maintenant, contacts: [lucie], sessions: [auTravail])).relance)
        // Plus rien n'attend : la reprise, sans bouton, point gris.
        let calme = domaine(.ventes, SourcesDomaines(maintenant: maintenant, sessions: [ventes], travaux: [futur]))
        XCTAssertEqual(calme.qui, "Ventes en pause depuis 2 h · reprend le jeu. 12/11 à 16:30 : « Vérifier le 1er paiement de Yanis »")
        XCTAssertNil(calme.relance)
        XCTAssertEqual(calme.quiTon, .gris)
        // Depuis quand : l'heure aujourd'hui, « hier 18:40 », le jour avant, rien de « 00:00 ».
        XCTAssertEqual(Libelles.depuisLe(heure(18, 40, jour: 8), maintenant: maintenant), "hier 18:40")
        XCTAssertEqual(Libelles.depuisLe(heure(9, jour: 5), maintenant: maintenant), "le jeu. 05/11")
        XCTAssertEqual(Libelles.depuisLe(heure(0), maintenant: maintenant), "aujourd'hui")
    }

    // MARK: Outil des cartes (base temporaire)

    private var chemin: URL!
    private var stock: Stockage!

    override func setUpWithError() throws {
        chemin = FileManager.default.temporaryDirectory.appendingPathComponent("pilote-cartes-\(UUID().uuidString).sqlite")
        stock = Stockage(base: try Base(chemin: chemin))
    }

    override func tearDown() {
        stock = nil
        for s in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: chemin.path + s) }
    }

    private func refus(_ bloc: () throws -> Void, contient: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try bloc(), file: file, line: line) { e in
            XCTAssertTrue("\(e)".contains(contient), "\(e)", file: file, line: line)
        }
    }

    func testReglesDeLaCarte() throws {
        refus({ try stock.poserCarte(domaine: .app, etat: .aFaire, texte: "", auteur: "t") }, contient: "vide")
        refus({ try stock.poserCarte(domaine: .app, etat: .aFaire, texte: String(repeating: "a", count: 121), auteur: "t") },
              contient: "121 caractères")
        refus({ try stock.poserCarte(domaine: .app, etat: .pasPuFaire, texte: "Corriger le PDF", auteur: "t") }, contient: "pourquoi")
        refus({ try stock.poserCarte(domaine: .app, etat: .aFaire, texte: "Corriger — vite", auteur: "t") }, contient: "tiret long")
        let ok = try stock.poserCarte(domaine: .app, etat: .aFaire, texte: String(repeating: "a", count: 120), auteur: "t")
        XCTAssertEqual(ok.texte.count, 120)
    }

    func testPlafondParCaseEtRemplacement() throws {
        var poses: [CarteDomaine] = []
        for i in 0..<CaseDomaine.enCours.plafond {
            poses.append(try stock.poserCarte(domaine: .ventes, etat: .enCours, texte: "Carte \(i)", auteur: "t", maintenant: maintenant))
        }
        refus({ try stock.poserCarte(domaine: .ventes, etat: .enCours, texte: "Une de trop", auteur: "t", maintenant: maintenant) },
              contient: "pleine (3 cartes au plus)")
        // Une autre case, un autre domaine : pas concernés.
        XCTAssertNoThrow(try stock.poserCarte(domaine: .freelance, etat: .enCours, texte: "Ailleurs", auteur: "t", maintenant: maintenant))
        // Remplacer une carte de la case pleine reste possible (même id) : elle ne s'ajoute pas.
        let remplacee = try stock.poserCarte(id: poses[0].id, domaine: .ventes, etat: .enCours, texte: "Carte 0 mise à jour",
                                             auteur: "t", maintenant: maintenant)
        XCTAssertEqual(remplacee.id, poses[0].id)
        XCTAssertEqual(try stock.cartesDomaine(maintenant: maintenant).filter { $0.domaine == .ventes }.count, 3)
        // Retirer libère une place.
        try stock.retirerCarte(id: poses[1].id, auteur: "t", maintenant: maintenant)
        XCTAssertNoThrow(try stock.poserCarte(domaine: .ventes, etat: .enCours, texte: "Place libérée", auteur: "t", maintenant: maintenant))
    }

    func testPlafondsDeChaqueCase() {
        XCTAssertEqual(CaseDomaine.allCases.map(\.plafond), [8, 3, 5, 5, 7])
    }

    func testChaqueMouvementVaAuJournal() throws {
        let c = try stock.poserCarte(domaine: .papiers, etat: .aFaire, texte: "Envoyer l'attestation", auteur: "Papiers", maintenant: maintenant)
        try stock.deplacerCarte(id: String(c.id.prefix(8)), vers: .pasPuFaire, pourquoi: "Il manque le Kbis", auteur: "Papiers", maintenant: maintenant)
        try stock.deplacerCarte(id: c.id, vers: .fait, auteur: "Papiers", maintenant: maintenant)
        try stock.retirerCarte(id: c.id, auteur: "Papiers", maintenant: maintenant)
        let textes = try stock.journal(limite: 10).map(\.texte).filter { $0.contains("Envoyer l'attestation") }
        XCTAssertEqual(textes.count, 4, "\(textes)")
        XCTAssertTrue(textes.contains { $0.hasPrefix("Carte posée · Papiers › À faire") })
        XCTAssertTrue(textes.contains { $0.contains("Carte déplacée (À faire → Pas pu faire)") && $0.contains("pourquoi : Il manque le Kbis") })
        XCTAssertTrue(textes.contains { $0.hasPrefix("Carte retirée") })
        XCTAssertTrue(try stock.cartesDomaine(maintenant: maintenant).isEmpty)
    }

    /// Une décision pour dans 13 jours ne passe pas devant le rendez-vous de cet après-midi (60) ni la vidéo à tourner (70).
    func testUrgenceDesDecisions() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Paris")!
        let iso = ISO8601DateFormatter()
        let maintenant = iso.date(from: "2026-11-09T11:38:00Z")!          // lun. 09/11 12:38 Paris
        let demain1630 = iso.date(from: "2026-11-10T15:30:00Z")!
        let demain2359 = iso.date(from: "2026-11-10T22:59:00Z")!
        let apresDemain = iso.date(from: "2026-11-10T23:00:00Z")!         // mer. 11/11 00:00 Paris
        let le22 = iso.date(from: "2026-11-22T11:30:00Z")!
        XCTAssertEqual(Domaines.urgenceDecision(echeance: le22, enRetard: true, maintenant: maintenant, calendrier: cal), 15)
        XCTAssertEqual(Domaines.urgenceDecision(echeance: maintenant, enRetard: false, maintenant: maintenant, calendrier: cal), 50)
        XCTAssertEqual(Domaines.urgenceDecision(echeance: demain1630, enRetard: false, maintenant: maintenant, calendrier: cal), 50)
        XCTAssertEqual(Domaines.urgenceDecision(echeance: demain2359, enRetard: false, maintenant: maintenant, calendrier: cal), 50)
        XCTAssertEqual(Domaines.urgenceDecision(echeance: apresDemain, enRetard: false, maintenant: maintenant, calendrier: cal), 80)
        XCTAssertEqual(Domaines.urgenceDecision(echeance: le22, enRetard: false, maintenant: maintenant, calendrier: cal), 80)
        XCTAssertEqual(Domaines.urgenceDecision(echeance: nil, enRetard: false, maintenant: maintenant, calendrier: cal), 50)
    }

    /// 09/11 (Organisation) : un échec est réglé dès qu'après lui un envoi part, un envoi est annulé ou la personne répond.
    func testUnEchecRegleNeComptePlus() throws {
        let maintenant = ISO8601DateFormatter().date(from: "2026-11-09T17:00:00Z")!
        func personne(_ nom: String, _ evenements: [(String, String, String)]) throws {
            let c = try stock.enregistrer(["nom": nom, "espace": "kryva", "etape": "contacte", "source": "test"]).id
            for (le, sens, statut) in evenements {
                _ = try stock.ajouterEvenement(contactId: c, ["le": le, "canal": "sms", "sens": sens, "type": "message",
                                                              "texte": "\(nom) \(le) \(statut)", "statut": statut, "par": "Claude"])
            }
        }
        try personne("Seul", [("2026-11-05T10:00:00Z", "sortant", "echec")])
        try personne("Annule", [("2026-11-05T10:00:00Z", "sortant", "echec"), ("2026-11-06T09:00:00Z", "sortant", "annule")])
        try personne("Reparti", [("2026-11-05T10:00:00Z", "sortant", "echec"), ("2026-11-05T11:00:00Z", "sortant", "envoye")])
        try personne("Repond", [("2026-11-05T10:00:00Z", "sortant", "echec"), ("2026-11-07T08:00:00Z", "entrant", "recu")])
        try personne("Avant", [("2026-11-04T10:00:00Z", "sortant", "envoye"), ("2026-11-05T10:00:00Z", "sortant", "echec")])
        let r = Dictionary(uniqueKeysWithValues: try stock.resumesContacts(maintenant: maintenant).map { ($0.nom, $0.echecs) })
        XCTAssertEqual(r["Seul"], 1)
        XCTAssertEqual(r["Annule"], 0)
        XCTAssertEqual(r["Reparti"], 0)
        XCTAssertEqual(r["Repond"], 0)
        XCTAssertEqual(r["Avant"], 1, "un envoi d'avant l'échec ne le règle pas")
    }

    // MARK: Qui une carte attend (09/11, Organisation)

    func testCarteQuiAttendDitQui() {
        let il = Dates.iso.string(from: maintenant.addingTimeInterval(-3600))                 // 09:00
        let rappel = TacheDomaine(id: "BE8CC75D-EEF0-439B-8AE1-95C1B3F4410C", titre: "Mot de passe du compte de test Apple",
                                  echeance: maintenant.addingTimeInterval(8 * 3600 + 25 * 60), faite: false, faiteLe: nil)
        let cartes = [
            CarteDomaine(id: "v202", domaine: .app, etat: .enCours, texte: "Version iPhone 2.0.2 : build chez Apple", auteur: "App",
                         majLe: il, attend: "Sacha", rappel: "BE8CC75D"),
            CarteDomaine(id: "pub", domaine: .app, etat: .enCours, texte: "Pub (option A) : lien montré", auteur: "App", majLe: il,
                         attend: "PILOTE"),
            CarteDomaine(id: "bts", domaine: .papiers, etat: .pasPuFaire, texte: "Dossier d'inscription", pourquoi: "On attend l'académie",
                         auteur: "Papiers", majLe: il, attend: "l'académie"),
        ]
        let s = SourcesDomaines(maintenant: maintenant, cartes: cartes, commits: [], taches: [], rappelsSacha: [rappel])
        let app = domaine(.app, s)
        // Attend Sacha : « Pour toi », dit par le rappel à son nom (la même ligne que dans À toi), jamais « Rien à faire pour toi ».
        let pourToi = Domaines.section(app, Domaines.pourToi)
        XCTAssertEqual(pourToi.map(\.titre), ["Mot de passe du compte de test Apple"])
        XCTAssertEqual(pourToi.first?.geste, "rappel:BE8CC75D-EEF0-439B-8AE1-95C1B3F4410C")
        XCTAssertEqual(pourToi.first?.detail.hasPrefix("App l'attend pour « Version iPhone 2.0.2 : build chez Apple » · échéance "), true)
        XCTAssertEqual(app.pastilles.map(\.texte), ["Pour toi : Mot de passe du compte de test Apple"])
        XCTAssertEqual(app.pastilles.first?.geste, "rappel:BE8CC75D-EEF0-439B-8AE1-95C1B3F4410C")
        // Attend PILOTE : compté en le nommant, et « Relancer PILOTE ».
        XCTAssertEqual(Domaines.section(app, "En cours").map(\.detail), ["App · attend PILOTE depuis 09:00"])
        XCTAssertEqual(app.bilanTexte, "1 en cours attend PILOTE depuis 09:00")
        XCTAssertEqual(app.relancePilote, "App t'attend depuis 09:00 : « Pub (option A) : lien montré ». "
                       + "Réponds-lui maintenant, puis dis-moi en une ligne où ça en est.")
        XCTAssertNil(app.relance)
        // Attend un tiers : pas un problème, pas de « Relancer ».
        let p = domaine(.papiers, s)
        XCTAssertTrue(Domaines.section(p, "Problème").isEmpty)
        XCTAssertEqual(Domaines.section(p, "En cours").map(\.detail), ["Papiers · attend l'académie depuis 09:00 : On attend l'académie"])
        XCTAssertEqual(p.bilanTexte, "1 en cours attend l'académie depuis 09:00")
        XCTAssertNil(p.relance)
        XCTAssertNil(p.relancePilote)
        // Rappel introuvable : un problème de la carte, à corriger par App. Rappel fait : App reprend.
        let sans = domaine(.app, SourcesDomaines(maintenant: maintenant, cartes: [cartes[0]], commits: [], taches: [], rappelsSacha: []))
        XCTAssertEqual(Domaines.section(sans, "Problème").map(\.detail), ["Attend toi, mais aucun rappel à ton nom (« BE8CC75D ») : à poser par App"])
        XCTAssertEqual(sans.pastilles.map(\.texte), ["Rien à faire pour toi"])
        var fait = rappel; fait.faite = true; fait.faiteLe = maintenant
        let repris = domaine(.app, SourcesDomaines(maintenant: maintenant, cartes: [cartes[0]], commits: [], taches: [], rappelsSacha: [fait]))
        XCTAssertEqual(Domaines.section(repris, "En cours").map(\.detail),
                       ["App y travaille depuis 1 h · ton geste est fait (« Mot de passe du compte de test Apple »), App reprend"])
        XCTAssertEqual(repris.pastilles.map(\.texte), ["Rien à faire pour toi"])
    }

    /// 09/11 (Organisation) : un ❓ ou un rappel de Sacha qui sert App (« Pour : App ») compte « 1 pour toi » dans App,
    /// même sans carte ; rattaché par l'agent écrit, jamais par l'étiquette KRYVA ; une seule ligne s'il est déjà là.
    func testDecisionOuRappelPourAppCompteDansApp() {
        let titreQ = "❓ Classification d'âge Apple : on répond 4+ ?"
        let q = TacheDomaine(id: "Q1", titre: titreQ, echeance: nil, faite: false, faiteLe: nil,
                             domaine: Domaines.domaineDuRappel(titre: titreQ, liste: "KRYVA", notes: "Option 1 : oui\nPour : App"),
                             decision: true)
        XCTAssertEqual(q.domaine, .app)
        let app = domaine(.app, SourcesDomaines(maintenant: maintenant, cartes: [], commits: [], taches: [], rappelsSacha: [q]))
        let pourToi = Domaines.section(app, Domaines.pourToi)
        XCTAssertEqual(pourToi.map(\.titre), ["Décider : Classification d'âge Apple : on répond 4+ ?"])
        XCTAssertEqual(pourToi.map(\.detail), ["App attend ta décision · sans échéance"])
        XCTAssertEqual(pourToi.first?.geste, "decision:Q1")
        XCTAssertNotEqual(app.pastilles.map(\.texte), ["Rien à faire pour toi"])
        XCTAssertEqual(app.pastilles.first?.geste, "decision:Q1")
        // Rattachement : l'agent écrit (« Pour : … »), ou la liste d'un ❓ ; jamais l'étiquette KRYVA, jamais PILOTE.
        XCTAssertNil(Domaines.domaineDuRappel(titre: titreQ, liste: "KRYVA", notes: "Option 1 : oui"))
        XCTAssertNil(Domaines.domaineDuRappel(titre: titreQ, liste: "KRYVA", notes: "Pour : PILOTE"))
        XCTAssertEqual(Domaines.domaineDuRappel(titre: "❓ Quel visuel ?", liste: "Contenu", notes: ""), .reseaux)
        XCTAssertEqual(Domaines.domaineDuRappel(titre: "Relire la fiche App Store", liste: "KRYVA", notes: "Pour : App"), .app)
        XCTAssertNil(Domaines.domaineDuRappel(titre: "Relire la fiche App Store", liste: "KRYVA", notes: ""))
        XCTAssertNil(Domaines.domaineDuRappel(titre: "Relire la fiche", liste: "Contenu", notes: ""))
        // Un rappel simple « Pour : App » dû aujourd'hui : sa ligne et son geste vers À toi.
        let r = TacheDomaine(id: "R1", titre: "Relire la fiche App Store", echeance: maintenant.addingTimeInterval(3600), faite: false,
                             faiteLe: nil, domaine: .app)
        let avecR = domaine(.app, SourcesDomaines(maintenant: maintenant, cartes: [], commits: [], taches: [], rappelsSacha: [r]))
        XCTAssertEqual(Domaines.section(avecR, Domaines.pourToi).map(\.geste), ["rappel:R1"])
        XCTAssertEqual(Domaines.section(avecR, Domaines.pourToi).first?.detail.hasPrefix("App attend ce geste · échéance "), true)
        // Fait : ne compte plus.
        var fait = q; fait.faite = true; fait.faiteLe = maintenant
        let apres = domaine(.app, SourcesDomaines(maintenant: maintenant, cartes: [], commits: [], taches: [], rappelsSacha: [fait]))
        XCTAssertEqual(apres.pastilles.map(\.texte), ["Rien à faire pour toi"])
        // Déjà lié à une carte qui attend Sacha : une seule ligne, celle de la carte, avec le geste du ❓.
        let carte = CarteDomaine(id: "v202", domaine: .app, etat: .enCours, texte: "Version iPhone 2.0.2 : build chez Apple", auteur: "App",
                                 majLe: Dates.iso.string(from: maintenant.addingTimeInterval(-3600)), attend: "Sacha", rappel: "Q1")
        let lie = domaine(.app, SourcesDomaines(maintenant: maintenant, cartes: [carte], commits: [], taches: [], rappelsSacha: [q]))
        XCTAssertEqual(Domaines.section(lie, Domaines.pourToi).map(\.titre), ["Décider : Classification d'âge Apple : on répond 4+ ?"])
        XCTAssertEqual(Domaines.section(lie, Domaines.pourToi).map(\.geste), ["decision:Q1"])
        // Un ❓ de la liste Papiers : déjà une ligne de Papiers, pas deux.
        let qp = TacheDomaine(id: "QP", titre: "❓ Envoyer la convention ?", echeance: nil, faite: false, faiteLe: nil,
                              domaine: Domaines.domaineDuRappel(titre: "❓ Envoyer la convention ?", liste: "Papiers", notes: ""), decision: true)
        let p = domaine(.papiers, SourcesDomaines(maintenant: maintenant, cartes: [], commits: [], taches: [qp], rappelsSacha: [qp]))
        XCTAssertEqual(Domaines.section(p, Domaines.pourToi).map(\.geste), ["decision:QP"])
        XCTAssertEqual(Domaines.section(p, Domaines.pourToi).map(\.titre), ["Décider : Envoyer la convention ?"])
    }

    func testDeuxCartesDeLaMemeChoseUneLigne() {
        let il = Dates.iso.string(from: maintenant.addingTimeInterval(-3600))
        // Les deux cartes réelles du 09/11 (App) : la Pub en cours et la Pub prête.
        let e = domaine(.app, SourcesDomaines(maintenant: maintenant, cartes: [
            CarteDomaine(id: "a", domaine: .app, etat: .enCours, texte: "Pub (option A) : balise testée, gclid codé. Reste : lien montré à "
                         + "PILOTE, texte confidentialité, push.", auteur: "App", majLe: il),
            CarteDomaine(id: "b", domaine: .app, etat: .prepare, texte: "Pub : gclid à l'inscription codé (a3fe65b, non poussé, après "
                         + "« Tout accepter »). Attend push + texte confidentialité.", auteur: "App", majLe: il),
            // Faite hier, à refaire : deux lignes.
            CarteDomaine(id: "f", domaine: .app, etat: .fait, texte: "Relever les erreurs Sentry de la semaine", auteur: "App", majLe: il),
            CarteDomaine(id: "r", domaine: .app, etat: .aFaire, texte: "Relever les erreurs Sentry de la semaine", auteur: "App", majLe: il),
        ], commits: []))
        XCTAssertEqual(e.elements(.enCours).map(\.carteId), ["a"])
        XCTAssertTrue(e.elements(.prepare).isEmpty)
        XCTAssertEqual(e.elements(.fait).map(\.carteId), ["f"])
        XCTAssertEqual(e.elements(.aFaire).map(\.carteId), ["r"])
    }

    func testPretDitQuiAgit() {
        let il = Dates.iso.string(from: maintenant.addingTimeInterval(-3600))
        func pret(_ id: String, _ texte: String, attend: String) -> CarteDomaine {
            CarteDomaine(id: id, domaine: .ventes, etat: .prepare, texte: texte, auteur: "Ventes", majLe: il, attend: attend)
        }
        let e = domaine(.ventes, SourcesDomaines(maintenant: maintenant, cartes: [
            pret("a", "SMS à Pascal validé", attend: "Ventes"), pret("b", "Devis Lucie relu", attend: "PILOTE"),
            pret("c", "Fiche Yanis", attend: ""),
        ]))
        XCTAssertEqual(e.bilanTexte, "1 prêt, à faire partir par Ventes · 1 prêt, attend PILOTE · 1 prêt, suite à préciser par Ventes")
        XCTAssertEqual(e.relancePilote?.hasPrefix("Ventes t'attend depuis 09:00 : « Devis Lucie relu »"), true)
    }

    func testCarteDitQuiElleAttend() throws {
        refus({ try stock.poserCarte(domaine: .ventes, etat: .prepare, texte: "SMS prêt", auteur: "t") }, contient: "qui agit ensuite")
        refus({ try stock.poserCarte(domaine: .app, etat: .enCours, texte: "2.0.2", attend: "toi", auteur: "t") }, contient: "rappel à son nom")
        refus({ try stock.poserCarte(domaine: .app, etat: .enCours, texte: "Pub", attend: "pilote", rappel: "X", auteur: "t") },
              contient: "seulement quand")
        let a = try stock.poserCarte(domaine: .app, etat: .enCours, texte: "2.0.2", attend: "toi", rappel: "x-apple-reminder://BE8C", auteur: "t")
        XCTAssertEqual([a.attend, a.rappel], ["Sacha", "BE8C"])
        let relue = try XCTUnwrap(stock.carteDomaine(a.id))
        XCTAssertEqual([relue.attend, relue.rappel], ["Sacha", "BE8C"])
        // Remplacée sans dire « attend » : gardé ; vers PILOTE : le rappel tombe ; faite : elle n'attend plus personne.
        let b = try stock.poserCarte(id: a.id, domaine: .app, etat: .enCours, texte: "2.0.2 chez Apple", auteur: "t")
        XCTAssertEqual([b.attend, b.rappel], ["Sacha", "BE8C"])
        let c = try stock.deplacerCarte(id: a.id, vers: .prepare, attend: "PILOTE", auteur: "t")
        XCTAssertEqual([c.attend, c.rappel], ["PILOTE", ""])
        let d = try stock.deplacerCarte(id: a.id, vers: .fait, auteur: "t")
        XCTAssertEqual([d.attend, d.rappel], ["", ""])
        // Un rappel donné seul : la carte attend Sacha. Un agent par son nom court.
        let e = try stock.poserCarte(domaine: .papiers, etat: .aFaire, texte: "Signer l'attestation", rappel: "Signer l'attestation", auteur: "t")
        XCTAssertEqual(e.attend, "Sacha")
        let pret = try stock.poserCarte(domaine: .ventes, etat: .prepare, texte: "SMS prêt", attend: "ventes", auteur: "t")
        XCTAssertEqual(pret.attend, "Ventes")
    }
}
