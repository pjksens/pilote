// « À toi » (09/11, Sacha : « aucun oubli, aucun bug, tout faire en un clic ») : le contrôle compte, dans les sources, tout ce
// qui attend Sacha et vérifie que l'écran montre exactement ce nombre ; chaque type de ligne a un bouton qui fait le geste
// jusqu'au bout. Sources construites à la main : ni base, ni Rappels, ni réseau.
import XCTest

final class ATOITests: XCTestCase {
    /// Lundi 9 novembre 2026, 14 h (heure de Paris).
    let maintenant: Date = {
        var c = DateComponents(); c.year = 2026; c.month = 11; c.day = 9; c.hour = 14
        c.timeZone = TimeZone(identifier: "Europe/Paris")
        return Calendar(identifier: .gregorian).date(from: c)!
    }()
    let heure: TimeInterval = 3600
    let aujourdhui = "2026-11-09"

    // MARK: Fabriques

    private func contact(_ id: String, _ nom: String, action: String = "", date: String = "") -> Contact {
        Contact(id: id, nom: nom, prochaineAction: action, prochaineDate: date)
    }

    private func message(_ id: String, canal: String = "sms", objet: String = "", condition: String = "",
                         texte: String = "Bonjour,\nOn revient vers vous.\nSacha, de l'équipe KRYVA", statut: String = "prepare",
                         date: String = "") -> MessageAEnvoyer {
        let e = Evenement(id: id, contactId: "c-\(id)", le: "2026-11-09T08:00:00+01:00", canal: canal, sens: "sortant",
                          type: "message", texte: texte, statut: statut, objet: objet, condition: condition)
        return MessageAEnvoyer(evenement: e, contact: contact("c-\(id)", "Contact \(id)", date: date), aujourdhui: aujourdhui)
    }

    private func rappel(_ id: String, _ titre: String, liste: String, dans h: Double = 2, retard: Bool = false,
                        notes: String = "") -> Rappel {
        Rappel(id: id, titre: titre, notes: notes, liste: liste, echeance: maintenant.addingTimeInterval(h * heure),
               enRetard: retard, priorite: 0, avecHeure: true)
    }

    private func pub(_ id: String, _ compte: String, _ etat: String, phase: String = "", titre: String = "", texte: String = "",
                     fichier: String = "", dans h: Double = 3) -> Publication {
        Publication(id: id, compte: compte, source: "", fichier: fichier, titre: titre, texte: texte,
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

    private func question(_ id: String, choix: [String]) -> QuestionATOI {
        var a = ActiviteSession(id: id)
        a.question = "On part sur quelle version ?"
        a.questionRef = "session:\(id):1"
        a.choix = choix
        a.depuis = maintenant.addingTimeInterval(-heure)
        return QuestionATOI(activite: a, nom: "Session \(id)")
    }

    private func candidat(_ m: MessageAEnvoyer, refus: [String] = []) -> CandidatFile {
        CandidatFile(evenement: m.evenement, contact: m.contact, jour: m.jour, refus: refus, aujourdhui: aujourdhui)
    }

    /// Une journée chargée, avec tout ce qui peut attendre Sacha, et des choses qui ne l'attendent pas.
    private func reponse(_ rang: Int, _ question: String, _ choix: String, pour: String) -> Decisions.Envoyee {
        Decisions.Envoyee(id: rang, question: question, choix: choix, pour: pour, heure: "13:10", transmise: false, enAttente: true)
    }

    private func journee() -> SourcesATOI {
        let mailOk = message("m1", canal: "mail", objet: "Votre devis")
        let mailBloque = message("m2", canal: "mail", objet: "")
        let sms = message("m3")
        let sousCondition = message("m4", condition: "après le test")          // pas dû : condition ouverte
        let plusTard = message("m5", date: "2026-11-12")                        // pas dû : prévu jeudi
        var s = SourcesATOI(maintenant: maintenant)
        s.aValider = [message("t1", statut: "a_valider"), message("t2", statut: "a_valider")]
        s.aEnvoyer = [mailOk, mailBloque, sms, sousCondition, plusTard]
        s.candidatsFile = [candidat(mailOk), candidat(mailBloque, refus: ["objet vide"])]
        s.questions = [question("q1", choix: ["Version A", "Version B"])]
        s.rappels = [
            rappel("d1", "❓ On garde le prix à 29 € ?", liste: "KRYVA", notes: "Option 1 : oui\nOption 2 : non, 39 €"),
            rappel("k1", "Sacha : taper push dans la session App", liste: "KRYVA", dans: -0.5),
            rappel("k2", "Publier la release 2.2", liste: "KRYVA", dans: -30, retard: true),
            rappel("k3", "Relire la note de version", liste: "KRYVA", dans: 3),
            rappel("k4", "Répondre au support", liste: "KRYVA", dans: 4),
            rappel("k5", "Vérifier le paiement", liste: "KRYVA", dans: 5),
            rappel("k6", "Préparer la démo", liste: "KRYVA", dans: 6),
            rappel("p1", "Déclarer l'URSSAF d'octobre", liste: "Papiers", dans: -50, retard: true),
            rappel("x1", "Travail d'agent", liste: "Agents", dans: 1),        // pas une liste de Sacha
        ]
        s.decisionsAVenir = [rappel("d2", "❓ Quel sujet jeudi ?", liste: "Contenu", dans: 72, notes: "A : le devis\nB : la facture")]
        s.rappelsDemain = [rappel("j1", "Appeler le conseiller", liste: "Papiers", dans: 20)]
        s.dus = [contact("c1", "Arthur", action: "Sacha : appeler Arthur", date: "2026-11-08"),
                 contact("c2", "Yanis", action: "Vérifier le site", date: "2026-11-09")]     // pas un geste de Sacha
        s.publications = [pub("v1", "yt-kryva", "a_valider", titre: "Le devis en 30 s"),
                          pub("v2", "tt-perso", "envoye", phase: "boite", fichier: "/x/repo-github-v3.mp4"),
                          pub("v3", "ig-perso", "planifie")]                                      // part toute seule
        s.rendezVous = [rdv("r1", dans: 1, url: URL(string: "https://meet.google.com/abc")),
                        rdv("r2", dans: -1, lieu: "Salle 11"),                                    // commencé
                        rdv("r3", dans: 0, journee: true)]                                        // journée entière
        s.reponses = [reponse(41, "Release ce soir ?", "Oui", pour: "App"),
                      reponse(42, "Sujet jeudi ?", "Le devis", pour: "Réseaux"),
                      reponse(44, "Prix à 29 € ?", "Oui", pour: "App")]
        return s
    }

    // MARK: Aucun oubli

    func testLeControleCompteExactementCeQueAToiMontre() {
        let s = journee()
        let lignes = GesteSacha.grouper(GesteSacha.du(s))
        let attendus = ControleATOI.attendus(s)
        XCTAssertEqual(attendus.count, 20)   // 2 textes, 3 messages, 1 question, 2 décisions, 7 tâches, 1 fiche, 2 publications, 1 RDV, 1 envoi des réponses
        XCTAssertEqual(ControleATOI.montres(lignes), Set(attendus.keys))           // rien en moins, rien en plus
        XCTAssertEqual(lignes.reduce(0) { $0 + $1.gestes.count }, attendus.count)   // le nombre en tête de « À toi »
        XCTAssertEqual(ControleATOI.manquants(s, lignes: lignes), [])
        XCTAssertNil(ControleATOI.alerte([]))
    }

    func testUnOubliSAfficheEnRouge() {
        let s = journee()
        let lignes = GesteSacha.grouper(GesteSacha.du(s)).filter { $0.id != "rappel:p1" }
        let manque = ControleATOI.manquants(s, lignes: lignes)
        XCTAssertEqual(manque, ["tâche « Déclarer l'URSSAF d'octobre »"])
        XCTAssertEqual(ControleATOI.alerte(manque),
                       "À toi : 1 chose ne s'affiche pas (tâche « Déclarer l'URSSAF d'octobre »). PILOTE est à prévenir.")
        // Une ligne qui part (5 s pour annuler) n'est pas un oubli.
        XCTAssertEqual(ControleATOI.manquants(s, lignes: lignes, masques: ["rappel:p1"]), [])
    }

    func testToutesLesTachesDuesDeSesListesSontLa() {
        let g = GesteSacha.du(journee())
        let taches = g.filter { if case .rappel = $0.genre { return true } else { return false } }
        XCTAssertEqual(Set(taches.map(\.id)), ["rappel:k1", "rappel:k2", "rappel:k3", "rappel:k4", "rappel:k5", "rappel:k6", "rappel:p1"])
        XCTAssertFalse(g.contains { $0.id == "rappel:x1" })                          // liste d'agent : pas chez Sacha
        // La plus en retard d'abord ; « Sacha : » retiré ; le domaine et le retard dits en clair.
        XCTAssertEqual(taches.first?.objet, "Déclarer l'URSSAF d'octobre")
        XCTAssertTrue(taches.first!.contexte.hasPrefix("Papiers · prévu"), taches.first!.contexte)
        XCTAssertTrue(g.contains { $0.objet == "Taper push dans la session App" })
    }

    func testLesTachesDUneMemeListeSeGroupentAuDelaDeTrois() {
        let lignes = GesteSacha.grouper(GesteSacha.du(journee()))
        let kryva = lignes.first { $0.id == "groupe:rappel:KRYVA" }
        XCTAssertEqual(kryva?.verbe, "Faire")
        XCTAssertEqual(kryva?.objet, "4 tâches KRYVA")
        XCTAssertEqual(kryva?.gestes.count, 4)
        // Le plus urgent n'est jamais groupé : en retard (k2), heure passée (k1), Papiers en retard (p1).
        XCTAssertTrue(lignes.contains { $0.id == "rappel:k1" })
        XCTAssertTrue(lignes.contains { $0.id == "rappel:k2" })
        XCTAssertTrue(lignes.contains { $0.id == "rappel:p1" })
    }

    func testPeuDeGestesGardentChacunSaLigneEtSonHeure() {
        var s = SourcesATOI(maintenant: maintenant)
        s.rappels = (1...5).map { rappel("r\($0)", "Tâche \($0)", liste: "Contenu", dans: Double($0)) }
        let lignes = GesteSacha.grouper(GesteSacha.du(s))
        XCTAssertEqual(lignes.count, 5)
        XCTAssertEqual(lignes.first?.verbe, "À 15:00")
    }

    func testUneTacheAHeurePasseeEstEnRetard() {
        // 09/11 : 13:30 vue à 13:47 ne disait rien. L'heure passée dit « En retard » (en rouge) et l'heure prévue.
        var s = SourcesATOI(maintenant: maintenant)
        s.rappels = [rappel("r1", "Poster les stories", liste: "Contenu", dans: -0.5), rappel("r2", "Plus tard", liste: "Contenu", dans: 1)]
        let g = GesteSacha.du(s)
        let passe = g.first { $0.id == "rappel:r1" }
        XCTAssertEqual(passe?.verbe, "En retard")
        XCTAssertEqual(passe?.retard, true)
        XCTAssertTrue(passe?.contexte.contains("prévu aujourd'hui à 13:30") ?? false, passe?.contexte ?? "")
        XCTAssertEqual(g.first { $0.id == "rappel:r2" }?.retard, false)
        XCTAssertEqual(g.first?.id, "rappel:r1")                                   // le retard passe devant
    }

    func testUneAdresseTientSurUneLigne() {
        var s = SourcesATOI(maintenant: maintenant)
        s.rendezVous = [rdv("r5", dans: 1, lieu: "Cabinet\n1 rue Exemple, 75000 Paris")]
        XCTAssertEqual(GesteSacha.du(s).first?.contexte, "à 15:00 · Cabinet, 1 rue Exemple, 75000 Paris")
    }

    func testDemainTientEnUneLigneRepliéeNonComptee() {
        let g = GesteSacha.du(journee())
        let d = g.last
        XCTAssertEqual(d?.verbe, "Demain")
        XCTAssertEqual(d?.objet, "1 tâche")
        XCTAssertEqual(d?.contexte, "Appeler le conseiller")
        XCTAssertEqual(d?.gestes.count, 0)
        XCTAssertEqual(d?.action, .deplier)
    }

    func testUnRendezVousCommenceSortDeAToi() {
        let g = GesteSacha.du(journee())
        let rdv = g.filter { if case .rendezVous = $0.genre { return true } else { return false } }
        XCTAssertEqual(rdv.map(\.objet), ["RDV r1"])                                  // ni commencé, ni journée entière
        XCTAssertEqual(rdv.first?.urgence, 0)                                         // dans moins de 2 h : en tête
    }

    func testUneDecisionAVenirArriveAvecSaDate() {
        let g = GesteSacha.du(journee())
        let d2 = g.first { $0.id == "decision:d2" }
        XCTAssertTrue(d2?.contexte.hasPrefix("Pour ") ?? false, d2?.contexte ?? "absente")
        XCTAssertEqual(d2?.choix, ["le devis", "la facture"])
    }

    // MARK: Jamais « Vidéo sans titre »

    func testUneVideoADesQueUnNom() {
        let v = Video(id: "s1", jour: aujourdhui, compte: "perso", sujet: "Ce repo GitHub remplace un SaaS", statut: "prete")
        XCTAssertEqual(ATOI.titre(pub("a", "tt-perso", "envoye", titre: "Mon titre"), videos: [v]), "Mon titre")
        XCTAssertEqual(ATOI.titre(pub("b", "tt-perso", "envoye"), videos: [v]), "Ce repo GitHub remplace un SaaS")
        XCTAssertEqual(ATOI.titre(pub("c", "yt-kryva", "envoye", texte: "Le devis en 30 s\n#artisan"), videos: [v]), "Le devis en 30 s")
        XCTAssertEqual(ATOI.titre(pub("d", "ig-kryva", "envoye", fichier: "/x/devis-v2.mp4"), videos: []), "devis-v2")
        let rien = ATOI.titre(pub("e", "ig-kryva", "envoye"), videos: [])
        XCTAssertFalse(rien.contains("sans titre"), rien)
        for g in GesteSacha.du(journee()) { XCTAssertFalse(g.objet.contains("sans titre"), g.id) }
    }

    // MARK: Un clic, un geste fini : un test par type de bouton

    private func ligne(_ id: String, _ s: SourcesATOI? = nil) -> GesteSacha {
        let g = GesteSacha.du(s ?? journee()).first { $0.id == id }
        XCTAssertNotNil(g, id)
        return g!
    }

    func testTexteAValider() {
        let g = ligne("texte:t1")
        XCTAssertEqual(g.bouton, "Valider")
        guard case .validerTexte(let m) = g.action else { return XCTFail("\(g.action)") }
        XCTAssertEqual(m.id, "t1")
    }

    func testMailEnvoyableVaDansLaFile() {
        let g = ligne("envoi:m1")
        XCTAssertEqual(g.bouton, "Envoyer")
        XCTAssertFalse(g.bloque)
        guard case .mettreEnFile(let m) = g.action else { return XCTFail("\(g.action)") }
        XCTAssertEqual(m.id, "m1")
    }

    func testMailQuePiloteNePeutPasEnvoyerResteEnRouge() {
        let g = ligne("envoi:m2")
        XCTAssertEqual(g.verbe, "Envoyer à la main")
        XCTAssertEqual(g.contexte, "Pilote ne peut pas l'envoyer : objet vide")
        XCTAssertTrue(g.bloque)
        XCTAssertEqual(g.bouton, "Envoyé")
        guard case .marquerEnvoye = g.action else { return XCTFail("\(g.action)") }
    }

    func testMessageAEnvoyerALaMain() {
        let g = ligne("envoi:m3")
        XCTAssertEqual(g.bouton, "Envoyé")
        guard case .marquerEnvoye(let m) = g.action else { return XCTFail("\(g.action)") }
        XCTAssertEqual(m.id, "m3")
    }

    func testTacheFaite() {
        let g = ligne("rappel:p1")
        XCTAssertEqual(g.bouton, "Fait")
        guard case .cocherRappel(let r) = g.action else { return XCTFail("\(g.action)") }
        XCTAssertEqual(r.id, "p1")
    }

    func testGesteDeFicheFait() {
        let g = ligne("prospect:c1")
        XCTAssertEqual(g.bouton, "Fait")
        XCTAssertEqual(g.contexte, "Appeler Arthur")
        guard case .prospectFait(let c) = g.action else { return XCTFail("\(g.action)") }
        XCTAssertEqual(c.id, "c1")
    }

    func testBrouillonTikTokPublie() {
        let g = ligne("tiktok:v2")
        XCTAssertEqual(g.bouton, "Publiée")
        XCTAssertEqual(g.objet, "repo-github-v3")
        guard case .tiktokPubliee(let p) = g.action else { return XCTFail("\(g.action)") }
        XCTAssertEqual(p.id, "v2")
    }

    func testPublicationValidee() {
        let g = ligne("publication:v1")
        XCTAssertEqual(g.bouton, "Valider")
        guard case .validerPublication(let p) = g.action else { return XCTFail("\(g.action)") }
        XCTAssertEqual(p.empreinte, "e-v1")
    }

    func testVideoTourneeEtPubliee() {
        var s = SourcesATOI(maintenant: maintenant)
        s.videos = [Video(id: "a", jour: "2026-11-10", compte: "kryva", sujet: "Le devis", statut: "valide"),
                    Video(id: "b", jour: aujourdhui, compte: "perso", sujet: "Le repo", statut: "prete")]
        let t = ligne("tourner:a", s), p = ligne("publier:b", s)
        XCTAssertEqual(t.bouton, "Tournée")
        XCTAssertEqual(p.bouton, "Publiée")
        guard case .videoFaite(let v1, let a1) = t.action, case .videoFaite(let v2, let a2) = p.action else {
            return XCTFail("\(t.action) \(p.action)")
        }
        XCTAssertEqual([v1.id, a1, v2.id, a2], ["a", "tourner", "b", "publier"])
    }

    func testRendezVousRejoindreOuItineraire() {
        XCTAssertEqual(ligne("rdv:r1:\(Int(maintenant.addingTimeInterval(heure).timeIntervalSince1970))").action,
                       .ouvrir(URL(string: "https://meet.google.com/abc")!))
        var s = SourcesATOI(maintenant: maintenant)
        s.rendezVous = [rdv("r4", dans: 3, lieu: "12 rue de la Paix")]
        let g = ligne("rdv:r4:\(Int(maintenant.addingTimeInterval(3 * heure).timeIntervalSince1970))", s)
        XCTAssertEqual(g.bouton, "Itinéraire")
        XCTAssertEqual(g.action, .ouvrir(URL(string: "maps://?daddr=12%20rue%20de%20la%20Paix")!))
    }

    func testDecisionSeTrancheSurLaLigne() {
        let g = ligne("decision:d1")
        XCTAssertEqual(g.choix, ["oui", "non, 39 €"])
        XCTAssertEqual(g.bouton, "")                                                  // les choix sont les boutons
        XCTAssertEqual(g.action, .aucune)
    }

    func testDecisionSansOptionSeRegleEnUnClic() {
        var s = SourcesATOI(maintenant: maintenant)
        s.rappels = [rappel("d3", "❓ Le local est réservé ?", liste: "Papiers")]
        let g = ligne("decision:d3", s)
        XCTAssertEqual(g.bouton, "C'est réglé")
        XCTAssertEqual(g.action, .choisir("réglé"))
    }

    func testDecisionAuxChoixTropLongsSeDeplie() {
        var s = SourcesATOI(maintenant: maintenant)
        s.rappels = [rappel("d4", "❓ Quel prix ?", liste: "KRYVA", notes: "A : 19\nB : 29\nC : 39\nD : 49")]
        let g = ligne("decision:d4", s)
        XCTAssertEqual(g.choix, [])
        XCTAssertEqual(g.bouton, "Répondre")
        XCTAssertEqual(g.action, .deplier)
    }

    func testQuestionDeSessionSurLaLigne() {
        let g = ligne("question:session:q1:1")
        XCTAssertEqual(g.choix, ["Version A", "Version B"])
        XCTAssertEqual(g.action, .aucune)
        var s = SourcesATOI(maintenant: maintenant)
        s.questions = [question("q2", choix: [])]
        let libre = ligne("question:session:q2:1", s)
        XCTAssertEqual(libre.bouton, "Répondre")
        XCTAssertEqual(libre.action, .deplier)
    }

    /// Seuls dépliant : une liste groupée, demain, la séance du dimanche, une question ou décision sans choix courts.
    func testToutesLesReponsesPartentEnUnBouton() {
        let s = journee()
        let g = ligne(GesteSacha.idReponses(s.reponses))
        XCTAssertEqual(g.bouton, "Tout envoyer (3)")
        XCTAssertEqual(g.objet, "tes 3 réponses")
        XCTAssertEqual(g.contexte, "pour App, Réseaux")
        XCTAssertEqual(g.action, .envoyerReponses([41, 42, 44]))
        XCTAssertLessThan(g.urgence, GesteSacha.urgenceGroupable)            // jamais rangée dans un groupe
        // Rien en attente : pas de bouton.
        var vide = s; vide.reponses = []
        XCTAssertFalse(GesteSacha.du(vide).contains { $0.id.hasPrefix("reponses:") })
        XCTAssertFalse(ControleATOI.attendus(vide).keys.contains { $0.hasPrefix("reponses:") })
        // Une seule : « Envoyer », et la réponse dite en clair.
        var une = s; une.reponses = [s.reponses[0]]
        let g1 = GesteSacha.du(une).first { $0.id.hasPrefix("reponses:") }
        XCTAssertEqual(g1?.bouton, "Envoyer")
        XCTAssertEqual(g1?.contexte, "pour App · Release ce soir ? → Oui")
        // Une réponse notée après l'envoi refait une ligne : l'ancienne, masquée, ne la cache pas.
        var apres = s; apres.reponses = [reponse(45, "Story ce soir ?", "Oui", pour: "Réseaux")]
        XCTAssertNotEqual(GesteSacha.idReponses(apres.reponses), g.id)
    }

    func testAucunBoutonNeFaitQueOuvrirSansRaison() {
        for g in GesteSacha.grouper(GesteSacha.du(journee())) where g.action == .deplier {
            switch g.genre {
            case .groupe, .demain, .seance: continue
            case .question, .decision: XCTAssertTrue(g.choix.isEmpty, g.id)
            default: XCTFail("\(g.id) : « \(g.bouton) » ne fait qu'ouvrir")
            }
        }
        for g in GesteSacha.du(journee()) where g.action == .aucune {
            XCTAssertFalse(g.choix.isEmpty, "\(g.id) : ni bouton ni choix")
        }
    }
}
