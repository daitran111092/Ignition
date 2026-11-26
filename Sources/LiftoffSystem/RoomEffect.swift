import Foundation

/// The "small room PA" voice effect, described the way the approved ffmpeg reference was written
/// (`highpass=f=180, lowpass=f=7000, aecho=0.85:0.6:35|70:0.25|0.15, volume=1.1`) and translated
/// into `AVAudioEngine` unit settings.
///
/// `aecho` is a pure FIR: `out = outGain × (inGain·x + Σ decayᵢ·x[t − delayᵢ])`. Its in/out gains
/// only make the whole line ~5 dB quieter, so they are normalised away: what is kept is each echo
/// tap's level *relative to the dry voice* (`decay / inGain`) and the final ×1.1 on the dry voice.
///
/// The engine realises the taps with two `AVAudioUnitDelay`s in series (no feedback). Apple's
/// delay crossfades with equal power — dry `√(1 − m)`, wet `√m` for a mix fraction `m` — so a tap at
/// relative level `r` needs `m = r² / (1 + r²)`. Series delays also add a third tap at the summed
/// delay (105 ms) with level `r₁·r₂` (≈ −26 dB), which is inaudible next to the other two.
public struct RoomEffect: Equatable, Sendable {
    public struct Tap: Equatable, Sendable {
        /// Seconds after the dry signal.
        public var delay: Double
        /// Amplitude relative to the dry signal.
        public var level: Double
    }

    public var highPassHz: Float
    public var lowPassHz: Float
    public var taps: [Tap]
    /// Linear gain applied to the dry voice after the effect.
    public var outputGain: Double
    /// How long `say` keeps waiting after the last sample so the echoes are heard (not the full ring-out).
    public var sayTail: TimeInterval

    /// Variant A ("phòng nhẹ"), approved on the ElevenLabs clips.
    public static let smallRoom: RoomEffect = {
        let inGain = 0.85
        return RoomEffect(highPassHz: 180, lowPassHz: 7000,
                          taps: [Tap(delay: 0.035, level: 0.25 / inGain), Tap(delay: 0.070, level: 0.15 / inGain)],
                          outputGain: 1.1, sayTail: 0.4)
    }()

    /// `AVAudioUnitDelay.wetDryMix` (percent) giving a wet/dry ratio of `level`.
    public static func delayMixPercent(forLevel level: Double) -> Float {
        let r2 = level * level
        return Float(100 * r2 / (1 + r2))
    }

    /// Dry amplitude left after one equal-power delay at `mixPercent`.
    static func dryAmplitude(mixPercent: Float) -> Double {
        (1 - Double(mixPercent) / 100).squareRoot()
    }

    /// `wetDryMix` for each tap's delay unit, in tap order.
    public var delayMixes: [Float] { taps.map { Self.delayMixPercent(forLevel: $0.level) } }

    /// Gain (dB, for `AVAudioUnitEQ.globalGain`) that brings the dry voice to `outputGain` after
    /// the delays' crossfades have attenuated it.
    public var makeupGainDB: Float {
        let dry = delayMixes.reduce(1.0) { $0 * Self.dryAmplitude(mixPercent: $1) }
        return Float(20 * log10(outputGain / dry))
    }

    public var summary: String {
        let taps = taps.map { String(format: "%.0f ms @ %.2f", $0.delay * 1000, $0.level) }.joined(separator: ", ")
        return String(format: "HP %.0f Hz, LP %.0f Hz, echo taps [%@], makeup %+.2f dB", highPassHz, lowPassHz, taps, makeupGainDB)
    }
}
