/// Strategies for resolving conflicts between local and remote changes.
///
/// When a record is modified both locally (offline) and remotely (by another device),
/// the sync engine must decide which version to keep.
enum SyncStrategy {
  /// Remote version always wins. Local changes are discarded.
  ///
  /// Use this when the server is the source of truth and local changes
  /// should not override remote updates.
  ///
  /// Example: Administrative settings, validation rules
  serverWins,

  /// Local version always wins. Remote changes are ignored.
  ///
  /// Use this when user's local work is always correct and should be
  /// preserved even if the server has updates.
  ///
  /// Example: User preferences, draft content
  localWins,

  /// Latest modification time wins.
  ///
  /// Compare the `updated_at` timestamps and keep the most recently
  /// modified version (local or remote).
  ///
  /// Example: General data synchronization with time-based conflict resolution
  lastWriteWins,

  /// Custom resolver function decides the outcome.
  ///
  /// Use this for application-specific conflict resolution logic.
  /// The resolver receives both local and remote versions and returns
  /// one of [UseLocal], [UseRemote], or [UseMerged].
  ///
  /// Example: Deep merge strategies, weighted scoring, business logic
  custom,
}

/// Explicit result type for custom conflict resolvers.
/// Using a sealed class makes the intent clear and avoids null-as-signal ambiguity.
sealed class ConflictResolution {
  const ConflictResolution();
}

/// Keep the local (dirty) record. The remote update is ignored.
class UseLocal extends ConflictResolution {
  const UseLocal();
}

/// Overwrite local with the remote record.
class UseRemote extends ConflictResolution {
  /// The resolved data (usually the remote record)
  final Map<String, dynamic> data;

  const UseRemote(this.data);
}

/// Save a manually merged record combining both versions.
class UseMerged extends ConflictResolution {
  /// The merged data combining elements from both versions
  final Map<String, dynamic> data;

  const UseMerged(this.data);
}
