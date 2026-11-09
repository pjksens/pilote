// Prospects (03/11, Sacha) : une colonne par étape, une carte par personne. La couleur de la carte dit
// depuis combien de jours on n'a rien fait (vert, ambre, rouge). Un clic ouvre la fiche ; glisser une carte change son étape.
// Deux tableaux séparés : les clients (artisans, clients freelance) et les partenaires et le réseau
// (apporteurs, associés possibles, comptables, négoces, syndicats). Une carte client KRYVA dit son statut : inscrit, essai, payant.
import SwiftUI

struct ProspectsVue: View {
    @Environment(Etat.self) private var etat
    @AppStorage("prospects.espace") private var espace = "kryva"
    @AppStorage("prospects.groupe") private var groupe = "clients"
    @State private var recherche = ""
    @State private var deplies: Set<String> = []

    /// Les colonnes du tableau ; « Perdu » et « Ne plus contacter » restent hors du tableau, comptés en haut.
    private var colonnes: [(String, String)] { Libelles.etapes.filter { $0.0 != "perdu" } }
    private let parColonne = 8

    /// Les types qui sont des clients ; tout le reste (partenaire, comptable, négoce, syndicat, autre) est le réseau.
    static let typesClients: Set<String> = ["artisan", "client"]
    static func estClient(_ c: Contact) -> Bool { typesClients.contains(c.type) }

    private var deLEspace: [Contact] { etat.contacts.filter { $0.espace == espace } }

    private var duTableau: [Contact] {
        let r = recherche.trimmingCharacters(in: .whitespaces).lowercased()
        return deLEspace.filter { c in
            Self.estClient(c) == (groupe == "clients")
                && (r.isEmpty || [c.nom, c.entreprise, c.ville, c.notes].contains { $0.lowercased().contains(r) })
        }
    }

    var body: some View {
        let contacts = duTableau
        let actifs = contacts.filter { !$0.nePlusContacter && $0.etape != "perdu" }
        let ficheOuverte = etat.contact(etat.selection)
        ZStack(alignment: .topTrailing) {
            ScrollView([.horizontal, .vertical]) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(colonnes, id: \.0) { e in
                        colonne(e, actifs.filter { $0.etape == e.0 }.sorted(by: Self.ordre))
                    }
                }
                .padding(20)
            }
            .defaultScrollAnchor(.topLeading)   // colonnes en haut à gauche, pas centrées dans la fenêtre
            .padding(.trailing, ficheOuverte == nil ? 0 : 440)
            if let c = ficheOuverte {
                HStack(spacing: 0) {
                    Rectangle().fill(Color.separateur).frame(width: 0.5)
                    FicheVue(contact: c).id(c.id).repere("fiche")
                }
                .frame(width: 440)
                .frame(maxHeight: .infinity)
                .transition(.move(edge: .trailing))
            }
        }
        .animation(.snappy(duration: 0.25), value: etat.selection)
        // 09/11 : recherche et « + » dans la barre de la page, plus dans la barre d'outils de la fenêtre : ouvrir la page
        // passe de 232 à 195 ms (médiane, Release, copie de la base ; mesures/ecran-unique.md).
        .safeAreaInset(edge: .top, spacing: 0) { barre(contacts: contacts, actifs: actifs.count) }
        .task(id: espace) { if espace == Comptes.espace { await etat.chargerStatutsComptes() } }
    }

    /// D'abord ce qui est en retard (la date la plus ancienne en premier), puis ce qui a une date, priorité haute d'abord.
    static func ordre(_ a: Contact, _ b: Contact) -> Bool {
        let da = a.prochaineDate.isEmpty ? "9999" : a.prochaineDate
        let db = b.prochaineDate.isEmpty ? "9999" : b.prochaineDate
        return (da, a.priorite, a.titre) < (db, b.priorite, b.titre)
    }

    private func barre(contacts: [Contact], actifs: Int) -> some View {
        let perdus = contacts.filter { $0.etape == "perdu" && !$0.nePlusContacter }.count
        let stop = contacts.filter(\.nePlusContacter).count
        let retard = contacts.filter { !$0.nePlusContacter && !$0.prochaineDate.isEmpty && $0.prochaineDate < Dates.aujourdhui()
            && $0.etape != "perdu" }.count
        let clients = deLEspace.filter { Self.estClient($0) && !$0.nePlusContacter && $0.etape != "perdu" }.count
        let reseau = deLEspace.filter { !Self.estClient($0) && !$0.nePlusContacter && $0.etape != "perdu" }.count
        return HStack(spacing: 14) {
            Picker("Espace", selection: $espace) {
                ForEach(Libelles.espaces, id: \.0) { Text($0.1).tag($0.0) }
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 220)
            Picker("Tableau", selection: $groupe) {
                Text("Clients · \(clients)").tag("clients")
                Text("Partenaires et réseau · \(reseau)").tag("partenaires")
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 300)
            .help("Clients : artisans et clients. Partenaires et réseau : apporteurs, associés possibles, comptables, négoces, syndicats.")
            if espace == Comptes.espace && groupe == "clients" { statutsKryva(contacts) }
            if retard > 0 {
                Label("\(retard) en retard", systemImage: "clock.badge.exclamationmark").font(.secondaire).foregroundStyle(Color.rouge)
            }
            Spacer()
            HStack(spacing: 10) {
                pointLegende(.vert, "≤ 3 j")
                pointLegende(.ambre, "4-10 j")
                pointLegende(.rouge, "> 10 j")
            }
            .fixedSize()
            .help("Couleur de la carte : jours depuis le dernier échange.")
            Text("\(perdus + stop) hors tableau").font(.petit).foregroundStyle(Color.texte3).fixedSize()
                .help("\(perdus) perdus, \(stop) à ne plus contacter. « Tous les contacts », dans Plus, les montre.")
            TextField("Chercher", text: $recherche).textFieldStyle(.roundedBorder).frame(width: 170)
                .help("Nom, entreprise, ville, notes")
            let nouveau = groupe == "clients" ? "Nouveau client" : "Nouveau partenaire"
            Button {
                etat.nouveauContact(espace: espace, type: groupe == "clients" ? (espace == "kryva" ? "artisan" : "client") : "partenaire")
            } label: { Image(systemName: "plus") }
                .buttonStyle(.borderedProminent).tint(.action)
                .help(nouveau).accessibilityLabel(nouveau)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(Color.surface)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.separateur).frame(height: 0.5) }
    }

    /// « 2 payants · 1 en essai · 165 inscrits » : les clients du tableau qui ont un compte KRYVA.
    private func statutsKryva(_ contacts: [Contact]) -> some View {
        let statuts = contacts.compactMap { $0.orgId.isEmpty ? nil : (etat.statutsComptes[$0.orgId] ?? .inscrit) }
        let n = { (s: StatutCompte) in statuts.filter { $0 == s }.count }
        let morceaux = [(StatutCompte.payant, "payant"), (.essai, "en essai"), (.essaiResilie, "essai résilié"), (.abonne, "abonné app"),
                        (.souci, "en souci"), (.aVerifier, "à vérifier"), (.inscrit, "inscrit")]
            .compactMap { s, mot in n(s) > 0 ? "\(n(s)) \(mot)\(n(s) > 1 && (s == .payant || s == .inscrit) ? "s" : "")" : nil }
        return Text(morceaux.joined(separator: " · ")).font(.secondaire).foregroundStyle(Color.texte2).lineLimit(1)
            .help(etat.erreurStatutsComptes ?? "Statuts des comptes, relus toutes les 5 minutes (module comptes et Stripe, lecture seule).")
    }

    private func pointLegende(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(c).frame(width: 8, height: 8)
            Text(t).font(.petit).foregroundStyle(Color.texte2)
        }
    }

    private func colonne(_ e: (String, String), _ cartes: [Contact]) -> some View {
        let deplie = deplies.contains(e.0)
        let montrees = deplie ? cartes : Array(cartes.prefix(parColonne))
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(e.1).font(.ligneForte).foregroundStyle(Color.texte)
                Spacer()
                Text("\(cartes.count)").font(.ligneForte.monospacedDigit()).foregroundStyle(Couleurs.etape(e.0))
            }
            Capsule().fill(Couleurs.etape(e.0)).frame(height: 3)
            if cartes.isEmpty {
                Text("Personne").font(.secondaire).foregroundStyle(Color.texte3).padding(.vertical, 8)
            }
            ForEach(montrees) { c in
                CarteProspect(contact: c, choisie: etat.selection == c.id)
                    .repere("prospect:\(c.nom)")
                    .onTapGesture { etat.selection = c.id }
                    .draggable(c.id)
            }
            if cartes.count > parColonne {
                Button(deplie ? "Replier" : "+ \(cartes.count - parColonne) autre\(cartes.count - parColonne > 1 ? "s" : "")") {
                    if deplie { deplies.remove(e.0) } else { deplies.insert(e.0) }
                }
                .buttonStyle(.link).font(.secondaire)
            }
        }
        .padding(12)
        .frame(width: 236, alignment: .topLeading)
        .frame(minHeight: 420, alignment: .top)
        .background(Color.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .dropDestination(for: String.self) { ids, _ in
            guard let id = ids.first, var c = etat.contact(id), c.etape != e.0 else { return false }
            c.etape = e.0
            etat.enregistrer(c)
            return true
        }
    }
}

/// Une carte de prospect : qui, ce qu'il faut faire, et une bande de couleur pour « depuis combien de jours ».
struct CarteProspect: View {
    @Environment(Etat.self) private var etat
    let contact: Contact
    var choisie = false

    /// Le statut du compte (module comptes, seulement pour un client inscrit).
    private var statutKryva: StatutCompte? {
        guard contact.espace == Comptes.espace, ProspectsVue.estClient(contact), !contact.orgId.isEmpty else { return nil }
        return etat.statutsComptes[contact.orgId] ?? .inscrit
    }

    static func couleur(_ s: StatutCompte) -> Color {
        switch s {
        case .payant: .vert
        case .essai, .abonne: .action
        case .essaiResilie: .ambre
        case .souci: .rouge
        case .inscrit, .aVerifier: .texte2
        }
    }

    var body: some View {
        let echange = etat.echanges[contact.id]
        let couleur = Couleurs.depuis(echange?.jours())
        let retard = !contact.prochaineDate.isEmpty && contact.prochaineDate < Dates.aujourdhui()
        let aujourdhui = contact.prochaineDate == Dates.aujourdhui()
        VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(contact.titre).font(.secondaire.weight(.semibold)).foregroundStyle(Color.texte).lineLimit(1)
                    Spacer(minLength: 0)
                    if let s = statutKryva { Pastille(texte: s.libelle, couleur: Self.couleur(s)).fixedSize().help(s.detail) }
                }
                if !contact.sousTitre.isEmpty {
                    Text(contact.sousTitre).font(.petit).foregroundStyle(Color.texte2).lineLimit(1)
                }
                if !contact.prochaineAction.isEmpty {
                    Text(contact.prochaineAction).font(.petit).foregroundStyle(Color.texte).lineLimit(2)
                }
                HStack(spacing: 4) {
                    if retard || aujourdhui {
                        Image(systemName: "clock").font(.system(size: 10))
                        Text(retard ? Dates.court(contact.prochaineDate) : "Aujourd'hui")
                    } else if !contact.prochaineDate.isEmpty {
                        Text(Dates.court(contact.prochaineDate))
                    }
                    Spacer(minLength: 0)
                    if let j = echange?.jours() { Text(j == 0 ? "auj." : "\(j) j") }
                }
                .font(.petit.monospacedDigit())
                .foregroundStyle(retard ? Color.rouge : (aujourdhui ? Color.ambre : Color.texte3))
        }
        .padding(.leading, 14).padding(.trailing, 10).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        // La bande de couleur suit la hauteur de la carte (un Rectangle dans la pile l'étirait).
        .overlay(alignment: .leading) { Rectangle().fill(couleur).frame(width: 4) }
        .background(Color.eleve, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(choisie ? Color.action : Color.separateur.opacity(0.6), lineWidth: choisie ? 1.5 : 0.5))
        .contentShape(Rectangle())
        .help(echange?.resume ?? "Aucun échange noté")
    }
}
