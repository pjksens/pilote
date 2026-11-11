// Claude : les sessions qui tournent, les récentes, et de quoi en préparer une nouvelle.
import AppKit
import SwiftUI

struct ClaudeVue: View {
    @Environment(Etat.self) private var etat
    @State private var feuille = false
    @State private var filtreJournal = "tout"

    private var recentes: [SessionClaude] {
        let vivantes = Set(etat.agents.map(\.sessionApp))
        return etat.recentes.filter { $0.etat.isEmpty && !vivantes.contains($0.id) }.prefix(15).map { $0 }
    }

    private var entrees: [EntreeJournal] {
        let liste = filtreJournal == "livrables" ? etat.journal.filter { $0.type != "tour" } : etat.journal
        return Array(liste.prefix(60))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                EnTete(titre: L("Agents"), detail: L("Ce que font vos sessions Claude Code en ce moment, et le journal de ce qu'elles ont fait"))
                PyramideCompacte(pyramide: etat.pyramide, charge: etat.pyramideChargee)
                HStack(alignment: .top, spacing: 20) {
                    carteJournal.frame(maxWidth: .infinity)
                    VStack(spacing: 20) {
                        carteRoutines
                        carte(titre: L("Récentes"), liste: recentes, vide: L("Aucune session récente."))
                    }
                    .frame(width: 380)
                }
            }
            .padding(28)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                BoutonPrincipal(titre: L("Nouvelle session"), symbole: "plus") { feuille = true }
            }
        }
        .sheet(isPresented: $feuille) { NouvelleSession() }
    }

    private var carteJournal: some View {
        Carte(titre: L("Journal")) {
            Picker("", selection: $filtreJournal) {
                Text("Tout").tag("tout")
                Text("Livrables et notes").tag("livrables")
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 260)
            .padding(.horizontal, 16).padding(.bottom, 8)
            if entrees.isEmpty {
                EtatVide(texte: filtreJournal == "tout"
                         ? L("Le journal se remplit à la fin de chaque réponse des sessions (à partir de leur prochain démarrage).")
                         : L("Aucun livrable noté pour l'instant."))
            } else {
                ForEach(Array(entrees.enumerated()), id: \.element.id) { i, e in
                    LigneCarte(dernier: i == entrees.count - 1) { LigneJournal(entree: e, avecProjet: true) }
                }
            }
        }
    }

    private func carte(titre: String, liste: [SessionClaude], vide: String) -> some View {
        Carte(titre: titre, detail: liste.isEmpty ? nil : "\(liste.count)") {
            if !etat.recentesChargees {
                EtatChargement(texte: L("Lecture des sessions…"))
            } else if liste.isEmpty {
                EtatVide(texte: vide)
            } else {
                ForEach(Array(liste.enumerated()), id: \.element.id) { i, s in
                    LigneCarte(dernier: i == liste.count - 1) {
                        Button { Claude.ouvrir(s) } label: { LigneSession(session: s) }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var carteRoutines: some View {
        Carte(titre: L("Routines")) {
            if Claude.routines.isEmpty {
                EtatVide(texte: L("Aucune routine : ajoutez les vôtres dans reglages.json (routines)."))
            }
            ForEach(Array(Claude.routines.enumerated()), id: \.element.id) { i, r in
                LigneCarte(dernier: i == Claude.routines.count - 1) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.titre).font(.ligneForte).foregroundStyle(Color.texte)
                            Text(r.detail).font(.secondaire).foregroundStyle(Color.texte2)
                        }
                        Spacer()
                        Button("Préparer") { Claude.nouvelle(consigne: r.consigne, dossier: r.dossier) }
                            .controlSize(.small)
                            .help("Ouvre une nouvelle session dans l'app Claude, consigne déjà écrite")
                    }
                }
            }
        }
    }
}

/// Une session qui tourne : son nom, son état, ce qu'elle fait en ce moment.
struct LigneActivite: View {
    @Environment(Etat.self) private var etat
    let activite: ActiviteSession

    var body: some View {
        let a = activite
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(a.etat == "busy" ? Color.vert : (a.etat == "waiting" ? Color.ambre : Color.texte3))
                .frame(width: 8, height: 8).padding(.top, 6)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(a.titre).font(.ligneForte).foregroundStyle(Color.texte).lineLimit(1)
                    if let p = etat.projet(pour: a.dossier) {
                        Button(p.nom) { etat.ouvrir(projet: p.id) }.buttonStyle(.link).font(.petit)
                    } else {
                        Text(Chemins.court(a.dossier)).font(.petit).foregroundStyle(Color.texte3).lineLimit(1)
                    }
                }
                if a.etat == "busy" {
                    if !a.etape.isEmpty { ligne(L("Étape"), a.etape) }
                    if !a.action.isEmpty { ligne(L("Fait"), a.action, quand: a.actionLe) }
                } else if !a.recap.isEmpty {
                    Text(a.recap).font(.secondaire).foregroundStyle(Color.texte).lineLimit(3)
                }
                if !a.demande.isEmpty {
                    Text("Demande : \(a.demande)").font(.petit).foregroundStyle(Color.texte3).lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                Text(a.libelleEtat).font(.secondaire).foregroundStyle(a.etat == "waiting" ? Color.ambre : Color.texte2)
                if a.contexte > 0 {
                    Text("\(a.contexte / 1000) k relus par action")
                        .font(.petit.monospacedDigit())
                        .foregroundStyle(a.contexte > 300_000 && a.etat == "busy" ? Color.rouge : (a.contexte > 200_000 ? Color.ambre : Color.texte3))
                        .help("Taille du contexte que la session relit à chaque action. Elle se résume toute seule vers 170 k (réglage autoCompactWindow à 200 k). Orange : au-dessus, elle se résumera à sa prochaine action. Rouge : elle travaille au-delà de 300 k, le résumé automatique n'a pas pris ; l'ouvrir et taper /compact.")
                }
                if let d = a.depuis {
                    Text(d.formatted(.relative(presentation: .named).locale(Loc.locale)))
                        .font(.petit).foregroundStyle(Color.texte3)
                }
                if !a.sessionApp.isEmpty {
                    Button("Ouvrir") { Claude.ouvrir(id: a.sessionApp) }.controlSize(.small)
                }
            }
        }
    }

    private func ligne(_ titre: String, _ texte: String, quand: Date? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(titre).font(.petit.weight(.medium)).foregroundStyle(Color.texte3).frame(width: 40, alignment: .leading)
            Text(texte).font(.secondaire).foregroundStyle(Color.texte).lineLimit(2)
            if let quand {
                Text(quand.formatted(.relative(presentation: .numeric).locale(Loc.locale)))
                    .font(.petit).foregroundStyle(Color.texte3)
            }
        }
    }
}

/// Une entrée du journal : quand, quelle session, ce qu'elle a fait, les fichiers touchés.
struct LigneJournal: View {
    @Environment(Etat.self) private var etat
    let entree: EntreeJournal
    let avecProjet: Bool
    @State private var ouvert = false

    var body: some View {
        let e = entree
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let d = Dates.date(e.le) {
                    Text(Loc.date(d, "dMMM") + " " + Libelles.heureFormat.string(from: d))
                        .font(.petit.monospacedDigit()).foregroundStyle(Color.texte3)
                }
                Text(e.titreSession.isEmpty ? L("Session") : e.titreSession).font(.secondaire.weight(.semibold))
                    .foregroundStyle(Color.texte).lineLimit(1)
                if e.type != "tour" { Pastille(texte: e.type == "livrable" ? L("Livrable") : L("Note"), couleur: .vert) }
                if avecProjet, let p = etat.projets.first(where: { $0.id == e.projetId }) {
                    Button(p.nom) { etat.ouvrir(projet: p.id) }.buttonStyle(.link).font(.petit)
                }
                Spacer()
                if !e.sessionApp.isEmpty {
                    Button { Claude.ouvrir(id: e.sessionApp) } label: { Image(systemName: "arrow.up.forward.square") }
                        .buttonStyle(.plain).foregroundStyle(Color.texte3).help("Ouvrir la session")
                }
            }
            Text(e.texte).font(.secondaire).foregroundStyle(Color.texte).lineLimit(ouvert ? nil : 3)
                .textSelection(.enabled)
                .onTapGesture { ouvert.toggle() }
            if ouvert, !e.demande.isEmpty {
                Text("Demande : \(e.demande)").font(.petit).foregroundStyle(Color.texte3)
            }
            if !e.listeFichiers.isEmpty {
                let fichiers = ouvert ? e.listeFichiers : Array(e.listeFichiers.prefix(3))
                ForEach(fichiers, id: \.self) { f in
                    Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: f)]) } label: {
                        Label((f as NSString).lastPathComponent, systemImage: "doc").font(.petit)
                    }
                    .buttonStyle(.plain).foregroundStyle(Color.texte2).help(Chemins.court(f))
                }
                if !ouvert, e.listeFichiers.count > 3 {
                    Text(L("et \(e.listeFichiers.count - 3) autres fichiers")).font(.petit).foregroundStyle(Color.texte3)
                }
            }
        }
    }
}

struct LigneSession: View {
    let session: SessionClaude
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(couleur).frame(width: 8, height: 8).padding(.top, 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.titre).font(.ligne).foregroundStyle(Color.texte).lineLimit(1)
                Text(session.dossierCourt).font(.petit).foregroundStyle(Color.texte3).lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if !session.libelleEtat.isEmpty {
                    Text(session.libelleEtat).font(.secondaire).foregroundStyle(session.etat == "waiting" ? Color.ambre : Color.texte2)
                }
                if let d = session.derniereActivite {
                    Text(d.formatted(.relative(presentation: .named).locale(Loc.locale)))
                        .font(.petit).foregroundStyle(Color.texte3)
                }
            }
        }
        .contentShape(Rectangle())
    }

    private var couleur: Color {
        switch session.etat {
        case "busy": return .vert
        case "waiting": return .ambre
        case "idle": return .texte3
        default: return .clear
        }
    }
}

struct NouvelleSession: View {
    @Environment(\.dismiss) private var fermer
    @State private var consigne = ""
    @State private var dossier = Claude.dossiers[0].1

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Nouvelle session").font(.system(size: 19, weight: .semibold))
            Text("La session s'ouvre dans l'app Claude avec votre consigne. Vous la lancez de là-bas.")
                .font(.secondaire).foregroundStyle(Color.texte2)
            Picker("Dossier", selection: $dossier) {
                ForEach(Claude.dossiers, id: \.1) { Text($0.0).tag($0.1) }
            }
            TextEditor(text: $consigne)
                .font(.ligne).frame(minHeight: 140)
                .scrollContentBackground(.hidden).padding(8)
                .background(Color.surface, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.separateur, lineWidth: 0.5))
            HStack {
                Spacer()
                Button("Annuler") { fermer() }.keyboardShortcut(.cancelAction)
                Button("Ouvrir dans Claude") {
                    Claude.nouvelle(consigne: consigne, dossier: dossier)
                    fermer()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(.action)
            }
        }
        .padding(22)
        .frame(width: 520)
    }
}
