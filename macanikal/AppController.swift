import AppKit
import Combine
import Foundation

final class AppController: ObservableObject {
    @Published var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: "isEnabled"); syncConfig() }
    }
    @Published var volume: Double {
        didSet {
            defaults.set(volume, forKey: "volume")
            engine.masterVolume = Float(volume)
        }
    }
    @Published var packId: String {
        didSet { defaults.set(packId, forKey: "soundPack"); syncConfig() }
    }
    @Published var keyUpSounds: Bool {
        didSet { defaults.set(keyUpSounds, forKey: "keyUpSounds"); syncConfig() }
    }
    @Published var playOnRepeat: Bool {
        didSet { defaults.set(playOnRepeat, forKey: "playOnRepeat"); syncConfig() }
    }
    @Published var hasInputPermission = KeyEventTap.hasPermission()

    private let defaults = UserDefaults.standard
    private let engine = SoundEngine()
    private let tap = KeyEventTap()

    /// Snapshot of the settings the tap thread needs, updated on the main
    /// thread and read under a lock so playback never touches @Published state.
    private struct Config {
        var enabled = true
        var packId = "mxbrown"
        var keyUpSounds = true
        var playOnRepeat = false
    }
    private var config = Config()
    private let configLock = NSLock()
    private var permissionTimer: Timer?

    init() {
        defaults.register(defaults: [
            "isEnabled": true,
            "volume": 0.7,
            "soundPack": "mxbrown",
            "keyUpSounds": true,
            "playOnRepeat": false,
        ])
        isEnabled = defaults.bool(forKey: "isEnabled")
        volume = defaults.double(forKey: "volume")
        let stored = defaults.string(forKey: "soundPack") ?? "mxbrown"
        packId = SoundPack.all.contains(where: { $0.id == stored }) ? stored : "mxbrown"
        keyUpSounds = defaults.bool(forKey: "keyUpSounds")
        playOnRepeat = defaults.bool(forKey: "playOnRepeat")
        syncConfig()
    }

    func start() {
        do {
            try engine.start(initialPack: packId)
            engine.masterVolume = Float(volume)
        } catch {
            NSLog("macanikal: audio engine failed to start: \(error)")
        }

        tap.handler = { [weak self] code, isDown, isRepeat in
            self?.handleKey(code: code, isDown: isDown, isRepeat: isRepeat)
        }

        if KeyEventTap.hasPermission() {
            startTap()
        } else {
            KeyEventTap.requestPermission()
            waitForPermission()
        }
    }

    private func startTap() {
        hasInputPermission = true
        if !tap.start() {
            // Tap creation can fail right after permission is granted until the
            // process is relaunched; keep the banner up so the user knows.
            hasInputPermission = false
            waitForPermission()
        }
    }

    private func waitForPermission() {
        guard permissionTimer == nil else { return }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            if KeyEventTap.hasPermission(), self.tap.start() {
                self.hasInputPermission = true
                self.permissionTimer?.invalidate()
                self.permissionTimer = nil
            }
        }
    }

    func openInputMonitoringSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
        NSWorkspace.shared.open(url)
    }

    func selectPack(_ id: String) {
        packId = id
        engine.preview(packId: id)
    }

    private func syncConfig() {
        configLock.lock()
        config = Config(
            enabled: isEnabled,
            packId: packId,
            keyUpSounds: keyUpSounds,
            playOnRepeat: playOnRepeat)
        configLock.unlock()
    }

    private func currentConfig() -> Config {
        configLock.lock()
        defer { configLock.unlock() }
        return config
    }

    // MARK: - Key mapping (ANSI layout rows, matching the kbsim recordings)

    private static let rowByKeyCode: [Int64: Int] = {
        var map: [Int64: Int] = [:]
        // R0: esc + function row
        for code: Int64 in [53, 122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113] { map[code] = 0 }
        // R1: number row
        for code: Int64 in [50, 18, 19, 20, 21, 23, 22, 26, 28, 25, 29, 27, 24] { map[code] = 1 }
        // R2: tab / qwerty row
        for code: Int64 in [48, 12, 13, 14, 15, 17, 16, 32, 34, 31, 35, 33, 30, 42] { map[code] = 2 }
        // R3: caps / home row
        for code: Int64 in [57, 0, 1, 2, 3, 5, 4, 38, 40, 37, 41, 39] { map[code] = 3 }
        // R4: shift row + bottom row modifiers and arrows
        for code: Int64 in [56, 60, 6, 7, 8, 9, 11, 45, 46, 43, 47, 44,
                            54, 55, 58, 59, 61, 62, 63, 123, 124, 125, 126] { map[code] = 4 }
        return map
    }()

    private func role(for code: Int64) -> KeyRole {
        switch code {
        case 49: return .space
        case 36, 76: return .enter
        case 51, 117: return .backspace
        default: return .row(Self.rowByKeyCode[code] ?? 3)
        }
    }

    private func handleKey(code: Int64, isDown: Bool, isRepeat: Bool) {
        let cfg = currentConfig()
        guard cfg.enabled else { return }
        if isRepeat && !cfg.playOnRepeat { return }
        if !isDown && !cfg.keyUpSounds { return }

        // Subtle humanization so repeated keys don't sound machine-gun identical.
        let rate = Float.random(in: 0.97...1.03)
        let pan = Float.random(in: -0.15...0.15)
        let gain = Float.random(in: 0.88...1.0)

        engine.play(packId: cfg.packId, role: role(for: code), isDown: isDown,
                    rate: rate, pan: pan, gain: gain)
    }
}
