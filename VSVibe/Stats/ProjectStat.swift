/// All persisted stats for one project. Per-day buckets hold the time series;
/// `transcriptBytes` records how far each Claude transcript file has been
/// scanned so re-scans only read new bytes.
internal struct ProjectStat: Codable {
    internal var days: [String: DayStat] = [:]
    internal var transcriptBytes: [String: UInt64] = [:]
}
