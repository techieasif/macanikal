import AVFoundation

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
enum KeyRole {
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

    private let engine = AVAudioEngine()
    private var voices: [Voice] = []
    private static let voiceCount = 14
    private let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!

    private var packs: [String: LoadedPack] = [:]
    private let packLock = NSLock()
    private let loadQueue = DispatchQueue(label: "macanikal.packLoader", qos: .userInitiated)

    private let voiceLock = NSLock()
    private var nextVoice = 0

    var masterVolume: Float {
        get { engine.mainMixerNode.outputVolume }
        set { engine.mainMixerNode.outputVolume = newValue }
    }

    func start(initialPack: String) throws {
        for _ in 0..<Self.voiceCount {
            let player = AVAudioPlayerNode()
            let varispeed = AVAudioUnitVarispeed()
            engine.attach(player)
            engine.attach(varispeed)
            engine.connect(player, to: varispeed, format: format)
            engine.connect(varispeed, to: engine.mainMixerNode, format: format)
            voices.append(Voice(player: player, varispeed: varispeed))
        }

        engine.isAutoShutdownEnabled = false
        engine.prepare()
        try engine.start()
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
    }

    @objc private func configurationChanged(_ note: Notification) {
        // Output device changed (headphones plugged in, etc.) — restart the graph.
        DispatchQueue.main.async { [self] in
            do {
                try engine.start()
                shrinkIOBuffer()
                for voice in voices { voice.player.play() }
            } catch {
                NSLog("macanikal: engine restart failed: \(error)")
            }
        }
    }

    private func shrinkIOBuffer() {
        guard let unit = engine.outputNode.audioUnit else { return }
        var frames: UInt32 = 128
        let status = AudioUnitSetProperty(
            unit, kAudioDevicePropertyBufferFrameSize, kAudioUnitScope_Global, 0,
            &frames, UInt32(MemoryLayout<UInt32>.size))
        if status != noErr {
            NSLog("macanikal: could not set IO buffer size (status \(status))")
        }
    }

    /// Safe to call from any thread (the event-tap thread calls it directly).
    func play(packId: String, role: KeyRole, isDown: Bool, rate: Float, pan: Float, gain: Float) {
        packLock.lock()
        let pack = packs[packId]
        packLock.unlock()
        guard let pack else { return }

        let buffer: AVAudioPCMBuffer?
        if isDown {
            switch role {
            case .row(let r): buffer = pack.pressRows[max(0, min(4, r))] ?? pack.pressRows.compactMap { $0 }.randomElement()
            case .space: buffer = pack.pressSpace
            case .enter: buffer = pack.pressEnter
            case .backspace: buffer = pack.pressBackspace
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

        normalize(pack)

        packLock.lock()
        packs[id] = pack
        packLock.unlock()
    }

    private var allBuffers: (LoadedPack) -> [AVAudioPCMBuffer] {
        { pack in
            (pack.pressRows.compactMap { $0 }) + [
                pack.pressSpace, pack.pressEnter, pack.pressBackspace,
                pack.releaseGeneric, pack.releaseSpace, pack.releaseEnter, pack.releaseBackspace,
            ].compactMap { $0 }
        }
    }

    /// Scale the whole pack so its loudest sample peaks at -1 dBFS. Keeps the
    /// press/release balance of the original recording but makes packs
    /// interchangeable without volume jumps.
    private func normalize(_ pack: LoadedPack) {
        var peak: Float = 0
        for buffer in allBuffers(pack) {
            guard let data = buffer.floatChannelData else { continue }
            for ch in 0..<Int(buffer.format.channelCount) {
                for i in 0..<Int(buffer.frameLength) {
                    peak = max(peak, abs(data[ch][i]))
                }
            }
        }
        guard peak > 0 else { return }
        let gain = 0.89 / peak
        for buffer in allBuffers(pack) {
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

    private func convert(_ input: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
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
    private func trimLeadingSilence(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer {
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
