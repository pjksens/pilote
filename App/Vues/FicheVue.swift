// La fiche d'un contact : tout se modifie sur place et s'enregistre tout seul. Le fil en dessous.
import SwiftUI

struct FicheVue: View {
    @Environment(Etat.self) private var etat
    @State private var brouillon: Contact
    @State private var fil: [Evenement] = []
    @State private var mails: [MessageMail] = []
    @State private var etatMails: Chargement = .attente
    @State private var noteTexte = ""
    @State private var noteCanal = "appel"
    @State private var noteType = "note"
    @State private var erreurMail: String?

    init(contact: Contact) { _brouillon = State(initialValue: contact) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                identite
                ScrollView(.horizontal, showsIndicators: false) {
                    ParcoursContact(contact: brouillon).frame(minWidth: 440).padding(.vertical, 2)
                }
                BarreEtapes(etape: $brouillon.etape)
                prochaineAction
                filSection
                suivi
                coordonnees
                notes
                mailsSection
            }
            .padding(20)
        }
        .background(Color.fond)
        .onAppear { fil = etat.evenements(brouillon.id) }
        .onChange(of: brouillon) { _, nouveau in
            guard let enBase = etat.contact(nouveau.id), !Self.memeContenu(enBase, nouveau) else { return }
            etat.enregistrer(nouveau)
        }
        .onChange(of: etat.revision) {
            fil = etat.evenements(brouillon.id)
            // Une écriture venue d'ailleurs (Claude, l'outil pilote) : on la reprend.
            if let enBase = etat.contact(brouillon.id), !Self.memeContenu(enBase, brouillon) { brouillon = enBase }
        }
    }

    static func memeContenu(_ a: Contact, _ b: Contact) -> Bool {
        NSDictionary(dictionary: Stockage.champs(a)).isEqual(to: Stockage.champs(b))
    }

    // MARK: Identité

    private var identite: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                TextField("Nom", text: $brouillon.nom, prompt: Text("Nom de la personne"), axis: .vertical)
                    .font(.system(size: 22, weight: .bold)).textFieldStyle(.plain).lineLimit(1...2)
                Button { etat.selection = nil } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless).foregroundStyle(Color.texte2).help("Fermer la fiche")
                    .keyboardShortcut(.cancelAction)
            }
            TextField("Entreprise", text: $brouillon.entreprise, prompt: Text("Entreprise"), axis: .vertical)
                .font(.ligne).textFieldStyle(.plain).foregroundStyle(Color.texte2).lineLimit(1...2)
            HStack(spacing: 8) {
                menu("Espace", $brouillon.espace, Libelles.espaces)
                menu("Type", $brouillon.type, Libelles.types)
                Spacer()
                Menu {
                    Button("Supprimer le contact", role: .destructive) { etat.supprimer(brouillon.id) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton).fixedSize().help("Plus d'actions")
            }
            actions
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            if !brouillon.email.isEmpty {
                Button { Task { await ecrire() } } label: { Label("Écrire un mail", systemImage: "envelope") }
            }
            if !brouillon.telephone.isEmpty, let url = URL(string: "tel:\(brouillon.telephone.filter { $0.isNumber || $0 == "+" })") {
                Button { NSWorkspace.shared.open(url) } label: { Label("Appeler", systemImage: "phone") }
            }
            if let url = brouillon.lienLinkedIn {
                Button(brouillon.linkedin.isEmpty ? L("Chercher sur LinkedIn") : "LinkedIn") { Safari.ouvrir(url) }
            }
            if !brouillon.facebook.isEmpty, let url = brouillon.lienFacebook {
                Button("Facebook") { NSWorkspace.shared.open(url) }
            }
        }
        .controlSize(.small)
        .padding(.top, 4)
        .overlay(alignment: .bottomLeading) {
            if let erreurMail { Text(erreurMail).font(.petit).foregroundStyle(Color.rouge).offset(y: 18) }
        }
    }

    // MARK: Prochaine action, en grand

    private var prochaineAction: some View {
        let date = brouillon.prochaineDate
        let retard = !date.isEmpty && date < Dates.aujourdhui()
        let couleur: Color = brouillon.nePlusContacter ? .texte3 : (retard ? .rouge : (date == Dates.aujourdhui() ? .ambre : .texte2))
        return VStack(alignment: .leading, spacing: 6) {
            Text(brouillon.nePlusContacter ? L("NE PLUS CONTACTER") : L("PROCHAINE ACTION"))
                .font(.petit.weight(.semibold)).tracking(0.6).foregroundStyle(couleur)
            Text(brouillon.prochaineAction.isEmpty ? L("Rien de prévu. Écrivez-la dans Suivi, plus bas.") : brouillon.prochaineAction)
                .font(.ligneForte)
                .foregroundStyle(brouillon.prochaineAction.isEmpty ? Color.texte3 : Color.texte)
                .lineLimit(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(brouillon.prochaineAction)
            HStack {
                Text(date.isEmpty ? L("Sans date") : (retard ? L("En retard, prévu le \(Dates.court(date))") : L("Pour le \(Dates.court(date))")))
                    .font(.secondaire).foregroundStyle(couleur)
                Spacer()
                if !brouillon.prochaineAction.isEmpty || !date.isEmpty {
                    Button("C'est fait") { etat.actionFaite(brouillon) }.controlSize(.small)
                        .help("La prochaine action passe dans le fil et la date se libère")
                }
            }
            if let e = etat.echanges[brouillon.id] {
                Text("Dernier échange : \(e.resumeAffiche)").font(.petit).foregroundStyle(Color.texte3)
            }
        }
        .padding(14)
        .background(couleur.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(couleur.opacity(0.3), lineWidth: 1))
    }

    // MARK: Suivi

    private var suivi: some View {
        Groupe(titre: "Suivi") {
            Champ("Étape") { menu("Étape", $brouillon.etape, Libelles.etapes) }
            Champ("Prochaine action") {
                TextField("", text: $brouillon.prochaineAction, prompt: Text("Ex. rappeler après sa visite de chantier"), axis: .vertical)
                    .textFieldStyle(.plain).lineLimit(1...3)
            }
            Champ("Pour le") {
                HStack(spacing: 6) {
                    if let d = Dates.jour.date(from: brouillon.prochaineDate) {
                        DatePicker("", selection: Binding(get: { d }, set: { brouillon.prochaineDate = Dates.jour.string(from: $0) }),
                                   displayedComponents: .date)
                            .labelsHidden().datePickerStyle(.field).environment(\.locale, Loc.locale)
                    }
                    Menu(brouillon.prochaineDate.isEmpty ? L("Choisir une date") : L("Changer")) {
                        Button("Aujourd'hui") { brouillon.prochaineDate = Dates.aujourdhui() }
                        Button("Demain") { brouillon.prochaineDate = Dates.dans(1) }
                        Button("Dans 3 jours") { brouillon.prochaineDate = Dates.dans(3) }
                        Button("Dans 5 jours") { brouillon.prochaineDate = Dates.dans(5) }
                        Button("Dans 1 semaine") { brouillon.prochaineDate = Dates.dans(7) }
                        if !brouillon.prochaineDate.isEmpty {
                            Divider()
                            Button("Retirer la date") { brouillon.prochaineDate = "" }
                        }
                    }
                    .fixedSize()
                }
                .controlSize(.small)
            }
            Champ("Priorité") {
                Picker("", selection: $brouillon.priorite) {
                    Text("Haute").tag(1); Text("Normale").tag(2); Text("Basse").tag(3)
                }
                .labelsHidden().fixedSize()
            }
            Champ("Ne plus contacter", dernier: true) {
                Toggle("", isOn: $brouillon.nePlusContacter).labelsHidden().toggleStyle(.switch).controlSize(.small)
            }
        }
    }

    // MARK: Coordonnées

    private var coordonnees: some View {
        Groupe(titre: "Coordonnées") {
            Champ("Téléphone") { texte($brouillon.telephone, "Ajouter") }
            Champ("E-mail") { texte($brouillon.email, "Ajouter") }
            Champ("LinkedIn") { texte($brouillon.linkedin, "Lien du profil") }
            Champ("Facebook") { texte($brouillon.facebook, "Lien du profil") }
            Champ("Site") {
                HStack(spacing: 8) {
                    texte($brouillon.site, "Ajouter")
                    if let url = brouillon.lienSite {
                        Button("Ouvrir le lien") { NSWorkspace.shared.open(url) }.controlSize(.small).help(url.absoluteString)
                    }
                }
            }
            Champ("Ville") { texte($brouillon.ville, "Ajouter") }
            Champ("Département", dernier: true) { texte($brouillon.departement, "Ajouter") }
        }
    }

    private var notes: some View {
        Groupe(titre: "Notes") {
            TextField("", text: $brouillon.notes, prompt: Text("Contexte, ce qu'il a dit, ce qui compte pour lui"), axis: .vertical)
                .textFieldStyle(.plain).lineLimit(3...12).font(.ligne)
                .padding(.horizontal, 14).padding(.vertical, 10)
        }
    }

    // MARK: Fil

    private var filSection: some View {
        Groupe(titre: "Fil") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    menu("Type", $noteType, Libelles.typesEvenement)
                    menu("Canal", $noteCanal, Libelles.canaux)
                    Spacer()
                }
                TextField("", text: $noteTexte, prompt: Text("Ce qui s'est passé (appel, visite, réponse…)"), axis: .vertical)
                    .textFieldStyle(.roundedBorder).lineLimit(1...6)
                HStack {
                    Spacer()
                    Button("Ajouter au fil") {
                        etat.ajouterNote(brouillon.id, canal: noteCanal, type: noteType, texte: noteTexte)
                        noteTexte = ""
                    }
                    .disabled(noteTexte.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            if fil.isEmpty {
                EtatVide(texte: L("Rien encore avec ce contact."))
            } else {
                ForEach(Array(fil.enumerated()), id: \.element.id) { i, e in
                    LigneEvenement(evenement: e, contact: brouillon).padding(.horizontal, 14).padding(.vertical, 8)
                    if i < fil.count - 1 { Rectangle().fill(Color.separateur).frame(height: 0.5).padding(.leading, 14) }
                }
            }
        }
    }

    // MARK: Mails

    private var mailsSection: some View {
        Groupe(titre: "Mails") {
            if brouillon.email.isEmpty {
                EtatVide(texte: L("Ajoutez son e-mail pour retrouver vos échanges dans Mail."))
            } else {
                switch etatMails {
                case .attente:
                    Button("Chercher nos échanges dans Mail (4 derniers mois)") { Task { await chargerMails() } }
                        .buttonStyle(.link).padding(14)
                case .enCours:
                    EtatChargement(texte: L("Recherche dans Mail…"))
                case .erreur(let e):
                    EtatErreur(texte: e) { Task { await chargerMails() } }
                case .pret:
                    if mails.isEmpty {
                        EtatVide(texte: L("Aucun échange avec \(brouillon.email) ces 4 derniers mois."))
                    } else {
                        ForEach(mails) { m in
                            Button { Mail.ouvrir(m) } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: m.envoye ? "arrow.up.right" : "arrow.down.left")
                                        .font(.petit).foregroundStyle(Color.texte3).frame(width: 14).padding(.top, 3)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(m.objet.isEmpty ? L("Sans objet") : m.objet).font(.secondaire).foregroundStyle(Color.texte).lineLimit(1)
                                        Text(m.envoye ? L("Vous") : m.correspondant).font(.petit).foregroundStyle(Color.texte3)
                                    }
                                    Spacer()
                                    Text(Dates.court(Dates.jour.string(from: m.date))).font(.petit).foregroundStyle(Color.texte3)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain).padding(.horizontal, 14).padding(.vertical, 6)
                        }
                    }
                }
            }
        }
    }

    private func chargerMails() async {
        etatMails = .enCours
        do {
            mails = try await Mail.echanges(adresse: brouillon.email.lowercased())
            etatMails = .pret
        } catch {
            etatMails = .erreur(error.localizedDescription)
        }
    }

    private func ecrire() async {
        do { try await Mail.brouillon(a: brouillon.email) ; erreurMail = nil } catch { erreurMail = error.localizedDescription }
    }

    // MARK: Petits morceaux

    private func menu(_ titre: LocalizedStringKey, _ valeur: Binding<String>, _ options: [(String, String)]) -> some View {
        Picker(titre, selection: valeur) {
            ForEach(options, id: \.0) { Text($0.1).tag($0.0) }
        }
        .labelsHidden().fixedSize()
    }

    private func texte(_ valeur: Binding<String>, _ exemple: LocalizedStringKey) -> some View {
        TextField("", text: valeur, prompt: Text(exemple)).textFieldStyle(.plain)
    }
}

/// Un groupe de la fiche : titre au-dessus, surface arrondie.
struct Groupe<Contenu: View>: View {
    let titre: LocalizedStringKey
    @ViewBuilder var contenu: Contenu
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(titre).font(.secondaire.weight(.semibold)).foregroundStyle(Color.texte2).padding(.leading, 4)
            VStack(alignment: .leading, spacing: 0) { contenu }
                .background(Color.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

/// Une ligne libellé / valeur d'un groupe.
struct Champ<Valeur: View>: View {
    let libelle: LocalizedStringKey
    var dernier = false
    @ViewBuilder var valeur: Valeur
    init(_ libelle: LocalizedStringKey, dernier: Bool = false, @ViewBuilder valeur: () -> Valeur) {
        self.libelle = libelle; self.dernier = dernier; self.valeur = valeur()
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(libelle).font(.secondaire).foregroundStyle(Color.texte2).frame(width: 108, alignment: .leading)
                valeur.font(.ligne).frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
            if !dernier { Rectangle().fill(Color.separateur).frame(height: 0.5).padding(.leading, 14) }
        }
    }
}

struct LigneEvenement: View {
    @Environment(Etat.self) private var etat
    let evenement: Evenement
    var contact: Contact? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: symbole).font(.petit).foregroundStyle(Color.texte3)
                Text(entete).font(.petit.weight(.medium)).foregroundStyle(Color.texte2)
                if evenement.statut == "prepare" { Pastille(texte: L("À envoyer"), couleur: .ambre) }
                if evenement.statut == "annule" { Pastille(texte: L("Pas envoyé"), couleur: .texte3) }
                if evenement.statut == "echec" { Pastille(texte: L("Échec"), couleur: .rouge) }
                Spacer()
                Text(Dates.court(evenement.le)).font(.petit).foregroundStyle(Color.texte3)
            }
            if !evenement.texte.isEmpty {
                Text(evenement.texte).font(.secondaire).foregroundStyle(Color.texte).textSelection(.enabled)
            }
            ConditionEnvoi(evenement: evenement)
            if evenement.statut == "prepare", let contact {
                if evenement.canal == "sms" {
                    BoutonOuvrirMessages(evenement: evenement, contact: contact).controlSize(.small).disabled(evenement.conditionEnAttente)
                } else if evenement.canal == "mail" {
                    BoutonOuvrirMail(evenement: evenement, contact: contact).controlSize(.small).disabled(evenement.conditionEnAttente)
                }
            }
        }
        .contextMenu {
            Button("Supprimer du fil", role: .destructive) { etat.supprimerEvenement(evenement.id) }
        }
    }

    private var entete: String {
        let qui = evenement.statut == "prepare" || evenement.statut == "annule" ? L("Préparé")
            : (evenement.sens == "entrant" ? L("Reçu") : (evenement.sens == "sortant" ? L("Envoyé") : L("Note")))
        return "\(Libelles.typeEvenement(evenement.type)) · \(Libelles.canal(evenement.canal)) · \(qui) · \(evenement.par)"
    }

    private var symbole: String {
        switch evenement.sens {
        case "entrant": return "arrow.down.left"
        case "sortant": return "arrow.up.right"
        default: return "text.alignleft"
        }
    }
}

/// Les étapes d'un prospect en une barre : celles passées sont pleines, l'étape en cours est marquée. Un clic la change.
struct BarreEtapes: View {
    @Binding var etape: String
    private var etapes: [(String, String)] { Libelles.etapes.filter { $0.0 != "perdu" } }

    var body: some View {
        let rang = Libelles.rang(etape)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                ForEach(Array(etapes.enumerated()), id: \.element.0) { i, e in
                    Button { etape = e.0 } label: {
                        VStack(spacing: 4) {
                            Capsule().fill(etape != "perdu" && i <= rang ? Couleurs.etape(etape).opacity(i == rang ? 1 : 0.5) : Color.separateur)
                                .frame(height: 6)
                            Text(e.1).font(.petit.weight(i == rang && etape != "perdu" ? .semibold : .regular))
                                .foregroundStyle(i == rang && etape != "perdu" ? Color.texte : Color.texte3)
                                .lineLimit(1).minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Passer à « \(e.1) »")
                }
            }
            if etape == "perdu" {
                Text("Perdu").font(.petit.weight(.semibold)).foregroundStyle(Color.texte3)
            } else {
                Button("Marquer perdu") { etape = "perdu" }.buttonStyle(.link).font(.petit).foregroundStyle(Color.texte3)
            }
        }
    }
}
