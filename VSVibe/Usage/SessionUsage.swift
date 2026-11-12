import Foundation

internal struct SessionUsage: Equatable {
    private enum Constants {
        static let percentScale = 100.0
    }

    internal var totalInput: Int = 0
    internal var totalOutput: Int = 0
    internal var totalCacheCreation: Int = 0
    internal var totalCacheRead: Int = 0

    /// Tokens sent to the model on the last request. Used to compute context %.
    internal var lastContextTokens: Int = 0
    internal var lastModel: String?
    internal var messageCount: Int = 0
    internal var updatedAt: Date?

    /// Best-effort context window size based on the most recent model name.
    internal var contextWindow: Int {
        ModelPricing.contextWindow(for: lastModel)
    }

    internal var contextPercent: Double {
        guard contextWindow > 0 else {
            return 0
        }
        return min(1.0, Double(lastContextTokens) / Double(contextWindow)) * Constants.percentScale
    }

    internal var estimatedCostUSD: Double {
        ModelPricing.cost(model: lastModel, usage: self)
    }
}
