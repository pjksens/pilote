// Envoyer un mail préparé, depuis le Gmail de Sacha, sur son clic. Un seul mail à la fois ; l'envoi groupé (un mail toutes
// les 5 min, bouton « Envoyer les mails validés ») passe par la file : App/Vues/FileEnvoiVue.swift et Shared/FileEnvoi.swift.
import SwiftUI

struct EnvoiMail: View {
    @Environment(Etat.self) private var etat
    @Environment(\.dismiss) private var fermer
    let message: MessageAEnvoyer
    @State private var de = ""
    @State private var a = ""
    @State private var objet = ""
    @State private var texte = ""
    @State private var envoi = false
    @State private var erreur: String?
    @State private var connexion = false
    @State private var reponseA = ""

    private var pret: Bool {
        Gmail.connecte && a.contains("@") && !objet.trimmingCharacters(in: .whitespaces).isEmpty
            && !texte.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !envoi && !message.evenement.conditionEnAttente
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Envoyer ce mail").font(.system(size: 19, weight: .semibold))
            if message.evenement.conditionEnAttente {
                Text("Bloqué : à envoyer seulement quand « \(message.evenement.condition) ». Cochez « Condition remplie… » d'abord.")
                    .font(.secondaire.weight(.medium)).foregroundStyle(Color.rouge)
            }
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("De").font(.secondaire).foregroundStyle(Color.texte2)
                    HStack {
                        Text(Gmail.connecte ? "\(de) (Gmail)" : "Gmail n'est pas encore connecté").font(.ligne)
                            .foregroundStyle(Gmail.connecte ? Color.texte : Color.rouge)
                        Spacer()
                        Button(Gmail.connecte ? "Changer" : "Connecter Gmail") { connexion = true }.controlSize(.small)
                    }
                }
                GridRow {
                    Text("À").font(.secondaire).foregroundStyle(Color.texte2)
                    TextField("", text: $a, prompt: Text("adresse@entreprise.fr")).textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Objet").font(.secondaire).foregroundStyle(Color.texte2)
                    TextField("", text: $objet, prompt: Text("L'objet du mail")).textFieldStyle(.roundedBorder)
                }
            }
            if !reponseA.isEmpty {
                Text("Part en réponse au mail précédent, dans le même fil.").font(.petit).foregroundStyle(Color.texte2)
            }
            TextEditor(text: $texte)
                .font(.ligne).frame(minHeight: 220)
                .scrollContentBackground(.hidden).padding(8)
                .background(Color.surface, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.separateur, lineWidth: 0.5))
            Text("Le mail part tel quel, maintenant, depuis votre Gmail, en texte simple et sans signature ajoutée. S'il existe aussi en brouillon dans Gmail, supprimez ce brouillon après l'envoi.")
                .font(.petit).foregroundStyle(Color.texte2)
            if let erreur {
                EtatErreur(texte: erreur).background(Color.surface, in: RoundedRectangle(cornerRadius: 10))
            }
            HStack {
                if envoi { ProgressView().controlSize(.small); Text("Envoi…").font(.secondaire).foregroundStyle(Color.texte2) }
                Spacer()
                Button("Annuler") { fermer() }.keyboardShortcut(.cancelAction).disabled(envoi)
                Button("Envoyer depuis Gmail") { Task { await envoyer() } }
                    .buttonStyle(.borderedProminent).tint(.action)
                    .disabled(!pret)
            }
        }
        .padding(22)
        .frame(width: 600)
        .onAppear {
            a = message.contact.email
            objet = message.evenement.objet
            texte = message.evenement.texte
            reponseA = message.evenement.reponseA
            // Gmail ne range une réponse dans le fil que si l'objet suit (« Re: » + même sujet). Règle partagée avec `pilote envoie`.
            objet = EnvoiPilote.objetDEnvoi(objet, reponseA: reponseA)
        }
        .onAppear { de = Gmail.adresse ?? "" }
        .task {
            // Objet en « Re: » sans reponse_a : on retrouve dans Mail le dernier mail reçu de la personne.
            guard reponseA.isEmpty, Mail.estReponse(message.evenement.objet) else { return }
            if let id = try? await Mail.dernierRecu(de: message.contact.email, objet: message.evenement.objet) { reponseA = id }
        }
        .sheet(isPresented: $connexion, onDismiss: { de = Gmail.adresse ?? "" }) { ConnexionGmail() }
    }

    private func envoyer() async {
        envoi = true
        erreur = nil
        // 05/11 (T7) : relu dans la base juste avant l'envoi (une condition a pu être posée depuis l'ouverture de la feuille).
        if let e = try? etat.stock?.evenement(message.id), e.conditionEnAttente {
            erreur = Stockage.refusCondition(e)
            envoi = false
            return
        }
        do {
            let id = try await Gmail.envoyer(a: a.trimmingCharacters(in: .whitespaces), objet: objet, texte: texte,
                                             reponseA: reponseA)
            // Le fil garde le texte exact parti, l'objet, le mail auquel il répond et l'identifiant du mail ; le mail est parti :
            // on le note toujours (malgreCondition), jamais d'erreur après un envoi réel. Même écriture que `pilote envoie`.
            if let stock = etat.stock {
                try EnvoiPilote.finaliser(stock, evenementId: message.id, texte: texte, objet: objet, reponseA: reponseA, messageId: id)
            }
            if message.contact.email.isEmpty || message.contact.email.lowercased() != a.lowercased() {
                var c = message.contact
                if c.email.isEmpty { c.email = a; etat.enregistrer(c) }
            }
            etat.charger()
            fermer()
        } catch {
            erreur = "Le mail n'est pas parti : \(error.localizedDescription)"
            envoi = false
        }
    }
}

/// Connecter Gmail une fois : un mot de passe d'application créé par Sacha chez Google, rangé dans le trousseau du Mac.
struct ConnexionGmail: View {
    @Environment(\.dismiss) private var fermer
    @State private var adresse = Gmail.adresse ?? ""
    @State private var motDePasse = ""
    @State private var verification = false
    @State private var erreur: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connecter Gmail").font(.system(size: 19, weight: .semibold))
            Text("Pilote envoie vos mails depuis votre Gmail perso, jamais depuis un domaine que vous avez interdit (reglages.json). Il lui faut un mot de passe d'application, créé par vous chez Google. Il reste dans le trousseau de ce Mac.")
                .font(.secondaire).foregroundStyle(Color.texte2).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 6) {
                Text("1. Ouvrez la page Google des mots de passe d'application (la validation en deux étapes doit être active).").font(.secondaire)
                Button("Ouvrir la page Google") { NSWorkspace.shared.open(URL(string: "https://myaccount.google.com/apppasswords")!) }
                    .controlSize(.small)
                Text("2. Créez un mot de passe nommé « Pilote », copiez les 16 lettres.").font(.secondaire)
                Text("3. Collez-les ici.").font(.secondaire)
            }
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("Adresse").font(.secondaire).foregroundStyle(Color.texte2)
                    TextField("", text: $adresse, prompt: Text("vous@gmail.com")).textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Mot de passe").font(.secondaire).foregroundStyle(Color.texte2)
                    SecureField("", text: $motDePasse, prompt: Text("16 lettres")).textFieldStyle(.roundedBorder)
                }
            }
            if let erreur { EtatErreur(texte: erreur).background(Color.surface, in: RoundedRectangle(cornerRadius: 10)) }
            HStack {
                if Gmail.connecte {
                    Button("Déconnecter Gmail") { Gmail.deconnecter(); fermer() }.buttonStyle(.borderless).foregroundStyle(Color.texte2)
                }
                if verification { ProgressView().controlSize(.small); Text("Vérification auprès de Gmail…").font(.secondaire).foregroundStyle(Color.texte2) }
                Spacer()
                Button("Annuler") { fermer() }.keyboardShortcut(.cancelAction)
                Button("Vérifier et enregistrer") { Task { await connecter() } }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent).tint(.action)
                    .disabled(verification || !adresse.contains("@") || motDePasse.replacingOccurrences(of: " ", with: "").count < 16)
            }
        }
        .padding(22)
        .frame(width: 520)
        .task {
            if adresse.isEmpty, let c = try? await Mail.compteGmail() { adresse = c.adresse }
        }
    }

    private func connecter() async {
        verification = true
        erreur = nil
        do {
            try await Gmail.connecter(adresse: adresse.trimmingCharacters(in: .whitespaces), motDePasse: motDePasse)
            motDePasse = ""
            fermer()
        } catch {
            erreur = error.localizedDescription
            verification = false
        }
    }
}
