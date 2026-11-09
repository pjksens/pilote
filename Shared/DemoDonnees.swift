// Les données fictives du mode démo (Demo.actif) : rendez-vous, rappels et sessions Claude, datés autour d'aujourd'hui.
// Contacts, fil, carte et journal fictifs : demo/*.json, chargés par scripts/demo.sh. Aucune donnée réelle.
import Foundation

enum DemoDonnees {
    private static var cal: Calendar { Calendar.current }
    private static func a(_ jours: Int, _ h: Int, _ m: Int = 0) -> Date {
        let j = cal.date(byAdding: .day, value: jours, to: cal.startOfDay(for: Date()))!
        return cal.date(bySettingHour: h, minute: m, second: 0, of: j)!
    }

    static func rendezVous() -> [RendezVous] {
        [
            RendezVous(id: "demo-rdv-1", titre: "Visio : maquette du site Studio Lumen", debut: a(0, 10), fin: a(0, 10, 30),
                       calendrier: "Rendez-vous", journee: false, lieu: "", url: URL(string: "https://meet.example.com/abc-defg-hij"),
                       ref: "demo-rdv-1"),
            RendezVous(id: "demo-rdv-2", titre: "Déjeuner avec Julie (architecte)", debut: a(0, 12, 30), fin: a(0, 13, 30),
                       calendrier: "Perso", journee: false, lieu: "Café des Arts", url: nil, ref: "demo-rdv-2"),
            RendezVous(id: "demo-rdv-3", titre: "Salle de sport", debut: a(0, 18, 30), fin: a(0, 19, 30),
                       calendrier: "Salle", journee: false, lieu: "", url: nil, ref: "demo-rdv-3"),
        ]
    }

    /// Les rappels du jour et en retard (non cochés), comme Agenda.charger les range.
    static func rappels() -> [Rappel] {
        let debut = cal.startOfDay(for: Date())
        return [
            (id: "demo-r1", titre: "Relancer la Boulangerie Martin (devis envoyé lundi)", liste: "Appels", quand: a(-1, 11), heure: true),
            (id: "demo-r2", titre: "Appeler l'Atelier Durand pour la visite", liste: "Appels", quand: a(0, 14), heure: true),
            (id: "demo-r3", titre: "Envoyer la facture du Café des Arts", liste: "Freelance", quand: a(0, 9), heure: false),
            (id: "demo-r4", titre: "Tourner la vidéo de demain (sujet : mon carnet de bord)", liste: "Contenu", quand: a(0, 17), heure: true),
            (id: "demo-r5", titre: "❓ Accepter le devis Studio Lumen à 1 800 € ?", liste: "Freelance", quand: a(0, 16), heure: true),
        ].map { r in
            Rappel(id: r.id, titre: r.titre, notes: "", liste: r.liste, echeance: r.quand, enRetard: r.quand < debut,
                   priorite: 0, avecHeure: r.heure)
        }.sorted { ($0.echeance ?? .distantFuture) < ($1.echeance ?? .distantFuture) }
    }

    static func rappelsDemain() -> [Rappel] {
        [
            Rappel(id: "demo-d1", titre: "Préparer la maquette du Café des Arts", notes: "But : client freelance", liste: "Freelance",
                   echeance: a(1, 9), enRetard: false, priorite: 0, avecHeure: true),
            Rappel(id: "demo-d2", titre: "Appeler Plomberie Garnier (rappel promis)", notes: "", liste: "Appels",
                   echeance: a(1, 11), enRetard: false, priorite: 0, avecHeure: true),
        ]
    }

    /// La semaine en grille (page Semaine) : les rendez-vous, rappels et quelques éléments les autres jours.
    static func planning(_ plage: DateInterval) -> [TachePlanning] {
        var t: [TachePlanning] = rendezVous().map {
            TachePlanning(genre: .evenement, ref: $0.ref, idLocal: $0.id, titre: $0.titre, debut: $0.debut, fin: $0.fin,
                          calendrier: $0.calendrier, journee: false, url: $0.url, notes: NotesPlanning.lire(""))
        }
        t += (rappels() + rappelsDemain()).compactMap { r in
            guard let e = r.echeance else { return nil }
            return TachePlanning(genre: .tache, ref: r.id, idLocal: r.id, titre: r.titre, debut: e,
                                 fin: e.addingTimeInterval(r.avecHeure ? TachePlanning.dureeTache : 86400), calendrier: r.liste,
                                 journee: !r.avecHeure, url: nil, notes: NotesPlanning.lire(r.notes))
        }
        let autres: [(Int, Int, String, String, Bool)] = [
            (2, 10, "Rendez-vous chez Atelier Durand", "Rendez-vous", false), (2, 18, "Salle de sport", "Salle", false),
            (3, 9, "Écrire la vidéo de vendredi", "Contenu", true), (3, 14, "Déclarer le chiffre d'affaires", "Papiers", true),
            (-1, 15, "Visio de lancement Studio Lumen", "Rendez-vous", false), (-2, 10, "Envoyer 5 messages de prospection", "KRYVA", true),
        ]
        for (i, o) in autres.enumerated() {
            let d = a(o.0, o.1)
            t.append(TachePlanning(genre: o.4 ? .tache : .evenement, ref: "demo-p\(i)", idLocal: "demo-p\(i)", titre: o.2, debut: d,
                                   fin: d.addingTimeInterval(o.4 ? TachePlanning.dureeTache : 3600), calendrier: o.3, journee: false,
                                   url: nil, notes: NotesPlanning.lire(""), faite: o.0 < 0))
        }
        return t.filter { $0.debut >= plage.start && $0.debut < plage.end }.sorted { ($0.debut, $0.titre) < ($1.debut, $1.titre) }
    }

    /// Les sessions Claude Code « vivantes » de la page Agents.
    static func sessions() -> [ActiviteSession] {
        let maintenant = Date()
        func plan(_ e: [(String, String)]) -> [EtapePlan] { e.map { EtapePlan(contenu: $0.0, statut: $0.1) } }
        var s1 = ActiviteSession(id: "demo-1", sessionApp: "local_demo-1", titre: "Site Studio Lumen", dossier: "~/Projects/studio-lumen",
                                 etat: "busy", depuis: maintenant.addingTimeInterval(-240))
        s1.demande = "Mets la page d'accueil au propre avec les photos de la visio"
        s1.action = "Modifie src/pages/accueil.tsx"; s1.actionLe = maintenant.addingTimeInterval(-20)
        s1.etape = "Intégrer les photos"
        s1.plan = plan([("Relire la maquette validée", "completed"), ("Intégrer les photos", "in_progress"), ("Vérifier sur mobile", "pending")])
        var s2 = ActiviteSession(id: "demo-2", sessionApp: "local_demo-2", titre: "Prospection", dossier: "~/Projects/prospection",
                                 etat: "waiting", depuis: maintenant.addingTimeInterval(-900))
        s2.demande = "Prépare la relance de la Boulangerie Martin"
        s2.recap = "Relance prête dans Pilote, en attente de votre validation."
        s2.question = "J'envoie la relance par SMS ou par mail ?"; s2.choix = ["SMS", "Mail"]; s2.questionGenre = "fin"
        s2.questionRef = "session:demo-2:q1"
        var s3 = ActiviteSession(id: "demo-3", sessionApp: "local_demo-3", titre: "Vidéos", dossier: "~/Projects/videos",
                                 etat: "idle", depuis: maintenant.addingTimeInterval(-5400))
        s3.demande = "Écris le prompteur de la vidéo de demain"
        s3.recap = "Prompteur écrit (45 s), accroche et fin vérifiées."
        s3.fichiers = ["~/Projects/videos/demain/prompteur.md"]
        return [s1, s2, s3]
    }
}

// MARK: La base fictive (remplie au premier lancement en démo, si elle n'a aucun contact)

extension DemoDonnees {
    private static func iso(_ jours: Int, _ h: Int, _ m: Int = 0) -> String { Dates.iso.string(from: a(jours, h, m)) }
    private static func jour(_ jours: Int) -> String { Dates.jour.string(from: a(jours, 9)) }

    /// Les jours ouvrés à partir d'aujourd'hui (les vidéos ne se posent pas le week-end).
    private static func ouvres(_ n: Int) -> [String] {
        (0..<10).map { jour($0) }.filter { VideoCalcul.estOuvre($0) }.prefix(n).map { $0 }
    }

    /// Le dépôt de l'app, vu par la carte « App » : deux changements en ligne, un prêt qui attend.
    static func commits(maintenant: Date = Date()) -> [CommitKryva] {
        [
            CommitKryva(hash: "d3m0a1", sujet: "feat: devis en un clic depuis la fiche chantier", le: maintenant.addingTimeInterval(-26 * 3600), enLigne: true),
            CommitKryva(hash: "d3m0a2", sujet: "fix: la photo du chantier s'affiche sur iPhone", le: maintenant.addingTimeInterval(-5 * 3600), enLigne: true),
            CommitKryva(hash: "d3m0a3", sujet: "feat: relance automatique des devis sans réponse", le: maintenant.addingTimeInterval(-2 * 3600), enLigne: false),
        ]
    }

    /// L'équipe fictive (EQUIPE.md) : PILOTE, les sessions de domaine, et les chantiers des sessions de démo.
    static func ecrireFichiers(dans maison: URL) {
        ecrireReglages(dans: maison)
        let dossier = maison.appendingPathComponent("Library/Application Support/\(Identite.app)")
        let fichier = dossier.appendingPathComponent("EQUIPE.md")
        guard !FileManager.default.fileExists(atPath: fichier.path) else { return }
        try? FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
        let texte = """
        # Équipe (démo)

        | Session | id | Domaine | Dossiers |
        |---|---|---|---|
        | PILOTE | local_demo-0 | tout | ~/Projects/pilote |
        | KRYVA · App et interface | local_demo-4 | app | ~/Projects/app |
        | KRYVA · Ventes | local_demo-5 | ventes | ~/Projects/prospection |
        | KRYVA · Réseaux, image, événements | local_demo-6 | reseaux | ~/Projects/videos |
        | FREELANCE | local_demo-7 | freelance | ~/Projects/studio-lumen |

        | Chantier | id | Remonte à |
        |---|---|---|
        | Site Studio Lumen | local_demo-1 | FREELANCE |
        | Prospection | local_demo-2 | KRYVA · Ventes |
        | Vidéos | local_demo-3 | KRYVA · Réseaux, image, événements |

        """
        try? texte.write(to: fichier, atomically: true, encoding: .utf8)
    }

    /// Des réglages fictifs (prénom, dossiers, routines) : sans eux, la démo montrerait une app vide de réglages.
    /// Aucune clé : en démo, rien ne part sur le réseau de toute façon.
    private static func ecrireReglages(dans maison: URL) {
        let fichier = maison.appendingPathComponent("Library/Application Support/\(Identite.app)/reglages.json")
        guard !FileManager.default.fileExists(atPath: fichier.path) else { return }
        try? FileManager.default.createDirectory(at: fichier.deletingLastPathComponent(), withIntermediateDirectories: true)
        let texte = """
        {
          "prenom": "Louis",
          "dossiers_sessions": [
            { "nom": "App", "chemin": "~/Projects/app" },
            { "nom": "Prospection", "chemin": "~/Projects/prospection" },
            { "nom": "Vidéos", "chemin": "~/Projects/videos" }
          ],
          "routines": [
            { "id": "matin", "titre": "Point du matin", "detail": "Réponses reçues, relances à préparer",
              "dossier": "~/Projects/prospection",
              "consigne": "Fais le point des réponses reçues et propose les relances à préparer dans Pilote. Rien ne part sans mon accord." },
            { "id": "soir", "titre": "Bilan du soir", "detail": "Ce qui est fait, ce qui reste pour demain",
              "dossier": "~/Projects/app",
              "consigne": "Fais le bilan de la journée et range ce qui reste pour demain dans Pilote." }
          ],
          "depot_suivi": "~/Projects/app",
          "rappels_calendrier": true,
          "mail": true
        }
        """
        try? texte.write(to: fichier, atomically: true, encoding: .utf8)
    }

    static func remplirSiVide(_ stock: Stockage) throws {
        guard Demo.actif, try stock.contacts().isEmpty else { return }
        typealias Fiche = (contact: [String: Any], fil: [[String: Any]])
        let fiches: [Fiche] = [
            (["espace": "freelance", "type": "client", "nom": "Camille Roux", "entreprise": "Studio Lumen", "ville": "Lyon",
              "telephone": "06 39 98 00 01", "email": "camille@studio-lumen.example", "etape": "rdv",
              "prochaine_action": "\(Moi.nom) : visio de la maquette à 10 h", "prochaine_date": jour(0), "source": "demo", "source_ref": "demo-1"],
             [["le": iso(-6, 9, 40), "canal": "mail", "sens": "sortant", "type": "message", "statut": "envoye", "par": "\(Moi.nom)",
               "objet": "Devis : site vitrine", "texte": "Bonjour Camille, voici le devis du site vitrine (5 pages, 1 800 €). Bonne journée."],
              ["le": iso(-3, 16, 5), "canal": "mail", "sens": "entrant", "type": "reponse", "statut": "fait", "par": "Camille Roux",
               "objet": "Re: Devis : site vitrine", "texte": "Merci ! On en parle en visio ? Jeudi 10 h, ça vous va ?"],
              ["le": iso(-3, 16, 30), "canal": "visio", "sens": "sortant", "type": "rdv", "statut": "fait", "par": "\(Moi.nom)",
               "texte": "Visio fixée aujourd'hui 10 h : maquette de la page d'accueil."]]),
            (["espace": "freelance", "type": "client", "nom": "Thomas Petit", "entreprise": "Café des Arts", "ville": "Nantes",
              "telephone": "06 39 98 00 02", "email": "thomas@cafe-des-arts.example", "etape": "gagne",
              "prochaine_action": "Envoyer la facture de novembre", "prochaine_date": jour(0), "source": "demo", "source_ref": "demo-2"],
             [["le": iso(-12, 11), "canal": "visite", "sens": "sortant", "type": "visite", "statut": "fait", "par": "\(Moi.nom)",
               "texte": "Menu en ligne et page de réservation livrés."],
              ["le": iso(0, 8, 15), "canal": "mail", "sens": "sortant", "type": "message", "statut": "prepare", "par": "Pilote",
               "objet": "Facture de novembre", "texte": "Bonjour Thomas, voici la facture de novembre pour la page de réservation. Merci encore pour votre confiance. Bonne journée."]]),
            (["espace": "kryva", "type": "artisan", "nom": "Paul Durand", "entreprise": "Atelier Durand Menuiserie", "ville": "Rennes",
              "telephone": "06 39 98 00 03", "etape": "repondu", "prochaine_action": "\(Moi.nom) : appeler pour fixer la visite",
              "prochaine_date": jour(0), "source": "demo", "source_ref": "demo-3"],
             [["le": iso(-5, 10), "canal": "sms", "sens": "sortant", "type": "message", "statut": "envoye", "par": "\(Moi.nom)",
               "texte": "Bonjour Monsieur Durand, on aide les menuisiers à faire leurs devis depuis le chantier. Je peux vous montrer en 10 minutes ?"],
              ["le": iso(-1, 18, 20), "canal": "sms", "sens": "entrant", "type": "reponse", "statut": "fait", "par": "Paul Durand",
               "texte": "Oui, passez à l'atelier, appelez-moi avant."]]),
            (["espace": "kryva", "type": "artisan", "nom": "Sophie Martin", "entreprise": "Boulangerie Martin", "ville": "Tours",
              "telephone": "06 39 98 00 04", "etape": "contacte", "prochaine_action": "Relancer par SMS",
              "prochaine_date": jour(-1), "source": "demo", "source_ref": "demo-4"],
             [["le": iso(-4, 9), "canal": "sms", "sens": "sortant", "type": "message", "statut": "envoye", "par": "\(Moi.nom)",
               "texte": "Bonjour Madame Martin, suite à notre échange en boutique, voici le lien pour essayer. Bonne journée."],
              ["le": iso(0, 7, 50), "canal": "sms", "sens": "sortant", "type": "message", "statut": "prepare", "par": "Prospection",
               "texte": "Bonjour Madame Martin, avez-vous pu essayer ? Je peux passer jeudi pour vous montrer. Bonne journée."]]),
            (["espace": "kryva", "type": "artisan", "nom": "Luc Garnier", "entreprise": "Plomberie Garnier", "ville": "Bordeaux",
              "telephone": "06 39 98 00 05", "etape": "a_contacter", "prochaine_action": "Premier message",
              "prochaine_date": jour(1), "source": "demo", "source_ref": "demo-5"], []),
            (["espace": "freelance", "type": "partenaire", "nom": "Julie Moreau", "entreprise": "Moreau Architecture", "ville": "Paris",
              "email": "julie@moreau-archi.example", "etape": "rdv", "prochaine_action": "\(Moi.nom) : déjeuner 12 h 30",
              "prochaine_date": jour(0), "source": "demo", "source_ref": "demo-6"],
             [["le": iso(-2, 14), "canal": "linkedin", "sens": "entrant", "type": "message", "statut": "fait", "par": "Julie Moreau",
               "texte": "J'ai deux clients qui cherchent un site, on déjeune cette semaine ?"]]),
            (["espace": "kryva", "type": "artisan", "nom": "Marc Fontaine", "entreprise": "Garage Fontaine", "ville": "Lille",
              "telephone": "06 39 98 00 06", "etape": "perdu", "source": "demo", "source_ref": "demo-7"],
             [["le": iso(-9, 15), "canal": "appel", "sens": "sortant", "type": "appel", "statut": "fait", "par": "\(Moi.nom)",
               "texte": "Pas intéressé pour l'instant, déjà équipé."]]),
        ]
        try stock.base.transaction {
            for f in fiches {
                let c = try stock.enregistrer(f.contact)
                for e in f.fil { _ = try stock.ajouterEvenement(contactId: c.id, e) }
            }
            for p: [String: Any] in [
                ["espace": "freelance", "nom": "Site Studio Lumen", "description": "Site vitrine, 5 pages", "dossier": "~/Projects/studio-lumen", "statut": "actif"],
                ["espace": "freelance", "nom": "Prospection", "description": "Messages et relances", "dossier": "~/Projects/prospection", "statut": "actif"],
                ["espace": "perso", "nom": "Vidéos", "description": "Une vidéo par jour ouvré", "dossier": "~/Projects/videos", "statut": "actif"],
                ["espace": "outils", "nom": "Pilote", "description": "Ce carnet de bord", "dossier": "~/Projects/pilote", "statut": "actif"],
            ] { _ = try stock.enregistrerProjet(p) }
            let journal: [[String: Any]] = [
                ["le": iso(0, 9, 12), "type": "livrable", "titre_session": "Site Studio Lumen", "dossier": "~/Projects/studio-lumen",
                 "texte": "Page d'accueil intégrée d'après la maquette validée, vérifiée sur mobile.", "fichiers": ["~/Projects/studio-lumen/src/pages/accueil.tsx"]],
                ["le": iso(0, 8, 15), "type": "livrable", "titre_session": "Prospection", "dossier": "~/Projects/prospection",
                 "texte": "Facture du Café des Arts et relance de la Boulangerie Martin prêtes, à valider."],
                ["le": iso(-1, 19, 40), "type": "livrable", "titre_session": "Vidéos", "dossier": "~/Projects/videos",
                 "texte": "Prompteur de la vidéo de demain écrit (45 s).", "fichiers": ["~/Projects/videos/demain/prompteur.md"]],
                ["le": iso(-1, 17), "type": "note", "titre_session": "Pilote", "dossier": "~/Projects/pilote",
                 "texte": "Copie publique de Pilote vérifiée : aucune donnée réelle."],
            ]
            for j in journal { _ = try stock.ajouterJournal(j) }
            let jours = ouvres(3)
            let videos: [[String: Any]] = [
                ["jour": jours[0], "compte": "perso", "sujet": "Mon carnet de bord tient tout seul grâce à Claude", "statut": "prete", "heure": "18:00"],
                ["jour": jours[1], "compte": "perso", "sujet": "Trois erreurs de débutant en freelance", "statut": "valide"],
                ["jour": jours[2], "compte": "kryva", "sujet": "Faire un devis depuis le chantier", "statut": "a_choisir"],
            ]
            for v in videos { _ = try stock.enregistrerVideo(v) }
        }
    }
}
