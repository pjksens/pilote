// Les textes à valider (03/11, Sacha : « afficher les textes exacts directement » et « je mets exactement ce que je
// corrige en gardant le texte à côté »). Un agent range son brouillon en « a_valider » ; Sacha le lit ici en entier.
// Valider : il passe « à envoyer » (le jour prévu sur la fiche). Corriger : sa version à côté de l'original, validée
// telle quelle. Renvoyer : une consigne pour l'agent, le texte revient quand il est réécrit. L'agent apprend chaque choix.
import SwiftUI
import AppKit

struct CarteTexte: View {
    @Environment(Etat.self) private var etat
    let message: MessageAEnvoyer

    private enum Mode { case lecture, correction, consigne }
    @State private var mode = Mode.lecture
    @State private var version = ""
    @State private var consigne = ""

    private var e: Evenement { message.evenement }
    private var c: Contact { message.contact }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            entete
            if c.prochaineAction.lowercased().hasPrefix("avant l'envoi") {
                Label(c.prochaineAction, systemImage: "exclamationmark.triangle.fill")
                    .font(.secondaire.weight(.medium)).foregroundStyle(Color.ambre)
            }
            if e.canal == "mail", !e.objet.isEmpty {
                Text("Objet : \(e.objet)").font(.secondaire.weight(.semibold)).foregroundStyle(Color.texte)
            }
            switch mode {
            case .lecture, .consigne:
                Text(e.texte).font(.ligne).foregroundStyle(Color.texte).textSelection(.enabled).lineSpacing(2)
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.fond, in: RoundedRectangle(cornerRadius: 8))
            case .correction:
                HStack(alignment: .top, spacing: 12) {
                    colonne("Le texte proposé") {
                        ScrollView {
                            Text(e.texte).font(.ligne).foregroundStyle(Color.texte2).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(8)
                        }
                    }
                    colonne("Votre version (c'est elle qui partira)") {
                        TextEditor(text: $version).font(.ligne).scrollContentBackground(.hidden).padding(4)
                    }
                }
                .frame(minHeight: 220)
            }
            if mode == .consigne {
                HStack(alignment: .bottom, spacing: 8) {
                    TextField("Que doit changer \(Etat.auteur(c)) ? (ex. : plus court, sans le prix)", text: $consigne, axis: .vertical)
                        .textFieldStyle(.roundedBorder).lineLimit(1...4)
                    Button("Renvoyer") { etat.renvoyer(message, consigne: consigne) }
                        .buttonStyle(.borderedProminent).tint(.action)
                        .disabled(consigne.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Annuler") { mode = .lecture }
                }
            }
            boutons
        }
    }

    private var entete: some View {
        HStack(spacing: 8) {
            Pastille(texte: e.canal == "mail" ? "Mail" : (e.canal == "instagram" ? "DM Instagram" : Libelles.canal(e.canal)), couleur: .action)
            Button { etat.ouvrir(c) } label: { Text(c.titre).font(.ligneForte).foregroundStyle(Color.texte) }.buttonStyle(.plain)
            if e.canal != "mail", !e.objet.isEmpty {
                Text(e.objet).font(.secondaire).foregroundStyle(Color.texte2)
            }
            Spacer()
            if !message.jour.isEmpty {
                Text("envoi \(Dates.court(message.jour))").font(.petit).foregroundStyle(Color.texte3)
            }
            if e.canal == "instagram", let u = Libelles.lienInstagram(e.objet) {
                Button { NSWorkspace.shared.open(u) } label: { Image(systemName: "arrow.up.forward.square") }
                    .buttonStyle(.borderless).help("Ouvrir son profil Instagram")
            }
        }
    }

    @ViewBuilder
    private var boutons: some View {
        HStack(spacing: 8) {
            switch mode {
            case .correction:
                Button { etat.valider(message, texte: version) } label: { Label("Valider ma version", systemImage: "checkmark") }
                    .buttonStyle(.borderedProminent).tint(.vert)
                    .disabled(version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Annuler") { mode = .lecture }
            case .lecture, .consigne:
                Button { etat.valider(message, texte: e.texte) } label: { Label("Valider", systemImage: "checkmark") }
                    .buttonStyle(.borderedProminent).tint(.vert)
                    .help("Le texte est bon : il passe « à envoyer » le jour prévu")
                Button { version = e.texte; mode = .correction } label: { Label("Corriger", systemImage: "pencil") }
                    .help("Écrire votre version à côté du texte proposé")
                Button { mode = .consigne } label: { Label("Renvoyer à \(Etat.auteur(c))", systemImage: "arrow.uturn.backward") }
                    .help("Dire ce qui ne va pas : l'agent le réécrit et il revient ici")
            }
            Spacer()
            Button("Ne pas envoyer") { etat.abandonner(message) }
                .buttonStyle(.borderless).foregroundStyle(Color.texte2)
        }
        .controlSize(.regular)
    }

    private func colonne<C: View>(_ titre: String, @ViewBuilder _ contenu: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(titre).font(.petit.weight(.semibold)).foregroundStyle(Color.texte2)
            contenu()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Color.fond, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.separateur, lineWidth: 0.5))
        }
        .frame(maxWidth: .infinity)
    }
}
