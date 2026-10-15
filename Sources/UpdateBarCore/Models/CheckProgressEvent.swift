public struct CheckProgressEvent: Equatable {
    public var phase: CheckProgressPhase
    public var id: String
    public var name: String
    public var result: CheckResult?
    /// A fresh local version read during this check, never a cached state value.
    public var observedCurrent: String?

    public init(
        phase: CheckProgressPhase, id: String, name: String, result: CheckResult? = nil,
        observedCurrent: String? = nil
    ) {
        self.phase = phase
        self.id = id
        self.name = name
        self.result = result
        self.observedCurrent = observedCurrent.map(SecretRedactor.redact)
    }
}

public enum CheckProgressPhase: Equatable {
    case itemStarted
    case itemFinished
}
