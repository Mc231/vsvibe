import Foundation

internal enum ModelPricing {
    private enum Constants {
        static let tokensPerMillion = 1_000_000.0
        /// All current Claude 4.x models advertise 200k token context.
        static let contextWindow = 200_000
    }

    /// Rates by model-name prefix.
    private static let table: [String: ModelRates] = [
        "claude-opus-4-7": .opus,
        "claude-opus-4-6": .opus,
        "claude-opus-4-5": .opus,
        "claude-opus-4": .opus,
        "claude-sonnet-4-6": .sonnet,
        "claude-sonnet-4-5": .sonnet,
        "claude-sonnet-4": .sonnet,
        "claude-3-5-sonnet": .sonnet,
        "claude-haiku-4-5": .haiku,
        "claude-haiku-4": .haiku,
        "claude-3-5-haiku": .haiku
    ]

    internal static func rates(for model: String?) -> ModelRates {
        guard let model else {
            return .opus
        }
        for (prefix, rates) in table where model.hasPrefix(prefix) {
            return rates
        }
        // Heuristic by family if exact key is missing
        if model.contains("opus") {
            return .opus
        }
        if model.contains("sonnet") {
            return .sonnet
        }
        if model.contains("haiku") {
            return .haiku
        }
        return .opus
    }

    internal static func cost(model: String?, usage: SessionUsage) -> Double {
        let rates = rates(for: model)
        let input = Double(usage.totalInput) * rates.input / Constants.tokensPerMillion
        let output = Double(usage.totalOutput) * rates.output / Constants.tokensPerMillion
        let cacheWrite = Double(usage.totalCacheCreation) * rates.cacheWrite / Constants.tokensPerMillion
        let cacheRead = Double(usage.totalCacheRead) * rates.cacheRead / Constants.tokensPerMillion
        return input + output + cacheWrite + cacheRead
    }

    internal static func contextWindow(for _: String?) -> Int {
        Constants.contextWindow
    }
}
