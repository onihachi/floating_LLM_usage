import Foundation
import Combine

/// Holds the latest usage for each provider and drives refreshes.
@MainActor
final class UsageStore: ObservableObject {
    @Published var claude = ProviderStatus()
    @Published var codex = ProviderStatus()

    /// - Parameter force: user-initiated refresh; bypasses the Claude
    ///   credential-lookup backoff so a fresh login is picked up immediately.
    func refreshAll(force: Bool = false) {
        refreshClaude(force: force)
        refreshCodex()
    }

    func refreshClaude(force: Bool = false) {
        refresh(\.claude) { try await ClaudeProvider.fetch(force: force) }
    }

    func refreshCodex() {
        refresh(\.codex) { try await CodexProvider.fetch() }
    }

    private func refresh(
        _ keyPath: ReferenceWritableKeyPath<UsageStore, ProviderStatus>,
        using fetch: @escaping @Sendable () async throws -> ProviderResult
    ) {
        guard !self[keyPath: keyPath].isLoading else { return }
        self[keyPath: keyPath].isLoading = true

        Task {
            do {
                let result = try await fetch()
                var status = self[keyPath: keyPath]
                status.windows = result.windows
                status.plan = result.plan ?? status.plan
                status.note = result.note
                status.errorMessage = nil
                status.updatedAt = Date()
                status.isLoading = false
                self[keyPath: keyPath] = status
            } catch {
                // Keep the previous numbers on screen; just surface the error.
                var status = self[keyPath: keyPath]
                status.errorMessage = error.localizedDescription
                status.note = nil
                status.isLoading = false
                self[keyPath: keyPath] = status
            }
        }
    }
}
