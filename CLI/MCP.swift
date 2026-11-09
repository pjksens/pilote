// `pilote mcp` : Pilote branché à Claude Code (serveur MCP sur l'entrée et la sortie standard).
// Toutes les sessions Claude Code de Sacha peuvent ainsi lire et enrichir Pilote en continu.
import Foundation

private let consignes = """
Pilote est le carnet de suivi de \(Moi.tiers) : tous ses contacts et tout son travail (KRYVA, freelance, autre), \
avec l'historique de chaque échange et la prochaine action. L'app Mac Pilote affiche ces données en direct.
Règles :
- Dès qu'une session apprend un fait sur une personne suivie (message envoyé par \(Moi.tiers), réponse reçue, appel, visite, \
rendez-vous pris, refus), l'ajouter au fil avec ajoute_au_fil, et mettre à jour l'étape et la prochaine action.
- Toujours chercher (cherche) avant de créer un contact, pour ne pas faire de doublon.
- N'inventer aucun fait : seulement ce que \(Moi.tiers) a dit ou ce qui a été vérifié.
- Un message à envoyer par \(Moi.tiers) se range avec statut « prepare », et seulement après que \(Moi.tiers) a validé le texte exact. \
Pilote n'envoie rien tout seul : pour un mail (canal « mail », avec un objet), \(Moi.tiers) clique « Envoyer depuis Gmail » dans l'app \
et le mail part de son Gmail perso ; ou il écrit « envoie » à PILOTE pour CE mail, après en avoir vu l'essai (outil envoie, \
essai puis envoi avec l'empreinte de l'essai) ; pour le reste, il envoie lui-même puis clique « Envoyé ».
- Un message qui ne doit partir qu'après quelque chose (un test, une réponse, une date) porte cette condition dans le champ condition (pas dans le texte) : l'app la montre en rouge et bloque l'envoi tant qu'elle n'est pas cochée. Le rappel qui la suit se lie au message avec rappel_id (identifiant ou titre exact du rappel) : Pilote le coche quand la condition est cochée.
- Mails : jamais depuis le domaine kryva.fr. Toujours un objet ; reponse_a (Message-ID) pour rester dans le fil d'un échange.
- « Ne plus contacter » (ne_plus_contacter) est définitif : ne jamais proposer de recontacter.
- Prochaine action : un geste de \(Moi.tiers) (appel, visio, rendez-vous, décision) commence par « \(Moi.tiers) : ». Tout le reste \
(attendre, vérifier, préparer un texte, relancer, classer) n'apparaît PAS chez \(Moi.tiers) : c'est la liste du jour de l'agent \
de l'espace (kryva → KRYVA · Ventes, freelance → FREELANCE, autre → PILOTE), lue avec jour et pour, traitée avant 9 h. \
Jamais une action « attendre » laissée à une date passée.
- Textes pour les artisans : au nom de l'équipe (« on », « nous »), en « vous », signés « \(Moi.tiers), de l'équipe KRYVA ».
Pilote est aussi la carte de tout l'espace de travail de \(Moi.tiers) (KRYVA, Krydor, freelance, projets perso, cours, papiers) :
- Avant de chercher un fichier ou un dossier, demander à Pilote : ou_est (projets, journal, contacts, fichiers) ou carte. \
Lire l'ETAT.md du projet (renvoyé par carte) avant de réexplorer ses fichiers : ça économise du temps et de l'usage.
- Ne créer aucun fichier en vrac (racine d'un dépôt, dossier personnel, Bureau, Téléchargements) : ranger dans le dossier \
du projet indiqué par la carte. Un nouveau dossier de travail s'ajoute à la carte avec enregistre_projet.
- La fin de chaque réponse de chaque session est notée toute seule dans le journal. Quand tu livres quelque chose \
(document, fichier, commit, décision), note-le avec note_au_journal en donnant les chemins. En fin de travail sur un projet, \
mets à jour son ETAT.md (15 lignes au plus : Fait, En cours, Prochaine étape, Fichiers clés).
- Avant de modifier des fichiers partagés, regarder agents : une autre session y travaille peut-être. \
Ne jamais déplacer ni renommer un dossier de travail sans l'accord de \(Moi.tiers).
"""

private let champsContact: [String: Any] = [
    "id": ["type": "string", "description": "Identifiant du contact à modifier. Absent : création (ou mise à jour si source + source_ref existent déjà)."],
    "espace": ["type": "string", "enum": ["kryva", "freelance", "autre"]],
    "type": ["type": "string", "enum": ["artisan", "comptable", "partenaire", "negoce", "syndicat", "client", "autre"]],
    "nom": ["type": "string", "description": "La personne (prénom et nom)."],
    "entreprise": ["type": "string"], "ville": ["type": "string"], "departement": ["type": "string"],
    "telephone": ["type": "string"], "email": ["type": "string"],
    "linkedin": ["type": "string", "description": "Adresse du profil LinkedIn (https://www.linkedin.com/in/…)."],
    "facebook": ["type": "string"], "site": ["type": "string"],
    "etape": ["type": "string", "enum": ["a_contacter", "contacte", "repondu", "rdv", "gagne", "perdu"]],
    "prochaine_action": ["type": "string", "description": "Ce qu'il faut faire ensuite, en une phrase."],
    "prochaine_date": ["type": "string", "description": "AAAA-MM-JJ, ou vide pour aucune date."],
    "priorite": ["type": "integer", "enum": [1, 2, 3], "description": "1 haute, 2 normale, 3 basse."],
    "ne_plus_contacter": ["type": "boolean"],
    "org_id": ["type": "string", "description": "Identifiant de l'entreprise inscrite sur KRYVA, si c'en est une."],
    "source": ["type": "string", "description": "D'où vient le contact (ex. « linkedin », « visite », « freelance »)."],
    "source_ref": ["type": "string"],
    "notes": ["type": "string", "description": "Remplace les notes : relire la fiche avant, et garder l'existant."],
]

private let outils: [[String: Any]] = [
    CarteDomaineCommande.outilMCP,
    ["name": "jour",
     "description": "Sans pour : toutes les fiches dues (ou en retard) et les messages préparés à envoyer. pour = sacha : ses gestes seulement (ce que l'app lui montre). pour = ventes, freelance ou pilote : la liste du jour de cet agent (fiches dues qui ne sont pas des gestes de \(Moi.tiers), fiches engagées sans date, consigne) : à traiter avant 9 h, rien ne reste dû le soir.",
     "inputSchema": ["type": "object", "properties": ["pour": ["type": "string", "enum": ["sacha", "ventes", "freelance", "pilote"]]]]],
    ["name": "cherche",
     "description": "Cherche des contacts par nom, entreprise, ville, e-mail, téléphone, profil LinkedIn ou identifiant.",
     "inputSchema": ["type": "object", "properties": ["texte": ["type": "string"]], "required": ["texte"]]],
    ["name": "fiche",
     "description": "Un contact et tout son fil (du plus récent au plus ancien).",
     "inputSchema": ["type": "object", "properties": ["id": ["type": "string"]], "required": ["id"]]],
    ["name": "contacts",
     "description": "Liste de contacts filtrée (100 au plus par défaut).",
     "inputSchema": ["type": "object", "properties": [
        "espace": ["type": "string", "enum": ["kryva", "freelance", "autre"]],
        "etape": ["type": "string", "enum": ["a_contacter", "contacte", "repondu", "rdv", "gagne", "perdu"]],
        "type": ["type": "string"],
        "limite": ["type": "integer"]]]],
    ["name": "enregistre_contact",
     "description": "Crée un contact ou modifie le contact existant (par id, sinon par source + source_ref). Seuls les champs fournis changent. Chercher avant de créer.",
     "inputSchema": ["type": "object", "properties": champsContact]],
    ["name": "ajoute_au_fil",
     "description": "Ajoute un événement au fil d'un contact. Un envoi (sens sortant, statut envoye ou fait) passe le contact à « Contacté », une réponse reçue (sens entrant) à « A répondu », sans jamais le faire reculer. statut « a_valider » = brouillon que \(Moi.tiers) lit et valide dans l'app (texte entier affiché, il peut le corriger) ; « prepare » = message dont \(Moi.tiers) a validé le texte exact, qu'il doit encore envoyer lui-même.",
     "inputSchema": ["type": "object", "properties": [
        "contact_id": ["type": "string"],
        "canal": ["type": "string", "enum": ["linkedin", "facebook", "instagram", "sms", "mail", "appel", "visite", "visio", "autre"]],
        "sens": ["type": "string", "enum": ["sortant", "entrant", "interne"]],
        "type": ["type": "string", "enum": ["invitation", "message", "reponse", "appel", "visite", "rdv", "note"]],
        "texte": ["type": "string", "description": "Le texte exact envoyé ou reçu, ou la note."],
        "statut": ["type": "string", "enum": ["a_valider", "prepare", "envoye", "echec", "fait"]],
        "par": ["type": "string", "description": "\(Moi.tiers) ou Claude (qui a fait ou préparé)."],
        "le": ["type": "string", "description": "Date ISO 8601 de l'événement si ce n'est pas maintenant."],
        "objet": ["type": "string", "description": "Mails : l'objet. Obligatoire pour qu'un mail préparé puisse partir depuis Pilote. DM Instagram : le pseudo « @… » du destinataire."],
        "reponse_a": ["type": "string", "description": "Mails : Message-ID du mail auquel on répond (le mail part dans le même fil)."],
        "condition": ["type": "string", "description": "Message prepare : ce qui doit être vrai avant l'envoi (« après le test de l'acompte sur un vrai devis »). L'envoi est bloqué tant qu'elle n'est pas cochée."],
        "rappel_id": ["type": "string", "description": "Le rappel (Rappels) lié au message : son identifiant (x-apple-reminder://… accepté) ou son titre exact. Coché par Pilote quand la condition l'est, ou à l'envoi s'il n'y a pas de condition."]],
        "required": ["contact_id", "canal", "sens", "type", "texte"]]],
    ["name": "modifie_evenement",
     "description": "Corrige un événement du fil avant envoi : texte, objet, reponse_a, canal, type, date, condition, rappel_id. condition_remplie (true) coche la condition d'un message préparé, seulement quand elle est vérifiée (par : qui l'a vérifiée).",
     "inputSchema": ["type": "object", "properties": [
        "evenement_id": ["type": "string"], "texte": ["type": "string"], "objet": ["type": "string"],
        "reponse_a": ["type": "string"], "canal": ["type": "string"], "type": ["type": "string"], "le": ["type": "string"],
        "condition": ["type": "string", "description": "Nouvelle condition (à recocher)."],
        "rappel_id": ["type": "string"],
        "condition_remplie": ["type": "boolean"],
        "par": ["type": "string", "description": "Avec condition_remplie : qui a vérifié (\(Moi.tiers), App…)."]],
        "required": ["evenement_id"]]],
    ["name": "carte",
     "description": "La carte de l'espace de travail : chaque projet avec son espace, son dossier, son dépôt, son site, ses documents clés, et le contenu de son ETAT.md s'il existe.",
     "inputSchema": ["type": "object", "properties": [
        "espace": ["type": "string", "enum": ["kryva", "krydor", "freelance", "perso", "outils", "cours", "administratif"]],
        "id": ["type": "string", "description": "Un seul projet (avec son journal récent)."]]]],
    ["name": "ou_est",
     "description": "Cherche partout : projets de la carte, journal des agents, contacts, et fichiers (Spotlight, par nom puis par contenu, dans les dossiers de la carte, Documents, Téléchargements et iCloud Drive).",
     "inputSchema": ["type": "object", "properties": ["texte": ["type": "string"]], "required": ["texte"]]],
    ["name": "enregistre_projet",
     "description": "Ajoute un projet à la carte ou le modifie (par id). Seuls les champs fournis changent. documents : une ligne par document, « Libellé : chemin ».",
     "inputSchema": ["type": "object", "properties": [
        "id": ["type": "string"], "espace": ["type": "string", "enum": ["kryva", "krydor", "freelance", "perso", "outils", "cours", "administratif"]],
        "nom": ["type": "string"], "description": ["type": "string", "description": "Une phrase : ce que c'est."],
        "dossier": ["type": "string"], "depot": ["type": "string"], "site": ["type": "string"],
        "statut": ["type": "string", "enum": ["actif", "en_pause", "archive"]],
        "documents": ["type": "string"], "notes": ["type": "string"], "ordre": ["type": "integer"]]]],
    ["name": "agents",
     "description": "Ce que font les sessions Claude Code en ce moment : nom, dossier, état (au travail, attend \(Moi.tiers), en pause), dernière action, étape en cours, dernier résumé.",
     "inputSchema": ["type": "object", "properties": [String: Any]()]],
    ["name": "pyramide",
     "description": "L'équipe de sessions Claude en arbre sur trois étages : PILOTE, les sessions de domaine, leurs chantiers. Pour chacune : état, poids du contexte, dernière action, signalements (À valider puis archiver, Relais). Hiérarchie lue dans EQUIPE.md.",
     "inputSchema": ["type": "object", "properties": [String: Any]()]],
    ["name": "journal",
     "description": "Les dernières entrées du journal des agents (ce que chaque session a fait), du plus récent au plus ancien.",
     "inputSchema": ["type": "object", "properties": [
        "limite": ["type": "integer"], "projet_id": ["type": "string"]]]],
    ["name": "note_au_journal",
     "description": "Note un livrable, une décision ou une note dans le journal de Pilote, avec les chemins des fichiers. La session et son dossier sont retrouvés tout seuls.",
     "inputSchema": ["type": "object", "properties": [
        "texte": ["type": "string", "description": "Ce qui a été fait ou décidé, en une ou deux phrases."],
        "fichiers": ["type": "array", "items": ["type": "string"], "description": "Chemins complets des fichiers livrés."],
        "type": ["type": "string", "enum": ["livrable", "note"]],
        "projet_id": ["type": "string"], "dossier": ["type": "string"]],
        "required": ["texte"]]],
    ["name": "radar",
     "description": "Le Radar (LECTURE SEULE) : veille de comptes, KRYVA = concurrents, perso = créateurs. Ratio d'un post = vues ÷ médiane des vues des AUTRES posts du compte (30 jours, au moins 5 autres, jamais deviné). action « top » (défaut) : classement des posts de 6 h à 24/48/72 h, Top 3 des pistes (ratio > 1), posts écartés avec la raison, avertissements (relevé ancien…). « comptes » : comptes suivis. « idees » : boîte à idées (source figée + brouillon). Les relevés se font avec la ligne de commande « pilote radar importe » ; les chiffres viennent du code, ne jamais les recalculer ni les inventer.",
     "inputSchema": ["type": "object", "properties": [
        "action": ["type": "string", "enum": ["top", "comptes", "idees"]],
        "espace": ["type": "string", "enum": ["kryva", "perso"], "description": "Absent : les deux espaces."],
        "fenetre": ["type": "integer", "enum": [24, 48, 72], "description": "Âge maximal des posts en heures (72 par défaut)."],
        "statut": ["type": "string", "enum": ["a_ecrire", "en_cours", "pret"], "description": "Pour « idees »."]]]],
    ["name": "marque",
     "description": "Change le statut d'un message préparé quand \(Moi.tiers) dit l'avoir envoyé (envoye), y avoir renoncé (annule) ou si l'envoi a échoué (echec). « envoye » pose aussi la suite à J+5 ouvrés. « a_valider » : texte réécrit après une consigne de \(Moi.tiers) (statut a_refaire), à lui remontrer.",
     "inputSchema": ["type": "object", "properties": [
        "evenement_id": ["type": "string"],
        "statut": ["type": "string", "enum": ["envoye", "annule", "echec", "a_valider"]],
        "malgre_condition": ["type": "boolean", "description": "Seulement si le message est DÉJÀ parti alors que sa condition n'était pas cochée : il passe à « envoye », le fil le note, le rappel lié reste ouvert."]],
        "required": ["evenement_id", "statut"]]],
    ["name": "a_envoyer",
     "description": "Les messages au statut « prepare » (texte validé par \(Moi.tiers), pas encore partis), du plus ancien au plus récent : id court, contact, canal, objet, début du texte, condition et son état (aucune, à cocher, cochée le …), jour d'envoi prévu, envoyable (l'outil envoie l'accepterait maintenant) et sinon les raisons. Lecture seule.",
     "inputSchema": ["type": "object", "properties": [
        "mail": ["type": "boolean", "description": "Seulement les mails (canal mail)."]]]],
    ["name": "envoie",
     "description": "Envoie UN mail préparé depuis le Gmail perso de \(Moi.tiers) (vous@exemple.fr), avec le même code que le bouton « Envoyer depuis Gmail » de l'app (objet en « Re: » et en-têtes de fil si reponse_a), puis le marque envoyé dans le fil (Message-ID gardé, suite J+5 posée). SEULEMENT quand \(Moi.tiers) a écrit « envoie » pour CE message dans son dernier message, après avoir vu l'essai : d'abord essai=true (montre exactement ce qui partirait : de, à, objet, fil, texte, empreinte ; rien envoyé ni écrit), le montrer à \(Moi.tiers) tel quel, puis envoyer avec empreinte = celle de l'essai (refus si le mail a changé depuis). Un seul mail par appel, jamais en lot. Refus, rien ne part : statut ≠ prepare ou déjà envoyé, canal ≠ mail, objet ou texte vide, condition pas cochée, « ne plus contacter », expéditeur ou destinataire en kryva.fr, Gmail non connecté ou mot de passe absent, trousseau pas encore autorisé pour l'outil (à faire une fois sur le Mac : pilote gmail-acces).",
     "inputSchema": ["type": "object", "properties": [
        "evenement_id": ["type": "string", "description": "L'id du message (complet, ou l'id court de a_envoyer)."],
        "essai": ["type": "boolean", "description": "true : montrer ce qui partirait, sans rien envoyer ni écrire."],
        "empreinte": ["type": "string", "description": "L'empreinte rendue par l'essai montré à \(Moi.tiers)."]],
        "required": ["evenement_id"]]],
    ["name": "videos",
     "description": "Les vidéos (règle de \(Moi.tiers) du 03/11 : 2 par jour du lundi au vendredi, 1 KRYVA + 1 perso, tournées et montées la veille ouvrée). Par défaut la semaine en cours (lundi à vendredi). Chaque vidéo : jour de publication, compte, sujet, statut, heure, prompteur, fiche, et le mot affiché à \(Moi.tiers) (affichage).",
     "inputSchema": ["type": "object", "properties": [
        "du": ["type": "string", "description": "AAAA-MM-JJ (défaut : lundi de la semaine en cours)."],
        "au": ["type": "string", "description": "AAAA-MM-JJ (défaut : vendredi de la semaine en cours)."],
        "reserve": ["type": "boolean", "description": "Ajoute les sujets de réserve (sans jour)."]]]],
    ["name": "stats_videos",
     "description": "Le suivi des vidéos postées (53 au 04/11). Chiffres lus en lecture seule dans reseaux-stats/stats.sqlite (une ligne = un post sur UN réseau) : relevés à 48 h et 7 jours, dernier relevé, rétention (r3s_pct = restés après 3 s, temps_moyen_s, vue_entier_pct), conversions de la période (PAR SOURCE ET PAR SEMAINE, jamais par vidéo) et les verdicts écrits par Réseaux (verdict_48h après le relevé à 48 h, verdict_7j après celui de 7 jours, avec l'analyse de fond), avec l'état de chaque palier (etat_48h, etat_7j : a_attendre, a_relever, a_juger, fait, manque). Les champs absents n'ont pas été relevés : ne rien inventer. Par défaut les vidéos visibles.",
     "inputSchema": ["type": "object", "properties": [
        "compte": ["type": "string", "description": "compte_id (tiktok_perso, tiktok_kryva, insta_perso, insta_kryva, youtube_kryva, linkedin_*, x_perso) ou « kryva » / « perso »."],
        "ref": ["type": "string", "description": "L'identifiant du post (TikTok, code Instagram…) pour une seule vidéo."],
        "sans_verdict": ["type": "boolean", "description": "Seulement les vidéos qui ont un relevé (48 h ou 7 j) dont le verdict reste à écrire."],
        "archivees": ["type": "boolean", "description": "Ajoute les vidéos masquées ou archivées."]]]],
    ["name": "releves_dus",
     "description": "Les relevés de vidéos postées à faire maintenant (état a_relever : 48 h ou 7 j après la publication, fenêtre ouverte) et les verdicts à écrire (a_juger : relevé fait, pas de verdict). Un relevé = lire le Studio / la page du post et l'ajouter à stats.sqlite avec stats.py ; ensuite verdict_video. tout=true ajoute le rattrapage (manque = fenêtre passée sans relevé, a_attendre = pas encore l'heure). C'est ce que la veille de Pilote signale à PILOTE après chaque publication.",
     "inputSchema": ["type": "object", "properties": [
        "tout": ["type": "boolean", "description": "Ajoute les relevés manqués, les verdicts en retard et les paliers à venir."]]]],
    ["name": "verdict_video",
     "description": "Écrit le verdict d'une vidéo postée POUR UN RELEVÉ : palier 48h (premier avis) puis 7j (l'analyse de fond). Clé = compte_id + ref de stats_videos + palier. verdict : marche | moyen | rate | trop_tot. pourquoi et lecon en une phrase chacun, appuyées sur les chiffres relevés ; analyse = le fond (au 7j surtout) : ce qui a marché ou non par rapport aux vidéos précédentes du compte, rétention, hypothèses. decrochage_s = la seconde où les gens décrochent (seulement si le Studio donne la courbe). base_releve_le = le relevé utilisé ; si palier manque, il s'en déduit. Seuls les champs fournis changent ; une vidéo inconnue de stats.sqlite est refusée.",
     "inputSchema": ["type": "object", "properties": [
        "compte_id": ["type": "string"], "ref": ["type": "string"],
        "palier": ["type": "string", "enum": ["48h", "7j"], "description": "Le relevé auquel répond ce verdict."],
        "verdict": ["type": "string", "enum": ["marche", "moyen", "rate", "trop_tot"]],
        "pourquoi": ["type": "string"], "lecon": ["type": "string"], "analyse": ["type": "string"],
        "decrochage_s": ["type": "number"], "decrochage_note": ["type": "string"],
        "base_releve_le": ["type": "string", "description": "AAAA-MM-JJTHH:MM du relevé sur lequel le verdict s'appuie."],
        "par": ["type": "string", "description": "Qui a écrit le verdict (ex. Réseaux)."]],
        "required": ["compte_id", "ref"]]],
    ["name": "enregistre_video",
     "description": "Crée ou modifie une vidéo : par id, sinon par (jour, compte). Seuls les champs fournis changent. statut : a_choisir (créneau sans sujet), valide (sujet validé par \(Moi.tiers), et SEULEMENT dans ce cas), tournee (rushes reçus, montage), prete (montée, contrôlée, à publier), publiee (\(Moi.tiers) l'a publiée), annulee. Jamais un samedi ni un dimanche. jour vide = sujet de réserve.",
     "inputSchema": ["type": "object", "properties": [
        "id": ["type": "string"],
        "jour": ["type": "string", "description": "AAAA-MM-JJ de publication (lundi à vendredi), vide pour la réserve."],
        "compte": ["type": "string", "enum": ["kryva", "perso"]],
        "sujet": ["type": "string", "description": "Le sujet en quelques mots, comme \(Moi.tiers) le dirait."],
        "statut": ["type": "string", "enum": ["a_choisir", "valide", "tournee", "prete", "publiee", "annulee"]],
        "heure": ["type": "string", "description": "HH:MM de publication."],
        "prompteur": ["type": "string", "description": "Chemin complet ou adresse du prompteur (ouvert d'un clic par \(Moi.tiers))."],
        "fiche": ["type": "string", "description": "Chemin complet de la fiche du sujet."],
        "notes": ["type": "string"]]]],
    ["name": "publications",
     "description": "Les publications programmées par Pilote (YouTube @sachaprljk et @kryva_app, Instagram @sachaprljk et @kryva.fr, TikTok perso et KRYVA) et l'état des 6 comptes. statut : a_valider (proposée, rien ne part), prevu, envoi, envoye (YouTube : privée chez YouTube, publiée seule à l'heure ; Instagram : vidéo chez Instagram, publiée par Pilote à l'heure ; TikTok : brouillon dans la boîte TikTok, \(Moi.tiers) le publie depuis l'app en collant la légende), publie, echec (raison), a_reconnecter (un clic de \(Moi.tiers) dans Pilote › Publications), annule.",
     "inputSchema": ["type": "object", "properties": [
        "jours": ["type": "integer", "description": "Les terminées des N derniers jours (défaut 30)."]]]],
    ["name": "programme_publication",
     "description": "PROPOSE une publication (statut a_valider) : rien ne part tant que \(Moi.tiers) ne l'a pas validée. Une ligne par compte. Rend pour chaque ligne le bloc exact à montrer à \(Moi.tiers) (compte, heure, vidéo, titre, texte, empreinte). Refus clairs : heure à moins de 15 min ou à plus de 6 mois, fichier absent, format, titre YouTube vide ou > 100 caractères, légende > 2 200, déjà programmée. Contenu : Réseaux ; jamais un texte que \(Moi.tiers) n'a pas vu.",
     "inputSchema": ["type": "object", "properties": [
        "comptes": ["type": "array", "items": ["type": "string", "enum": ["yt-perso", "yt-kryva", "ig-perso", "ig-kryva", "tt-perso", "tt-kryva"]]],
        "fichier": ["type": "string", "description": "Chemin complet de la vidéo (.mp4 ou .mov, verticale)."],
        "titre": ["type": "string", "description": "YouTube : le titre (100 caractères au plus). Ignoré pour Instagram et TikTok."],
        "texte": ["type": "string", "description": "YouTube : la description. Instagram : la légende. TikTok : la légende que \(Moi.tiers) colle dans l'app (l'API ne la transmet pas)."],
        "le": ["type": "string", "description": "AAAA-MM-JJ HH:MM, heure de Paris."],
        "ia": ["type": "boolean", "description": "Contenu réaliste généré ou modifié par IA (YouTube l'affiche)."],
        "couverture": ["type": "string", "description": "Chemin d'une image de couverture (.jpg ou .png). YouTube : miniature posée après le traitement. Instagram : l'API ne la prend pas (serveur public), donner aussi couverture_a. TikTok : \(Moi.tiers) la choisit dans l'app."],
        "couverture_a": ["type": "number", "description": "Instant de la vidéo (secondes) pris comme couverture : Instagram thumb_offset ; YouTube et le planning : cette image si aucune image n'est donnée."],
        "par": ["type": "string", "description": "Qui propose (ex. Réseaux)."]],
        "required": ["comptes", "fichier", "le"]]],
    ["name": "valide_publication",
     "description": "Valide une publication proposée. SEULEMENT après le « oui » explicite de \(Moi.tiers) au bloc exact rendu par programme_publication (vidéo comprise), avec son empreinte : si quoi que ce soit a changé, refusé. Ensuite elle part seule à l'heure.",
     "inputSchema": ["type": "object", "properties": [
        "id": ["type": "string"], "empreinte": ["type": "string"],
        "par": ["type": "string", "description": "Ex. « \(Moi.tiers) via PILOTE »."]],
        "required": ["id", "empreinte"]]],
    ["name": "annule_publication",
     "description": "Annule une publication pas encore publiée (YouTube déjà envoyée : la vidéo privée est supprimée de YouTube). Une publiée se retire dans l'app du réseau.",
     "inputSchema": ["type": "object", "properties": [
        "id": ["type": "string"], "par": ["type": "string"]],
        "required": ["id"]]],
    ["name": "publiee_publication",
     "description": "Note à la main qu'un brouillon TikTok (envoyé, dans la boîte) a été publié par \(Moi.tiers) dans l'app TikTok, quand la passe ne l'a pas vu. Refusé pour toute autre publication. Lien facultatif : https://www.tiktok.com/…",
     "inputSchema": ["type": "object", "properties": [
        "id": ["type": "string"], "lien": ["type": "string"], "par": ["type": "string"]],
        "required": ["id"]]],
]

private func jsonTexte(_ valeur: Encodable) -> String {
    let enc = JSONEncoder()
    enc.keyEncodingStrategy = .convertToSnakeCase
    enc.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return String(data: (try? enc.encode(AnyEncodable(valeur))) ?? Data("null".utf8), encoding: .utf8) ?? "null"
}

private func ecrire(_ objet: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: objet, options: [.withoutEscapingSlashes]) else { return }
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
}

private func appeler(_ nom: String, _ a: [String: Any], _ stock: Stockage) throws -> String {
    switch nom {
    case "jour":
        let pour = a["pour"] as? String ?? ""
        if let r = Responsable(rawValue: pour), r != .sacha {
            let l = try stock.listeAgent(r)
            try stock.noterListe(l)   // gardée pour le suivi « Les agents aujourd'hui »
            return jsonTexte(l)
        }
        let envois = try stock.aEnvoyer().map { AEnvoyer(evenement: $0.0, contact: $0.1) }
        return jsonTexte(Jour(date: Dates.aujourdhui(), dus: try pour == "sacha" ? stock.dusSacha() : stock.dus(), aEnvoyer: envois))
    case "cherche":
        return jsonTexte(try stock.chercher(a["texte"] as? String ?? ""))
    case "fiche":
        guard let id = a["id"] as? String, let c = try stock.contact(id) else { throw ErreurBase(description: "Contact introuvable") }
        return jsonTexte(Fiche(contact: c, evenements: try stock.evenements(c.id)))
    case "contacts":
        var liste = try stock.contacts()
        if let e = a["espace"] as? String { liste = liste.filter { $0.espace == e } }
        if let e = a["etape"] as? String { liste = liste.filter { $0.etape == e } }
        if let t = a["type"] as? String { liste = liste.filter { $0.type == t } }
        return jsonTexte(Array(liste.prefix(a["limite"] as? Int ?? 100)))
    case "enregistre_contact":
        return jsonTexte(try stock.enregistrer(a))
    case "ajoute_au_fil":
        guard let id = a["contact_id"] as? String else { throw ErreurBase(description: "contact_id manquant") }
        var champs = a
        champs.removeValue(forKey: "contact_id")
        if champs["par"] == nil { champs["par"] = "Claude" }
        return jsonTexte(try stock.ajouterEvenement(contactId: id, champs))
    case "modifie_evenement":
        guard let id = a["evenement_id"] as? String else { throw ErreurBase(description: "evenement_id manquant") }
        try stock.modifierEvenement(id, a)
        guard let e = try stock.evenement(id) else { throw ErreurBase(description: "Événement introuvable") }
        return jsonTexte(e)
    case "marque":
        guard let id = a["evenement_id"] as? String, let s = a["statut"] as? String else { throw ErreurBase(description: "evenement_id et statut requis") }
        try stock.marquer(evenementId: id, statut: s, malgreCondition: a["malgre_condition"] as? Bool ?? false)
        return "{\"ok\": true}"
    case "a_envoyer":
        var lignes = try EnvoiPilote.aEnvoyer(stock, outils: try OutilsEnvoi.selonEnvironnement())
        if a["mail"] as? Bool == true { lignes = lignes.filter { $0.canal == "mail" } }
        return jsonTexte(lignes)
    case "envoie":
        guard let id = a["evenement_id"] as? String else { throw ErreurBase(description: "evenement_id manquant") }
        do {
            return jsonTexte(try EnvoiPilote.envoyer(id, stock: stock, outils: try OutilsEnvoi.selonEnvironnement(),
                                                     essai: a["essai"] as? Bool ?? false, empreinte: a["empreinte"] as? String))
        } catch {
            throw ErreurBase(description: EnvoiPilote.messageErreur(error))
        }
    case "carte":
        if let id = a["id"] as? String {
            guard let p = try stock.projet(id) else { throw ErreurBase(description: "Projet introuvable") }
            return jsonTexte(FicheProjet(projet: p, etat: p.lireEtat() ?? "", journal: try stock.journal(limite: 15, projetId: id)))
        }
        var liste = try stock.projets()
        if let e = a["espace"] as? String { liste = liste.filter { $0.espace == e } }
        return jsonTexte(liste.map { FicheProjet(projet: $0, etat: $0.lireEtat() ?? "", journal: nil) })
    case "ou_est":
        return jsonTexte(try stock.chercherPartout(a["texte"] as? String ?? ""))
    case "enregistre_projet":
        return jsonTexte(try stock.enregistrerProjet(a))
    case "agents":
        return jsonTexte(Sessions.vivantes())
    case "pyramide":
        return Equipe.texte(Equipe.pyramide())
    case "journal":
        return jsonTexte(try stock.journal(limite: a["limite"] as? Int ?? 30, projetId: a["projet_id"] as? String))
    case "note_au_journal":
        return jsonTexte(try noterAuJournal(stock, a))
    case "carte_domaine":
        return jsonTexte(try CarteDomaineCommande.appelerMCP(stock, a))
    case "radar":
        let espace = a["espace"] as? String
        if let e = espace, !RadarVocabulaire.espaces.contains(e) { throw ErreurRadar.invalide("espace inconnu « \(e) » (kryva ou perso)") }
        switch a["action"] as? String ?? "top" {
        case "comptes":
            return jsonTexte(try stock.radarComptes(espace: espace))
        case "idees":
            return jsonTexte(try stock.radarIdees(espace: espace, statut: a["statut"] as? String))
        case "top":
            let h = (a["fenetre"] as? Int).map(Double.init) ?? RadarCalcul.fenetreParDefaut.upperBound
            guard [24.0, 48, 72].contains(h) else { throw ErreurRadar.invalide("fenetre : 24, 48 ou 72") }
            let fenetre = RadarCalcul.fenetreParDefaut.lowerBound...h
            return jsonTexte(try (espace.map { [$0] } ?? RadarVocabulaire.espaces).map { try stock.radarClassement(espace: $0, fenetre: fenetre) })
        default:
            throw ErreurRadar.invalide("action inconnue (top, comptes, idees)")
        }
    case "videos":
        return jsonTexte(try videosAffichees(stock, du: a["du"] as? String, au: a["au"] as? String, reserve: a["reserve"] as? Bool ?? false))
    case "enregistre_video":
        return jsonTexte(try stock.enregistrerVideo(a))
    case "stats_videos":
        return jsonTexte(try SuiviVideo.liste(stock: stock, compte: a["compte"] as? String, ref: a["ref"] as? String,
                                              sansVerdict: a["sans_verdict"] as? Bool ?? false, archivees: a["archivees"] as? Bool ?? false))
    case "releves_dus":
        return jsonTexte(try SuiviVideo.dus(stock: stock, tout: a["tout"] as? Bool ?? false))
    case "verdict_video":
        return jsonTexte(try stock.enregistrerVerdict(a))
    case "publications":
        return jsonTexte(try PublicationCommande.liste(stock, jours: a["jours"] as? Int ?? 30))
    case "programme_publication":
        do {
            return jsonTexte(try PublicationCommande.proposer(stock, comptes: a["comptes"] as? [String] ?? [], fichier: a["fichier"] as? String ?? "",
                                                              titre: a["titre"] as? String ?? "", texte: a["texte"] as? String ?? "",
                                                              le: a["le"] as? String ?? "", ia: a["ia"] as? Bool ?? false,
                                                              par: a["par"] as? String ?? "session",
                                                              couverture: a["couverture"] as? String ?? "",
                                                              couvertureA: (a["couverture_a"] as? NSNumber)?.doubleValue))
        } catch let e as RefusPublication { throw ErreurBase(description: e.description) }
    case "valide_publication":
        do {
            let p = try Publications.valider(stock, id: a["id"] as? String ?? "", empreinte: a["empreinte"] as? String ?? "",
                                             par: a["par"] as? String ?? "\(Moi.tiers) (via session)")
            if !FileEnvoi.surCopie() { Publications.reveillerAgent() }
            return jsonTexte(PublicationCommande.affichee(p))
        } catch let e as RefusPublication { throw ErreurBase(description: e.description) }
    case "annule_publication":
        do {
            return jsonTexte(PublicationCommande.affichee(try Publications.annuler(stock, id: a["id"] as? String ?? "", par: a["par"] as? String ?? "session",
                                                                                   plateformes: PlateformesReelles())))
        } catch let e as RefusPublication { throw ErreurBase(description: e.description) }
        catch let e as ErreurPlateforme { throw ErreurBase(description: "YouTube : \(e.description)") }
    case "publiee_publication":
        do {
            return jsonTexte(PublicationCommande.affichee(try Publications.marquerPubliee(stock, id: a["id"] as? String ?? "", lien: a["lien"] as? String ?? "",
                                                                                          par: a["par"] as? String ?? "session")))
        } catch let e as RefusPublication { throw ErreurBase(description: e.description) }
    default:
        throw ErreurBase(description: "Outil inconnu : \(nom)")
    }
}

func serveurMCP(_ stock: Stockage) {
    while let ligne = readLine(strippingNewline: true) {
        guard !ligne.isEmpty, let data = ligne.data(using: .utf8),
              let msg = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let methode = msg["method"] as? String else { continue }
        let id = msg["id"]
        let params = msg["params"] as? [String: Any] ?? [:]
        guard let id else { continue } // notification (ex. notifications/initialized) : pas de réponse
        switch methode {
        case "initialize":
            ecrire(["jsonrpc": "2.0", "id": id, "result": [
                "protocolVersion": params["protocolVersion"] as? String ?? "2025-06-18",
                "capabilities": ["tools": [String: Any]()],
                "serverInfo": ["name": "pilote", "version": "1.0"],
                "instructions": consignes,
            ]])
        case "ping":
            ecrire(["jsonrpc": "2.0", "id": id, "result": [String: Any]()])
        case "tools/list":
            ecrire(["jsonrpc": "2.0", "id": id, "result": ["tools": outils]])
        case "tools/call":
            let nom = params["name"] as? String ?? ""
            let args = params["arguments"] as? [String: Any] ?? [:]
            do {
                let texte = try appeler(nom, args, stock)
                ecrire(["jsonrpc": "2.0", "id": id, "result": ["content": [["type": "text", "text": texte]]]])
            } catch {
                ecrire(["jsonrpc": "2.0", "id": id, "result": ["content": [["type": "text", "text": "Erreur : \(error)"]], "isError": true]])
            }
        default:
            ecrire(["jsonrpc": "2.0", "id": id, "error": ["code": -32601, "message": "Méthode inconnue : \(methode)"]])
        }
    }
}
