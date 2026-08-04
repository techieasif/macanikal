import SwiftUI

struct ControlPanelView: View {
    @EnvironmentObject var controller: AppController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if !controller.hasInputPermission {
                permissionBanner
            }
            if controller.secureInputActive {
                secureInputBanner
            }
            switchList
            volumeSlider
            toggles
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 300)
    }

    private var header: some View {
        HStack {
            Image(systemName: "keyboard.fill")
                .foregroundStyle(.secondary)
            Text("Macanikal")
                .font(.headline)
            Spacer()
            Toggle("", isOn: $controller.isEnabled)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
        }
    }

    private var permissionBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Input Monitoring permission needed", systemImage: "exclamationmark.triangle.fill")
                .font(.caption.bold())
            Text("Macanikal listens to keystrokes (never records them) to play sounds. Grant access, then relaunch if sounds don't start.")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Button("Open System Settings") {
                controller.openInputMonitoringSettings()
            }
            .controlSize(.small)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.yellow.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
    }

    private var secureInputBanner: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Sounds paused — secure input", systemImage: "lock.fill")
                .font(.caption.bold())
            Text("A password field has keyboard focus. macOS blocks keystroke access so your passwords stay private. Sounds resume automatically.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    private var switchList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SWITCHES")
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(SoundPack.all) { pack in
                        PackRow(pack: pack, isSelected: controller.packId == pack.id) {
                            controller.selectPack(pack.id)
                        }
                    }
                }
            }
            .frame(height: 208)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var volumeSlider: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("VOLUME")
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Image(systemName: "speaker.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(value: $controller.volume, in: 0...1)
                Image(systemName: "speaker.wave.3.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var toggles: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Key release sounds", isOn: $controller.keyUpSounds)
            Toggle("Sound on key repeat", isOn: $controller.playOnRepeat)
        }
        .toggleStyle(.checkbox)
        .font(.callout)
    }

    private var footer: some View {
        HStack {
            Text("v1.1")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .controlSize(.small)
        }
    }
}

private struct PackRow: View {
    let pack: SoundPack
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false

    private var styleColor: Color {
        switch pack.style {
        case "Clicky": return .blue
        case "Tactile": return .orange
        case "Thocky": return .purple
        default: return .pink
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Circle()
                    .fill(styleColor)
                    .frame(width: 8, height: 8)
                Text(pack.name)
                    .font(.callout)
                Spacer()
                Text(pack.style)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.bold())
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected
                        ? Color.accentColor.opacity(0.18)
                        : hovering ? Color.primary.opacity(0.06) : .clear))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
