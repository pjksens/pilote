// Aujourd'hui (03/11, Sacha) : le seul écran à ouvrir le matin, quatre blocs et peu de mots.
// À publier · À tourner · Prospects du jour (5 au plus) · À décider (3 au plus). Le reste est replié en bas.
import SwiftUI

enum Chargement: Equatable { case attente, enCours, pret, erreur(String) }

/// Un prospect du jour : un message déjà prêt (texte validé) ou un suivi en retard.
enum ProspectDuJour: Identifiable {
    case message(MessageAEnvoyer)
    case suivi(Contact)
    var id: String {
        switch self {
        case .message(let m): return "m" + m.id
        case .suivi(let c): return "c" + c.id
        }
    }
}

struct AujourdhuiVue: View {
    @Environment(Etat.self) private var etat
    @Environment(Agenda.self) private var agenda
    @State private var detailCompteur = false
    @AppStorage("aujourdhuiReste") private var resteOuvert = false
    /// Les décisions au-delà des 3 premières, dépliées sur place (aucune ne doit rester cachée).
    @State private var toutesDecisions = false
    @State private var plusTardOuvert = false
    @State private var largeur: CGFloat = 0

    // Mails, compteur et inscrits vivent dans Etat : l'écran est recréé à chaque retour sur l'onglet, pas ces lectures.
    private var mails: [MessageMail] { etat.mails }
    private var etatMails: Chargement { etat.etatMails }
    private var compteur: Compteur? { etat.compteur }
    private var reglages: Reglages { Reglages.courants }
    private var etatCompteur: Chargement { etat.etatCompteur }
    private var inscrits: [Inscrit] { etat.inscrits }
    private var etatInscrits: Chargement { etat.etatInscrits }
    private var actualisationEnCours: Bool { etat.etatMails == .enCours || etat.etatCompteur == .enCours || etat.etatInscrits == .enCours }

    private var dateDuJour: String {
        let s = Loc.date(Date(), "EEEEdMMMM")
        return s.prefix(1).uppercased() + s.dropFirst()
    }


    private var aujourdhui: String { Dates.aujourdhui() }
    /// On tourne aujourd'hui les vidéos du jour ouvré suivant ; rien le samedi ni le dimanche.
    private var jourATourner: String? { VideoCalcul.estOuvre(aujourdhui) ? VideoCalcul.lendemainOuvre(aujourdhui) : nil }

    private var decisions: [Rappel] { agenda.rappels.filter { Decisions.estDecision($0.titre) } }
    private var autresRappels: [Rappel] { agenda.rappels.filter { !Decisions.estDecision($0.titre) } }

    /// D'abord les messages prêts (le texte est validé, il reste à l'envoyer), puis les suivis en retard, priorité haute d'abord.
    private var prospects: [ProspectDuJour] {
        let aujourdhui = etat.aEnvoyerAujourdhui
        let avecMessage = Set(etat.aEnvoyer.map(\.contact.id))
        let suivis = etat.dus.filter { !avecMessage.contains($0.id) }
            .sorted { ($0.priorite, $0.prochaineDate) < ($1.priorite, $1.prochaineDate) }
        return aujourdhui.map(ProspectDuJour.message) + suivis.map(ProspectDuJour.suivi)
    }

    /// 05/11 (T34) : un témoin est périmé (capteur, veille, Facteur, inscrits, disque, WhatsApp) : en rouge, tout en haut.
    private var bandeauArrets: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(etat.arrets.count == 1 ? "Un témoin est arrêté" : "\(etat.arrets.count) témoins sont arrêtés", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
            ForEach(etat.arrets, id: \.self) { Text($0).font(.callout).textSelection(.enabled) }
        }
        .foregroundStyle(.red)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.red.opacity(0.5)))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                EnTete(titre: L("Aujourd'hui"), detail: dateDuJour)
                if !etat.arrets.isEmpty { bandeauArrets }
                if let e = etat.erreurSynchro {
                    Carte(titre: L("Synchro KRYVA")) { EtatErreur(texte: L("Synchro avec l'admin KRYVA : \(e)")) }
                }
                TimelineView(.everyMinute) { contexte in bandeauRendezVous(a: contexte.date) }
                // « Demain prêt ? » : en haut le soir (dès 17 h) et le week-end, sous « À décider » le reste du temps.
                let soir = Calendar.current.component(.hour, from: Date()) >= 17 || !VideoCalcul.estOuvre(aujourdhui)
                // Le samedi et le dimanche : la séance des sujets de la semaine qui vient.
                if SeanceDimanche.affichee(aujourdhui) { CarteSeanceDimanche() }
                // « Ma journée » en haut pendant la journée de travail, « Demain » le soir.
                if soir { CarteDemain() } else { CarteJournee() }
                // Côte à côte sur une fenêtre large ; l'une sous l'autre quand le panneau de droite est ouvert.
                let cote = largeur == 0 || largeur > 860
                (cote ? AnyLayout(HStackLayout(alignment: .top, spacing: 16)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 16))) {
                    blocPublier
                    blocTourner
                }
                CarteFileEnvoi()
                blocProspects
                CarteAgentsDuJour()
                if !etat.aValider.isEmpty || !etat.aRefaire.isEmpty { blocValider }
                blocDecider
                if soir { CarteJournee() } else { CarteDemain() }
                CarteVosSessions()
                if !autresRappels.isEmpty { blocRappels }
                DisclosureGroup(isExpanded: $resteOuvert) {
                    VStack(alignment: .leading, spacing: 20) {
                        if reglages.mail == true { carteMails }
                        if reglages.comptes?.compteur != nil { carteChiffres }
                        CarteRadar()
                        if reglages.comptes != nil { carteInscrits }
                    }
                    .padding(.top, 12)
                } label: {
                    Text("Le reste : mails, chiffres, Radar, inscrits")
                        .font(.secondaire.weight(.semibold)).foregroundStyle(Color.texte2)
                }
            }
            .padding(28)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { largeur = $0 }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { Task { await etat.actualiserAujourdhui(force: true) } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(actualisationEnCours)
                .help("Actualiser les mails, le compteur et les inscrits")
            }
            if let r = Claude.routines.first {
                ToolbarItem(placement: .primaryAction) {
                    BoutonPrincipal(titre: r.titre, symbole: "sparkle") {
                        Claude.nouvelle(consigne: r.consigne, dossier: r.dossier)
                    }
                    .help("Ouvre une session Claude avec votre première routine (reglages.json). Rien ne part sans vous.")
                }
            }
        }
        .task { await etat.actualiserAujourdhui() }
    }

    private func sousTitre(_ titre: String, _ nombre: Int) -> some View {
        Text("\(titre) · \(nombre)").font(.secondaire.weight(.semibold)).foregroundStyle(Color.texte2)
            .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 4)
    }

    // MARK: Rendez-vous : une bande fine, seulement s'il en reste aujourd'hui

    @ViewBuilder
    private func bandeauRendezVous(a maintenant: Date) -> some View {
        let restants = agenda.restants(a: maintenant)
        if agenda.accesCalendrier == .accorde, !restants.isEmpty {
            Carte(titre: L("Rendez-vous"), detail: "\(restants.count)") {
                ForEach(Array(restants.enumerated()), id: \.element.id) { i, rv in
                    LigneCarte(dernier: i == restants.count - 1) { LigneRendezVous(rv: rv) }
                }
            }
        }
    }

    // MARK: Vidéos

    private var blocPublier: some View {
        Carte(titre: L("À publier aujourd'hui")) {
            if VideoCalcul.estOuvre(aujourdhui) {
                HStack(spacing: 10) {
                    ForEach(VideoVocabulaire.comptes, id: \.0) { TuileVideo(jour: aujourdhui, compte: $0.0) }
                }
                .padding(.horizontal, 12).padding(.bottom, 12)
            } else {
                EtatVide(texte: L("Rien le week-end."))
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var blocTourner: some View {
        Carte(titre: L("À tourner aujourd'hui"), detail: jourATourner.map { L("pour \(Dates.court($0))") }) {
            if let jour = jourATourner {
                HStack(spacing: 10) {
                    ForEach(VideoVocabulaire.comptes, id: \.0) { TuileVideo(jour: jour, compte: $0.0) }
                }
                .padding(.horizontal, 12).padding(.bottom, 12)
            } else {
                EtatVide(texte: L("Rien à tourner le week-end. Les vidéos de lundi se tournent vendredi."))
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Prospects du jour (5 au plus)

    private var blocProspects: some View {
        let tous = prospects
        let montres = Array(tous.prefix(5))
        return Carte(titre: L("Prospects du jour"), detail: tous.isEmpty ? nil : L("\(montres.count) sur \(tous.count) en attente")) {
            if tous.isEmpty {
                EtatVide(texte: L("Personne à relancer aujourd'hui."))
                lignePlusTard
            } else {
                ForEach(Array(montres.enumerated()), id: \.element.id) { i, p in
                    LigneCarte(dernier: i == montres.count - 1 && tous.count <= 5) {
                        switch p {
                        case .message(let m): LigneAEnvoyer(message: m)
                        case .suivi(let c): LigneSuiviDuJour(contact: c)
                        }
                    }
                }
                if tous.count > 5 {
                    Button(tous.count == 6 ? "Voir l'autre dans Prospects" : "Voir les \(tous.count - 5) autres dans Prospects") { etat.ecran = .prospects }
                        .buttonStyle(.link).font(.secondaire)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                }
                lignePlusTard
            }
        }
    }

    /// Les messages prêts pour un jour suivant : une ligne repliée (« 3 demain, 2 jeu. 5 »), dépliable.
    @ViewBuilder
    private var lignePlusTard: some View {
        let plusTard = etat.aEnvoyerPlusTard
        if !plusTard.isEmpty {
            let jours = Dictionary(grouping: plusTard, by: \.jour).sorted { $0.key < $1.key }
                .map { $0.key == Dates.dans(1) ? L("\($0.value.count) demain") : L("\($0.value.count) le \(Dates.court($0.key))") }
            Button { withAnimation(.snappy) { plusTardOuvert.toggle() } } label: {
                Label("Prêts pour plus tard, ils s'afficheront le jour venu : \(jours.joined(separator: ", "))",
                      systemImage: plusTardOuvert ? "chevron.down" : "chevron.right")
            }
            .buttonStyle(.plain).font(.secondaire).foregroundStyle(Color.texte2)
            .padding(.horizontal, 16).padding(.vertical, 10)
            if plusTardOuvert {
                ForEach(plusTard) { m in LigneCarte { LigneAEnvoyer(message: m) }.opacity(0.75) }
            }
        }
    }

    // MARK: Textes à valider (03/11) : le texte exact, en entier, avant qu'il soit rangé « à envoyer »

    private var blocValider: some View {
        let liste = etat.aValider
        let auteurs = Set(liste.map { Etat.auteur($0.contact) }).sorted().joined(separator: ", ")
        return Carte(titre: L("Textes à valider"), detail: liste.isEmpty ? nil : L("\(liste.count) · écrits par \(auteurs)")) {
            if liste.isEmpty {
                EtatVide(texte: L("Rien à valider."))
            }
            ForEach(Array(liste.enumerated()), id: \.element.id) { i, m in
                LigneCarte(dernier: i == liste.count - 1 && etat.aRefaire.isEmpty) { CarteTexte(message: m) }
            }
            if !etat.aRefaire.isEmpty {
                let n = etat.aRefaire.count
                Label(n > 1 ? L("\(n) textes renvoyés avec votre consigne : ils reviendront ici une fois réécrits.")
                          : L("1 texte renvoyé avec votre consigne : il reviendra ici une fois réécrit."),
                      systemImage: "arrow.uturn.backward")
                    .font(.secondaire).foregroundStyle(Color.texte2)
                    .padding(.horizontal, 16).padding(.vertical, 10)
            }
        }
    }

    // MARK: À décider (3 au plus)

    private var blocDecider: some View {
        let toutes = decisions
        let montrees = toutesDecisions ? toutes : Array(toutes.prefix(3))
        let questions = etat.questionsSessions
        return Carte(titre: L("À décider"), detail: toutes.count > 3 ? L("\(montrees.count) sur \(toutes.count)") : nil) {
            // Les questions des sessions d'abord : une session attend la réponse pour continuer.
            ForEach(Array(questions.enumerated()), id: \.element.id) { i, a in
                LigneCarte(dernier: i == questions.count - 1 && montrees.isEmpty) {
                    CarteQuestionSession(activite: a, nom: etat.nomSession(a))
                }
            }
            switch agenda.accesRappels {
            case .refuse:
                EtatErreur(texte: L("Pilote n'a pas accès à Rappels. Réglages Système › Confidentialité › Rappels."))
            case .coupe:
                if montrees.isEmpty && questions.isEmpty { EtatVide(texte: L("Rappels coupés : à activer dans reglages.json (rappels_calendrier).")) }
            case .inconnu:
                EtatChargement(texte: L("Lecture de vos rappels…"))
            case .accorde:
                if montrees.isEmpty {
                    if questions.isEmpty { EtatVide(texte: L("Aucune décision en attente.")) }
                } else {
                    ForEach(Array(montrees.enumerated()), id: \.element.id) { i, r in
                        LigneCarte(dernier: i == montrees.count - 1 && toutes.count <= 3) { CarteDecision(rappel: r) }
                    }
                    if toutes.count > 3 {
                        Button(toutesDecisions ? L("Replier") : (toutes.count == 4 ? L("Voir l'autre décision") : L("Voir les \(toutes.count - 3) autres décisions"))) {
                            withAnimation(.snappy) { toutesDecisions.toggle() }
                        }
                        .buttonStyle(.link).font(.secondaire).padding(.top, 8)
                    }
                }
                DecisionsEnvoyees()
            }
        }
    }

    // MARK: Les autres rappels du jour (3 au plus)

    private var blocRappels: some View {
        let tous = autresRappels
        let montres = Array(tous.prefix(3))
        return Carte(titre: L("Autres rappels du jour"), detail: tous.count > 3 ? L("3 sur \(tous.count)") : "\(tous.count)") {
            ForEach(Array(montres.enumerated()), id: \.element.id) { i, r in
                LigneCarte(dernier: i == montres.count - 1 && tous.count <= 3) { LigneRappel(rappel: r) }
            }
            if tous.count > 3 {
                Button(tous.count == 4 ? "Voir l'autre dans Tâches" : "Voir les \(tous.count - 3) autres dans Tâches") { etat.ecran = .taches }
                    .buttonStyle(.link).font(.secondaire)
                    .padding(.horizontal, 16).padding(.vertical, 10)
            }
        }
    }

    // MARK: Le reste (replié)

    private var carteMails: some View {
        Carte(titre: L("Mails de vos contacts"), detail: L("3 derniers jours")) {
            switch etatMails {
            case .attente, .enCours:
                EtatChargement(texte: L("Recherche des mails de vos contacts…"))
            case .erreur(let e):
                EtatErreur(texte: e) { Task { await etat.chargerMails(force: true) } }
            case .pret:
                if mails.isEmpty {
                    EtatVide(texte: L("Aucun mail de vos contacts ces 3 derniers jours."))
                } else {
                    ForEach(Array(mails.enumerated()), id: \.element.id) { i, m in
                        LigneCarte(dernier: i == mails.count - 1) {
                            Button { Mail.ouvrir(m) } label: { LigneMail(message: m, contact: contactPour(m)) }.buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    // MARK: En chiffres (module comptes, commande du compteur)

    private var carteChiffres: some View {
        Carte(titre: L("En chiffres"), detail: L("objectif : \(compteur?.objectif ?? 0) actifs")) {
            if let c = compteur {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(c.actifs)").font(.system(size: 34, weight: .bold).monospacedDigit()).foregroundStyle(Color.texte)
                    Text(c.actifs > 1 ? L("actifs sur \(c.objectif)") : L("actif sur \(c.objectif)")).font(.titreSection).foregroundStyle(Color.texte2)
                    Spacer()
                    Text("\(inscrits.count) inscrits en 14 jours").font(.secondaire).foregroundStyle(Color.texte2)
                }
                .padding(.horizontal, 16)
                ProgressView(value: Double(min(c.actifs, c.objectif)), total: Double(c.objectif))
                    .tint(.vert).padding(.horizontal, 16).padding(.bottom, 10)
                if !c.sections.isEmpty {
                    DisclosureGroup("Détail", isExpanded: $detailCompteur) {
                        ForEach(Array(c.sections.enumerated()), id: \.offset) { _, section in
                            Text(section.titre).font(.secondaire.weight(.semibold)).foregroundStyle(Color.texte2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 8).padding(.bottom, 2)
                            if section.lignes.isEmpty {
                                Text("Personne pour l'instant.").font(.secondaire).foregroundStyle(Color.texte3)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            ForEach(section.lignes) { l in
                                Text(l.texte).font(.secondaire).foregroundStyle(Color.texte)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .font(.secondaire).foregroundStyle(Color.texte2)
                    .padding(.horizontal, 16).padding(.bottom, 10)
                }
            } else {
                switch etatCompteur {
                case .erreur(let e): EtatErreur(texte: e) { Task { await etat.chargerCompteur(force: true) } }
                default: EtatChargement(texte: L("Calcul du compteur…"))
                }
            }
        }
    }

    // MARK: Inscrits à accompagner

    private var carteInscrits: some View {
        Carte(titre: L("Inscrits à accompagner"), detail: L("14 derniers jours")) {
            switch etatInscrits {
            case .attente where inscrits.isEmpty, .enCours where inscrits.isEmpty:
                EtatChargement(texte: L("Lecture de la base des comptes…"))
            case .erreur(let e):
                EtatErreur(texte: e) { Task { await etat.chargerInscrits(force: true) } }
            default:
                if inscrits.isEmpty {
                    EtatVide(texte: L("Aucune inscription ces 14 derniers jours."))
                } else {
                    ForEach(Array(inscrits.enumerated()), id: \.element.id) { i, ins in
                        LigneCarte(dernier: i == inscrits.count - 1) { LigneInscrit(inscrit: ins) }
                    }
                }
            }
        }
    }

    private func contactPour(_ m: MessageMail) -> Contact? {
        etat.contacts.first { !$0.email.isEmpty && $0.email.lowercased() == m.adresse }
    }
}

// MARK: Lignes

/// Un suivi du jour : la couleur dit depuis combien de jours on n'a rien fait, la phrase dit quoi faire.
struct LigneSuiviDuJour: View {
    @Environment(Etat.self) private var etat
    let contact: Contact
    @State private var choisirDate = false
    @State private var feuillePasFait = false
    @State private var date = Date()

    var body: some View {
        let echange = etat.echanges[contact.id]
        let jours = echange?.jours()
        HStack(alignment: .center, spacing: 12) {
            RoundedRectangle(cornerRadius: 2).fill(Couleurs.depuis(jours)).frame(width: 4, height: 40)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(contact.titre).font(.ligneForte).foregroundStyle(Color.texte)
                    if !contact.sousTitre.isEmpty { Text(contact.sousTitre).font(.secondaire).foregroundStyle(Color.texte2).lineLimit(1) }
                }
                Text(contact.prochaineAction.isEmpty ? L("Prochaine action à préciser") : contact.prochaineAction)
                    .font(.ligne).foregroundStyle(Color.texte).lineLimit(2)
                Text(echange?.resumeAffiche ?? L("Aucun échange noté"))
                    .font(.petit).foregroundStyle(Color.texte3)
                ParcoursContact(contact: contact, compact: true).padding(.top, 2)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                Text(contact.prochaineDate < Dates.aujourdhui() ? L("Prévu le \(Dates.court(contact.prochaineDate))") : L("Aujourd'hui"))
                    .font(.secondaire).foregroundStyle(contact.prochaineDate < Dates.aujourdhui() ? Color.rouge : Color.texte2)
                HStack(spacing: 6) {
                    Button("Fiche") { etat.ouvrir(contact) }
                    Menu {
                        ForEach(Report.allCases) { r in Button(r.libelle) { etat.reporterAction(contact, au: r.jour(depuis: Date())) } }
                        Divider()
                        Button("Date précise…") { date = Report.demain.jour(depuis: Date()); choisirDate = true }
                        Button("Pas fait : noter la raison…") { feuillePasFait = true }
                    } label: { Text("Reporter") }
                    .menuStyle(.borderlessButton).fixedSize()
                    .help("La même action, un autre jour : la ligne quitte Aujourd'hui")
                    if Invitation.attendue(contact.prochaineAction) {
                        // 04/11, Sacha : « pas d'option pour dire qu'une invitation n'a pas été acceptée »
                        Button("Pas encore") { etat.invitationPasEncore(contact) }
                            .help("Pas encore acceptée : on revoit dans \(Invitation.delai) jours ouvrés ; au \(Invitation.essais)e « pas encore », l'agent prépare un mail ou un DM Insta")
                        Button("Acceptée") { etat.invitationAcceptee(contact) }
                            .help("Acceptée : l'agent prépare le message après acceptation, à valider")
                    } else {
                        Button("Fait") { etat.actionFaite(contact) }
                            .help("La prochaine action est faite : elle passe dans le fil et la date se libère")
                    }
                }
                .controlSize(.small)
            }
        }
        .contentShape(Rectangle())
        .sheet(isPresented: $choisirDate) { feuilleDate }
        .sheet(isPresented: $feuillePasFait) { FeuillePasEnvoye(cible: .suivi(contact)) }
    }

    private var feuilleDate: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Reporter « \(contact.prochaineAction.isEmpty ? contact.titre : contact.prochaineAction) »")
                .font(.titreSection).foregroundStyle(Color.texte).lineLimit(2)
            DatePicker("Nouvelle date", selection: $date, in: Date()..., displayedComponents: [.date])
                .datePickerStyle(.graphical).labelsHidden()
            HStack {
                Spacer()
                Button("Annuler") { choisirDate = false }.keyboardShortcut(.cancelAction)
                Button("Reporter") { etat.reporterAction(contact, au: date); choisirDate = false }
                    .buttonStyle(.borderedProminent).tint(.action).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20).frame(width: 340)
    }
}

/// Une décision : la question, deux lignes de contexte, un bouton par choix. Un clic tranche.
struct CarteDecision: View {
    @Environment(Agenda.self) private var agenda
    @Environment(Etat.self) private var etat
    let rappel: Rappel
    @State private var choisi: String?
    @State private var erreur: String?
    @State private var autre = false
    @State private var texteAutre = ""

    var body: some View {
        let options = Decisions.options(rappel.notes)
        let contexte = Decisions.contexte(rappel.notes).trimmingCharacters(in: .whitespacesAndNewlines)
        let docs = Decisions.documents(rappel.notes)
        let pour = Decisions.pour(liste: rappel.liste, notes: rappel.notes)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: "questionmark.circle.fill").foregroundStyle(Color.ambre)
                Text(Decisions.question(rappel.titre)).font(.ligneForte).foregroundStyle(Color.texte)
                Spacer()
                Label(pour, systemImage: "paperplane").font(.petit).foregroundStyle(Color.texte3)
                    .help("Votre choix part tout seul à cette session (au plus tard 15 min après le clic).")
            }
            if !contexte.isEmpty {
                Text(contexte).font(.secondaire).foregroundStyle(Color.texte2).lineLimit(6).textSelection(.enabled)
            }
            if !docs.isEmpty {
                HStack(spacing: 6) {
                    ForEach(docs, id: \.self) { d in
                        Button { etat.montrer(d) } label: {
                            Label((d as NSString).lastPathComponent, systemImage: "doc.text").lineLimit(1)
                        }
                        .help("Lire à droite : \(Chemins.court(d))")
                    }
                }
                .buttonStyle(.bordered).controlSize(.small)
            }
            // Choix courts côte à côte ; longs, l'un sous l'autre.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { boutons(options) }
                VStack(alignment: .leading, spacing: 6) { boutons(options) }
            }
            .buttonStyle(.bordered)
            .disabled(choisi != nil)
            if autre {
                HStack(alignment: .bottom, spacing: 8) {
                    TextField("Ce que vous voulez, en une phrase ou plus", text: $texteAutre, axis: .vertical)
                        .textFieldStyle(.roundedBorder).lineLimit(1...5)
                        .onSubmit(envoyerAutre)
                    Button("Envoyer", action: envoyerAutre)
                        .buttonStyle(.borderedProminent).tint(.action)
                        .disabled(texteAutre.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || choisi != nil)
                }
            }
            if let erreur { Text(erreur).font(.petit).foregroundStyle(Color.rouge) }
        }
    }

    @ViewBuilder
    private func boutons(_ options: [String]) -> some View {
        if options.isEmpty {
            Button("C'est réglé") { choisir("réglé") }
        }
        ForEach(Array(options.enumerated()), id: \.offset) { _, o in
            Button { choisir(o) } label: {
                Label(o, systemImage: choisi == o ? "checkmark" : "circle").lineLimit(3).multilineTextAlignment(.leading)
            }
            .tint(choisi == o ? .vert : nil)
        }
        Button { withAnimation(.snappy) { autre.toggle() } } label: {
            Label("Autre…", systemImage: "pencil")
        }
        .help("Écrire ce que vous voulez : votre texte part tel quel à la session.")
    }

    private func envoyerAutre() {
        let t = texteAutre.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        choisir("Autre : \(t)")
    }

    private func choisir(_ o: String) {
        choisi = o
        do {
            try Decisions.noter(question: Decisions.question(rappel.titre), choix: o, ref: rappel.id, liste: rappel.liste,
                                pour: Decisions.pour(liste: rappel.liste, notes: rappel.notes))
        } catch {
            erreur = L("Le choix n'a pas pu être transmis : \(error.localizedDescription)")
            choisi = nil
            return
        }
        etat.relireDecisions()
        Task { try? await Task.sleep(for: .milliseconds(400)); agenda.trancher(rappel, choix: o) }
    }
}

/// La question de fin de tour d'une session (wrap_up) : ses boutons, ou « Autre… ». La réponse attend dans
/// « Vos réponses, prêtes à partir » jusqu'au clic Envoyer, puis le Facteur (ou la veille) la remet à cette session.
struct CarteQuestionSession: View {
    @Environment(Etat.self) private var etat
    let activite: ActiviteSession
    let nom: String
    @State private var choisi: String?
    @State private var erreur: String?
    @State private var autre = false
    @State private var texteAutre = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: "bubble.left.and.text.bubble.right.fill").foregroundStyle(Color.ambre)
                Text(activite.question).font(.ligneForte).foregroundStyle(Color.texte)
                Spacer()
                Label(nom, systemImage: "paperplane").font(.petit).foregroundStyle(Color.texte3)
                    .help("Question de la session \(nom). Votre réponse part quand vous cliquez Envoyer.")
            }
            if let origine {
                Text(origine.0).font(.petit).foregroundStyle(Color.texte3).help(origine.1)
            }
            if !activite.recap.isEmpty {
                Text(LectureMarkdown.enLigne(activite.recap)).font(.secondaire).foregroundStyle(Color.texte2).lineLimit(4)
                    .textSelection(.enabled)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { boutons }
                VStack(alignment: .leading, spacing: 6) { boutons }
            }
            .buttonStyle(.bordered)
            .disabled(choisi != nil)
            if autre {
                HStack(alignment: .bottom, spacing: 8) {
                    TextField("Votre réponse à \(nom)", text: $texteAutre, axis: .vertical)
                        .textFieldStyle(.roundedBorder).lineLimit(1...5)
                        .onSubmit(envoyerAutre)
                    Button("Garder", action: envoyerAutre)
                        .buttonStyle(.borderedProminent).tint(.action)
                        .disabled(texteAutre.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || choisi != nil)
                }
            }
            if let erreur { Text(erreur).font(.petit).foregroundStyle(Color.rouge) }
        }
    }

    @ViewBuilder
    private var boutons: some View {
        ForEach(Array(activite.choix.enumerated()), id: \.offset) { _, o in
            Button { choisir(o) } label: {
                Label(o, systemImage: choisi == o ? "checkmark" : "circle").lineLimit(2)
            }
            .tint(choisi == o ? .vert : nil)
        }
        Button { withAnimation(.snappy) { autre.toggle() } } label: { Label("Autre…", systemImage: "pencil") }
        Button("Ouvrir") { Claude.ouvrir(id: activite.sessionApp) }
            .help("Ouvrir la session dans l'app Claude")
        if activite.questionGenre == "texte" {
            Button("Pas une question") { etat.ignorerQuestion(activite.questionRef) }
                .help("Écarter cette phrase : elle ne s'affiche plus, rien ne part à la session.")
        }
    }

    /// D'où vient la question, quand ce n'est pas un bouton de fin de tour.
    private var origine: (String, String)? {
        switch activite.questionGenre {
        case "dialogue":
            return (L("Aussi en dialogue dans l'app Claude : la session y attend"),
                    L("Question posée avec AskUserQuestion. Le plus sûr : répondre dans la session (Ouvrir). Une réponse d'ici lui part aussi ; qu'elle ferme le dialogue n'est pas vérifié."))
        case "texte":
            return (L("Repérée dans son texte (sans bouton de fin de tour)"),
                    L("La session a écrit cette question sans la mettre dans sa fin de tour : Pilote l'a repérée quand même."))
        default: return nil
        }
    }

    private func envoyerAutre() {
        let t = texteAutre.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        choisir(t)
    }

    private func choisir(_ o: String) {
        choisi = o
        do {
            try Decisions.noter(question: activite.question, choix: o, ref: activite.questionRef, liste: "Sessions",
                                pour: nom, session: activite.sessionApp)
        } catch {
            erreur = L("Pas noté : \(error.localizedDescription)")
            choisi = nil
            return
        }
        Task { try? await Task.sleep(for: .milliseconds(400)); etat.relireDecisions() }
    }
}

/// Vos réponses (03/11, Sacha : « je choisis moi-même quand envoyer les réponses ») : une décision prise ici attend
/// son clic « Envoyer », puis Sacha voit qui l'a reçue, sans rien demander à personne.
struct DecisionsEnvoyees: View {
    @Environment(Etat.self) private var etat

    var body: some View {
        let attente = etat.decisionsEnvoyees.filter(\.enAttente)
        let parties = Array(etat.decisionsEnvoyees.filter { !$0.enAttente }.reversed())
        if !attente.isEmpty || !parties.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                if !attente.isEmpty {
                    HStack(spacing: 8) {
                        Text("Vos réponses, prêtes à partir").font(.petit.weight(.semibold)).foregroundStyle(Color.texte2)
                        Spacer()
                        Button { etat.envoyerReponses(attente.map(\.id)) } label: {
                            Label(attente.count == 1 ? L("Envoyer") : L("Tout envoyer (\(attente.count))"), systemImage: "paperplane.fill")
                        }
                        .buttonStyle(.borderedProminent).tint(.action).controlSize(.small)
                    }
                    ForEach(attente) { d in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "tray.full").foregroundStyle(Color.action)
                            Text(d.heure).font(.petit.monospacedDigit()).foregroundStyle(Color.texte3)
                            Text("\(d.question) → \(d.choix)").font(.petit).foregroundStyle(Color.texte).lineLimit(1)
                            Spacer(minLength: 8)
                            Text("pour \(d.pour)").font(.petit).foregroundStyle(Color.texte3).fixedSize()
                            Button("Envoyer") { etat.envoyerReponses([d.id]) }.controlSize(.small)
                            Button { etat.retirerReponse(d.id) } label: { Image(systemName: "xmark") }
                                .buttonStyle(.borderless).foregroundStyle(Color.texte3)
                                .help("Ne pas l'envoyer : \(d.pour) ne l'apprendra pas")
                        }
                        .help("\(d.question)\n→ \(d.choix)")
                    }
                }
                if !parties.isEmpty {
                    Text("Envoyées aujourd'hui").font(.petit.weight(.semibold)).foregroundStyle(Color.texte2)
                        .padding(.top, attente.isEmpty ? 0 : 6)
                    ForEach(Array(parties.prefix(4))) { d in
                        let l = d.transmise && d.remise == nil ? (texte: L("transmis à \(d.pour)"), fait: true)
                            : Facteur.libelle(d.remise, pour: d.pour, veille: etat.prochaineVeille)
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: l.fait ? "checkmark.circle.fill" : (d.remise?.etat == .retire ? "minus.circle" : "clock"))
                                .foregroundStyle(l.fait ? Color.vert : (d.remise?.etat == .retire ? Color.texte3 : Color.ambre))
                            Text(d.heure).font(.petit.monospacedDigit()).foregroundStyle(Color.texte3)
                            Text("\(d.question) → \(d.choix)").font(.petit).foregroundStyle(Color.texte).lineLimit(1)
                            Spacer(minLength: 8)
                            // Pas de .fixedSize() : un message d'échec très long (« pas remis à … : <raison> ») imposait
                            // sa largeur à tout l'écran, qui débordait sous la barre de navigation et hors de la fenêtre.
                            Text(l.texte).font(.petit).foregroundStyle(l.fait ? Color.vert : Color.ambre)
                                .lineLimit(2).multilineTextAlignment(.trailing)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: 380, alignment: .trailing).layoutPriority(1)
                        }
                        .help("\(d.question)\n→ \(d.choix)\n\(l.texte)")
                    }
                }
                EtatFacteur()
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
        }
    }
}

/// Comment partent les envois : le Facteur (quelques secondes) ou la veille (toutes les 15 min).
struct EtatFacteur: View {
    @Environment(Etat.self) private var etat

    var body: some View {
        HStack(spacing: 6) {
            if etat.facteurActif {
                Label("Le Facteur remet vos envois en quelques secondes", systemImage: "bolt.fill")
                    .font(.petit).foregroundStyle(Color.vert)
            } else {
                Label("Vos envois partent avec la veille, toutes les 15 min", systemImage: "clock")
                    .font(.petit).foregroundStyle(Color.texte3)
                Button("Démarrer le Facteur") { etat.demarrerFacteur() }
                    .buttonStyle(.link).font(.petit)
                    .help("Ouvre une session FACTEUR dans l'app Claude (modèle Haiku conseillé) : vos envois partent alors en quelques secondes")
            }
        }
        .padding(.top, 2)
    }
}

struct LigneRappel: View {
    @Environment(Agenda.self) private var agenda
    let rappel: Rappel
    @State private var coche = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                withAnimation(.snappy) { coche = true }
                Task { try? await Task.sleep(for: .milliseconds(250)); agenda.cocher(rappel) }
            } label: {
                Image(systemName: coche ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18)).foregroundStyle(coche ? Color.vert : Color.texte3)
            }
            .buttonStyle(.plain)
            .help("Cocher dans Rappels")
            VStack(alignment: .leading, spacing: 2) {
                Text(rappel.titre).font(.ligne).foregroundStyle(Color.texte)
                if let premiere = rappel.notes.split(separator: "\n").first, !premiere.hasPrefix("http") {
                    Text(premiere).font(.secondaire).foregroundStyle(Color.texte2).lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(echeance).font(.secondaire.monospacedDigit()).foregroundStyle(rappel.enRetard ? Color.rouge : Color.texte2)
                Text(rappel.liste).font(.petit).foregroundStyle(Color.texte3)
            }
        }
    }

    private var echeance: String {
        guard let d = rappel.echeance else { return "" }
        if rappel.enRetard { return L("En retard · \(Dates.court(Dates.jour.string(from: d)))") }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        let h = f.string(from: d)
        return h == "00:00" ? L("Aujourd'hui") : h
    }
}

struct LigneRendezVous: View {
    let rv: RendezVous
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(horaire).font(.secondaire.monospacedDigit()).foregroundStyle(Color.texte2).frame(width: 96, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(rv.titre).font(.ligne).foregroundStyle(Color.texte)
                Text([rv.calendrier, rv.lieu].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.petit).foregroundStyle(Color.texte3).lineLimit(1)
            }
            Spacer()
            if let url = rv.url {
                Button("Rejoindre") { NSWorkspace.shared.open(url) }.controlSize(.small)
            }
            BoutonPip(rv: rv)    // invisible si Pip n'est pas installé
        }
    }
    private var horaire: String {
        if rv.journee { return L("Toute la journée") }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return Loc.plage(f.string(from: rv.debut), f.string(from: rv.fin))
    }
}

struct LigneAEnvoyer: View {
    @Environment(Etat.self) private var etat
    let message: MessageAEnvoyer
    @State private var copie = false
    @State private var deplie = false
    @State private var feuilleMail = false
    @State private var feuillePasEnvoye = false
    @State private var erreurEnvoi: String?

    /// 05/11 (T7) : une condition pas encore cochée bloque tout ce qui fait partir le message.
    private var bloque: Bool { message.evenement.conditionEnAttente }
    /// 07/11 : déjà dans la file d'envoi (bouton « Envoyer les mails validés ») : il part tout seul, pas de second envoi d'ici.
    private var dansLaFile: ElementFile? { etat.fileEnvoi.first { $0.enCours && $0.evenementId == message.id } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button { etat.ouvrir(message.contact) } label: {
                    Text(message.contact.titre).font(.ligneForte).foregroundStyle(Color.texte)
                }.buttonStyle(.plain)
                if !message.contact.sousTitre.isEmpty {
                    Text(message.contact.sousTitre).font(.secondaire).foregroundStyle(Color.texte2)
                }
                Spacer()
                Pastille(texte: "\(Libelles.typeEvenement(message.evenement.type)) \(Libelles.canal(message.evenement.canal))", couleur: .texte2)
            }
            ParcoursContact(contact: message.contact, compact: true)
            if !message.evenement.objet.isEmpty {
                Text(message.evenement.canal == "mail" ? L("Objet : \(message.evenement.objet)") : L("À : \(message.evenement.objet)"))
                    .font(.secondaire.weight(.medium)).foregroundStyle(Color.texte2)
            }
            Text(message.evenement.texte).font(.ligne).foregroundStyle(Color.texte).textSelection(.enabled)
                .lineLimit(deplie ? nil : 3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onTapGesture { deplie.toggle() }
                .help(deplie ? "" : "Cliquer pour tout lire")
            ConditionEnvoi(evenement: message.evenement)
            if let f = dansLaFile {
                Text(f.etat == "envoi" ? L("Dans la file d'envoi : envoi en cours") : L("Dans la file d'envoi : part vers \(heureFile(f.prevuLe))"))
                    .font(.secondaire.weight(.medium)).foregroundStyle(Color.vert)
            }
            HStack(spacing: 8) {
                if message.evenement.canal == "mail" {
                    Button("Envoyer depuis Gmail…") { feuilleMail = true }.disabled(bloque || dansLaFile != nil)
                    BoutonOuvrirMail(evenement: message.evenement, contact: message.contact).disabled(bloque || dansLaFile != nil)
                } else if message.evenement.type != "invitation" {
                    if message.evenement.canal == "sms" {
                        BoutonOuvrirMessages(evenement: message.evenement, contact: message.contact).disabled(bloque)
                    }
                    Button(copie ? "Copié" : "Copier le texte") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(message.evenement.texte, forType: .string)
                        copie = true
                    }.disabled(bloque)
                }
                if let url = lienProfil {
                    Button(profilConnu ? "Ouvrir le profil" : "Chercher sur \(Libelles.canal(message.evenement.canal))") {
                        if message.evenement.canal == "linkedin" { Safari.ouvrir(url) } else { NSWorkspace.shared.open(url) }
                    }
                }
                if let site = message.contact.lienSite {
                    Button("Ouvrir le lien") { NSWorkspace.shared.open(site) }
                        .help(site.absoluteString)
                }
                Spacer()
                Button("Pas envoyé…") { feuillePasEnvoye = true }
                    .buttonStyle(.borderless).foregroundStyle(Color.texte2)
                    .help("Noter pourquoi il ne part pas : plus tard, texte à changer, plus d'actualité")
                Button(message.evenement.type == "invitation" ? "Invitation envoyée" : (message.evenement.canal == "mail" ? "Déjà envoyé" : "Envoyé")) {
                    erreurEnvoi = etat.marquer(message.id, statut: "envoye")
                }
                .disabled(bloque)
                .help(message.evenement.canal == "mail" ? "Vous l'avez envoyé d'ailleurs (Gmail) : il passe dans le fil" : "")
                    .help(bloque ? "Condition pas encore cochée : « Condition remplie… » d'abord" : "Vous l'avez envoyé : il passe dans le fil du contact")
            }
            .controlSize(.small)
            if let erreurEnvoi { Text(erreurEnvoi).font(.petit).foregroundStyle(Color.rouge) }
        }
        .sheet(isPresented: $feuilleMail) { EnvoiMail(message: message) }
        .sheet(isPresented: $feuillePasEnvoye) { FeuillePasEnvoye(cible: .message(message)) }
    }

    private var lienProfil: URL? {
        switch message.evenement.canal {
        case "linkedin": return message.contact.lienLinkedIn
        case "facebook": return message.contact.lienFacebook
        case "instagram": return Libelles.lienInstagram(message.evenement.objet)
        default: return nil
        }
    }

    private var profilConnu: Bool {
        switch message.evenement.canal {
        case "facebook": return !message.contact.facebook.isEmpty
        case "instagram": return true
        default: return !message.contact.linkedin.isEmpty
        }
    }
}

/// Ouvre Messages avec le texte (et le numéro s'il est dans la fiche). Rien ne part tout seul.
struct BoutonOuvrirMessages: View {
    let evenement: Evenement
    let contact: Contact
    var body: some View {
        Button("Ouvrir dans Messages") { Brouillon.messages(telephone: contact.telephone, texte: evenement.texte) }
            .help(contact.telephone.isEmpty
                  ? "Pas de numéro dans la fiche : Messages s'ouvre avec le texte, ajoutez le destinataire"
                  : "Brouillon prêt dans Messages pour \(Brouillon.numero(contact.telephone)) : relisez puis envoyez vous-même")
    }
}

/// Ouvre un brouillon dans Mail (Apple) avec le destinataire, l'objet et le texte, expéditeur = Gmail perso forcé
/// (jamais kryva.fr, même si c'est le compte par défaut de Mail). Sans compte Gmail dans Mail : message franc, rien ne s'ouvre.
/// Rien ne part tout seul.
/// Une réponse (reponse_a posé, ou objet en « Re: » avec un mail reçu de la personne) s'ouvre en « Répondre »
/// sur le mail d'origine : elle part dans le même fil. Mail d'origine introuvable : nouveau mail, et on le dit.
struct BoutonOuvrirMail: View {
    let evenement: Evenement
    let contact: Contact
    @State private var erreur: String?
    var body: some View {
        Button("Ouvrir dans Mail") {
            Task {
                do { try await ouvrir(); }
                catch { erreur = error.localizedDescription }
            }
        }
        .help(contact.email.isEmpty
              ? "Pas d'e-mail dans la fiche : Mail s'ouvre avec l'objet et le texte, ajoutez le destinataire"
              : "Brouillon prêt dans Mail (depuis votre Gmail) pour \(contact.email) : relisez puis envoyez vous-même")
        .alert("Ouvrir dans Mail", isPresented: Binding(get: { erreur != nil }, set: { if !$0 { erreur = nil } })) {
            Button("OK") { erreur = nil }
        } message: { Text(erreur ?? "") }
    }

    private func ouvrir() async throws {
        erreur = nil
        var id = evenement.reponseA
        if id.isEmpty, Mail.estReponse(evenement.objet) {
            id = (try? await Mail.dernierRecu(de: contact.email, objet: evenement.objet)) ?? ""
        }
        if !id.isEmpty {
            do { try await Mail.repondre(a: id, texte: evenement.texte); return }
            catch Mail.ErreurMail.echec(let m) where m.contains("4401") {
                try await Mail.brouillon(a: contact.email, objet: evenement.objet, texte: evenement.texte)
                erreur = L("Le mail d'origine n'est pas dans Mail : ce brouillon est un nouveau mail, hors du fil. « Envoyer depuis Gmail » le garde dans le fil.")
                return
            }
        }
        try await Mail.brouillon(a: contact.email, objet: evenement.objet, texte: evenement.texte)
    }
}

struct LigneContactDu: View {
    let contact: Contact
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(contact.titre).font(.ligneForte).foregroundStyle(Color.texte)
                    if !contact.sousTitre.isEmpty { Text(contact.sousTitre).font(.secondaire).foregroundStyle(Color.texte2) }
                }
                Text(contact.prochaineAction.isEmpty ? L("Prochaine action à préciser") : contact.prochaineAction)
                    .font(.secondaire).foregroundStyle(Color.texte2).lineLimit(2)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(contact.prochaineDate < Dates.aujourdhui() ? L("En retard · \(Dates.court(contact.prochaineDate))") : L("Aujourd'hui"))
                    .font(.secondaire).foregroundStyle(contact.prochaineDate < Dates.aujourdhui() ? Color.rouge : Color.texte2)
                Pastille(texte: Libelles.etape(contact.etape), couleur: Couleurs.etape(contact.etape))
            }
        }
        .contentShape(Rectangle())
    }
}

struct LigneMail: View {
    let message: MessageMail
    let contact: Contact?
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle().fill(message.lu ? Color.clear : Color.texte2).frame(width: 7, height: 7).padding(.top, 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(contact?.titre ?? message.correspondant).font(message.lu ? .ligne : .ligneForte).foregroundStyle(Color.texte)
                Text(message.objet).font(.secondaire).foregroundStyle(Color.texte2).lineLimit(1)
            }
            Spacer()
            Text(message.date.formatted(.dateTime.day().month(.abbreviated).hour().minute().locale(Loc.locale)))
                .font(.petit).foregroundStyle(Color.texte3)
        }
        .contentShape(Rectangle())
    }
}

struct LigneInscrit: View {
    @Environment(Etat.self) private var etat
    let inscrit: Inscrit

    private var suivi: Contact? { etat.contacts.first { $0.orgId == inscrit.id } }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(inscrit.nom.isEmpty ? inscrit.entreprise : inscrit.nom).font(.ligneForte).foregroundStyle(Color.texte)
                Text([inscrit.entreprise, inscrit.telephone.isEmpty ? "" : L("tél.")].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.secondaire).foregroundStyle(Color.texte2).lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(L("\(Dates.court(Dates.jour.string(from: inscrit.inscritLe))) · \(inscrit.devis) devis"))
                    .font(.secondaire.monospacedDigit()).foregroundStyle(Color.texte2)
                if let c = suivi {
                    Button("Voir la fiche") { etat.ouvrir(c) }.buttonStyle(.link).font(.petit)
                } else {
                    Button("Suivre") { suivre() }.controlSize(.small)
                        .help("Ajoute cet inscrit à vos contacts KRYVA")
                }
            }
        }
    }

    private func suivre() {
        guard let stock = etat.stock else { return }
        let c = try? stock.enregistrer([
            "espace": "kryva", "type": "artisan", "nom": inscrit.nom, "entreprise": inscrit.entreprise,
            "email": inscrit.email, "telephone": inscrit.telephone, "org_id": inscrit.id,
            "source": "kryva-org", "source_ref": inscrit.id, "etape": "a_contacter",
            "notes": "Inscrit sur KRYVA le \(Dates.court(Dates.jour.string(from: inscrit.inscritLe))), \(inscrit.devis) devis à ce jour.",
        ])
        etat.charger()
        if let c { etat.ouvrir(c) }
    }
}
