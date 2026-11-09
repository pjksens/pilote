// « Pas envoyé » / « Pas fait » avec une raison (04/11, Sacha) : la raison reste au fil du contact et remonte à l'agent.
import SwiftUI

struct FeuillePasEnvoye: View {
    enum Cible {
        case message(MessageAEnvoyer)
        case suivi(Contact)
    }

    @Environment(Etat.self) private var etat
    @Environment(\.dismiss) private var fermer
    let cible: Cible
    @State private var raison: RaisonPasEnvoye = .pasLeMoment
    @State private var precision = ""
    @State private var jour = Report.demain.jour(depuis: Date())

    private var contact: Contact {
        switch cible {
        case .message(let m): return m.contact
        case .suivi(let c): return c
        }
    }

    private var raisons: [RaisonPasEnvoye] {
        if case .message = cible { return RaisonPasEnvoye.pourMessage }
        return RaisonPasEnvoye.pourSuivi
    }

    private var titre: String {
        if case .message = cible { return "Pas envoyé : \(contact.titre)" }
        return "Pas fait : \(contact.titre)"
    }

    private var consigneObligatoire: Bool { raison == .texteAChanger }
    private var peutNoter: Bool { !consigneObligatoire || !precision.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private var explication: String {
        switch raison {
        case .pasLeMoment: return "Le message reste prêt, la fiche est reportée : il revient le jour choisi."
        case .texteAChanger: return "Le texte repart à l'agent avec ce que vous écrivez ci-dessous."
        case .plusDActualite:
            if case .message = cible { return "Le message est annulé. La fiche ne bouge pas : la ligne du jour reste pour décider de la suite." }
            return "L'action est abandonnée et la date se libère. La raison reste dans le fil."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(titre).font(.titreSection).foregroundStyle(Color.texte).lineLimit(2)
            Picker("Raison", selection: $raison) {
                ForEach(raisons) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden()
            Text(explication).font(.secondaire).foregroundStyle(Color.texte2)
            if raison == .pasLeMoment {
                DatePicker("Revoir le", selection: $jour, in: Date()..., displayedComponents: [.date])
                    .datePickerStyle(.compact)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(consigneObligatoire ? "Ce qu'il faut changer" : "Pourquoi ? (facultatif)")
                    .font(.secondaire.weight(.medium)).foregroundStyle(Color.texte2)
                TextField("", text: $precision, axis: .vertical)
                    .lineLimit(2...5).textFieldStyle(.roundedBorder)
            }
            HStack {
                Spacer()
                Button("Annuler") { fermer() }.keyboardShortcut(.cancelAction)
                Button("Noter") { noter() }
                    .buttonStyle(.borderedProminent).tint(.action)
                    .keyboardShortcut(.defaultAction).disabled(!peutNoter)
            }
        }
        .padding(20).frame(width: 380)
    }

    private func noter() {
        switch cible {
        case .message(let m): etat.pasEnvoye(m, raison: raison, precision: precision, au: jour)
        case .suivi(let c): etat.pasFait(c, raison: raison, precision: precision, au: jour)
        }
        fermer()
    }
}
