// L'écran unique (docs/ECRAN-UNIQUE.md) : les 5 domaines, lus et regroupés hors du fil principal, remplacés seulement
// quand ils changent. La base (cartes, publications, personnes) est relue quand une connexion y écrit ; le dépôt suivi
// toutes les 60 secondes ; les sessions et les Rappels arrivent de l'état de l'app (déjà lus ailleurs, hors du fil principal).
import SwiftUI
import os

/// Les intervalles mesurés de l'écran (Instruments, modèle « Points of Interest » ou os_signpost).
enum Mesure {
    static let journal = OSLog(subsystem: "fr.pilote.app", category: .pointsOfInterest)
    static let signposter = OSSignposter(logHandle: journal)
}

@MainActor @Observable
final class TableauDomaines {
    var domaines: [EtatDomaine] = []
    /// Les publications de 30 jours (aussi pour « À toi » : livrables à valider, À publier).
    var publications: [Publication] = []
    var charge = false
    var miseAJour = false
    var erreur: String?

    @ObservationIgnored private var lecteur: Stockage?
    @ObservationIgnored private var version = -1
    @ObservationIgnored private var cartes: [CarteDomaine] = []
    @ObservationIgnored private var contacts: [ResumeContact] = []
    @ObservationIgnored private var commits: [CommitKryva]? = []
    @ObservationIgnored private var sessions: [SessionDomaine] = []
    @ObservationIgnored private var travaux: [TravailAgent] = []
    @ObservationIgnored private var push: TacheDomaine?
    @ObservationIgnored private var taches: [TacheDomaine]? = nil
    @ObservationIgnored private var rappelsSacha: [TacheDomaine]? = nil
    @ObservationIgnored private var baseLue = false
    @ObservationIgnored private var regroupementEnCours = false
    @ObservationIgnored private var regrouperEncore = false
    @ObservationIgnored private var demarre = false

    /// Lancé une fois par la fenêtre : la base toutes les 2 s (si elle a changé), le dépôt toutes les 60 s.
    func demarrer() {
        guard !demarre else { return }
        demarre = true
        Task { await suivreBase() }
        Task { await suivreDepot() }
    }

    func reessayer() {
        erreur = nil
        version = -1
    }

    private struct Lu {
        var lecteur: Stockage?
        var version = -1
        var cartes: [CarteDomaine]?
        var publications: [Publication]?
        var contacts: [ResumeContact]?
        var erreur: String?
    }

    private func suivreBase() async {
        while !Task.isCancelled {
            let lecteur = self.lecteur, connue = version
            let lu = await Task.detached(priority: .userInitiated) { () -> Lu in
                var lu = Lu()
                do {
                    let l = try lecteur ?? Stockage(base: Base())
                    lu.lecteur = l
                    lu.version = l.base.versionDonnees()
                    guard lu.version != connue else { return lu }
                    let id = Mesure.signposter.makeSignpostID()
                    let etat = Mesure.signposter.beginInterval("Lecture des domaines", id: id)
                    lu.cartes = try l.cartesDomaine()
                    lu.publications = try Publications.liste(l, jours: 30)
                    lu.contacts = try l.resumesContacts()
                    Mesure.signposter.endInterval("Lecture des domaines", etat)
                } catch {
                    lu.erreur = "\(error)"
                }
                return lu
            }.value
            if self.lecteur == nil { self.lecteur = lu.lecteur }
            if let e = lu.erreur {
                if erreur != e { erreur = e }
            } else if let cartes = lu.cartes, let publications = lu.publications, let contacts = lu.contacts {
                version = lu.version
                if erreur != nil { erreur = nil }
                self.cartes = cartes
                self.contacts = contacts
                if self.publications != publications { self.publications = publications }
                baseLue = true
                regrouper()
            }
            try? await Task.sleep(for: .seconds(2))
        }
    }

    private func suivreDepot() async {
        while !Task.isCancelled {
            let lus = await Task.detached(priority: .utility) { GitKryva.lire() }.value
            if lus != commits {
                commits = lus
                regrouper()
            }
            try? await Task.sleep(for: .seconds(60))
        }
    }

    /// Les sessions vivantes (relues par l'état toutes les 4 s).
    func sessions(_ agents: [ActiviteSession]) {
        let s = agents.map(SessionDomaine.init)
        guard s != sessions else { return }
        sessions = s
        regrouper()
    }

    /// La liste Papiers des Rappels ; nil tant que les Rappels ne sont pas accessibles.
    func taches(_ liste: [Tache]?) {
        let t = liste?.filter { $0.liste.localizedCaseInsensitiveContains("papiers") }
            .map { TacheDomaine(id: $0.id, titre: $0.titre, echeance: $0.echeance, faite: $0.faite, faiteLe: $0.faiteLe) }
        // 09/11 : le travail d'agent (liste « Agents ») et le rappel du « push » de Sacha, lus dans les mêmes Rappels.
        let a = (liste ?? []).filter { $0.liste == TravailAgents.liste }
            .map { TravailAgents.lire(id: $0.id, titre: $0.titre, notes: $0.notes, faite: $0.faite, faiteLe: $0.faiteLe) }
        let p = (liste ?? []).filter { !$0.faite && ATOI.listeDeSacha($0.liste) && $0.titre.range(of: "push", options: .caseInsensitive) != nil }
            .min { ($0.echeance ?? .distantFuture) < ($1.echeance ?? .distantFuture) }
            .map { TacheDomaine(id: $0.id, titre: $0.titre, echeance: $0.echeance, faite: false, faiteLe: nil) }
        // 09/11 (Organisation) : les rappels de Sacha, pour les cartes qui l'attendent (« Pour toi » du domaine de l'agent).
        // Un ❓ est à Sacha quelle que soit sa liste.
        let r = liste?.filter { ATOI.listeDeSacha($0.liste) || Decisions.estDecision($0.titre) }
            .map { TacheDomaine(id: $0.id, titre: $0.titre, echeance: $0.echeance, faite: $0.faite, faiteLe: $0.faiteLe,
                                domaine: Domaines.domaineDuRappel(titre: $0.titre, liste: $0.liste, notes: $0.notes),
                                decision: Decisions.estDecision($0.titre)) }
        guard t != taches || a != travaux || p != push || r != rappelsSacha else { return }
        taches = t
        travaux = a
        push = p
        rappelsSacha = r
        regrouper()
    }

    /// Le regroupement est pur et court, mais tourne lui aussi hors du fil principal ; seuls les domaines changés sont remplacés.
    private func regrouper() {
        guard baseLue else { return }
        if regroupementEnCours { regrouperEncore = true; return }
        regroupementEnCours = true
        if charge { miseAJour = true }
        let sources = SourcesDomaines(maintenant: Date(), cartes: cartes, commits: commits, publications: publications,
                                      contacts: contacts, taches: taches, sessions: sessions, travaux: travaux, push: push,
                                      rappelsSacha: rappelsSacha)
        Task {
            let nouveaux = await Task.detached(priority: .userInitiated) { Domaines.regrouper(sources) }.value
            regroupementEnCours = false
            if nouveaux.count != domaines.count {
                domaines = nouveaux
            } else {
                for (i, d) in nouveaux.enumerated() where domaines[i] != d { domaines[i] = d }
            }
            if !charge { charge = true }
            miseAJour = false
            if regrouperEncore { regrouperEncore = false; regrouper() }
        }
    }
}
