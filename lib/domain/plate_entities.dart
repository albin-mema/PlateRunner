/// PlateRunner Domain Entities & Pure Services (Initial Scaffold)
///
/// This file defines foundational immutable value objects and pure service
/// function placeholders described in the domain model documentation.
/// Everything here is intentionally framework‑agnostic and side‑effect free:
/// - No logging
/// - No IO
/// - No platform APIs
///
/// NOTE: ID / time / UUID generation must be injected from the imperative
/// shell (e.g., use cases) — never generated internally so tests remain
/// deterministic.
///
/// References:
/// - docs/data/domain_model.md
/// - docs/architecture/overview.md
///
/// Keep this file focused and below ~400 lines; split when concepts grow.

/// Result type (lightweight) for domain operations.
/// Avoid throwing for recoverable domain errors; return Failure instead.
sealed class Result<T, E> {
  const Result();
  bool get isSuccess => this is Success<T, E>;
  bool get isFailure => this is Failure<T, E>;

  T expect(String message) {
    if (this is Success<T, E>) return (this as Success<T, E>).value;
    throw StateError(message);
  }

  E? errorOrNull() => this is Failure<T, E> ? (this as Failure<T, E>).error : null;
}

class Success<T, E> extends Result<T, E> {
  final T value;
  const Success(this.value);
  @override
  String toString() => 'Success($value)';
}

class Failure<T, E> extends Result<T, E> {
  final E error;
  const Failure(this.error);
  @override
  String toString() => 'Failure($error)';
}

/// Domain error taxonomy (initial subset).
sealed class DomainError {
  const DomainError();
}

class InvalidPlateFormat extends DomainError {
  final String raw;
  const InvalidPlateFormat(this.raw);
  @override
  String toString() => 'InvalidPlateFormat(raw="$raw")';
}

class ConfidenceOutOfRange extends DomainError {
  final double value;
  const ConfidenceOutOfRange(this.value);
  @override
  String toString() => 'ConfidenceOutOfRange(value=$value)';
}

class TimestampSkew extends DomainError {
  final int first;
  final int last;
  const TimestampSkew(this.first, this.last);
  @override
  String toString() => 'TimestampSkew(first=$first,last=$last)';
}

/// Plate identifier (surrogate). Generation happens outside domain layer.
final class PlateId {
  final String value;
  const PlateId._(this.value);

  static PlateId fromString(String v) {
    if (v.isEmpty) {
      throw ArgumentError.value(v, 'v', 'PlateId cannot be empty');
    }
    return PlateId._(v);
  }

  @override
  String toString() => value;
  @override
  bool operator ==(Object other) => other is PlateId && other.value == value;
  @override
  int get hashCode => value.hashCode;
}

/// Normalized plate string wrapper (enforces format invariant).
final class NormalizedPlate {
  static final RegExp _pattern = RegExp(r'^[A-Z0-9\-]{2,16}$');

  final String value;
  const NormalizedPlate._(this.value);

  static Result<NormalizedPlate, DomainError> create(String candidate) {
    if (_pattern.hasMatch(candidate)) {
      return Success(NormalizedPlate._(candidate));
    }
    return Failure(InvalidPlateFormat(candidate));
  }

  @override
  String toString() => value;
  @override
  bool operator ==(Object other) => other is NormalizedPlate && other.value == value;
  @override
  int get hashCode => value.hashCode;
}

/// Confidence score (0..1 inclusive)
final class ConfidenceScore {
  final double value;
  const ConfidenceScore._(this.value);

  static Result<ConfidenceScore, DomainError> create(double raw) {
    if (raw.isNaN || raw < 0 || raw > 1) {
      return Failure(ConfidenceOutOfRange(raw));
    }
    // Clamp tiny floating drift
    final v = raw < 0 ? 0.0 : (raw > 1 ? 1.0 : raw);
    return Success(ConfidenceScore._(v));
  }

  ConfidenceScore clampMin(double min) =>
      value < min ? ConfidenceScore._(min) : this;

  @override
  String toString() => value.toStringAsFixed(4);
  @override
  bool operator ==(Object other) => other is ConfidenceScore && other.value == value;
  @override
  int get hashCode => value.hashCode;
}

/// Time in epoch milliseconds (named type alias for clarity).
typedef EpochMs = int;

/// A single recognition event (pure data).
final class RecognitionEvent {
  final PlateId plateId; // May be placeholder for yet-unknown (temp) id.
  final NormalizedPlate plate;
  final ConfidenceScore confidence;
  final EpochMs timestamp;
  final double? latitude;
  final double? longitude;

  const RecognitionEvent({
    required this.plateId,
    required this.plate,
    required this.confidence,
    required this.timestamp,
    this.latitude,
    this.longitude,
  });

  RecognitionEvent copyWith({
    PlateId? plateId,
    NormalizedPlate? plate,
    ConfidenceScore? confidence,
    EpochMs? timestamp,
    double? latitude,
    double? longitude,
    bool clearGeo = false,
  }) =>
      RecognitionEvent(
        plateId: plateId ?? this.plateId,
        plate: plate ?? this.plate,
        confidence: confidence ?? this.confidence,
        timestamp: timestamp ?? this.timestamp,
        latitude: clearGeo ? null : (latitude ?? this.latitude),
        longitude: clearGeo ? null : (longitude ?? this.longitude),
      );
}

/// Plate aggregate (simplified) captured at query time.
final class PlateRecord {
  final PlateId id;
  final NormalizedPlate plate;
  final EpochMs firstSeen;
  final EpochMs lastSeen;
  final int totalRecognitions;

  const PlateRecord({
    required this.id,
    required this.plate,
    required this.firstSeen,
    required this.lastSeen,
    required this.totalRecognitions,
  });

  PlateRecord withNewEvent(EpochMs ts) {
    final newLast = ts > lastSeen ? ts : lastSeen;
    return PlateRecord(
      id: id,
      plate: plate,
      firstSeen: firstSeen,
      lastSeen: newLast,
      totalRecognitions: totalRecognitions + 1,
    );
  }

  Result<PlateRecord, DomainError> validateTemporal() {
    if (firstSeen > lastSeen) {
      return Failure(TimestampSkew(firstSeen, lastSeen));
    }
    return Success(this);
  }
}

/// Upsert plan describing persistence intent (pure DTO).
sealed class UpsertPlan {
  const UpsertPlan();
}

class InsertNewPlateAndEvent extends UpsertPlan {
  final PlateId newPlateId;
  final NormalizedPlate plate;
  final RecognitionEvent event;
  const InsertNewPlateAndEvent({
    required this.newPlateId,
    required this.plate,
    required this.event,
  });
}

class InsertEventAndUpdatePlate extends UpsertPlan {
  final PlateRecord updatedPlate;
  final RecognitionEvent event;
  const InsertEventAndUpdatePlate({
    required this.updatedPlate,
    required this.event,
  });
}

/// Context passed to confidence fusion (keep minimal; expand as heuristics grow).
class ConfidenceFusionContext {
  final bool lowLight;
  final bool partial;
  final bool blurred;
  final double rawScore;
  const ConfidenceFusionContext({
    required this.rawScore,
    this.lowLight = false,
    this.partial = false,
    this.blurred = false,
  });
}

/// Normalize raw plate text into canonical uppercase form and strip
/// non-alphanumeric (except dash). Region-specific rules can be added later.
///
/// Returns:
/// - Success<NormalizedPlate> if normalization yields valid pattern.
/// - Failure<InvalidPlateFormat> if still invalid.
///
/// This is intentionally conservative; do not apply ambiguous substitutions
/// (e.g., O -> 0) here — delegate to heuristic layers if needed.
Result<NormalizedPlate, DomainError> normalizePlate(String raw, {String? region}) {
  var cleaned = raw.trim().toUpperCase();
  // Replace spaces / underscores with dash if they appear between groups.
  cleaned = cleaned.replaceAll(RegExp(r'[\s_]+'), '-');
  // Remove any characters not A-Z / 0-9 / dash.
  cleaned = cleaned.replaceAll(RegExp(r'[^A-Z0-9\-]'), '');
  // Collapse multiple dashes.
  cleaned = cleaned.replaceAll(RegExp(r'-{2,}'), '-');
  // Strip leading/trailing dash.
  cleaned = cleaned.replaceAll(RegExp(r'^-+'), '').replaceAll(RegExp(r'-+$'), '');

  // Potential region-based adjustments (placeholder):
  if (region != null) {
    // TODO(region-rules): plug in region-specific normalization if required.
  }

  return NormalizedPlate.create(cleaned);
}

/// Fuse confidence given raw score + heuristic context.
/// Simple initial heuristic:
/// - Start with rawScore
/// - Apply penalties for partial / blurred / lowLight
/// - Clamp to [0,1]
Result<ConfidenceScore, DomainError> fuseConfidence(ConfidenceFusionContext ctx) {
  double score = ctx.rawScore;
  // Penalties (tune later)
  if (ctx.partial) score -= 0.10;
  if (ctx.blurred) score -= 0.08;
  if (ctx.lowLight) score -= 0.05;

  // Floor at minimal viable threshold (never negative).
  if (score < 0) score = 0;
  if (score > 1) score = 1;

  return ConfidenceScore.create(score);
}

/// Deduplicate events against existing window based on time distance.
/// Returns new list containing existing + accepted new events (no mutation).
///
/// Criterion (MVP):
/// - For each new event: if there exists an event in `existing` with same plate
///   and within `window` (|t_new - t_existing| <= window), then skip it.
/// - Future: incorporate geo distance.
List<RecognitionEvent> dedupeEvents({
  required List<RecognitionEvent> existing,
  required List<RecognitionEvent> incoming,
  required Duration window,
}) {
  if (incoming.isEmpty) return existing;
  final merged = List<RecognitionEvent>.from(existing);
  for (final e in incoming) {
    final duplicate = existing.any((prev) =>
        prev.plate == e.plate &&
        (e.timestamp - prev.timestamp).abs() <= window.inMilliseconds);
    if (!duplicate) merged.add(e);
  }
  return merged;
}

/// Build an upsert plan given optional existing plate record and new event.
/// The event's plateId may be a temporary placeholder; if inserting a new plate,
/// the caller must provide a freshly generated PlateId externally and pass via
/// `newPlateIdProvider`.
UpsertPlan buildUpsertPlan({
  required PlateRecord? existing,
  required RecognitionEvent event,
  required PlateId Function() newPlateIdProvider,
}) {
  if (existing == null) {
    final newId = newPlateIdProvider();
    final eventWithId = event.copyWith(plateId: newId);
    return InsertNewPlateAndEvent(
      newPlateId: newId,
      plate: event.plate,
      event: eventWithId,
    );
  }
  final updated = existing.withNewEvent(event.timestamp);
  final eventAligned = event.copyWith(plateId: existing.id);
  return InsertEventAndUpdatePlate(
    updatedPlate: updated,
    event: eventAligned,
  );
}

/// Aggregate basic statistics for a plate's events (placeholder).
class PlateStats {
  final NormalizedPlate plate;
  final int count;
  final EpochMs firstSeen;
  final EpochMs lastSeen;
  const PlateStats({
    required this.plate,
    required this.count,
    required this.firstSeen,
    required this.lastSeen,
  });
}

/// Compute aggregated statistics (pure, O(n)).
PlateStats aggregatePlateStats(List<RecognitionEvent> events) {
  if (events.isEmpty) {
    throw ArgumentError('Cannot aggregate empty event list');
  }
  events.sort((a, b) => a.timestamp.compareTo(b.timestamp)); // stable identity
  final first = events.first.timestamp;
  final last = events.last.timestamp;
  return PlateStats(
    plate: events.first.plate,
    count: events.length,
    firstSeen: first,
    lastSeen: last,
  );
}

/// Simple invariant checker utility (dev/testing aid).
void assertInvariants(PlateRecord record) {
  if (record.firstSeen > record.lastSeen) {
    throw StateError('Invariant violated: firstSeen > lastSeen for ${record.id}');
  }
  if (record.totalRecognitions <= 0) {
    throw StateError('Invariant violated: totalRecognitions <= 0 for ${record.id}');
  }
}

/// Future extension placeholder types (commented until needed):
/// - GeoPoint
/// - RecognitionCluster
/// - QualityFlags bitmask
///
/// Keep expansions incremental & measured.
///
/// End of file.