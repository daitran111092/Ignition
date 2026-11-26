import Testing
@testable import LiftoffSystem

struct VoicePreferenceTests {
    private func c(_ name: String, _ language: String, _ quality: VoiceCandidate.Quality) -> VoiceCandidate {
        VoiceCandidate(identifier: "\(name)-\(language)-\(quality)", name: name, language: language, quality: quality)
    }

    @Test func prefersZoeOverAvaOverSamantha() {
        let voices = [c("Samantha", "en-US", .premium), c("Ava", "en-US", .premium), c("Zoe", "en-US", .standard)]
        #expect(preferredVoice(among: voices)?.name == "Zoe")
        #expect(preferredVoice(among: Array(voices.prefix(2)))?.name == "Ava")
    }

    @Test func prefersHigherQualityWithinName() {
        let voices = [c("Ava", "en-US", .standard), c("Ava (Premium)", "en-US", .premium), c("Ava (Enhanced)", "en-US", .enhanced)]
        #expect(preferredVoice(among: voices)?.name == "Ava (Premium)")
        #expect(preferredVoice(among: [voices[0], voices[2]])?.name == "Ava (Enhanced)")
    }

    @Test func ignoresNonEnglishVoices() {
        let voices = [c("Zoe", "de-DE", .premium), c("Samantha", "en-US", .standard)]
        #expect(preferredVoice(among: voices)?.name == "Samantha")
    }

    @Test func fallsBackToAnyAmericanEnglishVoice() {
        let voices = [c("Thomas", "fr-FR", .premium), c("Daniel", "en-GB", .standard), c("Fred", "en-US", .standard)]
        #expect(preferredVoice(among: voices)?.name == "Fred")
        #expect(preferredVoice(among: [voices[0]]) == nil)
    }
}
