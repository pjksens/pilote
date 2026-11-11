// Pilote : le suivi de tout le travail de Sacha (KRYVA, freelance, autre), sur son Mac.
import SwiftUI

@main
struct PiloteApp: App {
    @State private var etat = Etat()
    @State private var agenda = Agenda()
    @State private var tableau = TableauDomaines()
    /// Clair par défaut, sombre au choix (charte, règle 1).
    @AppStorage("apparence") private var apparence = "clair"

    private var aFaireAujourdhui: Int {
        agenda.taches.filter { !$0.faite && $0.echeance != nil && Jours.colonne($0.echeance) == .aujourdhui }.count
    }

    var body: some Scene {
        WindowGroup("Pilote", id: "principale") {
            Racine()
                .environment(etat)
                .environment(agenda)
                .environment(tableau)
                .environment(\.locale, Loc.locale)
                .frame(minWidth: 760, minHeight: 560)
                .preferredColorScheme(apparence == "sombre" ? .dark : (apparence == "clair" ? .light : nil))
        }
        .defaultSize(width: 1440, height: 900)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Nouveau contact") { etat.nouveauContact(espace: "kryva") }
                    .keyboardShortcut("n")
            }
            CommandGroup(after: .textEditing) {
                Button("Chercher partout") { etat.rechercheOuverte = true }
                    .keyboardShortcut("k")
                Button("Ouvrir le Radar") { etat.radarOuvert = true }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
            }
            CommandMenu("Apparence") {
                Picker("Apparence", selection: $apparence) {
                    Text("Clair").tag("clair")
                    Text("Sombre").tag("sombre")
                    Text("Comme le Mac").tag("systeme")
                }
                .pickerStyle(.inline)
            }
            CommandGroup(after: .sidebar) {
                Button("Accueil") { etat.ecran = .aujourdhui }.keyboardShortcut("1")
            }
        }

        MenuBarExtra {
            BarreMenusVue()
                .environment(etat)
                .environment(agenda)
                .environment(\.locale, Loc.locale)
                .environment(\.colorScheme, apparence == "sombre" ? .dark : .light)
        } label: {
            Label("\(aFaireAujourdhui)", systemImage: "location.north.fill").labelStyle(.titleAndIcon)
        }
        .menuBarExtraStyle(.window)
    }
}

struct Racine: View {
    @Environment(Etat.self) private var etat
    @Environment(Agenda.self) private var agenda

    var body: some View {
        // Un seul écran (09/11) : l'accueil reste vivant sous les autres pages (retour instantané, sans relecture) ; les
        // autres pages s'ouvrent par ⌘K et reviennent par « Accueil » (⌘[). Le panneau de droite (fiche, aperçu) prend
        // sa place dans la fenêtre telle qu'elle est : 45 % de la largeur, l'écran se resserre à côté.
        GeometryReader { g in
            let large = (etat.apercu == nil && etat.fichePanneau == nil) ? 0 : min(max(g.size.width * 0.45, 380), 760)
            HStack(spacing: 0) {
                ZStack {
                    EcranUnique()
                        .opacity(etat.ecran == .aujourdhui ? 1 : 0)
                        .allowsHitTesting(etat.ecran == .aujourdhui)
                        .accessibilityHidden(etat.ecran != .aujourdhui)
                    if etat.ecran != .aujourdhui {
                        pageOuverte.transition(.opacity)
                    }
                }
                .frame(width: g.size.width - large)
                if let id = etat.fichePanneau {
                    Rectangle().fill(Color.separateur).frame(width: 0.5)
                    FichePanneau(contactId: id).frame(width: max(large - 0.5, 0))
                        .transition(.move(edge: .trailing))
                } else if let c = etat.apercu {
                    Rectangle().fill(Color.separateur).frame(width: 0.5)
                    ApercuVue(chemin: c).frame(width: max(large - 0.5, 0))
                        .transition(.move(edge: .trailing))
                }
            }
        }
        .background(Color.fond)
        .animation(.easeOut(duration: 0.18), value: etat.apercu)
        .animation(.easeOut(duration: 0.18), value: etat.fichePanneau)
        .animation(.easeOut(duration: 0.15), value: etat.ecran)
        .navigationTitle(etat.ecran == .aujourdhui ? "Pilote" : etat.ecran.titre)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                if etat.ecran != .aujourdhui {
                    Button { etat.ecran = .aujourdhui } label: { Label("Accueil", systemImage: "chevron.left") }
                        .help("Revenir à l'accueil (⌘[)")
                        .keyboardShortcut("[", modifiers: .command)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                if etat.ecran != .aujourdhui {
                    Button { etat.rechercheOuverte = true } label: { Label("Chercher", systemImage: "magnifyingglass") }
                        .help("Chercher partout et ouvrir une autre page (⌘K)")
                }
            }
        }
        .sheet(isPresented: Binding(get: { etat.rechercheOuverte }, set: { etat.rechercheOuverte = $0 })) { RechercheVue() }
        .sheet(isPresented: Binding(get: { etat.radarOuvert }, set: { etat.radarOuvert = $0 })) { RadarVue() }
        .task { await agenda.demarrer() }
        .onAppear { Notifs.demarrer { etat.ecran = .aujourdhui } }
        .onChange(of: annonces, initial: true) { _, a in Notifs.signaler(a) }
        .task { await surveillerDemain() }
        .task { await cocherRappelsLies() }
    }

    /// 05/11 (T7) : chaque minute, coche les rappels liés aux messages dont la condition est cochée (ou qui sont partis sans
    /// condition), quel que soit l'endroit où c'est arrivé (app, agent, capteur). Rien tant que Rappels n'est pas accessible.
    private func cocherRappelsLies() async {
        while !Task.isCancelled {
            if agenda.accesRappels == .accorde, let stock = etat.stock,
               let liste = await Task.detached(operation: { try? stock.rappelsAFermer() }).value, !liste.isEmpty {
                for r in liste {
                    let titre = await agenda.cocherRappelLie(r.rappel)
                    try? stock.rappelFerme(r, titre: titre)
                }
                etat.charger()
            }
            try? await Task.sleep(for: .seconds(60))
        }
    }

    /// Chaque minute : à partir de 19 h (du lundi au vendredi et le dimanche), une notification s'il manque quelque chose
    /// pour demain. Une seule par soir ; rien tant que les Rappels ne sont pas lus.
    private func surveillerDemain() async {
        var arretsVusAvant: Set<String> = []     // une alerte n'est confirmée qu'à la 2e passe (60 s) : le capteur écrit à son 1er passage après le réveil
        while !Task.isCancelled {
            let maintenant = Date()
            let arretsMaintenant = await Task.detached { AlerteArret.lire(maintenant: maintenant) }.value   // fichiers : hors du fil principal
            let arretsConfirmes = arretsMaintenant.filter { arretsVusAvant.contains($0) }
            arretsVusAvant = Set(arretsMaintenant)
            if etat.arrets != arretsConfirmes { etat.arrets = arretsConfirmes }
            if let cle = DemainPret.cleNotification(maintenant) {
                let b = etat.bilanDemain(agenda, maintenant: maintenant)
                if b.complet, !b.trous.isEmpty {
                    let titre = L("Demain (\(DemainPret.libelleJour(b.jour))) pas prêt : \(b.trous.count) trous")
                    Notifs.prevenir(cle: cle, titre: titre,
                                    corps: b.trous.prefix(3).map { "\($0.titre) : \($0.detail)" }.joined(separator: " · "))
                }
            }
            // Le brief de 7 h (du lundi au samedi) et la séance du dimanche (à partir de 10 h) : une fois chacun.
            if let cle = MaJournee.cleNotification(maintenant), agenda.tachesLues {
                let e = etat.journee(agenda, maintenant: maintenant)
                let n = e.filter { $0.genre != .cadre && !$0.fait }.count
                if n > 0 {
                    // Heure réelle de réveil du Mac (pmset -g log, ~10 s, hors du fil principal) : le brief n'est jamais « de 7 h » si le Mac dormait.
                    let reveil = await Task.detached { AlerteArret.reveilDuJour(maintenant: maintenant) }.value
                    let ligneReveil = reveil.map { r -> String in
                        " · " + L("Mac réveillé à \(Loc.date(r, "HH:mm"))")
                    } ?? ""
                    Notifs.prevenir(cle: cle, titre: L("Votre journée (\(DemainPret.libelleJour(Dates.jour.string(from: maintenant)))) : \(n) choses prévues"),
                                    corps: MaJournee.resume(e) + ligneReveil)
                }
            }
            // Le contrôle du suivi des prospects (04/11, Sacha : « on ne doit rien louper »), avec le brief de 7 h, une fois par jour.
            // Il signale seulement : l'action du jour (envoyés encore dus, dus sans texte, dates sans source) ; les étapes sans
            // fait (R1) sont dans `pilote controle`.
            if let cle = MaJournee.cleNotification(maintenant), let stock = etat.stock,
               let c = await Task.detached(operation: { try? stock.controle(envoisKryva: EnvoisKryva.lire(), verifierKryva: true, maintenant: maintenant) }).value,
               c.envoyesEncoreDus.count + c.dusSansTexte.count + c.datesSansSource.count + c.sansDate.count + c.envoyesDepuisKryva.count > 0 {
                let n = c.envoyesEncoreDus.count + c.dusSansTexte.count + c.datesSansSource.count + c.sansDate.count + c.envoyesDepuisKryva.count
                var morceaux: [String] = []
                if !c.envoyesDepuisKryva.isEmpty { morceaux.append(L("MAIL PARTI D'UN DOMAINE INTERDIT \(c.envoyesDepuisKryva.count)")) }
                morceaux.append(L("Dus sans texte \(c.dusSansTexte.count) · envoyés mais encore dus \(c.envoyesEncoreDus.count) · dates sans source \(c.datesSansSource.count) · sans date \(c.sansDate.count) · étapes sans fait \(c.etapesSansFait.count)"))
                if !c.sansDateAContacter.isEmpty { morceaux.append(L("Stock à contacter : \(c.sansDateAContacter.count) (non compté)")) }
                Notifs.prevenir(cle: "controle-" + cle, titre: L("Suivi des prospects : \(n) trous"),
                                corps: morceaux.joined(separator: " · ") + ". " + L("`pilote controle` les liste."))
            }
            // 04/11 (GO de PILOTE) : capteur ou veille arrêtés depuis plus de 2 h de la plage 7 h-23 h, signalé une fois par jour
            // avec le brief ; depuis le 05/11 (T34) aussi en rouge en haut d'Aujourd'hui (etat.arrets).
            if let cle = MaJournee.cleNotification(maintenant) {
                let arrets = arretsConfirmes
                if !arrets.isEmpty {
                    Notifs.prevenir(cle: "arret-" + cle, titre: L("Pilote : un témoin est arrêté"),
                                    corps: arrets.joined(separator: " · ") + ". " + L("`pilote controle` le dit aussi."))
                }
            }
            if let cle = SeanceDimanche.cleNotification(maintenant) {
                let c = SeanceDimanche.creneaux(etat.videos, aujourdhui: Dates.jour.string(from: maintenant))
                let reste = c.filter { !$0.choisi }.count
                if reste > 0 {
                    Notifs.prevenir(cle: cle, titre: L("Séance du dimanche : \(reste) sujets à choisir"),
                                    corps: L("\(c.count - reste) sur \(c.count) choisis. Les propositions de Réseaux sont sur l'accueil, dans « À toi »."))
                }
            }
            try? await Task.sleep(for: .seconds(60))
        }
    }

    /// Les autres pages (atteintes par ⌘K) ; l'accueil n'est jamais recréé.
    private var pageOuverte: some View {
        Group {
            if let erreur = etat.erreurBase {
                EtatErreur(texte: erreur, reessayer: { etat.charger() }).padding(28)
            } else {
                switch etat.ecran {
                case .aujourdhui: EmptyView()
                case .journee: AujourdhuiVue()
                case .semaine: SemaineVue()
                case .prospects: ProspectsVue()
                case .planning: PlanningVue()
                case .taches: TachesVue()
                case .contacts: ContactsVue()
                case .projets: ProjetsVue()
                case .stats: StatsVideosVue()
                case .publications: PublicationsVue()
                case .claude: ClaudeVue()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.fond)
    }

    /// Les décisions à prendre (❓ et questions des sessions) : une notification pour chaque nouvelle, et le Dock.
    private var annonces: [Notifs.Annonce] {
        agenda.rappels.filter { Decisions.estDecision($0.titre) }.map {
            Notifs.Annonce(cle: $0.id, titre: L("Décision à prendre"),
                           corps: L("\(Decisions.question($0.titre)) (pour \(Decisions.pour(liste: $0.liste, notes: $0.notes)))"))
        } + etat.questionsSessions.map {
            Notifs.Annonce(cle: $0.questionRef, titre: L("\(etat.nomSession($0)) vous demande"), corps: $0.question)
        }
    }

}

/// En-tête de page : grand titre à gauche, détail en dessous.
struct EnTete: View {
    let titre: String
    var detail: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(titre).font(.titrePage).tracking(-0.6).foregroundStyle(Color.texte)
            if let detail { Text(detail).font(.ligne).foregroundStyle(Color.texte2) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
