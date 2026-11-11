// Liaison Pilote ↔ Pip (10/11) : voir Shared/Pip.swift pour les règles. Ici, ce qui touche le Mac : trouver Pip, lire l'agenda,
// ouvrir Pip, lire ses dossiers de réunion. Facultative : sans Pip installé, `disponible` reste faux, aucun bouton ne
// s'affiche, rien n'est lu ni ouvert.
import AppKit
import EventKit
import UserNotifications

@MainActor @Observable
final class PipLiaison {
    static let partage = PipLiaison()

    /// Pip est installé sur ce Mac : les boutons s'affichent.
    private(set) var disponible = false
    /// Le Pip installé sait ouvrir une réunion par un lien (version récente). Sinon Pilote l'ouvre sans le nom.
    private(set) var accepteLien = false
    /// Pilote ouvre Pip tout seul 2 min avant une visio. Le clic sur « Lancer Pip » marche dans tous les cas.
    var auto: Bool = UserDefaults.standard.object(forKey: "pipAuto") as? Bool ?? true {
        didSet { UserDefaults.standard.set(auto, forKey: "pipAuto") }
    }
    /// La dernière chose faite par le retour (« Résumé de … ajouté au fil de … »), pour l'afficher et le tester.
    private(set) var dernierRetour: String?

    /// Ce que le clic a fait : le contact lié (nil : aucun), et si le nom de la réunion est parti dans le lien.
    struct Ouverture {
        var contact: String?
        var nomTransmis: Bool
    }

    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private var appPip: URL?
    @ObservationIgnored private var reglagePip: String?
    @ObservationIgnored private var boucle: Task<Void, Never>?
    @ObservationIgnored private var stock: (() -> Stockage?)?
    @ObservationIgnored private var apres: (() -> Void)?
    @ObservationIgnored private var importes = Set<String>()
    @ObservationIgnored private let cleLancees = "pipLancees"

    /// Démarre la veille (toutes les 30 s) ; appelé une fois, quand la base est ouverte.
    func demarrer(stock: @escaping () -> Stockage?, apres: @escaping () -> Void) {
        guard boucle == nil else { return }
        // Copie publique : la liaison lit l'agenda, donc elle suit le réglage `rappels_calendrier` (coupé par défaut) ;
        // en démo, jamais : Pip ne s'ouvre pas sur des réunions inventées.
        guard !Demo.actif, Reglages.courants.rappelsCalendrier == true else { return }
        self.stock = stock
        self.apres = apres
        detecter()
        boucle = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                await self?.passer()
            }
        }
    }

    // MARK: Trouver Pip

    /// Le Pip qui sait ouvrir un lien `heypip://`, sinon n'importe quel Pip installé (ancien : sans le nom de la réunion).
    func detecter() {
        let essai = URL(string: "\(Pip.schema)://meeting")!
        if let app = NSWorkspace.shared.urlsForApplications(toOpen: essai).first {
            appPip = app
            accepteLien = true
        } else {
            appPip = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Pip.identifiant)
            accepteLien = false
        }
        disponible = appPip != nil
        // Le dossier des réunions est celui que Pip déclare dans ses réglages ; à défaut, le dossier par défaut de Pip.
        if let id = appPip.flatMap({ Bundle(url: $0)?.bundleIdentifier }), id != Bundle.main.bundleIdentifier {
            reglagePip = UserDefaults(suiteName: id)?.string(forKey: "meetingsFolder")
        } else {
            reglagePip = nil
        }
    }

    // MARK: Ouvrir Pip

    /// Le clic sur « Lancer Pip » : ouvre Pip sur la réunion, l'encoche ouverte sur le formulaire. Pip n'enregistre rien
    /// tant que Sacha n'a pas cliqué « Start » dans Pip (il y voit le rappel de prévenir les participants).
    @discardableResult
    func lancer(_ rv: RendezVous) -> Ouverture? {
        detecter()
        guard disponible else { return nil }
        let reunion = reunion(pour: rv)
        marquerLancee(reunion)
        return ouvrir(reunion, ouvrirLEncoche: true)
    }

    /// Ce que Sacha colle dans Claude pour qu'il suive la réunion avec Pip. Jamais envoyé tout seul : Sacha le copie
    /// d'un clic, l'écoute de Claude reste son geste. Texte pour une session Claude : en français, jamais traduit.
    func consigne(pour rv: RendezVous) -> String {
        let r = reunion(pour: rv)
        var texte = "/pip Réunion « \(rv.titre) »"
        let contacts = (try? stock?()?.contacts()) ?? []
        if let c = Pip.contactLie(a: r, parmi: contacts) {
            texte += " avec \(c.nomAffiche)"
            if !c.prochaineAction.isEmpty { texte += ". Prochaine action en cours : \(c.prochaineAction)" }
        }
        return texte
    }

    private func reunion(pour rv: RendezVous) -> ReunionPip {
        lire(id: rv.id) ?? ReunionPip(id: rv.ref.isEmpty ? rv.id : rv.ref, titre: rv.titre, debut: rv.debut, fin: rv.fin,
                                      journee: rv.journee, lien: rv.url, participants: [])
    }

    /// Ouvre Pip sur cette réunion. Renvoie le contact lié et si le nom est parti dans le lien.
    private func ouvrir(_ r: ReunionPip, ouvrirLEncoche: Bool) -> Ouverture? {
        guard let app = appPip else { return nil }
        let contacts = (try? stock?()?.contacts()) ?? []
        let contact = Pip.contactLie(a: r, parmi: contacts)
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false      // le focus reste sur la visio ; l'encoche de Pip n'a pas besoin du focus
        if accepteLien {
            let lien = Pip.lien(titre: r.titre, ref: Pip.ref(contact: contact, reunion: r), ouvrir: ouvrirLEncoche)
            NSWorkspace.shared.open([lien], withApplicationAt: app, configuration: config)
        } else {
            NSWorkspace.shared.openApplication(at: app, configuration: config)
        }
        return Ouverture(contact: contact?.nomAffiche, nomTransmis: accepteLien)
    }

    // MARK: La veille : ouverture 2 min avant, retour du résumé

    private func passer() async {
        detecter()
        guard disponible else { return }
        if auto { ouvrirLesVisiosQuiViennent() }
        await importerLesResumes()
    }

    private func ouvrirLesVisiosQuiViennent() {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return }
        let maintenant = Date()
        let fenetre = store.predicateForEvents(withStart: maintenant.addingTimeInterval(-Pip.retard - 60),
                                               end: maintenant.addingTimeInterval(Pip.avance + 60), calendars: nil)
        for e in store.events(matching: fenetre) {
            let r = Self.reunion(e)
            guard Pip.aLancer(r, a: maintenant, dejaLancees: Set(lancees().keys)) else { continue }
            marquerLancee(r)    // d'abord : un échec d'ouverture ne se rejoue pas en boucle toutes les 30 s
            _ = ouvrir(r, ouvrirLEncoche: false)
        }
    }

    private func lancees() -> [String: Double] {
        UserDefaults.standard.dictionary(forKey: cleLancees) as? [String: Double] ?? [:]
    }

    private func marquerLancee(_ r: ReunionPip) {
        var l = lancees()
        l[Pip.cle(r)] = Date().timeIntervalSince1970
        let limite = Date().addingTimeInterval(-2 * 86400).timeIntervalSince1970
        UserDefaults.standard.set(l.filter { $0.value > limite }, forKey: cleLancees)
    }

    private func importerLesResumes() async {
        // Tant que Pilote n'a lancé aucune réunion, rien à relire : le dossier de Pip n'est pas touché (macOS demande l'accès
        // à Documents la première fois, autant que ce soit après un geste de Sacha).
        guard !lancees().isEmpty, let stock = stock?() else { return }
        let racine = PipRetour.racine(reglagePip: reglagePip)
        let vus = importes
        let maintenant = Date()
        let prets = await Task.detached { PipRetour.aImporter(racine: racine, a: maintenant).filter { !vus.contains($0.dossier) } }.value
        guard !prets.isEmpty, let nouveaux = try? stock.importerResumesPip(prets) else { return }
        importes.formUnion(prets.map(\.dossier))
        guard !nouveaux.isEmpty else { return }
        let phrase = nouveaux.map { n in
            n.contact.map { L("« \(n.reunion) » : fil de \($0.nomAffiche)") } ?? L("« \(n.reunion) » : journal (aucun contact lié)")
        }.joined(separator: " · ")
        dernierRetour = phrase
        apres?()
        annoncer(nouveaux.count, phrase)
    }

    private func annoncer(_ n: Int, _ phrase: String) {
        let c = UNMutableNotificationContent()
        c.title = L("\(n) résumés de réunion ajoutés")
        c.body = phrase
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "pip-retour-\(UUID().uuidString)", content: c, trigger: nil))
    }

    // MARK: L'agenda

    private func lire(id: String) -> ReunionPip? {
        (store.calendarItem(withIdentifier: id) as? EKEvent).map(Self.reunion)
    }

    private static func reunion(_ e: EKEvent) -> ReunionPip {
        let invites = ([e.organizer].compactMap { $0 } + (e.attendees ?? [])).filter { !$0.isCurrentUser }
        let participants = invites.map { p -> ParticipantPip in
            let adresse = p.url.absoluteString
            return ParticipantPip(nom: p.name ?? "", email: adresse.lowercased().hasPrefix("mailto:") ? String(adresse.dropFirst(7)) : "")
        }
        let notes = [e.notes, e.location].compactMap { $0 }.joined(separator: " ")
        return ReunionPip(id: e.calendarItemExternalIdentifier ?? e.calendarItemIdentifier, titre: e.title ?? "",
                          debut: e.startDate, fin: e.endDate, journee: e.isAllDay,
                          lien: e.url ?? Pip.lienVisio(dans: notes), participants: participants)
    }
}
