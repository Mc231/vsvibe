import Foundation

struct SessionUsage: Equatable {
    var totalInput: Int = 0
    var totalOutput: Int = 0
    var totalCacheCreation: Int = 0
    var totalCacheRead: Int = 0

    /// Tokens sent to the model on the last request. Used to compute context %.
    var lastContextTokens: Int = 0
    var lastModel: String?
    var messageCount: Int = 0
    var updatedAt: Date?

    /// Best-effort context window size based on the most recent model name.
    var contextWindow: Int {
        ModelPricing.contextWindow(for: lastModel)
    }

    var contextPercent: Double {
        guard contextWindow > 0 else { return 0 }
        return min(1.0, Double(lastContextTokens) / Double(contextWindow)) * 100
    }

    var estimatedCostUSD: Double {
        ModelPricing.cost(model: lastModel, usage: self)
    }
}

enum ModelPricing {
    /// Rates in USD per million tokens: (input, output, cacheWrite, cacheRead).
    private static let table: [String: (Double, Double, Double, Double)] = [
        "claude-opus-4-7":          (15.0, 75.0, 18.75, 1.50),
        "claude-opus-4-6":          (15.0, 75.0, 18.75, 1.50),
        "claude-opus-4-5":          (15.0, 75.0, 18.75, 1.50),
        "claude-opus-4":            (15.0, 75.0, 18.75, 1.50),
        "claude-sonnet-4-6":        (3.0,  15.0, 3.75,  0.30),
        "claude-sonnet-4-5":        (3.0,  15.0, 3.75,  0.30),
        "claude-sonnet-4":          (3.0,  15.0, 3.75,  0.30),
        "claude-3-5-sonnet":        (3.0,  15.0, 3.75,  0.30),
        "claude-haiku-4-5":         (1.0,  5.0,  1.25,  0.10),
        "claude-haiku-4":           (1.0,  5.0,  1.25,  0.10),
        "claude-3-5-haiku":         (1.0,  5.0,  1.25,  0.10)
    ]

    private static let opusFallback: (Double, Double, Double, Double) = (15.0, 75.0, 18.75, 1.50)

    static func rates(for model: String?) -> (input: Double, output: Double, cacheWrite: Double, cacheRead: Double) {
        guard let model else { return opusFallback }
        for (prefix, rates) in table where model.hasPrefix(prefix) {
            return rates
        }
        // Heuristic by family if exact key is missing
        if model.contains("opus") { return opusFallback }
        if model.contains("sonnet") { return (3.0, 15.0, 3.75, 0.30) }
        if model.contains("haiku") { return (1.0, 5.0, 1.25, 0.10) }
        return opusFallback
    }

    static func cost(model: String?, usage: SessionUsage) -> Double {
        let r = rates(for: model)
        let input = Double(usage.totalInput) * r.input / 1_000_000
        let output = Double(usage.totalOutput) * r.output / 1_000_000
        let cacheW = Double(usage.totalCacheCreation) * r.cacheWrite / 1_000_000
        let cacheR = Double(usage.totalCacheRead) * r.cacheRead / 1_000_000
        return input + output + cacheW + cacheR
    }

    static func contextWindow(for model: String?) -> Int {
        // All current Claude 4.x models advertise 200k token context.
        return 200_000
    }
}
