enum SyncStrategy { serverWins, localWins, lastWriteWins, custom }

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
  final Map<String, dynamic> data;
  const UseRemote(this.data);
}

/// Save a manually merged record.
class UseMerged extends ConflictResolution {
  final Map<String, dynamic> data;
  const UseMerged(this.data);
}
