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
        .font(.system(size: 13))
        .foregroundStyle(Palette.text)
        .frame(minWidth: 340, maxWidth: 460)
        .background(Palette.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .tint(Palette.green)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                header
                    .padding(.bottom, 6)
                if let warning = model.softWarning {
                    warningBanner(warning)
                }
                if let usage = model.usage {
                    rateLimitSection(usage)
                    if let additional = usage.additionalRateLimits, !additional.isEmpty {
                        additionalLimitsSection(additional)
                    }
                    if let credits = usage.credits, credits.hasCredits {
                        creditsCard(credits)
                    }
                    if let models = usage.modelUsage, !models.isEmpty {
                        modelsSection(models)
                    }
                    resetCreditsCard(usage)
                    if let limit = usage.spendControl?.individualLimit ?? usage.rateLimit?.individualLimit {
                        spendLimitCard(limit)
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            VStack(spacing: 12) {
                Divider().overlay(Palette.border)
                footer
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Overview")
                    .font(.system(size: 21, weight: .medium))
                if let email = model.usage?.email {
                    Text(email)
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 0)
            if let plan = model.usage?.planType {
                Text(PlanNames.display(plan))
                    .font(.system(size: 11, weight: .medium))
                    .fixedSize()
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Palette.raised, in: RoundedRectangle(cornerRadius: 5))
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Palette.border))
            }
        }
    }

    private func warningBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .padding(.top, 1)
            Text(message)
                .lineLimit(3)
                .textSelection(.enabled)
        }
        .font(.system(size: 12))
        .foregroundStyle(Palette.orange)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: Metric.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: Metric.cardRadius).strokeBorder(Palette.orange.opacity(0.2)))
    }

    @ViewBuilder
    private func rateLimitSection(_ usage: UsageResponse) -> some View {
        let rateLimit = usage.rateLimit
        if let window = rateLimit?.primaryWindow ?? rateLimit?.secondaryWindow {
            Card {
                HStack {
                    SectionTitle(text: "\(WindowLabels.length(window.limitWindowSeconds ?? 0)) window")
                    Spacer()
                    statusPills(rateLimit)
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(Int((remainingFraction(window) * 100).rounded()))%")
                        .font(.system(size: 34, weight: .medium))
                        .tracking(-1)
                        .monospacedDigit()
                    Text("remaining")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.secondary)
                    Spacer(minLength: 8)
                    Text("\(Int(window.usedPercent.rounded()))% used")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.secondary)
                        .monospacedDigit()
                }
                UsageBar(usedFraction: window.usedPercent / 100)
                resetDetails(window)
                if rateLimit?.primaryWindow != nil, let secondary = rateLimit?.secondaryWindow {
                    Divider().overlay(Palette.border)
                    compactWindowRow(title: WindowLabels.length(secondary.limitWindowSeconds ?? 0), window: secondary)
                }
            }
        } else if let rateLimit, rateLimit.limitReached == true || rateLimit.allowed == false {
            Card {
                HStack {
                    SectionTitle(text: "Usage limits")
                    Spacer()
                    statusPills(rateLimit)
                }
            }
        }
    }

    @ViewBuilder
    private func resetDetails(_ window: RateWindow) -> some View {
        if let reset = windowReset(window.resetAt) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(reset.relative.map { "Resets in \($0)" } ?? "Window just reset")
                    .foregroundStyle(Palette.secondary)
                Spacer(minLength: 0)
                Text(DateFormatters.dateTime.string(from: reset.date))
                    .foregroundStyle(Palette.muted)
            }
            .font(.system(size: 11))
            .monospacedDigit()
        }
    }

    @ViewBuilder
    private func statusPills(_ rateLimit: RateLimit?) -> some View {
        if rateLimit?.limitReached == true {
            pill("Limit reached", color: Palette.red, icon: "exclamationmark.octagon.fill")
        } else if rateLimit?.allowed == false {
            pill("Not allowed", color: Palette.orange, icon: "pause.circle.fill")
        }
    }

    private func pill(_ text: String, color: Color, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9))
            Text(text)
                .font(.system(size: 10, weight: .medium))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
        .foregroundStyle(color)
    }

    private func compactWindowRow(title: String, window: RateWindow) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(title) window")
                    .font(.system(size: 12))
                Spacer()
                Text("\(Int(window.usedPercent.rounded()))% used")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.secondary)
                    .monospacedDigit()
            }
            UsageBar(usedFraction: window.usedPercent / 100)
            resetDetails(window)
        }
    }

    private func additionalLimitsSection(_ limits: [AdditionalRateLimit]) -> some View {
        Card {
            SectionTitle(text: "Additional limits")
            VStack(spacing: 14) {
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

    private func modelsSection(_ models: [String: ModelAvailability]) -> some View {
        Card {
            SectionTitle(text: "Models")
            VStack(spacing: 12) {
                ForEach(models.keys.sorted(), id: \.self) { name in
                    modelRow(name: name, availability: models[name])
                }
            }
        }
    }

    private func modelRow(name: String, availability: ModelAvailability?) -> some View {
        HStack(spacing: 8) {
            if let availability {
                Circle()
                    .fill(modelStatusColor(availability))
                    .frame(width: 6, height: 6)
            }
            Text(name)
                .font(.system(size: 12, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            if let availability {
                Text(modelStatusText(availability))
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.secondary)
            }
        }
    }

    private func modelStatusColor(_ availability: ModelAvailability) -> Color {
        if availability.available == true {
            return Palette.green
        }
        if availability.creditsWouldEnable == true {
            return Palette.orange
        }
        return Palette.red
    }

    private func modelStatusText(_ availability: ModelAvailability) -> String {
        if availability.available == true {
            return "Available"
        }
        if availability.creditsWouldEnable == true {
            return "Credits would enable"
        }
        return "Unavailable"
    }

    private func creditsCard(_ credits: CreditDetails) -> some View {
        Card {
            SectionTitle(text: "Credits")
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if credits.unlimited {
                        Text("Unlimited")
                            .font(.system(size: 28, weight: .medium))
                    } else if let balance = credits.balance {
                        Text(balance.formatted(.number.precision(.fractionLength(0...2))))
                            .font(.system(size: 28, weight: .medium))
                            .tracking(-0.5)
                            .monospacedDigit()
                        Text("credits")
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.secondary)
                    }
                }
                if let caption = creditsApproximation(credits) {
                    Text(caption)
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
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
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.secondary)
                }
                if !credits.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(credits.prefix(3), id: \.stableID) { credit in
                            Divider().overlay(Palette.border)
                            resetRow(credit)
                                .padding(.vertical, 10)
                        }
                    }
                    .padding(.bottom, -4)
                }
            }
        }
    }

    private func resetRow(_ credit: ResetCredit) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(credit.title ?? "Rate limit reset")
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            if let expires = credit.expiresAt {
                Text("Expires \(DateFormatters.expiration.string(from: expires))")
                    .font(.system(size: 11))
                    .foregroundStyle(expires.timeIntervalSinceNow < 7 * 24 * 60 * 60 ? Palette.orange : Palette.secondary)
                    .monospacedDigit()
                    .fixedSize()
                    .help(expires.formatted(date: .long, time: .complete))
            }
        }
    }

    private func spendLimitCard(_ limit: SpendControlLimit) -> some View {
        Card {
            SectionTitle(text: "Spend limit")
            VStack(alignment: .leading, spacing: 7) {
                if let used = limit.used, let cap = limit.limit {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(used.formatted(.number.precision(.fractionLength(0...2)))) / \(cap.formatted(.number.precision(.fractionLength(0...2))))")
                            .font(.system(size: 24, weight: .medium))
                            .monospacedDigit()
                        Text("limit")
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.secondary)
                    }
                }
                if let caption = spendLimitCaption(limit) {
                    Text(caption)
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.secondary)
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
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.muted)
            }
            Spacer()
            Button {
                Task { await model.refresh() }
            } label: {
                HStack(spacing: 6) {
                    if model.isLoading {
                        ProgressView()
                            .controlSize(.mini)
                            .frame(width: 12, height: 12)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .frame(width: 12, height: 12)
                    }
                    Text("Refresh")
                }
            }
            .buttonStyle(ConsoleButtonStyle())
            .keyboardShortcut("r", modifiers: .command)
            .disabled(model.isLoading)
        }
    }

    private var loadingView: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.small)
            Text("Loading usage…")
                .font(.system(size: 12))
                .foregroundStyle(Palette.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 420, maxHeight: .infinity)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.octagon")
                .font(.system(size: 28))
                .foregroundStyle(Palette.red)
            Text("Unable to load usage")
                .font(.system(size: 15, weight: .medium))
            Text(message)
                .font(.system(size: 12))
                .multilineTextAlignment(.center)
                .foregroundStyle(Palette.secondary)
                .textSelection(.enabled)
            Button("Try again") {
                Task { await model.refresh() }
            }
            .buttonStyle(ConsoleButtonStyle())
            .disabled(model.isLoading)
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
    static let cardRadius: CGFloat = 7
}

private enum Palette {
    static let background = Color(white: 0.075)
    static let card = Color(white: 0.13)
    static let raised = Color(white: 0.17)
    static let border = Color(white: 0.21)
    static let track = Color(white: 0.32)
    static let text = Color(white: 0.93)
    static let secondary = Color(white: 0.62)
    static let muted = Color(white: 0.48)
    static let green = Color(red: 0.57, green: 0.81, blue: 0.61)
    static let orange = Color(red: 0.88, green: 0.65, blue: 0.40)
    static let red = Color(red: 0.93, green: 0.49, blue: 0.46)
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: Metric.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Metric.cardRadius)
                .strokeBorder(Palette.border, lineWidth: 1)
        )
    }
}

struct SectionTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Palette.text)
    }
}

private struct ConsoleButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12))
            .foregroundStyle(Palette.text)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                isEnabled && (isHovered || configuration.isPressed) ? Palette.border : Palette.raised,
                in: RoundedRectangle(cornerRadius: 5)
            )
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Palette.border))
            .contentShape(RoundedRectangle(cornerRadius: 5))
            .opacity(isEnabled ? 1 : 0.5)
            .onHover { isHovered = $0 }
    }
}

struct UsageBar: View {
    let usedFraction: Double

    var body: some View {
        let fraction = min(max(usedFraction, 0), 1)
        GeometryReader { geo in
            HStack(spacing: 3) {
                if fraction > 0 {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(tint)
                        .frame(width: max((geo.size.width - (fraction < 1 ? 3 : 0)) * fraction, 3))
                }
                if fraction < 1 {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Palette.track)
                }
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }

    private var tint: Color {
        let used = min(max(usedFraction, 0), 1)
        if used <= 0.7 {
            return Palette.green
        }
        if used <= 0.9 {
            return Palette.orange
        }
        return Palette.red
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

    static let expiration: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeZone = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("MMMdjmz")
        return formatter
    }()
}
