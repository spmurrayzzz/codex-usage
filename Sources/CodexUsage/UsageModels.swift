import Foundation

struct FlexDouble: Decodable {
    let value: Double

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Double.self) {
            value = number
            return
        }
        let raw = try container.decode(String.self)
        guard let number = Double(raw) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Not a number: \(raw)"
            )
        }
        value = number
    }
}

struct Lossy<T: Decodable>: Decodable {
    let value: T?

    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}

struct UsageResponse: Decodable, Encodable {
    var accountId: String?
    var email: String?
    var planType: String?
    var rateLimit: RateLimit?
    var additionalRateLimits: [AdditionalRateLimit]?
    var modelUsage: [String: ModelAvailability]?
    var credits: CreditDetails?
    var spendControl: SpendControl?
    var rateLimitResetCredits: ResetCreditsSummary?

    enum CodingKeys: String, CodingKey {
        case accountId = "account_id"
        case email
        case planType = "plan_type"
        case rateLimit = "rate_limit"
        case additionalRateLimits = "additional_rate_limits"
        case modelUsage = "model_usage"
        case credits
        case spendControl
        case rateLimitResetCredits = "rate_limit_reset_credits"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accountId = try? container.decodeIfPresent(String.self, forKey: .accountId)
        email = try? container.decodeIfPresent(String.self, forKey: .email)
        planType = try? container.decodeIfPresent(String.self, forKey: .planType)
        rateLimit = try? container.decodeIfPresent(RateLimit.self, forKey: .rateLimit)
        if let limits = try? container.decodeIfPresent([AdditionalRateLimit].self, forKey: .additionalRateLimits) {
            additionalRateLimits = limits
        } else if let lossy = try? container.decode([Lossy<AdditionalRateLimit>].self, forKey: .additionalRateLimits) {
            additionalRateLimits = lossy.compactMap(\.value)
        }
        modelUsage = try? container.decodeIfPresent([String: ModelAvailability].self, forKey: .modelUsage)
        credits = try? container.decodeIfPresent(CreditDetails.self, forKey: .credits)
        spendControl = try? container.decodeIfPresent(SpendControl.self, forKey: .spendControl)
        rateLimitResetCredits = try? container.decodeIfPresent(
            ResetCreditsSummary.self,
            forKey: .rateLimitResetCredits
        )
    }
}

struct RateLimit: Decodable, Encodable {
    var allowed: Bool?
    var limitReached: Bool?
    var primaryWindow: RateWindow?
    var secondaryWindow: RateWindow?
    var individualLimit: SpendControlLimit?

    enum CodingKeys: String, CodingKey {
        case allowed
        case limitReached = "limit_reached"
        case primaryWindow = "primary_window"
        case secondaryWindow = "secondary_window"
        case individualLimit = "individual_limit"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        allowed = try? container.decodeIfPresent(Bool.self, forKey: .allowed)
        limitReached = try? container.decodeIfPresent(Bool.self, forKey: .limitReached)
        primaryWindow = try? container.decodeIfPresent(RateWindow.self, forKey: .primaryWindow)
        secondaryWindow = try? container.decodeIfPresent(RateWindow.self, forKey: .secondaryWindow)
        individualLimit = try? container.decodeIfPresent(SpendControlLimit.self, forKey: .individualLimit)
    }
}

struct RateWindow: Decodable, Encodable {
    var usedPercent: Double
    var limitWindowSeconds: Int?
    var resetAt: Double?

    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case limitWindowSeconds = "limit_window_seconds"
        case resetAt = "reset_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        usedPercent = try container.decode(FlexDouble.self, forKey: .usedPercent).value
        limitWindowSeconds = try? container.decodeIfPresent(Int.self, forKey: .limitWindowSeconds)
        resetAt = (try? container.decodeIfPresent(FlexDouble.self, forKey: .resetAt))?.value
    }
}

struct AdditionalRateLimit: Decodable, Encodable {
    var limitName: String?
    var meteredFeature: String?
    var rateLimit: RateLimit?

    enum CodingKeys: String, CodingKey {
        case limitName = "limit_name"
        case meteredFeature = "metered_feature"
        case rateLimit = "rate_limit"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        limitName = try? container.decodeIfPresent(String.self, forKey: .limitName)
        meteredFeature = try? container.decodeIfPresent(String.self, forKey: .meteredFeature)
        rateLimit = try? container.decodeIfPresent(RateLimit.self, forKey: .rateLimit)
    }
}

struct ModelAvailability: Decodable, Encodable {
    var available: Bool?
    var creditsWouldEnable: Bool?

    enum CodingKeys: String, CodingKey {
        case available
        case creditsWouldEnable = "credits_would_enable"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        available = try? container.decodeIfPresent(Bool.self, forKey: .available)
        creditsWouldEnable = try? container.decodeIfPresent(Bool.self, forKey: .creditsWouldEnable)
    }
}

struct CreditDetails: Decodable, Encodable {
    var hasCredits: Bool
    var unlimited: Bool
    var balance: Double?
    var approxLocalMessages: [Double]?
    var approxCloudMessages: [Double]?

    enum CodingKeys: String, CodingKey {
        case hasCredits = "has_credits"
        case unlimited
        case balance
        case approxLocalMessages = "approx_local_messages"
        case approxCloudMessages = "approx_cloud_messages"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hasCredits = (try? container.decode(Bool.self, forKey: .hasCredits)) ?? false
        unlimited = (try? container.decode(Bool.self, forKey: .unlimited)) ?? false
        balance = (try? container.decodeIfPresent(FlexDouble.self, forKey: .balance))?.value
        approxLocalMessages = (try? container.decode([FlexDouble].self, forKey: .approxLocalMessages))?
            .map(\.value)
        approxCloudMessages = (try? container.decode([FlexDouble].self, forKey: .approxCloudMessages))?
            .map(\.value)
    }
}

struct SpendControl: Decodable, Encodable {
    var reached: Bool?
    var individualLimit: SpendControlLimit?

    enum CodingKeys: String, CodingKey {
        case reached
        case individualLimit = "individual_limit"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        reached = try? container.decodeIfPresent(Bool.self, forKey: .reached)
        individualLimit = try? container.decodeIfPresent(SpendControlLimit.self, forKey: .individualLimit)
    }
}

struct SpendControlLimit: Decodable, Encodable {
    var limit: Double?
    var used: Double?
    var remainingPercent: Double?
    var resetsAt: Date?

    enum CodingKeys: String, CodingKey {
        case limit
        case used
        case remainingPercent = "remaining_percent"
        case resetsAt = "resets_at"
        case resetAt = "reset_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        limit = (try? container.decodeIfPresent(FlexDouble.self, forKey: .limit))?.value
        used = (try? container.decodeIfPresent(FlexDouble.self, forKey: .used))?.value
        remainingPercent = (try? container.decodeIfPresent(FlexDouble.self, forKey: .remainingPercent))?.value
        if let epoch = (try? container.decodeIfPresent(FlexDouble.self, forKey: .resetsAt))?.value {
            resetsAt = Date(timeIntervalSince1970: epoch)
        } else if let epoch = (try? container.decodeIfPresent(FlexDouble.self, forKey: .resetAt))?.value {
            resetsAt = Date(timeIntervalSince1970: epoch)
        } else {
            resetsAt = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(limit, forKey: .limit)
        try container.encodeIfPresent(used, forKey: .used)
        try container.encodeIfPresent(remainingPercent, forKey: .remainingPercent)
        if let resetsAt {
            try container.encode(resetsAt.timeIntervalSince1970, forKey: .resetsAt)
        }
    }
}

struct ResetCreditsSummary: Decodable, Encodable {
    var availableCount: Int?
    var applicableAvailableCount: Int?

    enum CodingKeys: String, CodingKey {
        case availableCount = "available_count"
        case applicableAvailableCount = "applicable_available_count"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        availableCount = try? container.decodeIfPresent(Int.self, forKey: .availableCount)
        applicableAvailableCount = try? container.decodeIfPresent(Int.self, forKey: .applicableAvailableCount)
    }
}

struct ResetCreditsResponse: Decodable {
    var credits: [ResetCredit]
    var availableCount: Int?
    var totalEarnedCount: Int?

    enum CodingKeys: String, CodingKey {
        case credits
        case availableCount = "available_count"
        case totalEarnedCount = "total_earned_count"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        credits = (try? container.decode([Lossy<ResetCredit>].self, forKey: .credits))?.compactMap(\.value) ?? []
        availableCount = try? container.decodeIfPresent(Int.self, forKey: .availableCount)
        totalEarnedCount = try? container.decodeIfPresent(Int.self, forKey: .totalEarnedCount)
    }
}

struct ResetCredit: Decodable, Encodable, Identifiable {
    var id: String?
    var title: String?
    var status: String?
    var grantedAt: Date?
    var expiresAt: Date?

    var stableID: String {
        id ?? title ?? "reset-credit"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case status
        case grantedAt = "granted_at"
        case expiresAt = "expires_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try? container.decodeIfPresent(String.self, forKey: .id)
        title = try? container.decodeIfPresent(String.self, forKey: .title)
        status = try? container.decodeIfPresent(String.self, forKey: .status)
        grantedAt = try? container.decodeIfPresent(Date.self, forKey: .grantedAt)
        expiresAt = try? container.decodeIfPresent(Date.self, forKey: .expiresAt)
    }
}
