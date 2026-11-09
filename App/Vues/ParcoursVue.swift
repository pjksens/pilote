// Le parcours du prospect en une ligne de pastilles (04/11, Sacha : « SUPER VISUEL »). Vert = fait, orange = là où il en est
// (sablier = on attend l'autre), gris = à venir. Calculé à partir du fil par Parcours.etapes.
import SwiftUI

struct ParcoursContact: View {
    @Environment(Etat.self) private var etat
    let contact: Contact
    var compact = false
    @State private var etapes: [EtapeParcours] = []

    var body: some View {
        ParcoursVue(etapes: etapes, compact: compact)
            .onAppear { recalculer() }
            .onChange(of: etat.revision) { recalculer() }
            .onChange(of: contact) { recalculer() }
    }

    private func recalculer() {
        etapes = Parcours.etapes(contact: contact, fil: etat.evenements(contact.id))
    }
}

struct ParcoursVue: View {
    let etapes: [EtapeParcours]
    var compact = false

    private func couleur(_ e: EtapeParcours) -> Color {
        switch e.etat {
        case .fait: return .vert
        case .courante: return .ambre
        case .aVenir, .saute: return .texte3
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(etapes.enumerated()), id: \.element.id) { i, e in
                HStack(alignment: .top, spacing: 0) {
                    noeud(e)
                    if i < etapes.count - 1 {
                        Rectangle().fill(e.etat == .fait ? Color.vert.opacity(0.6) : Color.separateur)
                            .frame(height: 2).frame(maxWidth: .infinity)
                            .padding(.top, compact ? 6 : 8).padding(.horizontal, 2)
                    }
                }
                .frame(maxWidth: i < etapes.count - 1 ? .infinity : nil)
            }
        }
    }

    private func noeud(_ e: EtapeParcours) -> some View {
        let d = compact ? 14.0 : 18.0
        return VStack(spacing: 2) {
            ZStack {
                Circle().fill(e.etat == .aVenir || e.etat == .saute ? Color.clear : couleur(e))
                Circle().strokeBorder(couleur(e), lineWidth: e.etat == .courante ? 2.5 : 1.5)
                switch e.etat {
                case .fait: Image(systemName: "checkmark").font(.system(size: d * 0.55, weight: .bold)).foregroundStyle(.white)
                case .courante:
                    Image(systemName: e.attente ? "hourglass" : "arrow.right").font(.system(size: d * 0.5, weight: .bold))
                        .foregroundStyle(.white)
                case .saute: Image(systemName: "minus").font(.system(size: d * 0.5, weight: .bold)).foregroundStyle(Color.texte3)
                case .aVenir: EmptyView()
                }
            }
            .frame(width: d, height: d)
            Text(e.titre).font(.system(size: compact ? 10 : 11, weight: e.etat == .courante ? .bold : .medium))
                .foregroundStyle(e.etat == .courante ? Color.texte : (e.etat == .fait ? Color.texte2 : Color.texte3))
                .lineLimit(1).minimumScaleFactor(0.6)
            if !compact {
                Text(sousTitre(e)).font(.system(size: 10)).foregroundStyle(e.etat == .courante ? couleur(e) : Color.texte3)
                    .lineLimit(2).multilineTextAlignment(.center).minimumScaleFactor(0.7)
            } else if e.etat == .courante, !e.detail.isEmpty {
                Text(e.detail).font(.system(size: 9)).foregroundStyle(couleur(e)).lineLimit(1).minimumScaleFactor(0.6)
            }
        }
    }

    private func sousTitre(_ e: EtapeParcours) -> String {
        var p: [String] = []
        if !e.date.isEmpty { p.append(Dates.court(e.date)) }
        if !e.detail.isEmpty { p.append(e.detail) }
        return p.joined(separator: " · ")
    }
}
