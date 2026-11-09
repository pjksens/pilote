import XCTest

/// 05/11, chantier A « ne rien cacher » : tri du capteur (Shared/TriEntrants.swift, Shared/ExpediteurAuto.swift).
/// Noms et adresses fictifs.
final class TriEntrantsTests: XCTestCase {

    private func mail(_ adresse: String, nom: String = "", objet: String = "", texte: String = "",
                      listeId: Bool = false, reponseEnvoi: String = "") -> EntMessage {
        var m = EntMessage(canal: "mail", ref: "mail:1", date: Date())
        m.adresse = adresse.lowercased()
        m.mails = [m.adresse]
        m.objet = objet
        m.texte = texte
        m.reponseEnvoi = reponseEnvoi
        TriMail.preparer(&m, commentaire: nom, listeId: listeId)
        return m
    }

    private func contact(_ id: String, nom: String = "", email: String = "", tel: String = "") -> Contact {
        var c = Contact(id: id)
        c.nom = nom; c.email = email; c.telephone = tel
        return c
    }

    // MARK: T1 : un nom connu n'est jamais masqué

    func testMessageLinkedInDUnContactConnuEstTravail() {
        let a = EntAnnuaire(contacts: [contact("n1", nom: "Nadia Martin")])
        let m = mail("messaging-digest-noreply@linkedin.com", nom: "Nadia Martin via LinkedIn", objet: "Nadia vient de vous envoyer un message")
        XCTAssertEqual(m.affiche, "Nadia Martin")
        XCTAssertEqual(m.plateforme, "LinkedIn")
        XCTAssertTrue(m.linkedin)
        XCTAssertFalse(m.signalSeul)
        let r = a.classer(m)
        XCTAssertEqual(r.classe, "travail")
        XCTAssertEqual(r.contact?.id, "n1")
        XCTAssertEqual(r.via, "nom")
        XCTAssertFalse(TriMail.masquer(m, classe: r.classe, via: r.via))
    }

    func testMessageLinkedInDUnInconnuEstMontre() {
        let m = mail("messages-noreply@linkedin.com", nom: "Jules Bernard via LinkedIn", objet: "Jules vous a envoyé un message")
        XCTAssertEqual(m.plateforme, "LinkedIn")
        let r = EntAnnuaire(contacts: []).classer(m)
        XCTAssertEqual(r.classe, "inconnu")
        XCTAssertFalse(TriMail.masquer(m, classe: r.classe, via: r.via))
    }

    func testOffresEtSuggestionsLinkedInRestentMasquees() {
        let a = EntAnnuaire(contacts: [])
        for (adr, objet) in [("jobalerts-noreply@linkedin.com", "Lead AI engineer chez Exemple"),
                             ("messages-noreply@linkedin.com", "👤 Quelqu’un de Exemple que vous connaissez peut-être"),
                             ("messages-noreply@linkedin.com", "43 personnes ont consulté votre profil"),
                             ("jobs-noreply@linkedin.com", "Exemple recrute au poste de CTO")] {
            let m = mail(adr, nom: "LinkedIn", objet: objet)
            XCTAssertEqual(m.plateforme, "", objet)
            let r = a.classer(m)
            XCTAssertTrue(TriMail.masquer(m, classe: r.classe, via: r.via), objet)
        }
    }

    func testInvitationDUnContactConnuEstUneNoteSansRepondre() {
        let a = EntAnnuaire(contacts: [contact("e1", nom: "Edgar Durand")])
        let m = mail("invitations@linkedin.com", nom: "Edgar Durand", objet: "Je souhaite que nous nous connections")
        XCTAssertEqual(m.plateforme, "")
        XCTAssertTrue(m.linkedin)
        XCTAssertTrue(m.signalSeul)          // fil : note, pas d'action « Répondre à »
        let r = a.classer(m)
        XCTAssertEqual(r.classe, "travail")
        XCTAssertEqual(r.contact?.id, "e1")
    }

    func testNomPorteParDeuxFichesResteVisible() {
        let a = EntAnnuaire(contacts: [contact("f1", nom: "Florent Mercier"), contact("f2", nom: "Florent Mercier")])
        let m = mail("invitations@linkedin.com", nom: "Florent Mercier", objet: "Florent a accepté votre invitation")
        let r = a.classer(m)
        XCTAssertEqual(r.classe, "inconnu")
        XCTAssertEqual(r.via, "nom ambigu")
        XCTAssertNil(r.contact)
        XCTAssertFalse(TriMail.masquer(m, classe: r.classe, via: r.via))
    }

    // MARK: T1 : plateformes suivies en ligne courte, jamais masquées

    func testPlateformesSuivies() {
        let cas: [(String, String, String)] = [
            ("noreply-play-console@google.com", "Action requise pour votre compte", "Google Play Console"),
            ("no_reply@email.apple.com", "App Store Connect: The status of your app has changed", "App Store Connect"),
            ("testflight_no_reply@email.apple.com", "Build 12 disponible", "App Store Connect"),
            ("notifications@stripe.com", "Paiement reçu", "Stripe"),
            ("no-reply@resend.com", "Domain verified", "Resend"),
            ("noreply@mail.supabase.io", "Your project is paused", "Supabase"),
            ("noreply@md.getsentry.com", "New issue", "Sentry"),
            ("nepasrepondre@email.urssaf.fr", "Votre déclaration", "Administratif"),
            ("noreply@doctolib.fr", "Nouveau document", "Santé"),
            ("security@mail.exemple.com", "Nouvelle connexion à votre compte", "Action requise"),
        ]
        let a = EntAnnuaire(contacts: [])
        for (adr, objet, attendu) in cas {
            let m = mail(adr, objet: objet)
            XCTAssertEqual(m.plateforme, attendu, adr)
            let r = a.classer(m)
            XCTAssertNotEqual(r.classe, "ignore", adr)
            XCTAssertFalse(TriMail.masquer(m, classe: r.classe, via: r.via), adr)
        }
    }

    func testUnHumainNAPasDePlateforme() {
        // Le support Supabase qui répond : ligne ENTRANT complète, pas la ligne courte.
        let m = mail("support@supabase.com", nom: "Supabase Support", objet: "Dashboard login loop")
        XCTAssertEqual(m.plateforme, "")
        let r = EntAnnuaire(contacts: []).classer(m)
        XCTAssertEqual(r.classe, "inconnu")
        XCTAssertFalse(TriMail.masquer(m, classe: r.classe, via: r.via))
    }

    func testReponseAUnEnvoiJamaisMasquee() {
        let m = mail("notifications@exemple.fr", objet: "Re: Votre devis", reponseEnvoi: "fil")
        let r = EntAnnuaire(contacts: []).classer(m)
        XCTAssertEqual(r.classe, "inconnu")            // jamais « ignore » pour un en-tête automatique
        XCTAssertFalse(TriMail.masquer(m, classe: r.classe, via: r.via))
    }

    // MARK: T40 : une autre adresse de la même entreprise

    func testDomaineDUneSeuleFiche() {
        let a = EntAnnuaire(contacts: [contact("b1", nom: "Paul Bois", email: "paul@atelier-bois.fr")])
        let r = a.classer(mail("compta@atelier-bois.fr", nom: "Compta Atelier"))
        XCTAssertEqual(r.classe, "travail")
        XCTAssertEqual(r.contact?.id, "b1")
        XCTAssertEqual(r.via, "domaine")
    }

    func testDomaineGeneriquePartageOuAutomatiqueNeComptePas() {
        let a = EntAnnuaire(contacts: [contact("g1", nom: "Anne Lambert", email: "anne@gmail.com"),
                                       contact("d1", nom: "Luc Petit", email: "luc@deux-fiches.fr"),
                                       contact("d2", nom: "Eva Petit", email: "eva@deux-fiches.fr"),
                                       contact("b1", nom: "Paul Bois", email: "paul@atelier-bois.fr")])
        XCTAssertNotEqual(a.classer(mail("quelquun@gmail.com", nom: "Quelqu Un")).classe, "travail")
        XCTAssertNotEqual(a.classer(mail("contact@deux-fiches.fr", nom: "Accueil Deux")).classe, "travail")
        XCTAssertNotEqual(a.classer(mail("newsletter@atelier-bois.fr", nom: "Atelier Bois")).via, "domaine")
        XCTAssertNotEqual(a.classer(mail("news@atelier-bois.fr", listeId: true)).via, "domaine")
    }

    // MARK: T26 : un mail de Sacha non remis

    func testRebondRetrouveLaFiche() {
        let a = EntAnnuaire(contacts: [contact("b1", nom: "Paul Bois", email: "paul@atelier-bois.fr")])
        let m = mail("mailer-daemon@googlemail.com", nom: "Mail Delivery Subsystem", objet: "Delivery Status Notification (Failure)",
                     texte: "Address not found. Your message wasn't delivered to paul@atelier-bois.fr")
        XCTAssertTrue(m.rebond)
        XCTAssertEqual(m.rebondPour, ["paul@atelier-bois.fr"])
        let r = a.classer(m)
        XCTAssertEqual(r.classe, "inconnu")
        XCTAssertEqual(r.via, "rebond")
        XCTAssertEqual(r.contact?.id, "b1")
        XCTAssertFalse(TriMail.masquer(m, classe: r.classe, via: r.via))
        XCTAssertTrue(mail("postmaster@outlook.com", objet: "Non remis : Votre devis").rebond)
        XCTAssertFalse(mail("paul@atelier-bois.fr", objet: "Votre devis").rebond)
    }

    // MARK: T38 : groupes WhatsApp suivis

    func testGroupeSuivi() {
        var a = EntAnnuaire(contacts: [])
        a.groupesSuivis = ["plugkit"]
        var g = EntMessage(canal: "whatsapp", ref: "whatsapp:1", date: Date())
        g.groupe = true
        g.nomGroupe = "PlugKit · Créateurs"
        XCTAssertEqual(a.classer(g).classe, "inconnu")
        XCTAssertEqual(a.classer(g).via, "groupe suivi")
        g.nomGroupe = "Famille"
        XCTAssertEqual(a.classer(g).classe, "ignore")
    }

    // MARK: T14 : un numéro à qui Sacha a envoyé le texte d'une fiche

    func testNumeroSuiviApresUnEnvoi() {
        let paul = contact("p1", nom: "Paul Exemple")
        var a = EntAnnuaire(contacts: [paul])
        let cle = EntNorm.tel("+33 6 12 34 56 78")!
        a.suivis[cle] = EntSuivi(contactId: "p1", nom: "Paul Exemple", le: "2026-11-05T09:00:00Z")
        var m = EntMessage(canal: "whatsapp", ref: "whatsapp:2", date: Date())
        m.tels = [cle]
        m.texte = "Merci, je regarde ça"
        let r = a.classer(m)
        XCTAssertEqual(r.classe, "travail")
        XCTAssertEqual(r.contact?.id, "p1")
        XCTAssertEqual(r.via, "envoi")
        a.suivis[cle] = EntSuivi(contactId: "", nom: "", le: "2026-11-05T09:00:00Z")
        XCTAssertEqual(a.classer(m).classe, "inconnu")
        XCTAssertEqual(a.classer(m).via, "envoi")
    }

    // MARK: T47 : messages écartés, gardés 14 jours

    func testLigneEcartee() {
        var m = mail("hello@exemple.fr", nom: "Exemple", objet: "Une très longue annonce", texte: String(repeating: "abc ", count: 40))
        m.ref = "mail:9"
        let l = Ecartes.ligne(m, classe: "ignore", via: "automatique")
        XCTAssertEqual(l["ref"] as? String, "mail:9")
        XCTAssertEqual(l["classe"] as? String, "ignore")
        XCTAssertEqual(l["via"] as? String, "automatique")
        XCTAssertEqual(l["adresse"] as? String, "hello@exemple.fr")
        let extrait = l["extrait"] as? String ?? ""
        XCTAssertTrue(extrait.hasPrefix("Une très longue annonce · abc"))
        XCTAssertLessThanOrEqual(extrait.count, 61)
    }

    func testPurgeDesEcartes() {
        let maintenant = Date()
        func l(_ jours: Double) -> String {
            "{\"heure\":\"\(Ecartes.heure.string(from: maintenant.addingTimeInterval(-jours * 86400)))\",\"ref\":\"x\"}"
        }
        let gardees = Ecartes.purger([l(15), l(13), l(0), "illisible", ""], maintenant: maintenant)
        XCTAssertEqual(gardees, [l(13), l(0), "illisible"])
    }

    // MARK: ExpediteurAuto : règles LinkedIn

    func testReglesLinkedIn() {
        XCTAssertEqual(ExpediteurAuto.nomViaLinkedIn("Nadia Martin via LinkedIn"), "Nadia Martin")
        XCTAssertEqual(ExpediteurAuto.nomViaLinkedIn("Nadia Martin (via LinkedIn)"), "Nadia Martin")
        XCTAssertNil(ExpediteurAuto.nomViaLinkedIn("Nadia Martin"))
        XCTAssertTrue(ExpediteurAuto.messageLinkedIn(adresse: "messages-noreply@linkedin.com", nom: "Nadia Martin via LinkedIn", objet: "Nadia vous a écrit"))
        XCTAssertTrue(ExpediteurAuto.messageLinkedIn(adresse: "inmail-hit-reply@linkedin.com", nom: "", objet: "Une opportunité"))
        XCTAssertFalse(ExpediteurAuto.messageLinkedIn(adresse: "invitations@linkedin.com", nom: "Nadia Martin", objet: "Invitation"))
        XCTAssertFalse(ExpediteurAuto.messageLinkedIn(adresse: "jobalerts-noreply@linkedin.com", nom: "", objet: "Nouveau message de recruteur"))
        XCTAssertFalse(ExpediteurAuto.messageLinkedIn(adresse: "nadia@exemple.fr", nom: "Nadia Martin via LinkedIn", objet: "message"))
    }

    // MARK: T13 : Indésirables

    func testIndesirableSansFicheNiPlateformeEstEcarte() {
        var m = mail("quelquun@exemple.fr", nom: "Quelqu Un", objet: "Bonjour")
        m.indesirable = true
        XCTAssertFalse(TriMail.garderIndesirable(m, contact: nil))
    }

    func testIndesirableDUnContactConnuEstMontre() {
        var m = mail("nadia@exemple.fr", nom: "Nadia Martin", objet: "Bonjour")
        m.indesirable = true
        let c = contact("n1", nom: "Nadia Martin", email: "nadia@exemple.fr")
        XCTAssertTrue(TriMail.garderIndesirable(m, contact: EntAnnuaire(contacts: [c]).classer(m).contact))
    }

    func testIndesirableDUnePlateformeSuivieEstMontre() {
        var m = mail("noreply-play-developer-console@google.com", nom: "Google Play Console", objet: "Déclarez votre statut de professionnel")
        m.indesirable = true
        XCTAssertFalse(m.plateforme.isEmpty)
        XCTAssertTrue(TriMail.garderIndesirable(m, contact: nil))
    }

    func testMailHorsIndesirablesJamaisEcarte() {
        let m = mail("quelquun@exemple.fr", nom: "Quelqu Un")
        XCTAssertTrue(TriMail.garderIndesirable(m, contact: nil))
    }
}
