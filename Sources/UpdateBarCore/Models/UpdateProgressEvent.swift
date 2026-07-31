/// Live progress from an update run.
///
/// An enum rather than a struct mirroring `CheckProgressEvent` because
/// `.planned` carries a plan payload the flat shape cannot express without
/// dead fields.
public enum UpdateProgressEvent: Equatable {
    /// The full plan, in order, before anything runs.
    case planned([UpdatePlanItem])
    case itemStarted(id: String, name: String)
    case itemFinished(UpdateResult)
}
