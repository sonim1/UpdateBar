public struct CheckProgressEvent: Equatable {
    public var phase: CheckProgressPhase
    public var id: String
    public var name: String
    public var result: CheckResult?

    public init(phase: CheckProgressPhase, id: String, name: String, result: CheckResult? = nil) {
        self.phase = phase
        self.id = id
        self.name = name
        self.result = result
    }
}

public enum CheckProgressPhase: Equatable {
    case itemStarted
    case itemFinished
}
