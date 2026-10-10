import SwiftUI

struct UsageView: View {
    @ObservedObject var model: UsageModel

    var body: some View {
        Group {
            if model.usage == nil {
                if let message = model.hardError {
                    errorView(message)
                } else {
                    loadingView
                }
            } else {
                content
            }
        }
        .frame(minWidth: 340, maxWidth: 460)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                header
                if let warning = model.softWarning {
                    warningBanner(warning)
                }
                if let usage = model.usage {
                    rateLimitSection(usage)
                    if let additional = usage.additionalRateLimits, !additional.isEmpty {
                        additionalLimitsSection(additional)
                    }
                    if let models = usage.modelUsage, !models.isEmpty {
                        modelsSection(models)
                    }
                    if let credits = usage.credits, credits.hasCredits {
                        creditsCard(credits)
                    }
                    resetCreditsCard(usage)
                    if let limit = usage.spendControl?.individualLimit ?? usage.rateLimit?.individualLimit {
                        spendLimitCard(limit)
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Divider()
            footer
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            if let email = model.usage?.email {
                Text(email)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            if let plan = model.usage?.planType {
                planPill(plan)
            }
        }
    }

    private func planPill(_ plan: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "sparkles")
                .font(.system(size: 10, weight: .semibold))
            Text(PlanNames.display(plan))
                .font(.caption.weight(.semibold))
                .kerning(0.2)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.accentColor.opacity(0.14), in: Capsule())
        .overlay(Capsule().stroke(Color.accentColor.opacity(0.18), lineWidth: 1))
        .foregroundStyle(Color.accentColor)
    }

    private func warningBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .padding(.top, 1)
            Text(message)
                .font(.caption)
                .lineLimit(3)
                .textSelection(.enabled)
        }
        .foregroundStyle(.orange)
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: Metric.cardRadius, style: .continuous))
    }

    @ViewBuilder
    private func rateLimitSection(_ usage: UsageResponse) -> some View {
        let rateLimit = usage.rateLimit
        let heroWindow = rateLimit?.primaryWindow ?? rateLimit?.secondaryWindow
        if let heroWindow {
            Card {
                HStack(spacing: 16) {
                    RingView(fraction: remainingFraction(heroWindow), size: 76, lineWidth: 5.5) {
                        VStack(spacing: 1) {
                            Text("\(Int((100 - heroWindow.usedPercent).rounded()))%")
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .monospacedDigit()
                            Text("left")
                                .font(.system(size: 9, weight: .semibold))
                                .kerning(0.3)
                                .foregroundStyle(.secondary)
                        }
                    }
                    heroWindowDetails(heroWindow, rateLimit: rateLimit)
                    Spacer(minLength: 0)
                }
                if let secondary = rateLimit?.secondaryWindow {
                    Divider()
                        .overlay(Color.primary.opacity(0.06))
                    compactWindowRow(title: WindowLabels.length(secondary.limitWindowSeconds ?? 0), window: secondary)
                }
            }
        } else if let rateLimit, rateLimit.limitReached == true || rateLimit.allowed == false {
            Card {
                statusPills(rateLimit)
            }
        }
    }

    private func heroWindowDetails(_ window: RateWindow, rateLimit: RateLimit?) -> some View {
        let reset = windowReset(window.resetAt)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("\(WindowLabels.length(window.limitWindowSeconds ?? 0).uppercased()) WINDOW")
                    .font(.caption.weight(.semibold))
                    .kerning(0.5)
                    .foregroundStyle(.secondary)
                statusPills(rateLimit)
            }
            if let reset {
                Text(reset.relative.map { "Resets in \($0)" } ?? "Window just reset")
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                HStack(spacing: 5) {
                    Image(systemName: "clock")
                        .font(.caption2)
                    Text("\(DateFormatters.dateTime.string(from: reset.date)) · \(Int(window.usedPercent.rounded()))% used")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
            } else {
                Text("\(Int(window.usedPercent.rounded()))% used")
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
            }
        }
    }

    @ViewBuilder
    private func statusPills(_ rateLimit: RateLimit?) -> some View {
        if rateLimit?.limitReached == true {
            pill("Limit reached", color: .red, icon: "exclamationmark.octagon.fill")
        } else if rateLimit?.allowed == false {
            pill("Not allowed", color: .orange, icon: "pause.circle.fill")
        }
    }

    private func pill(_ text: String, color: Color, icon: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .bold))
            Text(text)
                .font(.caption2.weight(.semibold))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 2.5)
        .background(color.opacity(0.15), in: Capsule())
        .foregroundStyle(color)
    }

    @ViewBuilder
    private func compactWindowRow(title: String, window: RateWindow) -> some View {
        let reset = windowReset(window.resetAt)
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(title) window")
                    .font(.callout.weight(.medium))
                Spacer()
                Text("\(Int(window.usedPercent.rounded()))% used")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            UsageBar(usedFraction: window.usedPercent / 100)
            if let reset {
                Text(reset.relative.map { "Resets in \($0) · \(DateFormatters.dateTime.string(from: reset.date))" }
                    ?? "Reset \(DateFormatters.dateTime.string(from: reset.date))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    @ViewBuilder
    private func additionalLimitsSection(_ limits: [AdditionalRateLimit]) -> some View {
        Card {
            SectionTitle(text: "Additional limits")
            VStack(spacing: 12) {
                ForEach(limits.indices, id: \.self) { index in
                    let limit = limits[index]
                    if let window = limit.rateLimit?.primaryWindow {
                        compactWindowRow(
                            title: limit.limitName ?? limit.meteredFeature ?? "Additional limit",
                            window: window
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func modelsSection(_ models: [String: ModelAvailability]) -> some View {
        Card {
            SectionTitle(text: "Models")
            VStack(spacing: 11) {
                ForEach(models.keys.sorted(), id: \.self) { name in
                    modelRow(name: name, availability: models[name])
                }
            }
        }
    }

    private func modelRow(name: String, availability: ModelAvailability?) -> some View {
        HStack(spacing: 10) {
            if let availability {
                Circle()
                    .fill(modelStatusColor(availability))
                    .frame(width: 7, height: 7)
            }
            Text(name)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            if let availability {
                Text(modelStatusText(availability))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func modelStatusColor(_ availability: ModelAvailability) -> Color {
        if availability.available == true {
            return .green
        }
        if availability.creditsWouldEnable == true {
            return .orange
        }
        return .red
    }

    private func modelStatusText(_ availability: ModelAvailability) -> String {
        if availability.available == true {
            return "available"
        }
        if availability.creditsWouldEnable == true {
            return "credits would enable"
        }
        return "unavailable"
    }

    private func creditsCard(_ credits: CreditDetails) -> some View {
        Card {
            SectionTitle(text: "Credits")
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    if credits.unlimited {
                        Text("Unlimited")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.green)
                    } else if let balance = credits.balance {
                        Text(balance.formatted(.number.precision(.fractionLength(0...2))))
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Text("credits")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                if let caption = creditsApproximation(credits) {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func creditsApproximation(_ credits: CreditDetails) -> String? {
        var parts: [String] = []
        if let local = credits.approxLocalMessages, local.count == 2 {
            parts.append("≈ \(compact(local[0]))–\(compact(local[1])) local")
        }
        if let cloud = credits.approxCloudMessages, cloud.count == 2 {
            parts.append("≈ \(compact(cloud[0]))–\(compact(cloud[1])) cloud messages")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func compact(_ value: Double) -> String {
        value.formatted(.number.notation(.compactName).precision(.significantDigits(3))).lowercased()
    }

    @ViewBuilder
    private func resetCreditsCard(_ usage: UsageResponse) -> some View {
        let summary = usage.rateLimitResetCredits
        let credits = model.resetCredits
        let count = credits.isEmpty ? (summary?.availableCount ?? 0) : credits.count
        if count > 0 {
            Card {
                HStack {
                    SectionTitle(text: "Free resets")
                    Spacer()
                    Text("\(count) available")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                VStack(spacing: 0) {
                    ForEach(credits.prefix(3), id: \.stableID) { credit in
                        Divider()
                            .overlay(Color.primary.opacity(0.05))
                        resetRow(credit)
                            .padding(.vertical, 8)
                    }
                }
            }
        }
    }

    private func resetRow(_ credit: ResetCredit) -> some View {
        HStack(spacing: 10) {
            Text(credit.title ?? "Rate limit reset")
                .font(.callout.weight(.medium))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
            if let expires = credit.expiresAt {
                Text("expires \(DateFormatters.short.string(from: expires))")
                    .font(.caption)
                    .foregroundStyle(expires.timeIntervalSinceNow < 7 * 24 * 60 * 60 ? Color.orange : Color.secondary)
                    .monospacedDigit()
            }
        }
    }

    private func spendLimitCard(_ limit: SpendControlLimit) -> some View {
        Card {
            SectionTitle(text: "Spend limit")
            VStack(alignment: .leading, spacing: 3) {
                if let used = limit.used, let cap = limit.limit {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text("\(used.formatted(.number.precision(.fractionLength(0...2)))) / \(cap.formatted(.number.precision(.fractionLength(0...2))))")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Text("limit")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                if let caption = spendLimitCaption(limit) {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func spendLimitCaption(_ limit: SpendControlLimit) -> String? {
        var parts: [String] = []
        if let remaining = limit.remainingPercent {
            parts.append("\(Int(remaining.rounded()))% remaining")
        }
        if let resets = limit.resetsAt {
            parts.append("resets \(DateFormatters.dateTime.string(from: resets))")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if let fetchedAt = model.fetchedAt {
                Text("Updated \(DateFormatters.time.string(from: fetchedAt))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button {
                Task { await model.refresh() }
            } label: {
                if model.isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .labelStyle(.titleAndIcon)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .keyboardShortcut("r", modifiers: .command)
            .disabled(model.isLoading)
        }
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading usage…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 420, maxHeight: .infinity)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.octagon.fill")
                .font(.system(size: 32))
                .foregroundStyle(.red.opacity(0.85))
            Text(message)
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Button("Try Again") {
                Task { await model.refresh() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 420, maxHeight: .infinity)
    }

    private func remainingFraction(_ window: RateWindow) -> Double {
        min(max(1 - window.usedPercent / 100, 0), 1)
    }

    private struct WindowReset {
        let date: Date
        let relative: String?
    }

    private func windowReset(_ resetAt: Double?) -> WindowReset? {
        guard let resetAt, resetAt > 0 else { return nil }
        let date = Date(timeIntervalSince1970: resetAt)
        let relative = relativeDescription(to: date)
        return WindowReset(date: date, relative: relative)
    }

    private func relativeDescription(to date: Date) -> String? {
        guard date.timeIntervalSinceNow > 0 else { return nil }
        var components = Calendar.current.dateComponents([.day, .hour, .minute], from: .now, to: date)
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        if (components.day ?? 0) > 0 || (components.hour ?? 0) > 0 {
            if (components.minute ?? 0) >= 30 {
                components.minute = 0
                components.hour = (components.hour ?? 0) + 1
            }
            components.minute = nil
            formatter.allowedUnits = [.day, .hour]
        } else {
            formatter.allowedUnits = [.hour, .minute]
        }
        return formatter.string(from: components)
    }
}

private enum Metric {
    static let cardRadius: CGFloat = 14
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.primary.opacity(0.045),
            in: RoundedRectangle(cornerRadius: Metric.cardRadius, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Metric.cardRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

struct SectionTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .kerning(0.5)
    }
}

struct RingView<Label: View>: View {
    let fraction: Double
    var size: CGFloat = 76
    var lineWidth: CGFloat = 5.5
    @ViewBuilder var label: Label

    var body: some View {
        let clamped = min(max(fraction, 0), 1)
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.08), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            label
        }
        .padding(lineWidth / 2)
        .frame(width: size, height: size)
        .animation(.easeOut(duration: 0.5), value: clamped)
    }

    private var tint: Color {
        let remaining = min(max(fraction, 0), 1)
        if remaining >= 0.3 {
            return .green
        }
        if remaining >= 0.1 {
            return .orange
        }
        return .red
    }
}

struct UsageBar: View {
    let usedFraction: Double

    var body: some View {
        let fraction = min(max(usedFraction, 0), 1)
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(tint)
                    .frame(width: max(geo.size.width * fraction, fraction > 0 ? 5 : 0))
            }
        }
        .frame(height: 6)
        .animation(.easeOut(duration: 0.5), value: fraction)
    }

    private var tint: Color {
        let remaining = 1 - min(max(usedFraction, 0), 1)
        if remaining >= 0.3 {
            return .green
        }
        if remaining >= 0.1 {
            return .orange
        }
        return .red
    }
}

enum PlanNames {
    static func display(_ raw: String) -> String {
        switch raw.lowercased() {
        case "promax", "pro_max", "pro max":
            return "Pro Max"
        case "pro":
            return "Pro"
        case "prolite", "pro_lite", "pro lite", "pro-lite":
            return "Pro Lite"
        case "plus":
            return "Plus"
        case "go":
            return "Go"
        case "free":
            return "Free"
        case "guest":
            return "Guest"
        case "team":
            return "Team"
        case "business":
            return "Business"
        case "enterprise":
            return "Enterprise"
        case "education", "edu":
            return "Education"
        case "k12":
            return "K12"
        case "free_workspace":
            return "Free Workspace"
        default:
            return raw
                .split(separator: "_")
                .map { $0.prefix(1).uppercased() + $0.dropFirst() }
                .joined(separator: " ")
        }
    }
}

enum WindowLabels {
    static func length(_ seconds: Int) -> String {
        switch seconds {
        case 0:
            return "unknown"
        case 86_400:
            return "Daily"
        case 432_000:
            return "5-hour"
        case 604_800:
            return "7-day"
        case 2_592_000:
            return "30-day"
        default:
            let minutes = seconds / 60
            if minutes >= 1_440, minutes % 1_440 == 0 {
                return "\(minutes / 1_440)-day"
            }
            if minutes >= 60, minutes % 60 == 0 {
                return "\(minutes / 60)-hour"
            }
            if minutes > 0 {
                return "\(minutes)-minute"
            }
            return "\(seconds)-second"
        }
    }
}

enum DateFormatters {
    static let dateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter
    }()

    static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }()

    static let short: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()
}
