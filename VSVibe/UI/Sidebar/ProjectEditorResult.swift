internal struct ProjectEditorResult {
    internal let name: String
    internal let location: ProjectLocation
    internal let openImmediately: Bool
    internal let labelIDs: [ProjectLabel.ID]

    internal init(
        name: String,
        location: ProjectLocation,
        openImmediately: Bool,
        labelIDs: [ProjectLabel.ID] = []
    ) {
        self.name = name
        self.location = location
        self.openImmediately = openImmediately
        self.labelIDs = labelIDs
    }
}
