import SwiftUI
import AppKit

/// The content of the floating panel.
struct UsageView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var settings: Settings
    var onQuit: () -> Void

    private let cornerRadius: CGFloat = 14

    var body: some View {
        // Re-render every 30 s so the "あと◯分" countdowns stay current.
        TimelineView(.periodic(from: Date(), by: 30)) { context in
            VStack(alignment: .leading, spacing: 10) {
                if settings.showClaude {
                    ProviderSection(
                        title: "Claude Code",
                        status: store.claude,
                        accent: Color(red: 0.85, green: 0.47, blue: 0.34),
                        now: context.date
                    )
                }
                if settings.showClaude && settings.showCodex {
                    Divider().opacity(0.6)
                }
                if settings.showCodex {
                    ProviderSection(
                        title: "Codex",
                        status: store.codex,
                        accent: Color(red: 0.25, green: 0.78, blue: 0.60),
                        now: context.date
                    )
                }
                if !settings.showClaude && !settings.showCodex {
                    Text("右クリックで表示するサービスを選択")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                footer(now: context.date)
            }
            .padding(14)
            .frame(width: 300, alignment: .leading)
        }
        .background(VisualEffectBackground())
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
        )
        .contextMenu { menuItems }
    }

    // MARK: Footer

    private func footer(now: Date) -> some View {
        HStack(spacing: 8) {
            Button(action: { store.refreshAll() }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
            .help("今すぐ更新")

            Text(lastUpdatedText(now: now))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            Spacer()

            Menu {
                menuItems
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 11, weight: .medium))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("設定")
        }
        .padding(.top, 2)
    }

    private func lastUpdatedText(now: Date) -> String {
        let dates = [store.claude.updatedAt, store.codex.updatedAt].compactMap { $0 }
        guard let latest = dates.max() else { return "未取得" }
        return "更新 " + Format.timeOnly.string(from: latest)
    }

    // MARK: Menu (shared by right-click and the gear button)

    @ViewBuilder
    private var menuItems: some View {
        Button("今すぐ更新") { store.refreshAll() }

        Menu("不透明度") {
            ForEach(Settings.opacityOptions, id: \.self) { value in
                Button(action: { settings.opacity = value }) {
                    if abs(settings.opacity - value) < 0.001 {
                        Label("\(Int((value * 100).rounded()))%", systemImage: "checkmark")
                    } else {
                        Text("\(Int((value * 100).rounded()))%")
                    }
                }
            }
        }

        Menu("更新間隔") {
            ForEach(Settings.intervalOptions, id: \.seconds) { option in
                Button(action: { settings.refreshInterval = option.seconds }) {
                    if abs(settings.refreshInterval - option.seconds) < 0.5 {
                        Label(option.label, systemImage: "checkmark")
                    } else {
                        Text(option.label)
                    }
                }
            }
        }

        Divider()

        Toggle("Claude Code を表示", isOn: $settings.showClaude)
        Toggle("Codex を表示", isOn: $settings.showCodex)

        Divider()

        Button("終了") { onQuit() }
    }
}

// MARK: - Provider section

struct ProviderSection: View {
    let title: String
    let status: ProviderStatus
    let accent: Color
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Circle()
                    .fill(accent)
                    .frame(width: 8, height: 8)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                if let plan = status.plan, !plan.isEmpty {
                    Text(plan)
                        .font(.system(size: 9, weight: .medium))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.primary.opacity(0.10)))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if status.isLoading {
                    ProgressView()
                        .controlSize(.mini)
                }
            }

            if status.windows.isEmpty && status.errorMessage == nil {
                Text(status.isLoading ? "読み込み中…" : "データなし")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            ForEach(status.windows) { window in
                UsageRow(window: window, now: now)
            }

            if let error = status.errorMessage {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.red.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            } else if let note = status.note, !note.isEmpty {
                Text(note)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - One usage row

struct UsageRow: View {
    let window: UsageWindow
    let now: Date

    private var percent: Double { window.clampedPercent }

    private var barColor: Color {
        if percent < 50 { return Color.green }
        if percent < 80 { return Color.yellow }
        return Color.red
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(window.label)
                    .font(.system(size: 11))
                Spacer()
                Text("\(Int(percent.rounded()))% 使用")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .monospacedDigit()
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.12))
                    Capsule()
                        .fill(barColor)
                        .frame(width: max(0, geo.size.width * percent / 100))
                }
            }
            .frame(height: 6)

            HStack {
                if let reset = window.resetsAt {
                    Text("リセット \(Format.clock.string(from: reset))")
                    Spacer()
                    Text(Format.remaining(until: reset, from: now))
                } else {
                    Text("リセット時刻 不明")
                }
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Blur background

struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.isEmphasized = false
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
