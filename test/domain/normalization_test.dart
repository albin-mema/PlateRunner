import 'package:flutter_test/flutter_test.dart';
import 'package:plate_runner/domain/plate_entities.dart';

/// Helper to unwrap a Success<T,E> or throw with diagnostic message.
T expectSuccess<T, E>(Result<T, E> result) {
  if (result is Success<T, E>) return result.value;
  fail('Expected Success but got $result');
}

/// Helper to assert failure type.
void expectFailureOfType<T, E>(
  Result<T, E> result,
  Type failureType, {
  String? containing,
}) {
  expect(result, isA<Failure<T, E>>(),
      reason: 'Expected Failure of $failureType but got $result');
  if (result is Failure<T, E>) {
    expect(result.error.runtimeType, equals(failureType),
        reason: 'Failure type mismatch: ${result.error}');
    if (containing != null) {
      expect(result.error.toString(), contains(containing));
    }
  }
}

void main() {
  group('normalizePlate()', () {
    test('uppercases and trims whitespace', () {
      final r = normalizePlate('  abC123  ');
      final plate = expectSuccess(r);
      expect(plate.value, equals('ABC123'));
    });

    test('replaces internal spaces/underscores with single dash', () {
      final r = normalizePlate('ab c__12 3');
      final plate = expectSuccess(r);
      expect(plate.value, equals('AB-C-12-3'));
      // Ensure no double dashes remain (collapse logic)
      expect(plate.value.contains('--'), isFalse);
    });

    test('strips non-alphanumeric (except dash) characters', () {
      final r = normalizePlate('A*B#C@1!2?3');
      final plate = expectSuccess(r);
      expect(plate.value, equals('ABC123'));
    });

    test('collapses multiple dashes and trims leading/trailing dash', () {
      final r = normalizePlate('--ABC--123---');
      final plate = expectSuccess(r);
      expect(plate.value, equals('ABC-123'));
    });

    test('fails when resulting string too short', () {
      final r = normalizePlate('A');
      expectFailureOfType(r, InvalidPlateFormat);
    });

    test('fails when invalid characters only', () {
      final r = normalizePlate('@@@');
      expectFailureOfType(r, InvalidPlateFormat);
    });

    test('idempotence: normalizing an already normalized plate returns same value', () {
      final first = expectSuccess(normalizePlate('ABC-123'));
      final second = expectSuccess(normalizePlate(first.value));
      expect(second.value, equals(first.value));
    });

    test('does not apply ambiguous substitutions (O vs 0)', () {
      final r1 = expectSuccess(normalizePlate('O0O'));
      // Expect original pattern with both O and 0 preserved (after uppercase)
      expect(r1.value, equals('O0O'));
    });

    test('max length accepted (16 chars)', () {
      final raw = 'ABCD1234EFGH5678'; // 16 chars
      final plate = expectSuccess(normalizePlate(raw));
      expect(plate.value.length, equals(16));
    });

    test('over max length (17) rejected', () {
      final raw = 'ABCD1234EFGH56789'; // 17
      final result = normalizePlate(raw);
      expectFailureOfType(result, InvalidPlateFormat);
    });
  });

  group('ConfidenceScore.create()', () {
    test('accepts boundary 0 and 1', () {
      expectSuccess(ConfidenceScore.create(0)).value;
      expectSuccess(ConfidenceScore.create(1)).value;
    });

    test('rejects NaN', () {
      final r = ConfidenceScore.create(double.nan);
      expectFailureOfType(r, ConfidenceOutOfRange);
    });

    test('rejects negative', () {
      final r = ConfidenceScore.create(-0.01);
      expectFailureOfType(r, ConfidenceOutOfRange);
    });

    test('rejects >1', () {
      final r = ConfidenceScore.create(1.00001);
      expectFailureOfType(r, ConfidenceOutOfRange);
    });
  });

  group('dedupeEvents()', () {
    PlateId newId(String id) => PlateId.fromString(id);

    NormalizedPlate plate(String v) =>
        expectSuccess(NormalizedPlate.create(v));

    ConfidenceScore conf(double v) =>
        expectSuccess(ConfidenceScore.create(v));

    RecognitionEvent event(String id, String p, int t) => RecognitionEvent(
          plateId: newId(id),
          plate: plate(p),
          confidence: conf(0.9),
          timestamp: t,
        );

    test('skips event inside window with same plate', () {
      final existing = [event('1', 'ABC123', 1000)];
      final incoming = [event('2', 'ABC123', 1200)]; // within 300ms
      final merged = dedupeEvents(
        existing: existing,
        incoming: incoming,
        window: const Duration(seconds: 3),
      );
      expect(merged.length, equals(1));
    });

    test('accepts event outside window', () {
      final existing = [event('1', 'ABC123', 1000)];
      final incoming = [event('2', 'ABC123', 5000)]; // 4s later
      final merged = dedupeEvents(
        existing: existing,
        incoming: incoming,
        window: const Duration(seconds: 3),
      );
      expect(merged.length, equals(2));
    });

    test('does not dedupe different plates even if close in time', () {
      final existing = [event('1', 'ABC123', 1000)];
      final incoming = [event('2', 'XYZ999', 1100)];
      final merged = dedupeEvents(
        existing: existing,
        incoming: incoming,
        window: const Duration(seconds: 3),
      );
      expect(merged.length, equals(2));
    });
  });

  // Placeholder: Additional property-based tests can be added using a future
  // lightweight generator harness (see testing strategy doc).
}