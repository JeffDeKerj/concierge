import Foundation
import Testing
@testable import Concierge

struct LanguageSwitchTests {
    @Test func askingForALanguageIsHeardInEitherLanguage() {
        #expect(Language.asked(in: "speak French") == .french)
        #expect(Language.asked(in: "Can you speak French, please?") == .french)
        #expect(Language.asked(in: "Parle français.") == .french)
        #expect(Language.asked(in: "parle anglais") == .english)
        #expect(Language.asked(in: "En anglais, s'il te plaît") == .english)
        #expect(Language.asked(in: "Speak English") == .english)
    }

    @Test func aSwitchIsHeardThroughTheListenersCommasAndShortForms() {
        // What the French listener wrote on 2026-11-28.
        #expect(Language.asked(in: "Speak, English") == .english)
        #expect(Language.asked(in: "Anglais !") == .english)
        #expect(Language.asked(in: "English, please.") == .english)
        #expect(Language.asked(in: "Parle en anglais") == .english)
        #expect(Language.asked(in: "Passe en français, s'il te plaît") == .french)
        #expect(Language.asked(in: "French") == .french)
    }

    @Test func aQuestionThatMentionsALanguageIsNotASwitch() {
        #expect(Language.asked(in: "what's on tomorrow") == nil)
        #expect(Language.asked(in: "did the French group reply to Stephane about the assays yesterday") == nil)
        #expect(Language.asked(in: "what did Thierry say in French to the whole MIT group") == nil)
        #expect(Language.asked(in: "store Wat") == nil)
    }

    @Test func frenchIsUsedOnlyWhenItCanBe() {
        var s = ConciergeSettings()
        #expect(s.spokenLanguage(frenchOnThisMac: true) == .english)
        s.language = "fr"
        #expect(s.spokenLanguage(frenchOnThisMac: true) == .french)
        // Not on this Mac and Apple's servers not allowed: English.
        #expect(s.spokenLanguage(frenchOnThisMac: false) == .english)
        s.frenchOnline = true
        #expect(s.spokenLanguage(frenchOnThisMac: false) == .french)
        s.language = "nonsense"
        #expect(s.spokenLanguage(frenchOnThisMac: true) == .english)
    }

    @Test func eachLanguageHasItsOwnVoice() {
        var s = ConciergeSettings()
        s.voice = "jamie"
        s.voiceFr = "thomas"
        #expect(s.voiceID(for: .english) == "jamie")
        #expect(s.voiceID(for: .french) == "thomas")
        #expect(Speaker.voices(for: .french).allSatisfy { $0.language.hasPrefix("fr") })
        #expect(Speaker.voices(for: .english).allSatisfy { $0.language.hasPrefix("en") })
    }

    @Test func theModelIsToldToAnswerInFrench() {
        #expect(Conversation.spokenPrompt("quel temps demain", context: nil, language: .french).contains("Answer in French"))
        // English is said too: a conversation begun in French otherwise goes on in French.
        #expect(Conversation.spokenPrompt("what's on tomorrow", context: nil).contains("Answer in English"))
    }
}

struct FrenchPhraseTests {
    @Test func heardWordsAreMadePlain() {
        #expect(Phrases.plain("Montre-toi !") == "montre toi")
        #expect(Phrases.plain("C\u{2019}est tout.") == "c'est tout")
        #expect(Phrases.plain("Où es-tu ?") == "ou es tu")
    }

    @Test func frenchGoodbyesEndTheConversation() {
        for said in ["Merci.", "Non merci", "C'est tout", "Au revoir !", "Merci, c'est parfait"] {
            #expect(Conversation.isGoodbye(said))
        }
        #expect(!Conversation.isGoodbye("Merci, et qu'est-ce que Declan a répondu ?"))
        // A bare "non" leads into a correction, like "no".
        #expect(!Conversation.isGoodbye("Non, l'autre réunion"))
    }

    @Test func frenchWindowCommandsWork() {
        #expect(Conversation.windowCommand("Montre-toi") == .show)
        #expect(Conversation.windowCommand("Où es-tu ?") == .show)
        #expect(Conversation.windowCommand("Cache-toi") == .hide)
        #expect(Conversation.windowCommand("Est-ce que Stéphane a répondu à propos des essais de mutation hier") == nil)
    }

    @Test func aFrenchWordCutsInToo() {
        #expect(VoiceIO.isBargeIn(heard: "attends", speaking: "Demain vous avez un rendez-vous à dix heures."))
        #expect(VoiceIO.isBargeIn(heard: "arrête", speaking: "Demain vous avez un rendez-vous à dix heures."))
    }

    @Test func whatItSaysByItselfExistsInBothLanguages() {
        for language in Language.allCases {
            for phrase in [language.yes, language.hereIAm, language.okay, language.noAnswer, language.switched, language.sample,
                           language.letMeThink, language.standingBy] + language.stillComing {
                #expect(!phrase.isEmpty)
            }
        }
        #expect(Language.french.yes != Language.english.yes)
    }
}

/// A store of speech files that answers as the test says.
private final class FakeSpeechFiles: SpeechFiles, @unchecked Sendable {
    var status: SpeechFilesStatus
    var afterFetch: SpeechFilesStatus
    var error: Error?
    var steps: [Double] = []
    private(set) var fetches = 0

    init(_ status: SpeechFilesStatus, afterFetch: SpeechFilesStatus = .installed) {
        self.status = status
        self.afterFetch = afterFetch
    }

    func status(of language: Language) async -> SpeechFilesStatus { status }

    func fetch(_ language: Language, progress: @escaping @Sendable (Double) -> Void) async throws {
        fetches += 1
        steps.forEach(progress)
        if let error { throw error }
        status = afterFetch
    }
}

private struct Offline: LocalizedError {
    var errorDescription: String? { "No internet connection." }
}

@MainActor
struct SpeechDownloadTests {
    @Test func itShowsWhereTheLanguageStands() async {
        for (status, state) in [(SpeechFilesStatus.installed, SpeechDownload.State.installed),
                                (.missing, .missing), (.unsupported, .unavailable)] {
            let download = SpeechDownload(.french, files: FakeSpeechFiles(status))
            #expect(download.state == .checking)
            await download.refresh()
            #expect(download.state == state)
        }
    }

    @Test func aDownloadEndsInstalled() async {
        let files = FakeSpeechFiles(.missing)
        let download = SpeechDownload(.french, files: files)
        await download.start()
        #expect(download.state == .installed)
        #expect(files.fetches == 1)
    }

    @Test func aFailedDownloadSaysWhyAndCanBeTriedAgain() async {
        let files = FakeSpeechFiles(.missing)
        files.error = Offline()
        let download = SpeechDownload(.french, files: files)
        await download.start()
        #expect(download.state == .failed("No internet connection."))
        // Looking again does not hide the reason.
        await download.refresh()
        #expect(download.state == .failed("No internet connection."))
        files.error = nil
        await download.start()
        #expect(download.state == .installed)
    }

    @Test func aDownloadThatLeavesNothingIsAFailure() async {
        let download = SpeechDownload(.french, files: FakeSpeechFiles(.missing, afterFetch: .missing))
        await download.start()
        guard case .failed = download.state else {
            Issue.record("expected a failure, got \(download.state)")
            return
        }
    }
}

struct WrittenLanguageTests {
    @Test func eachSentenceIsReadByTheVoiceOfItsOwnLanguage() {
        #expect(Language.of("Switching to English. I still can't search the web for it.") == .english)
        #expect(Language.of("Je vous écoute. La recherche de l'article est toujours bloquée.") == .french)
        // Too short to tell: the conversation's language decides.
        #expect(Language.of("POMSyn.") == nil)
    }

    @Test func aWholeAnswerInTheOtherLanguageMovesTheConversation() {
        let english = "Okay, in English now. Nothing is on your calendar this evening."
        #expect(Conversation.switchTo(answer: english, from: .french) == .english)
        #expect(Conversation.switchTo(answer: english, from: .english) == nil)
        // A French answer that names an English paper stays French.
        let french = "Je vous conseille l'article Digitising Polyoxometalate Syntheses, car il décrit une chaîne de quatre étapes."
        #expect(Conversation.switchTo(answer: french, from: .french) == nil)
        #expect(Conversation.switchTo(answer: "Okay.", from: .french) == nil)
    }
}

struct PageAsTextTests {
    @Test func aPapersLinkKeepsItsAddress() {
        let html = #"<li>POMSyn, <a class="x" href="https://doi.org/10.26434/chemrxiv.15012663/v1">on ChemRxiv</a>.</li>"#
        #expect(AskContext.plainText(html) == "POMSyn, on ChemRxiv (https://doi.org/10.26434/chemrxiv.15012663/v1).")
        // Only web addresses: an in-page link stays plain words.
        #expect(AskContext.plainText(##"<a href="#urgent">Urgent</a>"##) == "Urgent")
    }

    @Test func theModelIsToldWhereThePapersLinksAre() {
        let opening = AskContext.opening(pageHTML: nil, pagePath: nil, updatesJSON: "[]", briefingsPath: "/b")
        #expect(opening.contains(AskContext.digests))
    }
}

struct ThinkingPauseTests {
    @Test func aQuestionLeftHangingGetsMoreTime() {
        let wait = { (heard: String) in VoiceIO.pauseNeeded(after: heard, normal: 1.6, midThought: 3) }
        #expect(wait("what's on tomorrow") == 1.6)
        #expect(wait("could you read the paper about") == 3)
        #expect(wait("what did Thierry say, um") == 3)
        #expect(wait("qu'est-ce que j'ai demain et") == 3)
        #expect(wait("Quels sont ces quatre agents ?") == 1.6)
    }
}

@MainActor
struct ProgressTests {
    final class Clock { var t = Date(timeIntervalSince1970: 0) }

    @Test func aSlowAnswerIsTalkedThrough() {
        let clock = Clock()
        let p = Progress(language: .english, now: { clock.t })
        clock.t += 2
        #expect(p.tick(answered: false) == nil)
        clock.t += 2
        #expect(p.tick(answered: false) == "Let me think.")
        clock.t += 7
        #expect(p.using("WebFetch") == "Reading it now.")
        // The same work again says nothing new.
        clock.t += 7
        #expect(p.using("WebFetch") == nil)
        clock.t += 6
        #expect(p.tick(answered: false) == "Still on it.")
        clock.t += 13
        #expect(p.tick(answered: false) == "It's coming.")
    }

    @Test func aQuickAnswerGetsNoFiller() {
        let clock = Clock()
        let p = Progress(language: .english, now: { clock.t })
        clock.t += 2
        p.said()
        clock.t += 5
        #expect(p.tick(answered: true) == nil)
        // A tool right after a sentence waits its turn.
        #expect(p.using("WebSearch") == nil)
    }

    @Test func theWorkIsNamedInFrenchToo() {
        #expect(Language.french.doing("WebSearch") == "Je cherche.")
        #expect(Language.english.doing("mcp__claude_ai_Gmail__get_thread") == "Checking your mail.")
        #expect(Language.english.doing("ToolSearch") == nil)
    }
}
