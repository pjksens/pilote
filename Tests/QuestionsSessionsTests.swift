// Tests des questions de session (03/11) : la question et les boutons du wrap_up deviennent une décision dans Pilote ;
// la réponse porte la session (« session ») et sa ref, pour n'être affichée et remise qu'une fois.
import XCTest

final class QuestionsSessionsTests: XCTestCase {
    private func tour(_ entree: [String: Any], uuid: String = "u-2") -> [[String: Any]] {
        [
            ["type": "user", "message": ["content": "Fais le point"]],
            ["type": "assistant", "uuid": uuid, "message": ["content": [
                ["type": "tool_use", "name": "mcp__ccd_turn__wrap_up", "input": entree],
            ]]],
        ]
    }

    func testQuestionEtBoutonsDuWrapUp() {
        let r = Sessions.resumer(tour(["recap": "Fait.", "ask": " On envoie la relance ? ",
                                       "actions": [["label": "Oui, envoie"], ["action": "commit"], ["label": ""]]]))
        XCTAssertEqual(r.question, "On envoie la relance ?")
        XCTAssertEqual(r.choix, ["Oui, envoie", "Commit"])
        XCTAssertEqual(r.questionUuid, "u-2")
    }

    func testSansQuestionPasDeDecision() {
        let r = Sessions.resumer(tour(["recap": "Fait.", "actions": [["label": "Oui"]]]))
        XCTAssertEqual(r.question, "")
        XCTAssertEqual(r.choix, [])
    }

    func testNouvelleDemandeEffaceLaQuestion() {
        var l = tour(["recap": "Fait.", "ask": "On y va ?", "actions": [["label": "Oui"]]])
        l.append(["type": "user", "message": ["content": "Oui, vas-y"]])
        XCTAssertEqual(Sessions.resumer(l).question, "")
    }

    func testLigneDecisionAvecSession() throws {
        let l = Decisions.ligne(question: "On y va ?", choix: "Oui", ref: "session:abc:u-2", liste: "Sessions", heure: Date(),
                                pour: "FREELANCE", session: "local_0000aaaa")
        let o = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(l.utf8)) as? [String: String])
        XCTAssertEqual(o["session"], "local_0000aaaa")
        XCTAssertEqual(o["pour"], "FREELANCE")
        // Sans session : le format du contrat ne change pas.
        let sans = Decisions.ligne(question: "Q", choix: "C", ref: "r", liste: "Contenu", heure: Date())
        XCTAssertFalse(sans.contains("\"session\""))
    }

    func testQuestionsRepondues() throws {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("questions-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: d) }
        try Decisions.noter(question: "On y va ?", choix: "Oui", ref: "session:abc:u-2", liste: "Sessions", pour: "FREELANCE",
                            session: "local_x", dossier: d)
        try Decisions.noter(question: "Q", choix: "C", ref: "rappel-1", liste: "Contenu", dossier: d)
        XCTAssertEqual(Decisions.questionsRepondues(dossier: d), ["session:abc:u-2"])
    }

    // MARK: Questions hors fin de tour (03/11, Sacha : « poser la question en AskUserQuestion et dans Pilote »)

    private func texte(_ s: String, puis fin: [String: Any]? = nil) -> [[String: Any]] {
        var l: [[String: Any]] = [
            ["type": "user", "message": ["content": "Prépare le prompteur"]],
            ["type": "assistant", "uuid": "u-3", "message": ["content": [["type": "text", "text": s]]]],
        ]
        if let fin {
            l.append(["type": "assistant", "uuid": "u-4", "message": ["content": [
                ["type": "tool_use", "name": "mcp__ccd_turn__wrap_up", "input": fin]]]])
        }
        return l
    }

    func testQuestionLaisseeDansLeTexte() {
        let r = Sessions.resumer(texte("Prompteur prêt.\nPour décider du mot-clé : tu veux que le prompteur dise **RELOOK** ?",
                                       puis: ["recap": "Prompteur prêt."]))
        XCTAssertEqual(r.question, "Pour décider du mot-clé : tu veux que le prompteur dise RELOOK ?")
        XCTAssertEqual(r.choix, ["Oui", "Non"])
        XCTAssertEqual(r.questionUuid, "u-3")
        XCTAssertEqual(r.questionGenre, "texte")
    }

    func testQuestionAvecOuSansOuiNon() {
        XCTAssertEqual(Sessions.resumer(texte("- On garde RELOOK ou RÉNOVE ?")).choix, [])
    }

    func testCitationsCodeEtTitresNeSontPasDesQuestions() {
        XCTAssertNil(Sessions.questionDansTexte("Le script dira « Vous voulez gagner du temps ? »\n```\nok ?\n```\n> Tu es sûr ?\n## Pourquoi ?"))
    }

    func testLaFinDeTourPrimeSurLeTexte() {
        let r = Sessions.resumer(texte("Tu veux RELOOK ?", puis: ["recap": "Fait.", "ask": "Quel mot-clé ?",
                                                                 "actions": [["label": "RELOOK"]]]))
        XCTAssertEqual(r.question, "Quel mot-clé ?")
        XCTAssertEqual(r.questionGenre, "fin")
    }

    func testDialogueAskUserQuestionPuisReponse() {
        var l: [[String: Any]] = [
            ["type": "user", "message": ["content": "Prépare le prompteur"]],
            ["type": "assistant", "uuid": "u-5", "message": ["content": [
                ["type": "tool_use", "id": "t-1", "name": "AskUserQuestion", "input": ["questions": [
                    ["question": "Quel mot-clé ?", "header": "Mot-clé", "multiSelect": false,
                     "options": [["label": "RELOOK", "description": "court"], ["label": "RÉNOVE", "description": "clair"]]],
                    ["question": "Quelle heure ?", "header": "Heure", "multiSelect": false, "options": []],
                ]]]]]],
        ]
        var r = Sessions.resumer(l)
        XCTAssertEqual(r.question, "Quel mot-clé ? (+ 1 autre dans la session)")
        XCTAssertEqual(r.choix, ["RELOOK", "RÉNOVE"])
        XCTAssertEqual(r.questionGenre, "dialogue")
        XCTAssertEqual(r.questionUuid, "u-5")
        // Répondu dans l'app Claude : plus rien à décider dans Pilote.
        l.append(["type": "user", "message": ["content": [["type": "tool_result", "tool_use_id": "t-1", "content": "RELOOK"]]]])
        r = Sessions.resumer(l)
        XCTAssertEqual(r.question, "")
    }
}
