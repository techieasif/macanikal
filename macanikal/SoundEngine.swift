import AVFoundation
import CoreAudio
import os

private let logger = Logger(subsystem: "com.macanikal.app", category: "engine")

struct SoundPack: Identifiable, Equatable {
    let id: String       // folder name in Resources/Audio
    let name: String
    let style: String    // Clicky / Tactile / Linear / Thocky

    static let all: [SoundPack] = [
        SoundPack(id: "mxbrown", name: "Cherry MX Brown", style: "Tactile"),
        SoundPack(id: "mxblue", name: "Cherry MX Blue", style: "Clicky"),
        SoundPack(id: "mxblack", name: "Cherry MX Black", style: "Linear"),
        SoundPack(id: "holypanda", name: "Holy Panda", style: "Tactile"),
        SoundPack(id: "cream", name: "NovelKeys Cream", style: "Linear"),
        SoundPack(id: "topre", name: "Topre", style: "Thocky"),
        SoundPack(id: "alpaca", name: "Alpaca", style: "Linear"),
        SoundPack(id: "blackink", name: "Gateron Black Ink", style: "Linear"),
        SoundPack(id: "redink", name: "Gateron Red Ink", style: "Linear"),
        SoundPack(id: "turquoise", name: "Tealios", style: "Linear"),
        SoundPack(id: "boxnavy", name: "Kailh Box Navy", style: "Clicky"),
        SoundPack(id: "buckling", name: "IBM Buckling Spring", style: "Clicky"),
        SoundPack(id: "bluealps", name: "Blue Alps", style: "Clicky"),
    ]
}

/// Which sample a key maps to, mirroring the kbsim recording layout:
/// five row-specific generic samples plus dedicated space/enter/backspace.
enum KeyRole: Equatable {
    case row(Int) // 0 = esc/function row ... 4 = bottom row
    case space, enter, backspace
}

/// Low-latency sample playback. Buffers are decoded to PCM up front, leading
/// silence is trimmed off every sample (recorded files often hide 5–20 ms of
/// dead air before the transient — that reads as input lag), a pool of player
/// nodes stays running at all times, and each keystroke schedules a buffer
/// with `.interrupts` so it starts on the next render cycle. The hardware IO
/// buffer is forced down to 128 frames (~2.7 ms @ 48 kHz).
final class SoundEngine {
    private final class LoadedPack {
        var pressRows: [AVAudioPCMBuffer?] = Array(repeating: nil, count: 5)
        var pressSpace, pressEnter, pressBackspace: AVAudioPCMBuffer?
        var releaseGeneric, releaseSpace, releaseEnter, releaseBackspace: AVAudioPCMBuffer?
    }

    private struct Voice {
        let player: AVAudioPlayerNode
        let varispeed: AVAudioUnitVarispeed
    }

    private var engine = AVAudioEngine()
    private var voices: [Voice] = []
    private var volumeValue: Float = 0.7
    private static let voiceCount = 14
    private let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!

    private var packs: [String: LoadedPack] = [:]
    private let packLock = NSLock()
    private let loadQueue = DispatchQueue(label: "macanikal.packLoader", qos: .userInitiated)

    private let voiceLock = NSLock()
    private var nextVoice = 0

    var masterVolume: Float {
        get { volumeValue }
        set {
            volumeValue = newValue
            engine.mainMixerNode.outputVolume = newValue
        }
    }

    private func buildGraph(on newEngine: AVAudioEngine) -> [Voice] {
        var built: [Voice] = []
        for _ in 0..<Self.voiceCount {
            let player = AVAudioPlayerNode()
            let varispeed = AVAudioUnitVarispeed()
            newEngine.attach(player)
            newEngine.attach(varispeed)
            newEngine.connect(player, to: varispeed, format: format)
            newEngine.connect(varispeed, to: newEngine.mainMixerNode, format: format)
            built.append(Voice(player: player, varispeed: varispeed))
        }
        newEngine.isAutoShutdownEnabled = false
        return built
    }

    func start(initialPack: String) throws {
        voices = buildGraph(on: engine)
        engine.prepare()
        try engine.start()
        engine.mainMixerNode.outputVolume = volumeValue
        shrinkIOBuffer()
        for voice in voices { voice.player.play() }

        // Selected pack loads synchronously so the first keystroke has sound;
        // the rest warm up in the background for instant pack switching.
        loadPack(initialPack)
        loadQueue.async { [weak self] in
            for pack in SoundPack.all { self?.loadPack(pack.id) }
        }

        NotificationCenter.default.addObserver(
            self, selector: #selector(configurationChanged),
            name: .AVAudioEngineConfigurationChange, object: engine)
        installDefaultDeviceListener()
    }

    @objc private func configurationChanged(_ note: Notification) {
        DispatchQueue.main.async { [weak self] in self?.scheduleRestart() }
    }

    /// AVAudioEngineConfigurationChange is not reliably posted on macOS when
    /// the default output device changes (e.g. Bluetooth headphones connect
    /// or disconnect) — the engine keeps rendering into a dead device and
    /// goes silent. Watch CoreAudio's default-output property directly.
    private func installDefaultDeviceListener() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main
        ) { [weak self] _, _ in
            logger.notice("default output device changed")
            self?.scheduleRestart()
        }
        if status != noErr {
            logger.error("could not observe default output device (status \(status))")
        }
    }

    private var restartWork: DispatchWorkItem?

    /// Debounced: device switches fire several change events back to back.
    private func scheduleRestart() {
        restartWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.restartEngine(attempt: 0) }
        restartWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    /// A stopped-and-restarted AVAudioEngine keeps its output unit bound to
    /// the device it was created on — after a Bluetooth toggle it reports the
    /// stale hardware format and renders into the void. The only reliable
    /// recovery is a brand-new engine: a fresh output unit always opens the
    /// CURRENT default device.
    private func restartEngine(attempt: Int) {
        NotificationCenter.default.removeObserver(
            self, name: .AVAudioEngineConfigurationChange, object: engine)
        engine.stop()

        let newEngine = AVAudioEngine()
        let newVoices = buildGraph(on: newEngine)
        newEngine.prepare()
        do {
            try newEngine.start()
            newEngine.mainMixerNode.outputVolume = volumeValue

            voiceLock.lock()
            engine = newEngine
            voices = newVoices
            nextVoice = 0
            voiceLock.unlock()

            shrinkIOBuffer()
            for voice in newVoices { voice.player.play() }
            NotificationCenter.default.addObserver(
                self, selector: #selector(configurationChanged),
                name: .AVAudioEngineConfigurationChange, object: newEngine)
            let hw = newEngine.outputNode.outputFormat(forBus: 0)
            logger.notice("engine rebuilt; output \(Int(hw.sampleRate))Hz \(hw.channelCount)ch (attempt \(attempt))")
        } catch {
            logger.error("engine rebuild failed (attempt \(attempt)): \(error)")
            guard attempt < 3 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.restartEngine(attempt: attempt + 1)
            }
        }
    }

    /// Ask for the smallest IO buffer the current output device supports.
    /// 128 frames is fine on built-in hardware, but Bluetooth devices have
    /// much larger minimums — forcing 128 there starves the stream into
    /// silence, so clamp to the device's own reported range.
    private func shrinkIOBuffer() {
        guard let unit = engine.outputNode.audioUnit else { return }

        var desired: UInt32 = 128
        var deviceID = AudioDeviceID(0)
        var idSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        if AudioUnitGetProperty(unit, kAudioOutputUnitProperty_CurrentDevice,
                                kAudioUnitScope_Global, 0, &deviceID, &idSize) == noErr {
            var range = AudioValueRange(mMinimum: 0, mMaximum: 0)
            var rangeSize = UInt32(MemoryLayout<AudioValueRange>.size)
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyBufferFrameSizeRange,
                mScope: kAudioObjectPropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain)
            if AudioObjectGetPropertyData(deviceID, &address, 0, nil, &rangeSize, &range) == noErr,
               range.mMaximum > 0 {
                desired = min(max(desired, UInt32(range.mMinimum)), UInt32(range.mMaximum))
            }
        }

        var frames = desired
        let status = AudioUnitSetProperty(
            unit, kAudioDevicePropertyBufferFrameSize, kAudioUnitScope_Global, 0,
            &frames, UInt32(MemoryLayout<UInt32>.size))
        if status == noErr {
            logger.notice("IO buffer set to \(frames) frames")
        } else {
            logger.error("could not set IO buffer size (status \(status))")
        }
    }

    /// Safe to call from any thread (the event-tap thread calls it directly).
    func play(packId: String, role: KeyRole, isDown: Bool, rate: Float, pan: Float, gain: Float) {
        // Last line of defense: if a device change slipped past the listeners
        // and killed the engine, notice it on the next keystroke and recover.
        if !engine.isRunning {
            DispatchQueue.main.async { [weak self] in self?.scheduleRestart() }
            return
        }

        packLock.lock()
        let pack = packs[packId]
        packLock.unlock()
        guard let pack else { return }

        // Not every pack has dedicated special-key recordings (MX Blue has
        // none), so every branch falls back to a generic row sample.
        let buffer: AVAudioPCMBuffer?
        if isDown {
            switch role {
            case .row(let r): buffer = pack.pressRows[max(0, min(4, r))] ?? pack.pressRows.compactMap { $0 }.randomElement()
            case .space: buffer = pack.pressSpace ?? pack.pressRows[4] ?? pack.pressRows.compactMap { $0 }.randomElement()
            case .enter: buffer = pack.pressEnter ?? pack.pressRows[3] ?? pack.pressRows.compactMap { $0 }.randomElement()
            case .backspace: buffer = pack.pressBackspace ?? pack.pressRows[1] ?? pack.pressRows.compactMap { $0 }.randomElement()
            }
        } else {
            switch role {
            case .row: buffer = pack.releaseGeneric
            case .space: buffer = pack.releaseSpace ?? pack.releaseGeneric
            case .enter: buffer = pack.releaseEnter ?? pack.releaseGeneric
            case .backspace: buffer = pack.releaseBackspace ?? pack.releaseGeneric
            }
        }
        guard let buffer else { return }

        voiceLock.lock()
        let voice = voices[nextVoice]
        nextVoice = (nextVoice + 1) % voices.count
        voiceLock.unlock()

        voice.varispeed.rate = rate
        voice.player.pan = pan
        voice.player.volume = gain
        voice.player.scheduleBuffer(buffer, at: nil, options: .interrupts)
    }

    /// Plays a preview keystroke, loading the pack first if needed.
    func preview(packId: String) {
        packLock.lock()
        let loaded = packs[packId] != nil
        packLock.unlock()
        if loaded {
            play(packId: packId, role: .row(2), isDown: true, rate: 1, pan: 0, gain: 1)
        } else {
            loadQueue.async { [weak self] in
                self?.loadPack(packId)
                self?.play(packId: packId, role: .row(2), isDown: true, rate: 1, pan: 0, gain: 1)
            }
        }
    }

    // MARK: - Loading

    private func loadPack(_ id: String) {
        packLock.lock()
        let exists = packs[id] != nil
        packLock.unlock()
        if exists { return }

        let pack = LoadedPack()
        for row in 0..<5 {
            pack.pressRows[row] = loadBuffer(pack: id, sub: "press", name: "GENERIC_R\(row)")
        }
        pack.pressSpace = loadBuffer(pack: id, sub: "press", name: "SPACE")
        pack.pressEnter = loadBuffer(pack: id, sub: "press", name: "ENTER")
        pack.pressBackspace = loadBuffer(pack: id, sub: "press", name: "BACKSPACE")
        pack.releaseGeneric = loadBuffer(pack: id, sub: "release", name: "GENERIC")
        pack.releaseSpace = loadBuffer(pack: id, sub: "release", name: "SPACE")
        pack.releaseEnter = loadBuffer(pack: id, sub: "release", name: "ENTER")
        pack.releaseBackspace = loadBuffer(pack: id, sub: "release", name: "BACKSPACE")

        normalize(buffers: allBuffers(pack))

        packLock.lock()
        packs[id] = pack
        packLock.unlock()
    }

    private func allBuffers(_ pack: LoadedPack) -> [AVAudioPCMBuffer] {
        (pack.pressRows.compactMap { $0 }) + [
            pack.pressSpace, pack.pressEnter, pack.pressBackspace,
            pack.releaseGeneric, pack.releaseSpace, pack.releaseEnter, pack.releaseBackspace,
        ].compactMap { $0 }
    }

    /// Scale the whole set so its loudest sample peaks at -1 dBFS. Keeps the
    /// press/release balance of the original recording but makes packs
    /// interchangeable without volume jumps.
    func normalize(buffers: [AVAudioPCMBuffer]) {
        var peak: Float = 0
        for buffer in buffers {
            guard let data = buffer.floatChannelData else { continue }
            for ch in 0..<Int(buffer.format.channelCount) {
                for i in 0..<Int(buffer.frameLength) {
                    peak = max(peak, abs(data[ch][i]))
                }
            }
        }
        guard peak > 0 else { return }
        let gain = 0.89 / peak
        for buffer in buffers {
            guard let data = buffer.floatChannelData else { continue }
            for ch in 0..<Int(buffer.format.channelCount) {
                for i in 0..<Int(buffer.frameLength) {
                    data[ch][i] *= gain
                }
            }
        }
    }

    private func loadBuffer(pack: String, sub: String, name: String) -> AVAudioPCMBuffer? {
        guard let url = Bundle.main.url(
            forResource: name, withExtension: "mp3",
            subdirectory: "Audio/\(pack)/\(sub)") else { return nil }
        do {
            let file = try AVAudioFile(forReading: url)
            guard let raw = AVAudioPCMBuffer(
                pcmFormat: file.processingFormat,
                frameCapacity: AVAudioFrameCount(file.length)) else { return nil }
            try file.read(into: raw)
            let converted = convert(raw) ?? raw
            return trimLeadingSilence(converted)
        } catch {
            NSLog("macanikal: failed to load \(pack)/\(sub)/\(name): \(error)")
            return nil
        }
    }

    func convert(_ input: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        if input.format == format { return input }
        guard let converter = AVAudioConverter(from: input.format, to: format) else { return nil }
        let ratio = format.sampleRate / input.format.sampleRate
        let capacity = AVAudioFrameCount(Double(input.frameLength) * ratio) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        var fed = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if fed {
                status.pointee = .endOfStream
                return nil
            }
            fed = true
            status.pointee = .haveData
            return input
        }
        return error == nil ? output : nil
    }

    /// Recorded samples routinely carry several ms of near-silence before the
    /// attack transient; cutting it is a free latency win.
    func trimLeadingSilence(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer {
        guard let data = buffer.floatChannelData, buffer.frameLength > 0 else { return buffer }
        let channels = Int(buffer.format.channelCount)
        let frames = Int(buffer.frameLength)

        var peak: Float = 0
        for ch in 0..<channels {
            for i in 0..<frames { peak = max(peak, abs(data[ch][i])) }
        }
        let threshold = max(0.002, peak * 0.03)

        var first = 0
        outer: for i in 0..<frames {
            for ch in 0..<channels where abs(data[ch][i]) > threshold {
                first = i
                break outer
            }
        }
        // keep a 1 ms pre-roll so the attack isn't clipped
        first = max(0, first - 48)
        guard first > 0 else { return buffer }

        let newFrames = frames - first
        guard let trimmed = AVAudioPCMBuffer(
            pcmFormat: buffer.format, frameCapacity: AVAudioFrameCount(newFrames)) else { return buffer }
        for ch in 0..<channels {
            trimmed.floatChannelData![ch].update(from: data[ch] + first, count: newFrames)
        }
        trimmed.frameLength = AVAudioFrameCount(newFrames)
        return trimmed
    }
}
