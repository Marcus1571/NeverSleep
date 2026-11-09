extension SleepController.Outcome {
    var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }
}
