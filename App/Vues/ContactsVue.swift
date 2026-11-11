// Contacts : un seul carnet (KRYVA, freelance, autre) en tableau, la fiche s'ouvre en panneau latéral.
import SwiftUI

struct ContactsVue: View {
    @Environment(Etat.self) private var etat
    @State private var recherche = ""
    @AppStorage("contacts.espace") private var espace = "tous"
    @AppStorage("contacts.etape") private var etape = "en_cours"
    @AppStorage("contacts.type") private var type = "tous"
    @State private var tri = [KeyPathComparator(\Contact.importance), KeyPathComparator(\Contact.titre)]

    private var filtres: [Contact] {
        let r = recherche.trimmingCharacters(in: .whitespaces).lowercased()
        return etat.contacts.filter { c in
            (espace == "tous" || c.espace == espace)
                && (type == "tous" || c.type == type)
                && (etape == "toutes" || (etape == "en_cours" ? !["gagne", "perdu"].contains(c.etape) && !c.nePlusContacter : c.etape == etape))
                && (r.isEmpty || [c.nom, c.entreprise, c.ville, c.email, c.telephone, c.notes].contains { $0.lowercased().contains(r) })
        }
        .sorted(using: tri)
    }

    var body: some View {
        @Bindable var etat = etat
        let liste = filtres
        let ficheOuverte = etat.contact(etat.selection)
        ZStack(alignment: .topTrailing) {
        VStack(spacing: 0) {
            if etat.contacts.isEmpty {
                ContentUnavailableView("Aucun contact", systemImage: "person.2",
                                       description: Text("Ajoutez un contact, ou laissez la routine du matin les importer."))
            } else if liste.isEmpty {
                ContentUnavailableView("Aucun contact pour ces filtres", systemImage: "line.3.horizontal.decrease.circle")
            } else {
                Table(liste, selection: $etat.selection, sortOrder: $tri) {
                    TableColumn("Nom", value: \.titre) { c in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(c.titre).font(.ligneForte).foregroundStyle(c.nePlusContacter ? Color.texte3 : Color.texte)
                            if !c.sousTitre.isEmpty { Text(c.sousTitre).font(.secondaire).foregroundStyle(Color.texte2) }
                        }
                        .padding(.vertical, 3)
                    }
                    .width(min: 150, ideal: 170)
                    TableColumn("Type", value: \.type) { c in
                        Text(Libelles.type(c.type)).font(.secondaire).foregroundStyle(Color.texte2)
                    }
                    .width(min: 64, ideal: 72)
                    TableColumn("Ville", value: \.ville) { c in
                        Text(c.ville).font(.secondaire).foregroundStyle(Color.texte2)
                    }
                    .width(min: 70, ideal: 90)
                    TableColumn("Étape", value: \.etape) { c in
                        Pastille(texte: c.nePlusContacter ? L("Ne plus contacter") : Libelles.etape(c.etape),
                                 couleur: c.nePlusContacter ? .rouge : Couleurs.etape(c.etape))
                    }
                    .width(min: 96, ideal: 104)
                    TableColumn("Prochaine action", value: \.prochaineAction) { c in
                        Text(c.prochaineAction).font(.secondaire).foregroundStyle(Color.texte).lineLimit(2)
                    }
                    .width(min: 120, ideal: 160)
                    TableColumn("Date", value: \.prochaineDate) { c in
                        Text(c.prochaineDate.isEmpty ? "" : Dates.court(c.prochaineDate))
                            .font(.secondaire.monospacedDigit())
                            .foregroundStyle(enRetard(c) ? Color.rouge : Color.texte2)
                    }
                    .width(min: 56, ideal: 64)
                }
                .contextMenu(forSelectionType: Contact.ID.self) { ids in
                    if let id = ids.first, ids.count == 1 {
                        Button("Supprimer le contact", role: .destructive) { etat.supprimer(id) }
                    }
                }
            }
        }
        .padding(.trailing, ficheOuverte == nil ? 0 : 380)
            // La fiche, en panneau latéral de largeur fixe (charte, règle 7).
            if let c = ficheOuverte {
                HStack(spacing: 0) {
                    Rectangle().fill(Color.separateur).frame(width: 0.5)
                    FicheVue(contact: c).id(c.id)
                }
                .frame(width: 380)
                .frame(maxHeight: .infinity)
                .transition(.move(edge: .trailing))
            }
        }
        .animation(.snappy(duration: 0.25), value: etat.selection)
        .safeAreaInset(edge: .top, spacing: 0) { barreFiltres(total: liste.count) }
        .searchable(text: $recherche, placement: .toolbar, prompt: "Nom, entreprise, ville, notes")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                BoutonPrincipal(titre: L("Nouveau contact"), symbole: "plus") {
                    etat.nouveauContact(espace: espace == "tous" ? "kryva" : espace)
                }
            }
        }
    }

    private func enRetard(_ c: Contact) -> Bool {
        !c.prochaineDate.isEmpty && c.prochaineDate < Dates.aujourdhui() && c.etape != "perdu"   // « gagné » suivi (05/11, T3)
    }

    private func barreFiltres(total: Int) -> some View {
        HStack(spacing: 12) {
            Picker("Espace", selection: $espace) {
                Text("Tout").tag("tous")
                ForEach(Libelles.espaces, id: \.0) { Text($0.1).tag($0.0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 300)
            Picker("Étape", selection: $etape) {
                Text("En cours").tag("en_cours")
                Text("Toutes les étapes").tag("toutes")
                Divider()
                ForEach(Libelles.etapes, id: \.0) { Text($0.1).tag($0.0) }
            }
            .frame(width: 170)
            Picker("Type", selection: $type) {
                Text("Tous les types").tag("tous")
                Divider()
                ForEach(Libelles.types, id: \.0) { Text($0.1).tag($0.0) }
            }
            .frame(width: 160)
            Spacer()
            Text("\(total) contacts").font(.secondaire).foregroundStyle(Color.texte2)
        }
        .labelsHidden()
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(Color.surface)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.separateur).frame(height: 0.5) }
    }
}
