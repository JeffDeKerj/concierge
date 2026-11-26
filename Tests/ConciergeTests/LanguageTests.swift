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

    @Test func aQuestionThatMentionsALanguageIsNotASwitch() {
        #expect(Language.asked(in: "what's on tomorrow") == nil)
        #expect(Language.asked(in: "did the French group reply to Stephane about the assays yesterday") == nil)
        #expect(Language.asked(in: "what did Thierry say in French to the whole MIT group") == nil)
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
        #expect(!Conversation.spokenPrompt("what's on tomorrow", context: nil).contains("French"))
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
            for phrase in [language.yes, language.hereIAm, language.okay, language.noAnswer, language.switched, language.sample] {
                #expect(!phrase.isEmpty)
            }
        }
        #expect(Language.french.yes != Language.english.yes)
    }
}
