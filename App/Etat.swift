// L'état de l'app : la base locale, relue dès que l'outil `pilote` (ou Claude) y écrit.
import SwiftUI

/// Un seul écran d'ouverture (09/11, Sacha) : « Accueil ». Les autres pages s'ouvrent par ⌘K (RechercheVue, « Pages »).
enum Ecran: String, CaseIterable, Identifiable {
    case aujourdhui, journee, semaine, prospects, planning, taches, contacts, projets, stats, publications, claude
    var id: String { rawValue }
    /// Les pages ouvertes par ⌘K (tout sauf l'accueil).
    static let pages: [Ecran] = [.journee, .prospects, .contacts, .semaine, .publications, .planning, .taches, .projets, .stats, .claude]
    var titre: String {
        switch self {
        case .aujourdhui: return L("Accueil")
        case .journee: return L("Journée en détail")
        case .semaine: return L("Vidéos")
        case .prospects: return L("Prospects")
        case .planning: return L("Planning")
        case .taches: return L("Tâches")
        case .contacts: return L("Tous les contacts")
        case .projets: return L("Projets")
        case .stats: return L("Stats vidéos")
        case .publications: return L("Publications")
        case .claude: return L("Agents")
        }
    }
    /// Ce qu'on trouve sur la page (pour ⌘K).
    var resume: String {
        switch self {
        case .aujourdhui: return L("les gestes du moment et les 5 domaines")
        case .journee: return L("l'ancien écran du jour : file d'envoi, agents, demain, inscrits, chiffres")
        case .semaine: return L("vidéos de la semaine, prompteurs, sujets")
        case .prospects: return L("les personnes suivies, par étape")
        case .planning: return L("rendez-vous et agenda")
        case .taches: return L("les Rappels, par jour")
        case .contacts: return L("tout le carnet")
        case .projets: return L("la carte des projets et leur état")
        case .stats: return L("vues et verdicts des vidéos postées")
        case .publications: return L("publications programmées et à valider")
        case .claude: return L("les sessions et ce qu'elles font")
        }
    }
    var symbole: String {
        switch self {
        case .aujourdhui: return "house"
        case .journee: return "sun.max"
        case .semaine: return "video"
        case .prospects: return "person.2"
        case .planning: return "calendar"
        case .taches: return "rectangle.split.3x1"
        case .contacts: return "list.bullet"
        case .projets: return "folder"
        case .stats: return "chart.bar"
        case .publications: return "play.rectangle.on.rectangle"
        case .claude: return "sparkle"
        }
    }
}

// MessageAEnvoyer : Shared/ATOI.swift.

/// 09/11 (écran unique) : tout ce que `charger()` lit, lu d'un coup hors du fil principal sur la connexion de lecture.
struct LectureEtat {
    var version = 0
    var jour = ""
    var erreur: String?
    var contacts: [Contact] = []
    var dus: [Contact] = []
    var journeesAgents: [JourneeAgent] = []
    var aEnvoyer: [MessageAEnvoyer] = []
    var fileEnvoi: [ElementFile] = []
    var candidatsFile: [CandidatFile] = []
    var aValider: [MessageAEnvoyer] = []
    var aRefaire: [MessageAEnvoyer] = []
    var projets: [Projet] = []
    var videos: [Video] = []
    var echanges: [String: DernierEchange] = [:]
    var journal: [EntreeJournal] = []
    var radar: [RadarClassement] = []

    init(_ stock: Stockage) {
        // La version d'abord : une écriture faite pendant la lecture sera vue au tour suivant.
        version = stock.base.versionDonnees()
        jour = Dates.aujourdhui()
        do {
            contacts = try stock.contacts()
            dus = try stock.dusSacha()   // ses gestes seulement ; le reste est la liste du jour des agents (05/11)
            journeesAgents = (try? stock.journeesAgents()) ?? []
            aEnvoyer = try stock.aEnvoyer().map { MessageAEnvoyer(evenement: $0.0, contact: $0.1) }
            fileEnvoi = (try? FileEnvoi.duJour(stock)) ?? []
            candidatsFile = (try? FileEnvoi.candidats(stock, outils: .mac)) ?? []
            aValider = try stock.messages(statut: "a_valider").map { MessageAEnvoyer(evenement: $0.0, contact: $0.1) }
            aRefaire = try stock.messages(statut: "a_refaire").map { MessageAEnvoyer(evenement: $0.0, contact: $0.1) }
            projets = try stock.projets()
            videos = try stock.videos(du: "0000-00-00", au: "9999-99-99", reserve: true)
            echanges = try stock.derniersEchanges()
            journal = try stock.journal(limite: 300)
            radar = (try? RadarVocabulaire.espaces.map { try stock.radarClassement(espace: $0) }) ?? []
        } catch {
            erreur = "\(error)"
        }
    }
}

@MainActor @Observable
final class Etat {
    /// La connexion des gestes (écritures). Ouverte hors du fil principal au lancement : nil les premières millisecondes.
    private(set) var stock: Stockage?
    /// 09/11 : une seconde connexion, pour les lectures seulement, toujours hors du fil principal (mode WAL : elle ne bloque pas
    /// les écritures). Sa `data_version` change à chaque écriture d'une autre connexion, celle des gestes comprise.
    @ObservationIgnored private(set) var lecteur: Stockage?
    @ObservationIgnored private var lectureEnCours = false
    @ObservationIgnored private var relire = false
    @ObservationIgnored private var jourLu = ""
    /// Vrai dès la première lecture finie : l'écran montre ses squelettes avant, jamais un faux « vide ».
    var premiereLecture = false
    var erreurBase: String?
    /// 05/11 (T34) : témoins arrêtés (capteur, veille, Facteur, inscrits, disque, WhatsApp), affichés en rouge en haut d'Aujourd'hui.
    var arrets: [String] = []
    var contacts: [Contact] = []
    var dus: [Contact] = []
    /// La liste du jour de chaque agent : traitées et restantes (05/11).
    var journeesAgents: [JourneeAgent] = []
    var aEnvoyer: [MessageAEnvoyer] = []
    /// La file d'envoi des mails validés : ce qui attend et ce qui est passé aujourd'hui (07/11, Shared/FileEnvoi.swift).
    var fileEnvoi: [ElementFile] = []
    /// Les mails « prepare » que le bouton « Envoyer les mails validés » propose (refus compris, comme `pilote envoie`).
    var candidatsFile: [CandidatFile] = []
    /// Brouillons dont Sacha doit lire le texte exact (03/11) ; ceux qu'il a renvoyés à l'agent avec une consigne.
    var aValider: [MessageAEnvoyer] = []
    var aRefaire: [MessageAEnvoyer] = []
    /// Le fichier montré dans le panneau de droite (chemin complet), nil si le panneau est fermé.
    var apercu: String?
    /// La fiche montrée dans le panneau de droite (id du contact), nil si aucune. Un seul panneau à la fois : fiche ou fichier.
    var fichePanneau: Contact.ID?
    /// Les fiches en cours de modification : l'état avant la première frappe, et la minuterie qui consigne la rafale.
    @ObservationIgnored private var avantModification: [String: Contact] = [:]
    @ObservationIgnored private var minuteriesModification: [String: Task<Void, Never>] = [:]
    /// Les choix faits aujourd'hui dans Pilote, et s'ils sont partis (relu toutes les 4 secondes).
    var decisionsEnvoyees: [Decisions.Envoyee] = []
    var prochaineVeille: Date?
    /// Les messages de Sacha aux sessions (48 h) et si le Facteur attend (envoi en quelques secondes).
    var messagesSessions: [Facteur.Message] = []
    var facteurActif = false
    /// Les questions de session (wrap_up) auxquelles Sacha a déjà répondu dans Pilote.
    var questionsRepondues: Set<String> = []
    /// Les vidéos (toutes : la table est petite) et le dernier échange de chaque contact.
    var videos: [Video] = []
    /// 04/11 : le suivi de chaque vidéo postée (chiffres lus dans reseaux-stats/stats.sqlite, verdicts dans Pilote).
    var suivi = SuiviCharge()
    var suiviSelection: PostVideo.ID?
    private var suiviSignature = ""
    var echanges: [String: DernierEchange] = [:]
    /// PILOTE_ECRAN=stats (par exemple) ouvre l'app directement sur cet écran : pratique pour la vérifier sans cliquer.
    var ecran: Ecran = Ecran(rawValue: ProcessInfo.processInfo.environment["PILOTE_ECRAN"] ?? "") ?? .aujourdhui
    var selection: Contact.ID?
    var projets: [Projet] = []
    var journal: [EntreeJournal] = []
    /// Les sessions Claude Code qui tournent, et ce qu'elles font (relu toutes les 4 secondes).
    var agents: [ActiviteSession] = []
    var projetSelection: Projet.ID?
    var rechercheOuverte = false
    /// Le Radar : classement de chaque espace (kryva, perso), relu avec le reste, et sa feuille.
    var radar: [RadarClassement] = []
    var radarOuvert = false
    /// Augmente à chaque rechargement : les fiches ouvertes relisent leur fil.
    var revision = 0
    /// Dernière synchro KRYVA avec l'admin : nil si tout va bien, sinon ce qui a coincé.
    var erreurSynchro: String?
    private var version = 0

    // MARK: Lectures lentes gardées ici (et non dans les écrans, qui sont recréés à chaque changement d'onglet)
    var mails: [MessageMail] = []
    var etatMails: Chargement = .attente
    var compteur: Compteur?
    var etatCompteur: Chargement = .attente
    var inscrits: [Inscrit] = []
    var etatInscrits: Chargement = .attente
    /// Statut de chaque compte inscrit (module comptes : id → statut), relu toutes les 5 minutes au plus.
    var statutsComptes: [String: StatutCompte] = [:]
    var erreurStatutsComptes: String?
    @ObservationIgnored private var dernierComptes: Date?
    @ObservationIgnored private var enCoursComptes = false
    /// La pyramide des agents (relue avec les sessions vivantes, toutes les 4 secondes).
    var pyramide = Pyramide()
    var pyramideChargee = false
    /// Les sessions récentes de l'app Claude (relues toutes les 12 secondes environ).
    var recentes: [SessionClaude] = []
    var recentesChargees = false
    @ObservationIgnored private var dernierMails: Date?
    @ObservationIgnored private var dernierCompteur: Date?
    @ObservationIgnored private var dernierInscrits: Date?
    @ObservationIgnored private var enCoursMails = false
    @ObservationIgnored private var enCoursCompteur = false
    @ObservationIgnored private var enCoursInscrits = false

    init() {
        Task { await ouvrirBase() }
        Task { await suivreAgents() }
    }

    /// 09/11 : la base s'ouvre (et se met à jour) hors du fil principal ; la fenêtre se dessine sans l'attendre.
    private func ouvrirBase() async {
        let (gestes, lectures, erreur) = await Task.detached(priority: .userInitiated) { () -> (Stockage?, Stockage?, String?) in
            do {
                let g = Stockage(base: try Base())
                try DemoDonnees.remplirSiVide(g)
                return (g, Stockage(base: try Base()), nil)
            } catch {
                let detail = "\(error)"
                return (nil, nil, L("La base de Pilote ne s'ouvre pas : \(detail)"))
            }
        }.value
        stock = gestes
        lecteur = lectures
        erreurBase = erreur
        guard gestes != nil else { premiereLecture = true; return }
        charger()
        // Liaison facultative avec Pip (réunions de l'agenda) : ne fait rien si Pip n'est pas installé.
        PipLiaison.partage.demarrer(stock: { [weak self] in self?.stock }, apres: { [weak self] in self?.charger() })
        Task { await surveiller() }
        // Sur une copie de la base (PILOTE_BASE, essais) : ni synchro avec l'admin KRYVA, ni sauvegarde iCloud.
        if !FileEnvoi.surCopie() {
            Task { await synchroniser() }
            sauvegarderSiBesoin()
        }
    }

    /// Relit le suivi des vidéos si stats.sqlite ou la base de Pilote (verdicts, planning) a changé depuis la dernière lecture.
    func chargerSuivi(force: Bool = false) {
        guard let stock else { return }
        let modif = (try? FileManager.default.attributesOfItem(atPath: SuiviVideo.cheminStats.path)[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let signature = "\(modif)|\(stock.base.versionDonnees())"
        guard force || signature != suiviSignature else { return }
        suivi = SuiviVideo.charger(stock: stock)
        suiviSignature = signature
    }

    /// 09/11 : relit la base hors du fil principal, puis ne remplace que ce qui a changé (un écran qui ne lit pas une liste
    /// inchangée n'est pas redessiné). Un appel pendant une lecture en relance une seule à la fin.
    func charger() {
        guard let lecteur else { return }
        if lectureEnCours { relire = true; return }
        lectureEnCours = true
        Task.detached(priority: .userInitiated) { [weak self] in
            let lu = LectureEtat(lecteur)
            await self?.appliquer(lu)
        }
    }

    private func maj<T: Equatable>(_ chemin: ReferenceWritableKeyPath<Etat, T>, _ valeur: T) {
        if self[keyPath: chemin] != valeur { self[keyPath: chemin] = valeur }
    }

    private func maj<T>(_ chemin: ReferenceWritableKeyPath<Etat, T>, _ valeur: T) {
        self[keyPath: chemin] = valeur
    }

    private func appliquer(_ l: LectureEtat) {
        lectureEnCours = false
        if let e = l.erreur {
            erreurBase = L("Lecture impossible : \(e)")
        } else {
            if erreurBase != nil { erreurBase = nil }
            maj(\.contacts, l.contacts)
            maj(\.dus, l.dus)
            maj(\.journeesAgents, l.journeesAgents)
            maj(\.aEnvoyer, l.aEnvoyer)
            maj(\.fileEnvoi, l.fileEnvoi)
            maj(\.candidatsFile, l.candidatsFile)
            maj(\.aValider, l.aValider)
            maj(\.aRefaire, l.aRefaire)
            maj(\.projets, l.projets)
            maj(\.videos, l.videos)
            maj(\.echanges, l.echanges)
            maj(\.journal, l.journal)
            maj(\.radar, l.radar)
            revision += 1
            if ecran == .stats { chargerSuivi() }
        }
        version = l.version
        jourLu = l.jour
        if !premiereLecture { premiereLecture = true }
        if relire { relire = false; charger() }
    }

    /// Toutes les 2 secondes, hors du fil principal : si une autre connexion a écrit dans la base (ou si le jour a changé), on relit.
    private func surveiller() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(2))
            guard let lecteur else { continue }
            let v = await Task.detached { lecteur.base.versionDonnees() }.value
            if v != version || Dates.aujourdhui() != jourLu { charger() }
        }
    }

    /// Au lancement puis toutes les 60 secondes, si reglages.json l'active (`synchro`) : contacts et fil d'un espace
    /// échangés avec les tables distantes. Sa propre connexion à la base, hors du fil principal ; la surveillance relit ensuite l'écran.
    private func synchroniser() async {
        while !Task.isCancelled {
            guard Reglages.courants.synchro != nil, !Demo.actif else {
                erreurSynchro = nil
                try? await Task.sleep(for: .seconds(60))
                continue
            }
            erreurSynchro = await Task.detached { () -> String? in
                do {
                    let bilan = try Synchro(base: try Base()).lancer()
                    return bilan.erreurs.isEmpty ? nil : bilan.erreurs.prefix(3).joined(separator: "\n")
                } catch { return "\(error)" }
            }.value
            try? await Task.sleep(for: .seconds(60))
        }
    }

    /// Toutes les 4 secondes, hors du fil principal : sessions vivantes et pyramide (une seule lecture des sessions pour les deux).
    /// Les sessions récentes de l'app Claude (lecture plus lourde) suivent une fois sur trois.
    private func suivreAgents() async {
        var tour = 0
        while !Task.isCancelled {
            let (vivantes, pyr) = await Task.detached { () -> ([ActiviteSession], Pyramide) in
                let v = Sessions.vivantes()
                return (v, Equipe.pyramide(vivantes: v))
            }.value
            if vivantes != agents { agents = vivantes }
            pyramide = pyr
            if !pyramideChargee { pyramideChargee = true }
            await relireDecisionsHorsFil()
            if tour % 3 == 0 {
                recentes = await Task.detached { Claude.sessions() }.value
                recentesChargees = true
            }
            tour += 1
            try? await Task.sleep(for: .seconds(4))
        }
    }

    // MARK: Aujourd'hui : mails, compteur, inscrits (lus une fois, relus s'ils ont plus de 3 à 5 minutes)

    /// Relit ce qui est périmé (mails et inscrits : 3 min, compteur : 5 min) ; `force` relit tout.
    /// Les données déjà affichées restent à l'écran pendant la relecture, et en cas d'échec.
    func actualiserAujourdhui(force: Bool = false) async {
        async let a: Void = chargerMails(force: force)
        async let b: Void = chargerCompteur(force: force)
        async let c: Void = chargerInscrits(force: force)
        _ = await (a, b, c)
    }

    private func frais(_ date: Date?, _ duree: TimeInterval) -> Bool {
        guard let date else { return false }
        return Date().timeIntervalSince(date) < duree
    }

    private static let mailsGardes = Demo.maison
        .appendingPathComponent("Library/Application Support/\(Identite.app)/mails.json")

    func chargerMails(force: Bool = false) async {
        guard !enCoursMails, force || !frais(dernierMails, 180) else { return }
        enCoursMails = true
        defer { enCoursMails = false }
        // Mail met 15 à 20 s à répondre au lancement : on montre d'abord la dernière liste gardée sur disque.
        if mails.isEmpty, let data = try? Data(contentsOf: Etat.mailsGardes),
           let gardes = try? JSONDecoder().decode([MessageMail].self, from: data) {
            mails = gardes
            etatMails = .pret
        }
        if etatMails != .pret { etatMails = .enCours }
        do {
            let recus = try await Mail.recus(jours: 3)
            let adresses = Set(contacts.map { $0.email.lowercased() }.filter { !$0.isEmpty })
            mails = recus.filter { adresses.contains($0.adresse) }.sorted { $0.date > $1.date }
            etatMails = .pret
            dernierMails = Date()
            if let data = try? JSONEncoder().encode(mails) { try? data.write(to: Etat.mailsGardes) }
        } catch {
            if etatMails != .pret { etatMails = .erreur(error.localizedDescription) }
        }
    }

    func chargerCompteur(force: Bool = false) async {
        guard !enCoursCompteur, force || !frais(dernierCompteur, 300) else { return }
        enCoursCompteur = true
        defer { enCoursCompteur = false }
        if compteur == nil { etatCompteur = .enCours }
        do {
            compteur = try await Comptes.compteur()
            etatCompteur = .pret
            dernierCompteur = Date()
        } catch {
            if compteur == nil { etatCompteur = .erreur(error.localizedDescription) }
        }
    }

    func chargerInscrits(force: Bool = false) async {
        guard !enCoursInscrits, force || !frais(dernierInscrits, 180) else { return }
        enCoursInscrits = true
        defer { enCoursInscrits = false }
        if etatInscrits != .pret { etatInscrits = .enCours }
        do {
            inscrits = try await Comptes.inscrits()
            etatInscrits = .pret
            dernierInscrits = Date()
        } catch {
            if etatInscrits != .pret { etatInscrits = .erreur(error.localizedDescription) }
        }
    }

    func chargerStatutsComptes(force: Bool = false) async {
        guard !enCoursComptes, force || !frais(dernierComptes, 300) else { return }
        enCoursComptes = true
        defer { enCoursComptes = false }
        do {
            statutsComptes = try await Comptes.statutsComptes()
            erreurStatutsComptes = nil
            dernierComptes = Date()
        } catch {
            let detail = error.localizedDescription
            erreurStatutsComptes = L("Statuts des comptes non lus : \(detail)")
        }
    }

    /// Le projet de la carte qui contient ce dossier (le plus précis gagne).
    func projet(pour dossier: String) -> Projet? {
        let chemin = Chemins.complet(dossier)
        return projets.filter { p in
            let d = p.cheminComplet
            return !d.isEmpty && (chemin == d || chemin.hasPrefix(d + "/"))
        }.max { $0.cheminComplet.count < $1.cheminComplet.count }
    }

    func agents(dans p: Projet) -> [ActiviteSession] {
        agents.filter { projet(pour: $0.dossier)?.id == p.id }
    }

    func enregistrer(projet champs: [String: Any]) {
        guard let stock else { return }
        do { try stock.enregistrerProjet(champs); charger() } catch { erreurBase = erreurEnregistrement(error) }
    }

    func ouvrir(projet id: String) {
        projetSelection = id
        ecran = .projets
    }

    /// « Envoyer ces N mails » : le fil des « Re: » sans reponse_a est cherché dans Mail ici (l'app a le droit de le piloter,
    /// pas l'agent launchd), puis les mails entrent dans la file et l'agent est réveillé pour le premier. Renvoie l'erreur à montrer.
    func mettreEnFile(_ ids: [String]) async -> String? {
        guard let stock else { return L("La base de Pilote n'est pas ouverte.") }
        var fils: [String: String] = [:]
        for id in ids {
            guard let e = try? stock.evenement(id), FileEnvoi.filACherche(e), let c = try? stock.contact(e.contactId) else { continue }
            if let f = try? await Mail.dernierRecu(de: c.email.trimmingCharacters(in: .whitespaces), objet: e.objet, delaiMax: 75), !f.isEmpty {
                fils[id] = f
            }
        }
        do {
            try FileEnvoi.mettreEnFile(stock, ids: ids, fils: fils, outils: .mac)
        } catch {
            let detail = "\(error)"
            return L("Mise en file impossible, rien ne part : \(detail)")
        }
        charger()
        return FileEnvoi.reveillerAgent()
    }

    /// « Arrêter la file » : ce qui attend est annulé et reste à envoyer.
    func arreterFile() -> String? {
        guard let stock else { return L("La base de Pilote n'est pas ouverte.") }
        do { try FileEnvoi.arreter(stock, raison: "file arrêtée par \(Moi.nom) (bouton « Arrêter la file »)") } catch { return "\(error)" }
        charger()
        return nil
    }

    private func sauvegarderSiBesoin() {
        let cle = "derniereSauvegarde"
        guard UserDefaults.standard.string(forKey: cle) != Dates.aujourdhui(), let stock else { return }
        Task.detached {
            if (try? stock.sauvegardeDuJour()) != nil {
                await MainActor.run { UserDefaults.standard.set(Dates.aujourdhui(), forKey: cle) }
            }
        }
    }

    // MARK: Actions

    func contact(_ id: String?) -> Contact? {
        guard let id else { return nil }
        return contacts.first { $0.id == id }
    }

    /// Une modification de la fiche : enregistrée tout de suite ; la trace au fil et l'avis à l'agent partent une fois la rafale
    /// de frappes finie (3 s sans rien de neuf), avec ce qui a changé entre le début et la fin.
    func enregistrer(_ c: Contact) {
        guard let stock else { return }
        if avantModification[c.id] == nil, let avant = contact(c.id) { avantModification[c.id] = avant }
        do { try stock.enregistrer(c); charger() } catch { erreurBase = erreurEnregistrement(error) }
        minuteriesModification[c.id]?.cancel()
        minuteriesModification[c.id] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.consignerModification(c.id)
        }
    }

    private func consignerModification(_ id: String) {
        minuteriesModification[id] = nil
        guard let stock, let avant = avantModification.removeValue(forKey: id), let apres = contact(id) else { return }
        guard let note = try? stock.consignerChangements(avant: avant, apres: apres) else { return }
        charger()
        informerAgent(apres, note)
    }

    /// L'agent du contact (Ventes ou FREELANCE) apprend ce que Sacha vient de faire : le Facteur le lui remet. Il relit la fiche,
    /// met l'étape, la prochaine action et la date à jour, et prend les dispositions (texte à préparer, relance).
    func informerAgent(_ c: Contact, _ fait: String) {
        let nom = Self.nomComplet(c)
        try? Decisions.noter(question: "Suivi de \(nom) (\(c.id))",
                             choix: "\(fait). La fiche porte déjà la trace au fil. À toi : vérifie l'étape, la prochaine action et la date, prends les dispositions (texte à préparer pour validation, relance), n'oublie rien.",
                             ref: "suivi:\(c.id):\(Int(Date().timeIntervalSince1970))",
                             liste: c.espace == "kryva" ? "Appels" : "Freelance", pour: Self.auteur(c))
    }

    func nouveauContact(espace: String, type: String? = nil) {
        guard let stock else { return }
        if let c = try? stock.enregistrer(["espace": espace, "type": type ?? (espace == "freelance" ? "client" : "autre")]) {
            charger()
            ecran = .prospects
            selection = c.id
        }
    }

    func supprimer(_ id: String) {
        guard let stock else { return }
        try? stock.supprimer(id)
        if selection == id { selection = nil }
        charger()
    }

    /// La fiche glisse dans le panneau de droite, comme un document : on reste sur la page où l'on est (04/11, Sacha).
    func ouvrir(_ c: Contact) {
        apercu = nil
        fichePanneau = c.id
    }

    /// L'ancien comportement : la page Prospects avec la fiche sélectionnée (bouton du panneau).
    func ouvrirDansProspects(_ c: Contact) {
        fichePanneau = nil
        ecran = .prospects
        selection = c.id
    }

    // MARK: Vidéos

    func video(jour: String, compte: String) -> Video? {
        videos.first { $0.jour == jour && $0.compte == compte }
    }

    /// Change l'état de la vidéo de ce jour et de ce compte (la crée au besoin).
    /// Une étape de vidéo cochée (ou décochée) dans Ma journée : la vidéo change de statut, et la session Réseaux l'apprend.
    func marquerVideoJournee(jour: String, compte: String, action: String, fait: Bool) {
        guard let statut = VideoCalcul.statutApres(action: action, fait: fait) else { return }
        changerVideo(jour: jour, compte: compte, statut: statut)
        let sujet = video(jour: jour, compte: compte)?.sujet ?? ""
        try? Decisions.noter(question: "Vidéo \(VideoVocabulaire.compteFrancais(compte)) du \(jour)\(sujet.isEmpty ? "" : " : \(sujet)")",
                             choix: "\(fait ? "Fait" : "Remis à faire") dans Ma journée (\(action)) : statut « \(VideoVocabulaire.statutFrancais(statut)) ».",
                             ref: "video:\(jour):\(compte):\(action):\(Int(Date().timeIntervalSince1970))", liste: "Contenu")
    }

    func changerVideo(jour: String, compte: String, statut: String) {
        enregistrer(video: ["jour": jour, "compte": compte, "statut": statut])
    }

    func enregistrer(video champs: [String: Any]) {
        guard let stock else { return }
        do { try stock.enregistrerVideo(champs); charger() } catch { erreurBase = erreurEnregistrement(error) }
    }

    private func erreurEnregistrement(_ error: Error) -> String {
        let detail = "\(error)"
        return L("Enregistrement impossible : \(detail)")
    }

    /// Ouvre un prompteur ou une fiche : une adresse web, sinon un chemin (« ~ » compris).
    /// Messages prêts qui partent aujourd'hui : sans date d'envoi sur la fiche, ou date arrivée.
    /// Ceux d'un jour suivant attendent leur jour (03/11, Sacha : « c'est des trucs que j'envoie demain »).
    var aEnvoyerAujourdhui: [MessageAEnvoyer] {
        let j = Dates.aujourdhui()
        return aEnvoyer.filter { $0.jour.isEmpty || $0.jour <= j }
    }
    var aEnvoyerPlusTard: [MessageAEnvoyer] {
        let j = Dates.aujourdhui()
        return aEnvoyer.filter { $0.jour > j }.sorted { $0.jour < $1.jour }
    }

    /// Chaque question de fin de tour d'une session (03/11, Sacha : « chaque décision à prendre s'affiche dans Pilote
    /// obligatoirement ») : une décision dans « À décider », tant que Sacha n'y a pas répondu ici ou dans la session.
    var questionsSessions: [ActiviteSession] {
        agents.filter { !$0.question.isEmpty && !$0.questionRef.isEmpty && !$0.sessionApp.isEmpty && $0.etat != "busy"
            && !questionsRepondues.contains($0.questionRef) && !questionsIgnorees.contains($0.questionRef) }
    }

    /// Les phrases en « ? » repérées dans un texte que Sacha a écartées (« Pas une question »).
    var questionsIgnorees: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "questions.ignorees") ?? [])

    func ignorerQuestion(_ ref: String) {
        questionsIgnorees.insert(ref)
        UserDefaults.standard.set(Array(questionsIgnorees).suffix(200), forKey: "questions.ignorees")
    }

    /// Le nom d'équipe d'une session (EQUIPE.md), sinon son titre dans l'app Claude.
    func nomSession(_ a: ActiviteSession) -> String {
        pyramide.tous.first { $0.activite?.id == a.id || (!a.sessionApp.isEmpty && $0.membre.sessionApp == a.sessionApp) }?.membre.nom
            ?? a.titre
    }

    /// Relit décisions, messages du Facteur et questions répondues. Les fichiers sont lus hors du fil principal
    /// (100 à 150 ms toutes les 4 s mesurées le 09/11) ; seules les valeurs changées sont remplacées.
    func relireDecisions() {
        Task { await relireDecisionsHorsFil() }
    }

    private func relireDecisionsHorsFil() async {
        let (d, m, actif, q, veille) = await Task.detached(priority: .userInitiated) {
            () -> ([Decisions.Envoyee], [Facteur.Message], Bool, Set<String>, Date?) in
            let d = Decisions.envoyees()
            let m = Facteur.messages()
            let attente = d.contains { !$0.transmise && !$0.enAttente && $0.remise?.etat != .retire }
                || m.contains { $0.remise?.etat != .remis }
            return (d, m, Facteur.actif(), Decisions.questionsRepondues(), attente ? Decisions.prochaineVeille() : nil)
        }.value
        if d != decisionsEnvoyees { decisionsEnvoyees = d }
        if m != messagesSessions { messagesSessions = m }
        if actif != facteurActif { facteurActif = actif }
        if q != questionsRepondues { questionsRepondues = q }
        if veille != prochaineVeille { prochaineVeille = veille }
    }

    /// Sacha envoie ses réponses en attente (ou en retire une) : elles partent avec le Facteur, ou la veille.
    func envoyerReponses(_ rangs: [Int]) {
        do { try Facteur.noter(rangs, etat: .pret) } catch { erreurBase = error.localizedDescription }
        relireDecisions()
    }
    func retirerReponse(_ rang: Int) {
        do { try Facteur.noter([rang], etat: .retire) } catch { erreurBase = error.localizedDescription }
        relireDecisions()
    }

    /// Un message de Sacha à une session : le Facteur le lui remet en quelques secondes (la veille sinon).
    /// `qui` sans valeur par défaut (09/11, Organisation) : « Sacha » seulement depuis un bouton cliqué par Sacha ;
    /// un essai ou tout autre dépôt donne son propre nom, sinon le Facteur l'annoncerait comme un accord de Sacha.
    func ecrire(a nom: String, session: String, texte: String, qui: String) throws {
        let t = texte.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        try Facteur.ecrire(pour: nom, session: session, texte: t, qui: qui)
        relireDecisions()
    }

    /// « Relancer » : l'agent reçoit ses fiches qui restent et la consigne du matin (le Facteur, ou la veille).
    func relancer(_ j: JourneeAgent) {
        do { try ecrire(a: j.session, session: "", texte: Stockage.relance(j), qui: "\(Moi.nom)") } catch { erreurBase = error.localizedDescription }
    }

    /// La dernière relance de Sacha à cet agent aujourd'hui, si elle existe.
    func derniereRelance(_ j: JourneeAgent) -> Facteur.Message? {
        messagesSessions.first { $0.pour == j.session && $0.texte.hasPrefix("Relance de \(Moi.nom)")
            && Dates.jour.string(from: $0.heure) == j.date }
    }

    /// Ouvre une nouvelle session FACTEUR dans l'app Claude, consigne prête (Sacha appuie sur Entrée).
    func demarrerFacteur() {
        Claude.nouvelle(consigne: Facteur.consigne, dossier: Identite.depot.path)
    }

    /// Montre un fichier ou un dossier dans le panneau de droite ; une adresse web s'ouvre dans le navigateur.
    func montrer(_ chemin: String) {
        if chemin.hasPrefix("http") { ouvrirChemin(chemin); return }
        fichePanneau = nil
        apercu = Chemins.complet(chemin)
    }

    // MARK: Textes à valider

    /// La session qui a écrit le brouillon : FREELANCE pour le freelance, KRYVA · Ventes pour les artisans.
    static func auteur(_ c: Contact) -> String { c.espace == "kryva" ? "KRYVA · Ventes" : "FREELANCE" }

    /// Sacha valide le texte (tel quel, ou sa version) : il passe « à envoyer », et l'agent l'apprend.
    func valider(_ m: MessageAEnvoyer, texte: String) {
        guard let stock else { return }
        let propre = texte.trimmingCharacters(in: .whitespacesAndNewlines)
        let corrige = propre != m.evenement.texte.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if corrige { try stock.modifierEvenement(m.evenement.id, ["texte": propre]) }
            try stock.marquer(evenementId: m.evenement.id, statut: "prepare")
            try Decisions.noter(question: "Texte pour \(m.contact.nom) (\(m.evenement.id))",
                                choix: corrige ? "Validé avec la correction de \(Moi.nom). Texte exact : \(propre)" : "Validé tel quel.",
                                ref: m.evenement.id, liste: "Textes", pour: Self.auteur(m.contact))
        } catch { erreurBase = error.localizedDescription }
        charger()
    }

    /// Sacha renvoie le texte à l'agent avec sa consigne : il sort de la liste jusqu'à la nouvelle version.
    func renvoyer(_ m: MessageAEnvoyer, consigne: String) {
        guard let stock else { return }
        do {
            try stock.marquer(evenementId: m.evenement.id, statut: "a_refaire")
            try Decisions.noter(question: "Texte pour \(m.contact.nom) (\(m.evenement.id))",
                                choix: "À refaire. Consigne de \(Moi.nom) : \(consigne.trimmingCharacters(in: .whitespacesAndNewlines))",
                                ref: m.evenement.id, liste: "Textes", pour: Self.auteur(m.contact))
        } catch { erreurBase = error.localizedDescription }
        charger()
    }

    /// « Pas envoyé… » (04/11) : la raison va au fil du contact et à l'agent ; l'effet dépend de la raison (RaisonPasEnvoye).
    func pasEnvoye(_ m: MessageAEnvoyer, raison: RaisonPasEnvoye, precision: String, au jour: Date) {
        guard let stock else { return }
        do {
            let note = try stock.pasEnvoye(evenementId: m.evenement.id, raison: raison, precision: precision,
                                           au: Dates.jour.string(from: jour))
            let p = precision.trimmingCharacters(in: .whitespacesAndNewlines)
            let choix: String
            switch raison {
            case .texteAChanger: choix = "À refaire. Consigne de \(Moi.nom) : \(p)"
            case .plusDActualite: choix = "Ne pas envoyer. \(note)"
            case .pasLeMoment: choix = note
            }
            try Decisions.noter(question: "Texte pour \(m.contact.nom) (\(m.evenement.id))", choix: choix,
                                ref: m.evenement.id, liste: "Textes", pour: Self.auteur(m.contact))
        } catch { erreurBase = error.localizedDescription }
        charger()
    }

    /// « Pas fait… » sur une ligne de suivi du jour (sans texte prêt) : raison au fil, action reportée ou abandonnée.
    func pasFait(_ c: Contact, raison: RaisonPasEnvoye, precision: String, au jour: Date) {
        guard let stock else { return }
        do {
            let note = try stock.pasFait(contactId: c.id, raison: raison, precision: precision, au: Dates.jour.string(from: jour))
            informerAgent(c, note)
        } catch { erreurBase = error.localizedDescription }
        charger()
    }

    /// Sacha ne veut pas de ce message : il est annulé, l'agent l'apprend.
    func abandonner(_ m: MessageAEnvoyer) {
        guard let stock else { return }
        do {
            try stock.marquer(evenementId: m.evenement.id, statut: "annule")
            try Decisions.noter(question: "Texte pour \(m.contact.nom) (\(m.evenement.id))", choix: "Ne pas envoyer.",
                                ref: m.evenement.id, liste: "Textes", pour: Self.auteur(m.contact))
        } catch { erreurBase = error.localizedDescription }
        charger()
    }

    func ouvrirChemin(_ chemin: String) {
        if chemin.hasPrefix("http"), let url = URL(string: chemin) { NSWorkspace.shared.open(url); return }
        NSWorkspace.shared.open(URL(fileURLWithPath: Chemins.complet(chemin)))
    }

    func ajouterNote(_ contactId: String, canal: String, type: String, texte: String) {
        guard let stock, !texte.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let sens = (type == "reponse") ? "entrant" : (type == "note" ? "interne" : "sortant")
        _ = try? stock.ajouterEvenement(contactId: contactId, [
            "canal": canal, "type": type, "sens": sens, "texte": texte, "statut": "fait", "par": "\(Moi.nom)",
        ])
        charger()
        if let c = contact(contactId) {
            informerAgent(c, "\(Moi.nom) a noté au fil (\(Libelles.typeEvenementFr(type)) \(Libelles.canalFr(canal))) : \(texte.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300))")
        }
    }

    /// La prochaine action d'un contact est faite : noté au fil ; une action d'envoi pose la suite de la routine (Stockage.actionFaite).
    func actionFaite(_ c: Contact) {
        guard let stock, let note = try? stock.actionFaite(contactId: c.id), !note.isEmpty else { return }
        charger()
        informerAgent(c, note)
    }

    /// « Acceptée » (04/11) : noté au fil, et l'agent du contact prépare le message après acceptation.
    func invitationAcceptee(_ c: Contact) {
        guard let stock, (try? stock.invitationAcceptee(c.id)) != nil else { return }
        prevenir(c, choix: "Acceptée", consigne: "Invitation LinkedIn acceptée : \(Self.nomComplet(c)). Prépare le message après acceptation (modèle de la routine), statut a_valider dans Pilote.")
        charger()
    }

    /// « Pas encore » (04/11) : on revoit dans 3 jours ouvrés ; au 2e, l'agent prépare un mail ou un DM Insta.
    func invitationPasEncore(_ c: Contact) {
        guard let stock, let changer = try? stock.invitationPasEncore(c.id) else { return }
        if changer {
            prevenir(c, choix: "Passer par un mail ou Insta", consigne: "Invitation LinkedIn de \(Self.nomComplet(c)) toujours pas acceptée (\(Invitation.essais)e « pas encore »). Prépare un mail ou un DM Insta à la place, statut a_valider dans Pilote ; s'il n'y a ni e-mail ni Insta, dis-le à PILOTE.")
        }
        charger()
    }

    func reporterAction(_ c: Contact, au jour: Date) {
        guard let note = try? stock?.reporterEtNoter(c.id, au: Dates.jour.string(from: jour)), !note.isEmpty else { return }
        charger()
        informerAgent(c, note)
    }

    private static func nomComplet(_ c: Contact) -> String { c.sousTitre.isEmpty ? c.titre : "\(c.titre) (\(c.sousTitre))" }

    /// La ligne pour l'agent du contact (Ventes ou FREELANCE), remise par le Facteur ou la veille.
    private func prevenir(_ c: Contact, choix: String, consigne: String) {
        try? Decisions.noter(question: consigne, choix: choix, ref: "invitation:\(c.id):\(Dates.aujourdhui())",
                             liste: c.espace == "kryva" ? "Appels" : "Freelance", pour: Self.auteur(c))
    }

    /// Renvoie l'erreur à montrer (05/11, T7 : un message dont la condition n'est pas cochée ne passe pas à « envoyé »), sinon nil.
    @discardableResult
    func marquer(_ evenementId: String, statut: String, malgreCondition: Bool = false) -> String? {
        let m = aEnvoyer.first { $0.id == evenementId }
        do {
            try stock?.marquer(evenementId: evenementId, statut: statut, malgreCondition: malgreCondition)
        } catch {
            return "\(error)"
        }
        charger()
        informerApresMarque(m, statut: statut)
        return nil
    }

    /// 05/11 (T7) : Sacha coche la condition d'un message préparé ; l'envoi se débloque, le rappel lié sera coché par Pilote.
    func conditionRemplie(_ evenementId: String) {
        let m = aEnvoyer.first { $0.id == evenementId }
        guard let note = try? stock?.conditionRemplie(evenementId: evenementId, par: "\(Moi.nom)"), !note.isEmpty else { return }
        charger()
        if let m { informerAgent(m.contact, note) }
    }

    private func informerApresMarque(_ m: MessageAEnvoyer?, statut: String) {
        guard let m, statut == "envoye" || statut == "annule" else { return }
        if statut == "annule" { informerAgent(m.contact, "Message \(Libelles.canalFr(m.evenement.canal)) annulé, pas envoyé"); return }
        let c = contact(m.contact.id) ?? m.contact
        let suite = c.prochaineAction.isEmpty ? "aucune suite posée" : "suite : « \(c.prochaineAction.prefix(80)) » le \(Dates.court(c.prochaineDate, francais: true))"
        informerAgent(c, "Message \(Libelles.canalFr(m.evenement.canal)) envoyé par \(Moi.nom), étape « \(Libelles.etapeFr(c.etape)) », \(suite)")
    }

    func supprimerEvenement(_ id: String) {
        try? stock?.supprimerEvenement(id)
        charger()
    }

    func evenements(_ contactId: String) -> [Evenement] {
        (try? stock?.evenements(contactId)) ?? []
    }
}
