import SwiftUI

@MainActor
final class UsageModel: ObservableObject {
    @Published var usage: UsageResponse?
    @Published var resetCredits: [ResetCredit] = []
    @Published var fetchedAt: Date?
    @Published var isLoading = false
    @Published var hardError: String?
    @Published var softWarning: String?

    private var loopTask: Task<Void, Never>?
    private let service = CodexUsageService()
    private let refreshInterval: TimeInterval = 60

    func start() {
        guard loopTask == nil else { return }
        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    func stop() {
        loopTask?.cancel()
        loopTask = nil
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await service.fetch()
            usage = result.usage
            resetCredits = result.resetCredits
            fetchedAt = Date()
            hardError = nil
            softWarning = nil
        } catch {
            if usage != nil {
                softWarning = error.localizedDescription
            } else {
                hardError = error.localizedDescription
            }
        }
    }
}
