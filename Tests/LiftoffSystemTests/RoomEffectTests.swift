import Foundation
import Testing
@testable import LiftoffSystem

struct RoomEffectTests {
    private let effect = RoomEffect.smallRoom

    @Test func matchesTheApprovedFfmpegReference() {
        // highpass=f=180, lowpass=f=7000, aecho=0.85:0.6:35|70:0.25|0.15, volume=1.1
        #expect(effect.highPassHz == 180)
        #expect(effect.lowPassHz == 7000)
        #expect(effect.taps.map(\.delay) == [0.035, 0.070])
        #expect(abs(effect.taps[0].level - 0.25 / 0.85) < 1e-9)
        #expect(abs(effect.taps[1].level - 0.15 / 0.85) < 1e-9)
        #expect(effect.outputGain == 1.1)
        #expect(effect.sayTail == 0.4)
    }

    @Test func delayMixGivesTheTapLevelUnderEqualPowerCrossfade() {
        for tap in effect.taps {
            let m = Double(RoomEffect.delayMixPercent(forLevel: tap.level)) / 100
            let wetOverDry = m.squareRoot() / (1 - m).squareRoot()
            #expect(abs(wetOverDry - tap.level) < 1e-4)
        }
        #expect(RoomEffect.delayMixPercent(forLevel: 0) == 0)
        #expect(RoomEffect.delayMixPercent(forLevel: 1) == 50)
    }

    @Test func makeupGainRestoresTheDryVoiceToOutputGain() {
        let mixes = effect.delayMixes
        #expect(abs(mixes[0] - 7.96) < 0.01)
        #expect(abs(mixes[1] - 3.02) < 0.01)
        let dry = mixes.reduce(1.0) { $0 * (1 - Double($1) / 100).squareRoot() }
        let gain = pow(10, Double(effect.makeupGainDB) / 20)
        #expect(abs(dry * gain - 1.1) < 1e-4)
        #expect(effect.makeupGainDB > 1 && effect.makeupGainDB < 1.5)  // ≈ +1.3 dB
    }
}
