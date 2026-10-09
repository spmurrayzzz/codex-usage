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
        .frame(minHeight: 420)
    }

    private var content: some View {
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
            Spacer(minLength: 8)
            Divider()
            footer
        }
        .padding(14)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            if let email = model.usage?.email {
                Text(email)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if let plan = model.usage?.planType {
                planPill(plan)
            }
        }
    }

    private func planPill(_ plan: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "sparkles")
                .font(.system(size: 9, weight: .bold))
            Text(PlanNames.display(plan))
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Color.accentColor.opacity(0.16), in: Capsule())
        .foregroundStyle(Color.accentColor)
    }

    private func warningBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
                .padding(.top, 1)
            Text(message)
                .font(.caption)
                .lineLimit(3)
                .textSelection(.enabled)
        }
        .foregroundStyle(.orange)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private func rateLimitSection(_ usage: UsageResponse) -> some View {
        let rateLimit = usage.rateLimit
        let heroWindow = rateLimit?.primaryWindow ?? rateLimit?.secondaryWindow
        if let heroWindow {
            Card {
                HStack(spacing: 14) {
                    RingView(fraction: remainingFraction(heroWindow)) {
                        VStack(spacing: 0) {
                            Text("\(Int((100 - heroWindow.usedPercent).rounded()))%")
                                .font(.system(size: 16, weight: .bold))
                                .monospacedDigit()
                            Text("left")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .padding(.top, 1)
                        }
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text("\(WindowLabels.length(heroWindow.limitWindowSeconds ?? 0)) window")
                                .font(.callout.weight(.semibold))
                            statusPills(rateLimit)
                        }
                        if let reset = windowReset(heroWindow.resetAt) {
                            Text(reset.relative.map { "Resets in \($0)" } ?? "Window just reset")
                                .font(.callout)
                                .monospacedDigit()
                            HStack(spacing: 4) {
                                Image(systemName: "clock")
                                Text("\(DateFormatters.dateTime.string(from: reset.date)) · \(Int(heroWindow.usedPercent.rounded()))% used")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        }
                    }
                    Spacer(minLength: 0)
                }
                if let secondary = rateLimit?.secondaryWindow {
                    Divider()
                    compactWindowRow(title: WindowLabels.length(secondary.limitWindowSeconds ?? 0), window: secondary)
                }
            }
        } else if let rateLimit {
            if rateLimit.limitReached == true || rateLimit.allowed == false {
                Card {
                    statusPills(rateLimit)
                }
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
        VStack(alignment: .leading, spacing: 5) {
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
            if let reset = windowReset(window.resetAt) {
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

    @ViewBuilder
    private func modelsSection(_ models: [String: ModelAvailability]) -> some View {
        Card {
            SectionTitle(text: "Models")
            ForEach(models.keys.sorted(), id: \.self) { name in
                HStack(spacing: 10) {
                    IconChip(systemName: "cpu")
                    Text(name)
                        .font(.callout)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    modelStatusLabel(models[name])
                }
            }
        }
    }

    @ViewBuilder
    private func modelStatusLabel(_ availability: ModelAvailability?) -> some View {
        if let availability {
            HStack(spacing: 5) {
                Circle()
                    .fill(modelStatusColor(availability))
                    .frame(width: 6, height: 6)
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
            HStack(spacing: 10) {
                IconChip(systemName: "creditcard")
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        if credits.unlimited {
                            Text("Unlimited")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.green)
                        } else if let balance = credits.balance {
                            Text(balance.formatted(.number.precision(.fractionLength(0...2))))
                                .font(.title3.weight(.semibold))
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
                Spacer(minLength: 0)
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
                ForEach(credits.prefix(3), id: \.stableID) { credit in
                    HStack(spacing: 10) {
                        IconChip(systemName: "rotate.left")
                        Text(credit.title ?? "Rate limit reset")
                            .font(.callout)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer()
                        if let expires = credit.expiresAt {
                            Text("expires \(DateFormatters.short.string(from: expires))")
                                .font(.caption)
                                .foregroundStyle(expires.timeIntervalSinceNow < 7 * 24 * 60 * 60 ? .orange : .secondary)
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
    }

    private func spendLimitCard(_ limit: SpendControlLimit) -> some View {
        Card {
            HStack(spacing: 10) {
                IconChip(systemName: "dollarsign.circle")
                VStack(alignment: .leading, spacing: 2) {
                    if let used = limit.used, let cap = limit.limit {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("\(used.formatted(.number.precision(.fractionLength(0...2)))) / \(cap.formatted(.number.precision(.fractionLength(0...2))))")
                                .font(.title3.weight(.semibold))
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
                Spacer(minLength: 0)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.primary.opacity(0.04),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
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
            .kerning(0.4)
    }
}

struct IconChip: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: 24, height: 24)
            .background(
                Color.primary.opacity(0.06),
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
    }
}

struct RingView<Label: View>: View {
    let fraction: Double
    var size: CGFloat = 64
    var lineWidth: CGFloat = 6
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
        .animation(.easeOut(duration: 0.6), value: clamped)
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
        .frame(height: 5)
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
