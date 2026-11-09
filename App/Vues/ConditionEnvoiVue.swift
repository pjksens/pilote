// La condition d'un message préparé et son rappel lié (05/11, T7 : le SMS à Marc Lefèvre est parti avant le test qui en
// était la condition). En rouge tant qu'elle n'est pas cochée : les boutons d'envoi sont bloqués à côté (LigneAEnvoyer, fiche).
import SwiftUI

struct ConditionEnvoi: View {
    @Environment(Etat.self) private var etat
    @Environment(Agenda.self) private var agenda
    let evenement: Evenement
    @State private var confirmer = false
    @State private var erreur: String?

    private var condition: String { evenement.condition.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        if !condition.isEmpty || !evenement.rappelId.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                if evenement.conditionEnAttente {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.rouge)
                        Text("À envoyer seulement quand : \(condition)")
                            .font(.secondaire.weight(.medium)).foregroundStyle(Color.rouge)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if evenement.statut == "prepare" || evenement.statut == "envoye" {
                            Button("Condition remplie…") { confirmer = true }.controlSize(.small)
                                .help("À cocher seulement quand c'est vérifié : l'envoi se débloque")
                        }
                    }
                } else if !condition.isEmpty {
                    Label("Condition remplie le \(Dates.court(evenement.conditionOkLe)) : \(condition)", systemImage: "checkmark.circle.fill")
                        .font(.petit).foregroundStyle(Color.vert)
                }
                if !evenement.rappelId.isEmpty {
                    Label(texteRappel, systemImage: "bell").font(.petit).foregroundStyle(Color.texte2)
                }
                if let erreur { Text(erreur).font(.petit).foregroundStyle(Color.rouge) }
            }
            .confirmationDialog("La condition est-elle remplie ?", isPresented: $confirmer) {
                Button("Oui, c'est vérifié") { etat.conditionRemplie(evenement.id) }
                if evenement.statut == "prepare" {
                    Button("Le message est déjà parti sans elle") {
                        erreur = etat.marquer(evenement.id, statut: "envoye", malgreCondition: true)
                    }
                }
                Button("Annuler", role: .cancel) {}
            } message: {
                Text("« \(condition) »\nÀ cocher seulement si c'est vérifié : le message pourra partir.")
            }
        }
    }

    private var texteRappel: String {
        let ref = Libelles.refRappel(evenement.rappelId)
        let t = agenda.taches.first { $0.id == ref || $0.titre == ref }
        let titre = t?.titre ?? ref
        if let t { return "Rappel lié : « \(titre) », \(t.faite ? "coché" : "à faire")" }
        return evenement.rappelFermeLe.isEmpty ? "Rappel lié : « \(titre) »" : "Rappel lié : « \(titre) », traité par Pilote"
    }
}
