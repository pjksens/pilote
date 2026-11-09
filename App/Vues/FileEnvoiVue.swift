// « Envoyer les mails validés » (07/11, Sacha : « il faut qu'ils soient envoyés automatiquement dès que je clique sur un
// bouton (ils sont envoyés à 5 min d'intervalle chacun) »). La carte montre la file (en attente avec l'heure prévue, partis,
// sautés ou pas partis avec la raison) et « Arrêter la file » ; la feuille montre ce qui partira, à qui, et demande de confirmer.
// L'envoi lui-même : l'agent launchd et Shared/FileEnvoi.swift (chemin de `pilote envoie`). SMS, LinkedIn : jamais ici.
import SwiftUI

struct CarteFileEnvoi: View {
    @Environment(Etat.self) private var etat
    @State private var feuille = false
    @State private var erreur: String?

    private var prets: [CandidatFile] { etat.candidatsFile.filter(\.cocheParDefaut) }
    private var actifs: [ElementFile] { etat.fileEnvoi.filter(\.enCours) }
    private var passes: [ElementFile] { etat.fileEnvoi.filter { !$0.enCours } }

    var body: some View {
        if !etat.candidatsFile.isEmpty || !etat.fileEnvoi.isEmpty {
            Carte(titre: "Envoi des mails", detail: detail) {
                if !actifs.isEmpty {
                    ForEach(actifs) { x in LigneCarte { LigneFile(element: x) } }
                }
                if !passes.isEmpty {
                    ForEach(passes.reversed()) { x in LigneCarte { LigneFile(element: x) } }
                }
                HStack(spacing: 10) {
                    BoutonPrincipal(titre: prets.isEmpty ? "Envoyer les mails validés" : "Envoyer les mails validés (\(prets.count))",
                                    symbole: "paperplane") { feuille = true }
                        .disabled(etat.candidatsFile.isEmpty)
                    if !actifs.isEmpty {
                        Button("Arrêter la file") { erreur = etat.arreterFile() }
                            .help("Ce qui attend ne part pas et reste à envoyer ; un mail déjà en cours d'envoi finit")
                    }
                    Spacer()
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                if let erreur { EtatErreur(texte: erreur) }
            }
            .sheet(isPresented: $feuille) { FeuilleFileEnvoi() }
        }
    }

    private var detail: String? {
        if let p = actifs.first {
            return "\(actifs.count) en attente · prochain vers \(heureFile(p.prevuLe))"
        }
        let partis = passes.filter { $0.etat == "envoye" }.count
        return passes.isEmpty ? "un mail toutes les 5 minutes, depuis votre Gmail" : "\(partis) parti(s) aujourd'hui"
    }
}

/// Une ligne de la file : à qui, l'objet, et ce qui lui arrive.
struct LigneFile: View {
    let element: ElementFile

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text(element.contact).font(.ligneForte).foregroundStyle(Color.texte)
                Text(element.a).font(.secondaire).foregroundStyle(Color.texte2)
                Spacer()
                Pastille(texte: libelle, couleur: couleur)
            }
            Text("Objet : \(element.objet)").font(.secondaire).foregroundStyle(Color.texte2)
            if !element.raison.isEmpty && element.etat != "envoye" && element.etat != "attente" {
                Text(element.raison).font(.petit).foregroundStyle(element.etat == "annule" ? Color.texte2 : Color.rouge)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var libelle: String {
        switch element.etat {
        case "attente": return "part vers \(heureFile(element.prevuLe))"
        case "envoi": return "envoi en cours"
        case "envoye": return "parti à \(heureFile(element.faitLe))"
        case "refuse": return "sauté"
        case "echec": return "pas parti"
        case "incertain": return "à vérifier"
        case "annule": return "annulé"
        default: return element.etat
        }
    }

    private var couleur: Color {
        switch element.etat {
        case "envoye": return .vert
        case "attente", "envoi", "annule": return .texte2
        default: return .rouge
        }
    }
}

/// Ce qui partira, à qui, quand ; Sacha décoche ce qu'il ne veut pas et confirme.
struct FeuilleFileEnvoi: View {
    @Environment(Etat.self) private var etat
    @Environment(\.dismiss) private var fermer
    @State private var coches: Set<String> = []
    @State private var acces: String?
    @State private var verification = true
    @State private var envoi = false
    @State private var erreur: String?

    private var envoyables: [CandidatFile] { etat.candidatsFile.filter(\.envoyable) }
    private var bloques: [CandidatFile] { etat.candidatsFile.filter { !$0.envoyable } }
    private var choisis: [String] { envoyables.map(\.id).filter(coches.contains) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Envoyer les mails validés").font(.system(size: 19, weight: .semibold))
            Text("De : \(Gmail.adresse ?? "Gmail non connecté")").font(.secondaire.weight(.medium)).foregroundStyle(Color.texte2)
            Text(calendrier).font(.secondaire).foregroundStyle(Color.texte2)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(envoyables) { c in
                        Toggle(isOn: Binding(get: { coches.contains(c.id) },
                                             set: { if $0 { coches.insert(c.id) } else { coches.remove(c.id) } })) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(EnvoiPilote.nomContact(c.contact)).font(.ligneForte)
                                    Text(c.contact.email).font(.secondaire).foregroundStyle(Color.texte2)
                                    if c.plusTard { Pastille(texte: "prévu le \(Dates.jjmm(c.jour))", couleur: .texte2) }
                                }
                                Text("Objet : \(c.evenement.objet)").font(.secondaire).foregroundStyle(Color.texte2)
                                Text(c.evenement.texte).font(.petit).foregroundStyle(Color.texte2).lineLimit(2)
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                    if !bloques.isEmpty {
                        Text("Ne partiront pas").font(.ligneForte).padding(.top, 6)
                        ForEach(bloques) { c in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(EnvoiPilote.nomContact(c.contact)) · \(c.evenement.objet.isEmpty ? "(sans objet)" : c.evenement.objet)")
                                    .font(.secondaire.weight(.medium))
                                Text(c.refus.joined(separator: " ; ")).font(.petit).foregroundStyle(Color.rouge)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 160, maxHeight: 420)
            if verification {
                EtatChargement(texte: "Vérification de l'envoi automatique…")
            } else if let acces {
                Text(acces).font(.secondaire.weight(.medium)).foregroundStyle(Color.rouge).fixedSize(horizontal: false, vertical: true)
            }
            if let erreur { Text(erreur).font(.secondaire).foregroundStyle(Color.rouge).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Text("SMS et LinkedIn ne partent pas d'ici : vous les envoyez vous-même.").font(.petit).foregroundStyle(Color.texte2)
                Spacer()
                Button("Annuler") { fermer() }.keyboardShortcut(.cancelAction)
                Button(choisis.isEmpty ? "Envoyer" : choisis.count == 1 ? "Envoyer ce mail" : "Envoyer ces \(choisis.count) mails") {
                    envoi = true
                    Task {
                        erreur = await etat.mettreEnFile(choisis)
                        envoi = false
                        if erreur == nil { fermer() }
                    }
                }
                .buttonStyle(.borderedProminent).tint(.action)
                .disabled(choisis.isEmpty || envoi || verification || acces != nil)
            }
        }
        .padding(20)
        .frame(width: 620)
        .onAppear {
            etat.charger()
            coches = Set(etat.candidatsFile.filter(\.cocheParDefaut).map(\.id))
        }
        .task {
            // Ce que l'agent verra une fois l'app fermée : installé, et capable de lire le mot de passe sans fenêtre.
            let r = await Task.detached { () -> String? in
                if !FileEnvoi.agentCharge() {
                    return "L'envoi automatique n'est pas installé (agent \(FileEnvoi.etiquette)) : rien ne partirait. Prévenir PILOTE."
                }
                return FileEnvoi.accesOutil()
            }.value
            acces = r
            verification = false
        }
    }

    /// « Le premier part tout de suite, puis un toutes les 5 minutes : le dernier vers HH:MM. »
    private var calendrier: String {
        let n = choisis.count
        guard n > 0 else { return "Cochez les mails à envoyer." }
        var debut = Date()
        let derniers = etat.fileEnvoi.filter { ["envoye", "echec", "incertain"].contains($0.etat) }.compactMap { Dates.iso.date(from: $0.faitLe) }
        let enAttente = etat.fileEnvoi.filter(\.enCours).count
        if let d = derniers.max(), d.addingTimeInterval(FileEnvoi.intervalle) > debut { debut = d.addingTimeInterval(FileEnvoi.intervalle) }
        debut = debut.addingTimeInterval(Double(enAttente) * FileEnvoi.intervalle)
        let fin = debut.addingTimeInterval(Double(n - 1) * FileEnvoi.intervalle)
        let premier = enAttente > 0 ? "Le premier part après les \(enAttente) déjà en file (vers \(heureFile(debut)))" : "Le premier part tout de suite"
        return n == 1 ? premier + "." : "\(premier), puis un toutes les 5 minutes : le dernier vers \(heureFile(fin)), même si l'app est fermée."
    }
}

/// HH:MM, heure de Paris, d'une date ISO de la base.
func heureFile(_ iso: String) -> String {
    guard let d = Dates.iso.date(from: iso) else { return "?" }
    return heureFile(d)
}

func heureFile(_ d: Date) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "fr_FR")
    f.timeZone = TimeZone(identifier: "Europe/Paris")
    f.dateFormat = "HH:mm"
    return f.string(from: d)
}
