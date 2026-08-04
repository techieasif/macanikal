import AVFoundation
import XCTest
@testable import Macanikal

final class SoundEngineTests: XCTestCase {
    private var engine: SoundEngine!

    override func setUp() {
        super.setUp()
        engine = SoundEngine()
    }

    // MARK: - Helpers

    /// Mono buffer of `frames` zeros with a decaying burst starting at `attackFrame`.
    private func makeBuffer(frames: Int, attackFrame: Int?, sampleRate: Double = 48000,
                            channels: AVAudioChannelCount = 1, amplitude: Float = 0.5) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channels)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
        buffer.frameLength = AVAudioFrameCount(frames)
        if let attack = attackFrame {
            for ch in 0..<Int(channels) {
                let data = buffer.floatChannelData![ch]
                for i in attack..<frames {
                    data[i] = amplitude * exp(-Float(i - attack) / 500)
                }
            }
        }
        return buffer
    }

    private func peak(of buffer: AVAudioPCMBuffer) -> Float {
        var p: Float = 0
        for ch in 0..<Int(buffer.format.channelCount) {
            let data = buffer.floatChannelData![ch]
            for i in 0..<Int(buffer.frameLength) { p = max(p, abs(data[i])) }
        }
        return p
    }

    // MARK: - trimLeadingSilence

    func testTrimRemovesLeadingSilence() {
        let silentFrames = 960 // 20 ms of dead air @ 48 kHz
        let buffer = makeBuffer(frames: 4800, attackFrame: silentFrames)
        let trimmed = engine.trimLeadingSilence(buffer)

        XCTAssertLessThan(trimmed.frameLength, buffer.frameLength)
        // Attack must land within the 1 ms (48-frame) pre-roll of the trimmed start.
        let expected = AVAudioFrameCount(4800 - silentFrames + 48)
        XCTAssertLessThanOrEqual(trimmed.frameLength, expected)
        // The transient itself must survive.
        XCTAssertEqual(peak(of: trimmed), peak(of: buffer), accuracy: 0.001)
    }

    func testTrimKeepsBufferWithImmediateAttack() {
        let buffer = makeBuffer(frames: 4800, attackFrame: 0)
        let trimmed = engine.trimLeadingSilence(buffer)
        XCTAssertEqual(trimmed.frameLength, buffer.frameLength)
    }

    func testTrimHandlesAllSilentBuffer() {
        let buffer = makeBuffer(frames: 4800, attackFrame: nil)
        let trimmed = engine.trimLeadingSilence(buffer)
        // Nothing above threshold — the buffer comes back unharmed, no crash.
        XCTAssertEqual(trimmed.frameLength, buffer.frameLength)
    }

    // MARK: - convert

    func testConvertResamplesToCanonicalFormat() {
        let input = makeBuffer(frames: 4410, attackFrame: 0, sampleRate: 44100, channels: 1)
        let output = engine.convert(input)
        XCTAssertNotNil(output)
        XCTAssertEqual(output!.format.sampleRate, 48000)
        XCTAssertEqual(output!.format.channelCount, 2)
        // 4410 frames @ 44.1k ≈ 4800 @ 48k
        XCTAssertEqual(Double(output!.frameLength), 4800, accuracy: 128)
    }

    func testConvertPassesThroughCanonicalFormat() {
        let input = makeBuffer(frames: 4800, attackFrame: 0, sampleRate: 48000, channels: 2)
        let output = engine.convert(input)
        XCTAssertTrue(output === input, "canonical-format buffers should not be copied")
    }

    // MARK: - normalize

    func testNormalizeScalesLoudestPeakToMinusOneDB() {
        let loud = makeBuffer(frames: 1000, attackFrame: 0, amplitude: 0.4)
        let quiet = makeBuffer(frames: 1000, attackFrame: 0, amplitude: 0.1)
        engine.normalize(buffers: [loud, quiet])

        XCTAssertEqual(peak(of: loud), 0.89, accuracy: 0.005)
        // Relative balance must be preserved (quiet was 1/4 of loud).
        XCTAssertEqual(peak(of: quiet), 0.89 / 4, accuracy: 0.005)
    }

    func testNormalizeHandlesSilentBuffers() {
        let silent = makeBuffer(frames: 1000, attackFrame: nil)
        engine.normalize(buffers: [silent]) // must not divide by zero / crash
        XCTAssertEqual(peak(of: silent), 0)
    }

    // MARK: - engine lifecycle & playback smoke test

    func testStartLoadsPackAndPlaysWithoutCrashing() throws {
        try engine.start(initialPack: "mxbrown")
        engine.masterVolume = 0 // keep the test run silent

        engine.play(packId: "mxbrown", role: .row(2), isDown: true, rate: 1, pan: 0, gain: 1)
        engine.play(packId: "mxbrown", role: .space, isDown: false, rate: 1, pan: 0, gain: 1)
        // MX Blue has no dedicated special-key samples — must fall back, not go silent.
        engine.play(packId: "mxblue", role: .space, isDown: true, rate: 1, pan: 0, gain: 1)
        // Unknown pack must be a no-op, not a crash.
        engine.play(packId: "doesnotexist", role: .row(0), isDown: true, rate: 1, pan: 0, gain: 1)
    }

    func testMasterVolumeRoundTrips() throws {
        try engine.start(initialPack: "mxbrown")
        engine.masterVolume = 0.42
        XCTAssertEqual(engine.masterVolume, 0.42, accuracy: 0.001)
    }
}
