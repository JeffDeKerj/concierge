import Foundation
import Testing
@testable import Concierge

struct DeskSealTests {
    let key = Data(String(repeating: "k", count: 32).utf8)

    @Test func aMessageSealedByTheHookOpensHere() throws {
        // Made by ~/.claude/hooks/nestor_desk.py with the same test key.
        let fromHook = "{\"body\": \"{\\\"kind\\\": \\\"question\\\", \\\"id\\\": \\\"q1\\\", \\\"type\\\": \\\"card\\\", \\\"host\\\": \\\"spark\\\", \\\"project\\\": \\\"code/brain\\\", \\\"questions\\\": [{\\\"question\\\": \\\"Which?\\\", \\\"multiSelect\\\": false, \\\"options\\\": [\\\"Alpha\\\", \\\"Beta\\\"]}]}\", \"sig\": \"b02b4a66cd2677795d638d92c60097f6c2dbead374284d7f53244bc81d806a17\"}"
        let body = try #require(DeskSeal.unseal(fromHook, key))
        let question = try #require(DeskQuestion(body))
        #expect(question.kind == .card && question.host == "spark" && question.parts[0].options == ["Alpha", "Beta"])
        #expect(question.spokenName == "the brain session on spark")
        #expect(DeskSeal.topic(key) == "nestor-desk-54284fc7b811ef34ddf47680")
    }

    @Test func onlyAValidSealOpens() throws {
        let sealed = try #require(DeskSeal.seal(["kind": "answer", "id": "q1", "text": "yes"], key))
        #expect(DeskSeal.unseal(sealed, key)?["text"] as? String == "yes")
        #expect(DeskSeal.unseal(sealed, Data("other".utf8)) == nil)
        #expect(DeskSeal.unseal(#"{"body": "{\\"kind\\": \\"answer\\"}", "sig": "00"}"#, key) == nil)
    }
}

struct DeskTalkTests {
    @Test func theAwaySwitchIsHeard() {
        #expect(DeskTalk.awayCommand("I'm stepping away for a bit") == .away)
        #expect(DeskTalk.awayCommand("Je m'absente") == .away)
        #expect(DeskTalk.awayCommand("I'm back") == .back)
        #expect(DeskTalk.awayCommand("what's on tomorrow") == nil)
        #expect(DeskTalk.asksForQuestions("Are any sessions waiting for me?"))
        #expect(DeskTalk.asksForQuestions("read the questions"))
        #expect(!DeskTalk.asksForQuestions("any questions from Thierry"))
    }

    @Test func aChoiceIsHeardByNumberOrName() {
        let options = ["Push them", "Not yet"]
        #expect(DeskTalk.interpret("the first one", options: options) == .choice(["Push them"]))
        #expect(DeskTalk.interpret("second", options: options) == .choice(["Not yet"]))
        #expect(DeskTalk.interpret("not yet", options: options) == .choice(["Not yet"]))
        #expect(DeskTalk.interpret("la deuxième", options: options) == .choice(["Not yet"]))
        #expect(DeskTalk.interpret("one and two", options: options, multiSelect: true) == .choice(["Push them", "Not yet"]))
        #expect(DeskTalk.interpret("skip", options: options) == .skip)
        #expect(DeskTalk.interpret("Use the cheaper model and run it again", options: options)
                == .text("Use the cheaper model and run it again"))
    }

    @Test func onlyAClearYesSends() {
        #expect(DeskTalk.confirm("Yes, send it") == .yes)
        #expect(DeskTalk.confirm("oui") == .yes)
        #expect(DeskTalk.confirm("No, wait") == .no)
        #expect(DeskTalk.confirm("hmm") == nil)
    }

    @Test func aLongQuestionIsReadFromItsLastSentences() {
        let long = String(repeating: "Some background here. ", count: 30) + "Shall I push it?"
        let short = DeskTalk.shortened(long)
        #expect(short.count <= 280 && short.hasSuffix("Shall I push it?"))
    }
}
