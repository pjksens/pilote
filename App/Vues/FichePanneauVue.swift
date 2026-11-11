// La fiche d'un contact dans le panneau de droite (04/11, Sacha : « Fiche » dans Prospects du jour m'envoyait dans Prospects ;
// je veux qu'elle glisse à droite comme les documents, sans aller-retour entre les pages).
import SwiftUI

struct FichePanneau: View {
    @Environment(Etat.self) private var etat
    let contactId: String

    private var contact: Contact? { etat.contacts.first { $0.id == contactId } }

    var body: some View {
        VStack(spacing: 0) {
            entete
            Rectangle().fill(Color.separateur).frame(height: 0.5)
            if let c = contact {
                FicheVue(contact: c).id(c.id)
            } else {
                EtatErreur(texte: L("Fiche introuvable"))
                Spacer()
            }
        }
        .background(Color.surface)
        .id(contactId)
    }

    private var entete: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.crop.circle.fill").foregroundStyle(Color.action)
            VStack(alignment: .leading, spacing: 1) {
                Text(contact?.titre ?? L("Fiche")).font(.ligneForte).foregroundStyle(Color.texte).lineLimit(1)
                if let s = contact?.sousTitre, !s.isEmpty {
                    Text(s).font(.petit).foregroundStyle(Color.texte3).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if let c = contact {
                Button { etat.ouvrirDansProspects(c) } label: { Image(systemName: "arrow.up.forward.app") }
                    .help("L'ouvrir dans la page Prospects")
            }
            Button { etat.fichePanneau = nil } label: { Image(systemName: "xmark") }
                .help("Fermer le panneau (Échap)").keyboardShortcut(.cancelAction)
        }
        .buttonStyle(.borderless).font(.system(size: 14))
        .padding(.horizontal, 14).padding(.vertical, 10)
    }
}
