/// Token rates in USD per million tokens for one model family.
internal struct ModelRates: Equatable, Sendable {
    private enum Constants {
        static let opusInput = 15.0
        static let opusOutput = 75.0
        static let opusCacheWrite = 18.75
        static let opusCacheRead = 1.50
        static let sonnetInput = 3.0
        static let sonnetOutput = 15.0
        static let sonnetCacheWrite = 3.75
        static let sonnetCacheRead = 0.30
        static let haikuInput = 1.0
        static let haikuOutput = 5.0
        static let haikuCacheWrite = 1.25
        static let haikuCacheRead = 0.10
    }

    internal static let opus = Self(
        input: Constants.opusInput,
        output: Constants.opusOutput,
        cacheWrite: Constants.opusCacheWrite,
        cacheRead: Constants.opusCacheRead
    )
    internal static let sonnet = Self(
        input: Constants.sonnetInput,
        output: Constants.sonnetOutput,
        cacheWrite: Constants.sonnetCacheWrite,
        cacheRead: Constants.sonnetCacheRead
    )
    internal static let haiku = Self(
        input: Constants.haikuInput,
        output: Constants.haikuOutput,
        cacheWrite: Constants.haikuCacheWrite,
        cacheRead: Constants.haikuCacheRead
    )

    internal let input: Double
    internal let output: Double
    internal let cacheWrite: Double
    internal let cacheRead: Double
}
