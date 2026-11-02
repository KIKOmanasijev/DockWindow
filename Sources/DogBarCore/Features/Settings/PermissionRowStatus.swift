/// A pending first check is distinct from a denied permission. Rechecks retain the known result.
enum PermissionRowStatus: Equatable {
    case checking, granted, missing
    init(hasChecked: Bool, granted: Bool) {
        self = hasChecked ? (granted ? .granted : .missing) : .checking
    }
    var label: String {
        switch self { case .checking: return "Checking…"; case .granted: return "Allowed"; case .missing: return "Not allowed" }
    }
    var symbol: String {
        switch self { case .checking: return "clock"; case .granted: return "checkmark"; case .missing: return "exclamationmark" }
    }
}
