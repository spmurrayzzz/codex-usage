import Foundation

enum UsageDumper {
    static func dump(_ result: CodexUsageService.Result) {
        var lines: [String] = []
        lines.append("codex usage")
        lines.append(String(repeating: "-", count: 40))
        if let email = result.usage.email {
            lines.append("email: \(email)")
        }
        if let plan = result.usage.planType {
            lines.append("plan: \(plan)")
        }
        if let primary = result.usage.rateLimit?.primaryWindow {
            lines.append("primary window: \(Int(primary.usedPercent))% used (\(WindowLabels.length(primary.limitWindowSeconds ?? 0)))")
            appendReset(&lines, resetAt: primary.resetAt)
        }
        if let secondary = result.usage.rateLimit?.secondaryWindow {
            lines.append("secondary window: \(Int(secondary.usedPercent))% used (\(WindowLabels.length(secondary.limitWindowSeconds ?? 0)))")
            appendReset(&lines, resetAt: secondary.resetAt)
        }
        if let models = result.usage.modelUsage {
            for (name, availability) in models.sorted(by: { $0.key < $1.key }) {
                if availability.available == true {
                    lines.append("model \(name): available")
                } else {
                    lines.append("model \(name): unavailable")
                }
            }
        }
        if let credits = result.usage.credits, credits.hasCredits {
            if credits.unlimited {
                lines.append("credits: unlimited")
            } else if let balance = credits.balance {
                lines.append("credits balance: \(balance)")
            }
        }
        if let summary = result.usage.rateLimitResetCredits {
            lines.append("free reset credits: \(summary.availableCount ?? 0) available")
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        for credit in result.resetCredits {
            var line = "reset credit: \(credit.title ?? "rate limit reset")"
            if let expires = credit.expiresAt {
                line += " (expires \(formatter.string(from: expires)))"
            }
            lines.append(line)
        }
        print(lines.joined(separator: "\n"))

        if let data = try? JSONEncoder().encode(result.usage),
           let json = String(data: data, encoding: .utf8) {
            print()
            print("raw usage JSON:")
            print(json)
        }
    }

    private static func appendReset(_ lines: inout [String], resetAt: Double?) {
        guard let resetAt, resetAt > 0 else { return }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        lines.append("  resets: \(formatter.string(from: Date(timeIntervalSince1970: resetAt)))")
    }
}
