import 'dart:async';

import 'package:erp_client/core/models/access_source.dart';
import 'package:erp_client/features/workspace/data/access_repository.dart';
import 'package:erp_client/features/workspace/presentation/access_gate_view_model.dart';
import 'package:flutter_test/flutter_test.dart';

class _Source implements AccessSource {
  @override
  String account = 'synthetic';
  @override
  int accessRevision = 0;
  @override
  bool accessReady = true;
}

class _Repository implements AccessRepository {
  @override
  final _Source source = _Source();
  final listeners = <void Function()>{};
  @override
  void addListener(void Function() listener) => listeners.add(listener);
  @override
  void removeListener(void Function() listener) => listeners.remove(listener);
  void publish({required bool ready}) {
    source.accessReady = ready;
    for (final callback in listeners.toList()) {
      callback();
    }
  }
}

void main() {
  test('initial readiness does not replay a reload or business action', () {
    final repository = _Repository();
    var reads = 0;
    final model = AccessGateViewModel(
      repository,
      revalidate: () async {
        reads++;
      },
    );
    expect(model.valid, isTrue);
    expect(reads, 0);
    model.dispose();
    expect(repository.listeners, isEmpty);
  });
  test('dirty access hides data immediately and fresh access waits for the child read', () async {
    final repository = _Repository();
    final reading = Completer<void>();
    final model = AccessGateViewModel(
      repository,
      revalidate: () => reading.future,
    );
    repository.publish(ready: false);
    expect(model.valid, isFalse);
    repository.source.accessRevision++;
    repository.publish(ready: true);
    expect(model.valid, isFalse);
    reading.complete();
    await Future<void>.delayed(Duration.zero);
    expect(model.valid, isTrue);
    model.dispose();
  });
  test(
    'an older successful read cannot override the latest failed revalidation',
    () async {
      final repository = _Repository();
      final reads = <Completer<void>>[];
      final model = AccessGateViewModel(
        repository,
        revalidate: () {
          final next = Completer<void>();
          reads.add(next);
          return next.future;
        },
        validateInitially: true,
      );
      final first = model.refresh(), next = model.refresh();
      reads[1].completeError(StateError('Latest failed'));
      await next;
      reads[0].complete();
      await first;
      expect(model.valid, isFalse);
      expect(model.error, contains('Latest failed'));
      model.dispose();
    },
  );
  test(
    'account change or disposal rejects a pending child revalidation',
    () async {
      for (final dispose in [false, true]) {
        final repository = _Repository();
        final reading = Completer<void>();
        final model = AccessGateViewModel(
          repository,
          revalidate: () => reading.future,
          validateInitially: true,
        );
        final checking = model.refresh();
        if (dispose) {
          model.dispose();
        } else {
          repository.source.account = 'replacement';
          repository.publish(ready: false);
        }
        reading.complete();
        await checking;
        expect(model.valid, isFalse);
        if (!dispose) model.dispose();
      }
    },
  );
}
