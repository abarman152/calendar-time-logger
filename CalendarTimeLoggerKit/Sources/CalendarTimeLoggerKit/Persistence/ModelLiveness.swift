import SwiftData

extension PersistentModel {
    /// Whether the model still belongs to a context and hasn't been deleted.
    ///
    /// Once a delete is saved, a model keeps its identity but loses its context,
    /// and reading any attribute that wasn't already loaded is a fatal error
    /// ("backing data was detached from a context"). `isDeleted` alone isn't
    /// enough: it is only true until the delete is saved. Code that holds a
    /// model across a delete, a sheet, or an `await` checks this first.
    public var isLive: Bool { modelContext != nil && !isDeleted }
}
