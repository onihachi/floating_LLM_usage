import SwiftUI
import AppKit

/// The content of the floating panel.
struct UsageView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var settings: Settings
    var onQuit: () -> Void

    @GestureState private var dragActive = false
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
                        now: context.date,
                        settings: settings
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
                        now: context.date,
                        settings: settings
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
            .contentShape(Rectangle())
            // Drag anywhere that is not a button to move the panel. Child controls
            // (buttons, the gear menu) keep precedence over this container gesture.
            .gesture(
                DragGesture(minimumDistance: 3, coordinateSpace: .global)
                    // GestureState resets when the gesture is cancelled, so a new
                    // drag always re-captures its starting point.
                    .updating($dragActive) { value, active, _ in
                        if !active {
                            active = true
                            FloatingPanel.current?.beginDrag(translationSoFar: value.translation)
                        }
                    }
                    .onChanged { _ in FloatingPanel.current?.continueDrag() }
                    .onEnded { _ in FloatingPanel.current?.endDrag() }
            )
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
            Button(action: { store.refreshAll(force: true) }) {
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
        Button("今すぐ更新") { store.refreshAll(force: true) }

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

        Menu("表示モード") {
            ForEach(WindowMode.allCases, id: \.self) { mode in
                Button(action: { settings.windowMode = mode }) {
                    if settings.windowMode == mode {
                        Label(mode.label, systemImage: "checkmark")
                    } else {
                        Text(mode.label)
                    }
                }
            }
        }

        Menu("位置") {
            ForEach(PanelCorner.allCases, id: \.self) { corner in
                Button(corner.label) { FloatingPanel.current?.snap(to: corner) }
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
    @ObservedObject var settings: Settings

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
                UsageRow(
                    window: window,
                    now: now,
                    collapsed: !settings.expandedWindows.contains(window.id),
                    onToggle: { settings.toggleExpanded(window.id) }
                )
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
    /// Collapsed rows show one line (label, percent, time left) and no bar.
    var collapsed: Bool = false
    var onToggle: () -> Void = {}

    private var percent: Double { window.clampedPercent }

    private var barColor: Color {
        if percent < 50 { return Color.green }
        if percent < 80 { return Color.yellow }
        return Color.red
    }

    var body: some View {
        Group {
            if collapsed {
                collapsedBody
            } else {
                expandedBody
            }
        }
        .contentShape(Rectangle())
        // A plain click toggles; drags still go to the panel-move gesture.
        .onTapGesture { onToggle() }
    }

    /// Width of the compact bar; small enough to leave room for the label,
    /// the percentage and the time-left text on one 300pt-wide line.
    private let compactBarWidth: CGFloat = 56

    private var collapsedBody: some View {
        HStack(spacing: 6) {
            Image(systemName: "chevron.right")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.tertiary)
            Text(window.label)
                .font(.system(size: 11))
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.12))
                Capsule()
                    .fill(barColor)
                    .frame(width: max(0, compactBarWidth * percent / 100))
            }
            .frame(width: compactBarWidth, height: 5)
            Text("\(Int(percent.rounded()))%")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .monospacedDigit()
            Spacer()
            if let reset = window.resetsAt {
                Text(Format.remaining(until: reset, from: now))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var expandedBody: some View {
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
