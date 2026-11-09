// Rappels et Calendrier (EventKit) : la journée de Sacha telle que la synchro Notion ↔ Rappels la prépare.
import EventKit
import SwiftUI

// Rappel et RendezVous : Shared/ATOI.swift (lus ici, testés là-bas).

/// Une tâche du tableau : un rappel (toutes listes), à faire ou fait ces 7 derniers jours.
struct Tache: Identifiable, Hashable {
    let id: String
    var titre: String
    var notes: String
    var liste: String
    var echeance: Date?
    var avecHeure: Bool
    var faite: Bool
    var faiteLe: Date?
    var priorite: Int
    var lienNotion: URL?
    var recurrente: Bool
}

/// `coupe` : Rappels et Calendrier ne sont pas activés dans reglages.json (rappels_calendrier), rien n'est demandé à macOS.
enum Acces { case inconnu, accorde, refuse, coupe }

@MainActor @Observable
final class Agenda {
    private let store = EKEventStore()
    var rappels: [Rappel] = []
    /// Les décisions ❓ ouvertes dont l'échéance est après aujourd'hui (ou sans date) : la question attend déjà Sacha,
    /// l'écran unique les montre dans « À toi ». À part de `rappels` pour ne pas changer les notifications ni les autres vues.
    var decisionsAVenir: [Rappel] = []
    /// Les rappels à faire dont l'échéance est demain (toutes listes) : la ligne « Demain » de l'écran unique.
    var rappelsDemain: [Rappel] = []
    var taches: [Tache] = []
    /// true après la première lecture des tâches (le contrôle « Demain prêt ? » ne notifie rien avant).
    var tachesLues = false
    var listes: [String] = []
    var rendezVous: [RendezVous] = []
    var accesRappels: Acces = .inconnu
    var accesCalendrier: Acces = .inconnu
    var chargement = false
    var erreur: String?
    /// Le planning (docs/PLANNING-CONTRAT.md) : tâches (Rappels) et événements (Calendrier) de la plage affichée, et l'état « Terminé ».
    var planning: [TachePlanning] = []
    var terminees: [String: String] = [:]
    /// Les listes et calendriers du contrat présents sur le Mac (vide : le planning n'est pas encore rempli).
    var calendriersPlanning: [String] = []
    /// false jusqu'à la première lecture : l'écran dit « Lecture… » au lieu de « rien sur ce Mac ».
    var planningLu = false
    var erreurPlanning: String?
    @ObservationIgnored private var plagePlanning: DateInterval?
    @ObservationIgnored private let termine = TachesTerminees(dossier: TachesTerminees.dossierParDefaut)

    /// Les rendez-vous du jour pas encore finis, plus les événements « journée » : l'écran les relit à chaque minute.
    func restants(a maintenant: Date) -> [RendezVous] {
        rendezVous.filter { RendezVousFiltre.encoreAffiche(fin: $0.fin, journee: $0.journee, a: maintenant) }
    }

    init() {
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.charger() }
        }
    }

    func demarrer() async {
        if Demo.actif { remplirDemo(); return }
        guard Reglages.courants.rappelsCalendrier == true else {
            accesRappels = .coupe
            accesCalendrier = .coupe
            return
        }
        if accesRappels == .coupe { accesRappels = .inconnu }
        if accesCalendrier == .coupe { accesCalendrier = .inconnu }
        if accesRappels == .inconnu {
            let ok = (try? await store.requestFullAccessToReminders()) ?? false
            accesRappels = ok ? .accorde : .refuse
        }
        if accesCalendrier == .inconnu {
            let ok = (try? await store.requestFullAccessToEvents()) ?? false
            accesCalendrier = ok ? .accorde : .refuse
        }
        await charger()
    }

    func charger() async {
        if Demo.actif { remplirDemo(); return }
        chargement = true
        defer { chargement = false }
        let cal = Calendar.current
        let debutJour = cal.startOfDay(for: Date())
        let finJour = cal.date(byAdding: .day, value: 1, to: debutJour)!

        if accesRappels == .accorde {
            let predicat = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: finJour, calendars: nil)
            let trouves: [EKReminder] = await withCheckedContinuation { cont in
                store.fetchReminders(matching: predicat) { cont.resume(returning: $0 ?? []) }
            }
            rappels = trouves.map { r in
                let echeance = r.dueDateComponents.flatMap { cal.date(from: $0) }
                return Rappel(id: r.calendarItemIdentifier, titre: r.title ?? "", notes: r.notes ?? "",
                              liste: r.calendar?.title ?? "", echeance: echeance,
                              enRetard: (echeance ?? Date()) < debutJour, priorite: r.priority,
                              avecHeure: r.dueDateComponents?.hour != nil)
            }
            .sorted { ($0.echeance ?? .distantFuture) < ($1.echeance ?? .distantFuture) }
            let dejaVus = Set(rappels.map(\.id))
            let tous: [EKReminder] = await withCheckedContinuation { cont in
                store.fetchReminders(matching: store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)) {
                    cont.resume(returning: ($0 ?? []).filter { !dejaVus.contains($0.calendarItemIdentifier) })
                }
            }
            let apresDemain = cal.date(byAdding: .day, value: 1, to: finJour)!
            let autres = tous.map { r in
                Rappel(id: r.calendarItemIdentifier, titre: r.title ?? "", notes: r.notes ?? "", liste: r.calendar?.title ?? "",
                       echeance: r.dueDateComponents.flatMap { cal.date(from: $0) }, enRetard: false, priorite: r.priority,
                       avecHeure: r.dueDateComponents?.hour != nil)
            }
            .sorted { ($0.echeance ?? .distantFuture) < ($1.echeance ?? .distantFuture) }
            decisionsAVenir = autres.filter { Decisions.estDecision($0.titre) }
            // 09/11 : les tâches de demain, en une ligne repliée sous « À toi ».
            rappelsDemain = autres.filter { r in r.echeance.map { $0 >= finJour && $0 < apresDemain } ?? false }
        }
        if accesRappels == .accorde { await chargerTaches() }
        if accesCalendrier == .accorde {
            let predicat = store.predicateForEvents(withStart: debutJour, end: finJour, calendars: nil)
            rendezVous = store.events(matching: predicat).map { e in
                RendezVous(id: e.calendarItemIdentifier, titre: e.title ?? "", debut: e.startDate, fin: e.endDate,
                           calendrier: e.calendar?.title ?? "", journee: e.isAllDay, lieu: e.location ?? "",
                           url: e.url ?? Self.lienVisio(e), ref: e.calendarItemExternalIdentifier ?? e.calendarItemIdentifier)
            }
            .sorted { $0.debut < $1.debut }
            terminees = termine.lire()
        }
        await signalerCoches()
        if let p = plagePlanning { await chargerPlanning(p) }
    }

    // MARK: Ma journée : rendez-vous fait (noté par Pilote, Calendrier inchangé, comme le planning) ou reporté (déplacé)

    func planning(_ r: RendezVous) -> TachePlanning {
        TachePlanning(genre: .evenement, ref: r.ref.isEmpty ? r.id : r.ref, idLocal: r.id, titre: r.titre, debut: r.debut,
                      fin: r.fin, calendrier: r.calendrier, journee: r.journee, url: r.url, notes: NotesPlanning.lire(""))
    }

    func estFait(_ r: RendezVous) -> Bool { terminees[planning(r).id] != nil }

    func terminer(_ r: RendezVous) { terminer(planning(r)) }

    func rouvrir(_ r: RendezVous) {
        do {
            try termine.rouvrir(planning(r))
            erreurPlanning = nil
        } catch { erreurPlanning = "Pas remis à faire : \(error.localizedDescription)" }
        terminees = termine.lire()
    }

    /// Reporte cette occurrence du rendez-vous à `debut`, même durée. Calendrier le reporte sur l'iPhone ; PILOTE le verra au planning.
    func reporter(_ r: RendezVous, vers debut: Date) {
        let cal = Calendar.current
        let predicat = store.predicateForEvents(withStart: cal.startOfDay(for: r.debut), end: r.fin.addingTimeInterval(1), calendars: nil)
        guard let e = store.events(matching: predicat).first(where: { $0.calendarItemIdentifier == r.id && $0.startDate == r.debut }) else {
            erreurPlanning = "Ce rendez-vous n'existe plus dans Calendrier."
            Task { await charger() }
            return
        }
        guard e.calendar?.allowsContentModifications != false else {
            erreurPlanning = "Le calendrier « \(r.calendrier) » ne se modifie pas depuis Pilote : reportez-le dans Calendrier."
            return
        }
        let duree = e.endDate.timeIntervalSince(e.startDate)
        e.startDate = debut
        e.endDate = debut.addingTimeInterval(duree)
        do {
            try store.save(e, span: .thisEvent, commit: true)
            erreurPlanning = nil
        } catch { erreurPlanning = "Calendrier n'a pas accepté le report (\(error.localizedDescription))." }
        Task { await charger() }
    }

    // MARK: Planning : tâches = Rappels, événements = Calendrier (lecture seule ; seule écriture : cocher un rappel)

    private var listesPlanning: [EKCalendar] {
        accesRappels == .accorde ? store.calendars(for: .reminder).filter { CalendriersPlanning.tache($0.title) } : []
    }

    func chargerPlanning(_ plage: DateInterval) async {
        plagePlanning = plage
        if Demo.actif {
            planning = DemoDonnees.planning(plage)
            calendriersPlanning = CalendriersPlanning.tous.map(\.nom)
            planningLu = true
            return
        }
        terminees = termine.lire()
        var elements: [TachePlanning] = []
        var trouves: Set<String> = []
        // Une liste vide voudrait dire « tous les calendriers » pour EventKit : on ne la passe jamais.
        let cals = accesCalendrier == .accorde ? store.calendars(for: .event).filter { CalendriersPlanning.evenement($0.title) } : []
        if !cals.isEmpty {
            trouves.formUnion(cals.map(\.title))
            let predicat = store.predicateForEvents(withStart: plage.start, end: plage.end, calendars: cals)
            elements += store.events(matching: predicat).map(Self.element)
        }
        let listes = listesPlanning
        if !listes.isEmpty {
            trouves.formUnion(listes.map(\.title))
            let afaire = await rappels(store.predicateForIncompleteReminders(withDueDateStarting: plage.start, ending: plage.end, calendars: listes))
            // Les rappels cochés : par date de coche (un mois avant la plage au plus), puis gardés si l'échéance tombe dans la plage.
            let faits = await rappels(store.predicateForCompletedReminders(
                withCompletionDateStarting: plage.start.addingTimeInterval(-31 * 86400), ending: max(Date(), plage.end), calendars: listes))
            elements += (afaire + faits).compactMap(Self.element).filter { $0.debut >= plage.start && $0.debut < plage.end }
        }
        guard plagePlanning == plage else { return }   // une plage plus récente a été demandée entre-temps
        calendriersPlanning = CalendriersPlanning.tous.map(\.nom).filter(trouves.contains)
        planningLu = true
        planning = elements.sorted { ($0.debut, $0.titre) < ($1.debut, $1.titre) }
    }

    private func rappels(_ predicat: NSPredicate) async -> [EKReminder] {
        await withCheckedContinuation { cont in store.fetchReminders(matching: predicat) { cont.resume(returning: $0 ?? []) } }
    }

    private static func element(_ e: EKEvent) -> TachePlanning {
        TachePlanning(genre: .evenement, ref: e.calendarItemExternalIdentifier ?? e.calendarItemIdentifier, idLocal: e.calendarItemIdentifier,
                      titre: e.title ?? "", debut: e.startDate, fin: e.endDate, calendrier: e.calendar?.title ?? "",
                      journee: e.isAllDay, url: e.url, notes: NotesPlanning.lire(e.notes ?? ""))
    }

    /// Un rappel avec échéance : placé à son heure (30 min dans la grille), ou en haut de la journée s'il n'a pas d'heure.
    private static func element(_ r: EKReminder) -> TachePlanning? {
        guard let c = r.dueDateComponents, let echeance = Calendar.current.date(from: c) else { return nil }
        let avecHeure = c.hour != nil
        return TachePlanning(genre: .tache, ref: r.calendarItemExternalIdentifier ?? r.calendarItemIdentifier, idLocal: r.calendarItemIdentifier,
                             titre: r.title ?? "", debut: echeance,
                             fin: echeance.addingTimeInterval(avecHeure ? TachePlanning.dureeTache : 86400),
                             calendrier: r.calendar?.title ?? "", journee: !avecHeure, url: r.url,
                             notes: NotesPlanning.lire(r.notes ?? ""), faite: r.isCompleted)
    }

    /// « Terminé » : une tâche est cochée dans Rappels (donc sur l'iPhone) ; un événement n'est jamais modifié dans
    /// Calendrier, Pilote le note seulement (il ne s'affiche plus). Puis une ligne dans entrants.jsonl (PILOTE est prévenu).
    func terminer(_ t: TachePlanning) {
        if t.genre == .tache {
            guard let r = store.calendarItem(withIdentifier: t.idLocal) as? EKReminder else {
                erreurPlanning = "Ce rappel n'existe plus dans Rappels. Rien n'est noté."
                return
            }
            if !r.isCompleted {
                r.isCompleted = true
                do { try store.save(r, commit: true) } catch {
                    erreurPlanning = "Rappels n'a pas accepté la coche. Rien n'est noté, PILOTE n'est pas prévenu."
                    return
                }
            }
        }
        do {
            try termine.terminer(t)
            erreurPlanning = nil
        } catch {
            erreurPlanning = (t.genre == .tache ? "Rappel coché, mais la" : "La") + " ligne pour PILOTE n'a pas pu être écrite (\(error.localizedDescription))."
        }
        terminees = termine.lire()
        Task { await charger() }
    }

    /// « Fait » sur une tâche de « À toi » : comme « Terminé » du planning (le rappel est coché, PILOTE est prévenu).
    /// Renvoie l'erreur à montrer, nil si c'est fait.
    func terminer(rappel: Rappel) -> String? {
        guard let r = store.calendarItem(withIdentifier: rappel.id) as? EKReminder else {
            Task { await charger() }
            return "Ce rappel n'existe plus dans Rappels. Rien n'est noté."
        }
        if let t = Self.element(r) {
            terminer(t)
            return erreurPlanning
        }
        // Sans échéance (cas rare) : coché seulement.
        r.isCompleted = true
        do { try store.save(r, commit: true) } catch { return "Rappels n'a pas accepté la coche." }
        rappels.removeAll { $0.id == rappel.id }
        Task { await charger() }
        return nil
    }

    /// « Supprimer » (après confirmation de Sacha) : le rappel est supprimé de Rappels, partout ; PILOTE est prévenu.
    func supprimer(_ t: TachePlanning) {
        guard t.genre == .tache else { return }
        guard let r = store.calendarItem(withIdentifier: t.idLocal) as? EKReminder else {
            erreurPlanning = "Ce rappel n'existe plus dans Rappels."
            Task { await charger() }
            return
        }
        do { try store.remove(r, commit: true) } catch {
            erreurPlanning = "Rappels n'a pas accepté la suppression (\(error.localizedDescription))."
            return
        }
        do {
            try termine.ajouter(TachesTerminees.ligne(t, heure: Date(), classe: "tache_supprimee"))
            erreurPlanning = nil
        } catch {
            erreurPlanning = "Rappel supprimé, mais la ligne pour PILOTE n'a pas pu être écrite (\(error.localizedDescription))."
        }
        Task { await charger() }
    }

    /// Un rappel des listes du planning coché ailleurs (iPhone, Rappels) pendant que Pilote tourne : la même ligne pour PILOTE.
    private func signalerCoches() async {
        let listes = listesPlanning
        guard !listes.isEmpty, let depuis = try? termine.depuis() else { return }
        let faits = await rappels(store.predicateForCompletedReminders(withCompletionDateStarting: depuis, ending: Date().addingTimeInterval(60), calendars: listes))
        let cochees = faits.compactMap { r -> (tache: TachePlanning, le: Date)? in
            guard let t = Self.element(r), let le = r.completionDate else { return nil }
            return (t, le)
        }
        for c in TachesTerminees.nouvellesCoches(cochees, etat: termine.lire(), depuis: depuis) {
            try? termine.terminer(c.tache, a: c.le)
        }
        terminees = termine.lire()
    }

    // MARK: Tableau des tâches

    /// Tous les rappels à faire (avec ou sans date) et ceux faits ces 7 derniers jours.
    func chargerTaches() async {
        if Demo.actif { return }
        let afaire: [EKReminder] = await withCheckedContinuation { cont in
            store.fetchReminders(matching: store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)) {
                cont.resume(returning: $0 ?? [])
            }
        }
        let ilYa7Jours = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        let faites: [EKReminder] = await withCheckedContinuation { cont in
            store.fetchReminders(matching: store.predicateForCompletedReminders(withCompletionDateStarting: ilYa7Jours, ending: Date(), calendars: nil)) {
                cont.resume(returning: $0 ?? [])
            }
        }
        taches = (afaire + faites).map(Self.tache)
        tachesLues = true
        listes = Array(Set(taches.map(\.liste))).sorted { a, b in a == "KRYVA" ? true : (b == "KRYVA" ? false : a < b) }
    }

    /// Mode démo : rien n'est lu dans Rappels ni Calendrier (DemoDonnees).
    private func remplirDemo() {
        accesRappels = .accorde
        accesCalendrier = .accorde
        rappels = DemoDonnees.rappels()
        decisionsAVenir = []
        rappelsDemain = DemoDonnees.rappelsDemain()
        rendezVous = DemoDonnees.rendezVous()
        taches = (DemoDonnees.rappels() + DemoDonnees.rappelsDemain()).map {
            Tache(id: $0.id, titre: $0.titre, notes: $0.notes, liste: $0.liste, echeance: $0.echeance, avecHeure: $0.avecHeure,
                  faite: false, faiteLe: nil, priorite: 0, lienNotion: nil, recurrente: false)
        }
        listes = Array(Set(taches.map(\.liste))).sorted()
        tachesLues = true
    }

    static func tache(_ r: EKReminder) -> Tache {
        let c = r.dueDateComponents
        let echeance = c.flatMap { Calendar.current.date(from: $0) }
        let lien = [r.url?.absoluteString, r.notes].compactMap { $0 }.joined(separator: " ")
        var notion: URL?
        if let plage = lien.range(of: #"https://(www\.)?notion\.so/[^\s]+"#, options: .regularExpression) {
            notion = URL(string: String(lien[plage]))
        }
        return Tache(id: r.calendarItemIdentifier, titre: r.title ?? "", notes: r.notes ?? "", liste: r.calendar?.title ?? "",
                     echeance: echeance, avecHeure: c?.hour != nil, faite: r.isCompleted, faiteLe: r.completionDate,
                     priorite: r.priority, lienNotion: notion, recurrente: r.hasRecurrenceRules)
    }

    /// Change le jour d'un rappel en gardant son heure (et son alarme). Rappels gagne : la synchro reporte dans Notion.
    func deplacer(_ id: String, vers jour: Date?) {
        guard let r = store.calendarItem(withIdentifier: id) as? EKReminder else { return }
        let cal = Calendar.current
        if let jour {
            var comp = cal.dateComponents([.year, .month, .day], from: jour)
            if let ancien = r.dueDateComponents, ancien.hour != nil {
                comp.hour = ancien.hour
                comp.minute = ancien.minute ?? 0
            }
            r.dueDateComponents = comp
            // L'alarme suit la nouvelle date, seulement si le rappel en avait une (on n'en crée pas).
            if comp.hour != nil, let d = cal.date(from: comp), r.alarms?.contains(where: { $0.absoluteDate != nil }) == true {
                for a in r.alarms ?? [] where a.absoluteDate != nil { r.removeAlarm(a) }
                r.addAlarm(EKAlarm(absoluteDate: d))
            }
        } else {
            r.dueDateComponents = nil
            for a in r.alarms ?? [] { r.removeAlarm(a) }
        }
        r.isCompleted = false
        enregistrer(r)
    }

    func changerEcheance(_ id: String, date: Date, avecHeure: Bool) {
        guard let r = store.calendarItem(withIdentifier: id) as? EKReminder else { return }
        let champs: Set<Calendar.Component> = avecHeure ? [.year, .month, .day, .hour, .minute] : [.year, .month, .day]
        r.dueDateComponents = Calendar.current.dateComponents(champs, from: date)
        let avaitAlarme = r.alarms?.contains(where: { $0.absoluteDate != nil }) == true
        for a in r.alarms ?? [] where a.absoluteDate != nil { r.removeAlarm(a) }
        if avecHeure && avaitAlarme { r.addAlarm(EKAlarm(absoluteDate: date)) }
        enregistrer(r)
    }

    /// 05/11 (T7) : coche le rappel lié à un message préparé. `ref` : identifiant EventKit, ou titre exact d'un rappel à faire.
    /// Renvoie son titre ; nil s'il est introuvable (ou si Rappels n'est pas accessible : on ne conclut rien, voir l'appelant).
    func cocherRappelLie(_ ref: String) async -> String? {
        guard accesRappels == .accorde, !ref.isEmpty else { return nil }
        var r = store.calendarItem(withIdentifier: ref) as? EKReminder
        if r == nil {
            let afaire: [EKReminder] = await withCheckedContinuation { cont in
                store.fetchReminders(matching: store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)) {
                    cont.resume(returning: $0 ?? [])
                }
            }
            r = afaire.first { ($0.title ?? "").trimmingCharacters(in: .whitespaces) == ref }
        }
        guard let r else { return nil }
        if !r.isCompleted {
            r.isCompleted = true
            enregistrer(r)
        }
        return r.title ?? ref
    }

    func marquerFaite(_ id: String, _ faite: Bool) {
        guard let r = store.calendarItem(withIdentifier: id) as? EKReminder else { return }
        r.isCompleted = faite
        enregistrer(r)
    }

    /// Nouvelle tâche, dans la liste choisie (par défaut KRYVA : la synchro du matin lui crée sa ligne Notion).
    func creer(titre: String, notes: String, liste: String, date: Date?, avecHeure: Bool) {
        let r = EKReminder(eventStore: store)
        r.title = titre
        r.notes = notes.isEmpty ? nil : notes
        r.calendar = store.calendars(for: .reminder).first { $0.title == liste } ?? store.defaultCalendarForNewReminders()
        if let date {
            let champs: Set<Calendar.Component> = avecHeure ? [.year, .month, .day, .hour, .minute] : [.year, .month, .day]
            r.dueDateComponents = Calendar.current.dateComponents(champs, from: date)
            if avecHeure { r.addAlarm(EKAlarm(absoluteDate: date)) }
        }
        enregistrer(r)
    }

    private func enregistrer(_ r: EKReminder) {
        do {
            try store.save(r, commit: true)
            erreur = nil
        } catch {
            erreur = "Rappels n'a pas accepté la modification."
        }
        Task { await charger() }
    }

    /// Coche le rappel dans Rappels : la synchro de 6 h 30 reporte la case dans Notion.
    func cocher(_ rappel: Rappel) {
        guard let r = store.calendarItem(withIdentifier: rappel.id) as? EKReminder else { return }
        r.isCompleted = true
        do {
            try store.save(r, commit: true)
            rappels.removeAll { $0.id == rappel.id }
            decisionsAVenir.removeAll { $0.id == rappel.id }
        } catch {
            erreur = "Le rappel n'a pas pu être coché."
        }
    }

    /// Une décision « ❓ » tranchée : le choix s'ajoute aux notes du rappel, puis le rappel est coché.
    func trancher(_ rappel: Rappel, choix: String) {
        guard let r = store.calendarItem(withIdentifier: rappel.id) as? EKReminder else { return }
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "dd/MM HH:mm"
        r.notes = [r.notes ?? "", "Choix de \(Moi.nom) (\(f.string(from: Date()))) : \(choix)"].filter { !$0.isEmpty }.joined(separator: "\n")
        r.isCompleted = true
        do {
            try store.save(r, commit: true)
            rappels.removeAll { $0.id == rappel.id }
            decisionsAVenir.removeAll { $0.id == rappel.id }
        } catch {
            erreur = "La décision n'a pas pu être notée dans Rappels."
        }
    }

    private static func lienVisio(_ e: EKEvent) -> URL? {
        let texte = [e.notes, e.location].compactMap { $0 }.joined(separator: " ")
        guard let r = texte.range(of: #"https://(meet\.google\.com|[a-z0-9.]*zoom\.us|teams\.microsoft\.com)/[^\s>]+"#, options: .regularExpression)
        else { return nil }
        return URL(string: String(texte[r]))
    }
}
