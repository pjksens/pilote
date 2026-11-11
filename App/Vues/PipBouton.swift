// Le bouton « Lancer Pip » d'une réunion de l'agenda (10/11). N'existe que si Pip est installé sur ce Mac ; sinon la vue
// est vide et rien ne change à l'écran. Le clic prépare Pip (nom de la réunion, contact lié) : l'enregistrement, lui,
// reste le clic « Start » de Sacha dans Pip, et l'écoute de Claude un geste de Sacha aussi.
import AppKit
import SwiftUI

struct BoutonPip: View {
    let rv: RendezVous
    private let liaison = PipLiaison.partage
    @State private var retour: String?

    var body: some View {
        if liaison.disponible && !rv.journee {
            HStack(spacing: 8) {
                if let retour {
                    Text(retour).font(.petit).foregroundStyle(Color.texte2).lineLimit(1)
                }
                Menu {
                    Button("Copier la consigne pour Claude") { copier() }
                    Divider()
                    @Bindable var l = liaison
                    Toggle("Lancer Pip tout seul avant les visios", isOn: $l.auto)
                } label: {
                    Text("Lancer Pip")
                } primaryAction: {
                    lancer()
                }
                .controlSize(.small)
                .fixedSize()
                .help("Ouvre Pip sur cette réunion, avec son nom et le contact lié. Pip n'enregistre qu'après votre clic sur Start.")
            }
        }
    }

    private func lancer() {
        guard let o = liaison.lancer(rv) else { return }
        retour = if let nom = o.contact { L("Pip ouvert · fil de \(nom)") }
                 else if o.nomTransmis { L("Pip ouvert · aucun contact lié") }
                 else { L("Pip ouvert (à mettre à jour pour le nom)") }
    }

    private func copier() {
        let tableau = NSPasteboard.general
        tableau.clearContents()
        tableau.setString(liaison.consigne(pour: rv), forType: .string)
        retour = L("Consigne copiée : collez-la dans Claude")
    }
}
