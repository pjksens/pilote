// « Les agents aujourd'hui » (05/11, Sacha : « toutes les fiches traitées, j'aimerais bien les voir quelque part dans
// Pilote pour voir si elles ont été traitées aujourd'hui par les agents, si elles l'ont pas été, que je puisse les relancer »).
// Par agent : sa liste du jour (gardée dès le matin), ce qui est traité, ce qui reste, et un bouton pour le relancer.
import SwiftUI

struct CarteAgentsDuJour: View {
    @Environment(Etat.self) private var etat

    var body: some View {
        let journees = etat.journeesAgents.filter { !$0.traitees.isEmpty || !$0.restantes.isEmpty }
        let faites = journees.reduce(0) { $0 + $1.faites.count }
        let reportees = journees.reduce(0) { $0 + $1.reportees.count }
        let sansTrace = journees.reduce(0) { $0 + $1.sansTrace.count }
        let restent = journees.reduce(0) { $0 + $1.restantes.count }
        // T5 : trois compteurs, pas un seul « traitée » : fait (preuve au fil ou classée), reporté (date seule), sans trace.
        Carte(titre: L("Les agents aujourd'hui"),
              detail: journees.isEmpty ? nil : [L("\(faites) faites"), L("\(reportees) reportées"), L("\(sansTrace) sans trace"), L("\(restent) restent")].joined(separator: " · ")) {
            if journees.isEmpty {
                EtatVide(texte: L("Aucune fiche sur la liste des agents aujourd'hui."))
            }
            ForEach(Array(journees.enumerated()), id: \.element.id) { i, j in
                LigneCarte(dernier: i == journees.count - 1) { BlocAgent(journee: j) }
            }
        }
    }
}

private struct BlocAgent: View {
    @Environment(Etat.self) private var etat
    let journee: JourneeAgent
    @State private var traiteesOuvertes = false

    private var nom: String { journee.session.replacingOccurrences(of: "KRYVA · ", with: "") }

    var body: some View {
        let total = journee.traitees.count + journee.restantes.count
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(nom).font(.ligneForte).foregroundStyle(Color.texte)
                Text([L("\(journee.faites.count) faites"), L("\(journee.reportees.count) reportées"), L("\(journee.sansTrace.count) sans trace")].joined(separator: " · ") + " " + L("(sur \(total))"))
                    .font(.secondaire).foregroundStyle(Color.texte2)
                if journee.reservoir > 0 {
                    Text("\(journee.reservoir) à contacter en réserve")
                        .font(.petit).foregroundStyle(Color.texte3)
                        .help("Prospects « à contacter » sans date : le stock, hors liste du jour")
                }
                if !journee.restantes.isEmpty {
                    Text(L("\(journee.restantes.count) restent"))
                        .font(.secondaire.weight(.semibold)).foregroundStyle(Color.rouge)
                } else {
                    Label("tout est traité", systemImage: "checkmark").font(.secondaire).foregroundStyle(Color.vert)
                }
                Spacer()
                if let r = etat.derniereRelance(journee) {
                    let l = Facteur.libelle(r.remise, pour: nom, veille: etat.prochaineVeille)
                    Text("Relancé à \(Libelles.heureFormat.string(from: r.heure)), \(l.texte)")
                        .font(.petit).foregroundStyle(Color.texte3).lineLimit(1)
                }
                if !journee.restantes.isEmpty {
                    Button("Relancer \(nom)") { etat.relancer(journee) }
                        .controlSize(.small)
                        .help("Envoie à \(nom) ses \(journee.restantes.count) fiches qui restent et la consigne du matin")
                }
            }
            ForEach(journee.restantes) { LigneFicheAgent(fiche: $0) }
            if !journee.traitees.isEmpty {
                Button { withAnimation(.snappy) { traiteesOuvertes.toggle() } } label: {
                    Label(traiteesOuvertes ? "Masquer les traitées" : "Voir les \(journee.traitees.count) traitées",
                          systemImage: traiteesOuvertes ? "chevron.down" : "chevron.right")
                }
                .buttonStyle(.plain).font(.secondaire).foregroundStyle(Color.texte2)
                if traiteesOuvertes { ForEach(journee.traitees) { LigneFicheAgent(fiche: $0) } }
            }
        }
    }
}

private struct LigneFicheAgent: View {
    @Environment(Etat.self) private var etat
    let fiche: FicheAgent

    var body: some View {
        Button { etat.ouvrir(fiche.contact) } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: fiche.traitee ? (fiche.preuve == "sans_trace" ? "questionmark.circle" : "checkmark.circle.fill") : "circle")
                    .foregroundStyle(fiche.traitee ? (fiche.preuve == "faite" ? Color.vert : Color.texte2) : Color.rouge)
                VStack(alignment: .leading, spacing: 2) {
                    Text(fiche.contact.titre).font(.ligne).foregroundStyle(Color.texte)
                    Text(action).font(.petit).foregroundStyle(Color.texte2).lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(fiche.devenue).font(.secondaire)
                    .foregroundStyle(fiche.traitee ? Color.texte2 : Color.rouge).lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Ouvrir la fiche")
    }

    /// Traitée : la nouvelle action ; restante : l'action qui attend.
    private var action: String {
        let a = Libelles.sansDateEnTete(fiche.contact.prochaineAction).replacingOccurrences(of: "\n", with: " ")
        return a.isEmpty ? L("Aucune prochaine action") : a
    }
}
