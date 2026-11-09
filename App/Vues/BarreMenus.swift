// Pilote dans la barre des menus : la journée d'un coup d'œil, cocher, ajouter une tâche en une ligne.
import ServiceManagement
import SwiftUI

struct BarreMenusVue: View {
    @Environment(Etat.self) private var etat
    @Environment(Agenda.self) private var agenda
    @Environment(\.openWindow) private var ouvrirFenetre
    @State private var saisie = ""
    @State private var auDemarrage = SMAppService.mainApp.status == .enabled

    private var duJour: [Tache] {
        agenda.taches.filter { !$0.faite && Jours.colonne($0.echeance) == .aujourdhui && $0.echeance != nil }
            .sorted { ($0.echeance ?? .distantFuture) < ($1.echeance ?? .distantFuture) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Aujourd'hui").font(.titreSection).foregroundStyle(Color.texte)
                Text("\(duJour.count) à faire").font(.secondaire).foregroundStyle(Color.texte2)
                Spacer()
                if !etat.dus.isEmpty || !etat.aEnvoyerAujourdhui.isEmpty {
                    Text("\(etat.dus.count) relance\(etat.dus.count > 1 ? "s" : "") · \(etat.aEnvoyerAujourdhui.count) à envoyer")
                        .font(.petit).foregroundStyle(Color.texte2)
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if duJour.isEmpty {
                        Text("Rien à faire aujourd'hui.").font(.secondaire).foregroundStyle(Color.texte2).padding(.vertical, 8)
                    }
                    ForEach(duJour) { t in
                        HStack(alignment: .top, spacing: 8) {
                            Button { agenda.marquerFaite(t.id, true) } label: {
                                Image(systemName: "circle").foregroundStyle(Color.texte3)
                            }
                            .buttonStyle(.plain).help("Fait")
                            Text(t.titre).font(.secondaire).foregroundStyle(Color.texte).lineLimit(2)
                            Spacer(minLength: 6)
                            if t.avecHeure, let d = t.echeance {
                                Text(Jours.heure(d))
                                    .font(.petit.monospacedDigit())
                                    .foregroundStyle(Calendar.current.startOfDay(for: d) < Jours.aujourdhui ? Color.rouge : Color.texte3)
                            }
                        }
                        .padding(.vertical, 5)
                    }
                }
            }
            // Une fenêtre de barre des menus ne donne pas de hauteur à une zone qui défile : on la fixe.
            .frame(height: min(max(CGFloat(duJour.count), 1) * 34, 340))
            TextField("", text: $saisie, prompt: Text("Ajouter une tâche pour aujourd'hui"))
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    let t = saisie.trimmingCharacters(in: .whitespaces)
                    guard !t.isEmpty else { return }
                    agenda.creer(titre: t, notes: "", liste: agenda.listes.contains("KRYVA") ? "KRYVA" : "", date: Jours.aujourdhui, avecHeure: false)
                    saisie = ""
                }
            Divider()
            HStack {
                Toggle("Ouvrir au démarrage du Mac", isOn: $auDemarrage)
                    .toggleStyle(.checkbox).font(.petit)
                    .onChange(of: auDemarrage) { _, oui in
                        if oui { try? SMAppService.mainApp.register() } else { try? SMAppService.mainApp.unregister() }
                        auDemarrage = SMAppService.mainApp.status == .enabled
                    }
                Spacer()
                Button("Ouvrir Pilote") {
                    ouvrirFenetre(id: "principale")
                    NSApp.activate(ignoringOtherApps: true)
                }
                .buttonStyle(.borderedProminent).tint(.action).controlSize(.small)
            }
        }
        .padding(14)
        .frame(width: 360)
        .background(Color.fond)
        .task { if agenda.accesRappels == .inconnu { await agenda.demarrer() } }
    }
}
