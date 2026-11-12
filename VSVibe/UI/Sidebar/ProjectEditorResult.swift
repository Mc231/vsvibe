internal struct ProjectEditorResult {
    internal let name: String
    internal let launchCommand: String
    internal let openImmediately: Bool
    internal let labelIDs: [ProjectLabel.ID]

    internal init(
        name: String,
        launchCommand: String,
        openImmediately: Bool,
        labelIDs: [ProjectLabel.ID] = []
    ) {
        self.name = name
        self.launchCommand = launchCommand
        self.openImmediately = openImmediately
        self.labelIDs = labelIDs
    }
}
