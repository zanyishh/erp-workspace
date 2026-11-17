import 'dart:async';
import 'dart:typed_data';

import 'package:erp_client/erp_api.dart';
import 'package:erp_client/features/imported_history/models/history_models.dart';
import 'package:erp_client/features/imported_history/presentation/original_record_preview_view_model.dart';
import 'package:flutter_test/flutter_test.dart';

import 'history_architecture_test.dart'
    show MemoryHistoryRepository, originalPrint;

class _Repository extends MemoryHistoryRepository {
  bool denied = false;
  int reads = 0;
  @override
  Future<OriginalRecordData> printData(String name) async {
    reads++;
    if (denied) {
      throw const ErpException(
        'Original record access was revoked.',
        permissionDenied: true,
      );
    }
    return OriginalRecordData.fromJson(
      originalPrint(name: name),
      company: 'A',
      name: name,
    );
  }
}

Future<Uint8List> _render(OriginalRecordData _) async =>
    Uint8List.fromList([1, 2, 3]);
void main() {
  test('preview output snapshots immutable bytes and the original sanitized filename', () async {
    final model = OriginalRecordPreviewViewModel(
      _Repository(),
      name: 'history-1',
      render: _render,
    );
    addTearDown(model.dispose);
    final file = await model.result;
    expect(file.filename, 'ORDER-1 - Orders - Original source copy.pdf');
    expect(file.bytes, [1, 2, 3]);
    expect(() => file.bytes[0] = 9, throwsUnsupportedError);
    expect(model.canUse(file), isTrue);
  });
  test('late rendering rejects an obsolete account scope', () async {
    final repository = _Repository(), pending = Completer<Uint8List>();
    final started = Completer<void>();
    final model = OriginalRecordPreviewViewModel(
      repository,
      name: 'history-1',
      render: (data) {
        started.complete();
        return pending.future;
      },
    );
    addTearDown(model.dispose);
    final expectation = expectLater(model.result, throwsA(isA<ErpException>()));
    await started.future;
    repository.scope = 2;
    pending.complete(Uint8List.fromList([1]));
    await expectation;
    expect(model.currentFile, isNull);
  });
  test(
    'export reauthorizes before platform action and when the picker returns',
    () async {
      final repository = _Repository();
      final active = OriginalRecordPreviewViewModel(
        repository,
        name: 'history-1',
        render: _render,
      );
      addTearDown(active.dispose);
      await active.result;
      var effects = 0;
      await active.exportTo((first, reauthorize) async {
        expect(active.canUse(first), isTrue);
        final current = await reauthorize();
        expect(active.canUse(current), isTrue);
        effects++;
      });
      expect(repository.reads, 3);
      expect(effects, 1);
      expect(active.working, isFalse);
    },
  );
  test(
    'permission rejection invalidates cached bytes without a revision change',
    () async {
      final repository = _Repository();
      final model = OriginalRecordPreviewViewModel(
        repository,
        name: 'history-1',
        render: _render,
      );
      addTearDown(model.dispose);
      final old = await model.result;
      repository.denied = true;
      await expectLater(
        model.exportTo((file, reauthorize) async {}),
        throwsA(isA<ErpException>()),
      );
      await expectLater(model.result, throwsA(isA<ErpException>()));
      expect(model.currentFile, isNull);
      expect(model.canUse(old), isFalse);
      expect(model.errorInPreview, isTrue);
    },
  );
  test(
    'revalidation invalidates an export but never releases its active token',
    () async {
      final repository = _Repository();
      final model = OriginalRecordPreviewViewModel(
        repository,
        name: 'history-1',
        render: _render,
      );
      addTearDown(model.dispose);
      await model.result;
      final opened = Completer<void>(), closed = Completer<void>();
      var effects = 0;
      final writing = model.exportTo((file, reauthorize) async {
        opened.complete();
        await closed.future;
        await reauthorize();
        effects++;
      });
      final expectation = expectLater(writing, throwsA(isA<ErpException>()));
      await opened.future;
      await model.reload();
      expect(model.working, isTrue);
      await model.exportTo((file, reauthorize) async {
        effects++;
      });
      expect(effects, 0);
      closed.complete();
      await expectation;
      expect(model.working, isFalse);
      expect(effects, 0);
    },
  );
  test('unready preview never reads or renders source material', () async {
    final repository = _Repository()..scope = null;
    var renders = 0;
    final model = OriginalRecordPreviewViewModel(
      repository,
      name: 'history-1',
      render: (data) async {
        renders++;
        return Uint8List(0);
      },
    );
    addTearDown(model.dispose);
    await expectLater(model.result, throwsA(isA<ErpException>()));
    expect(repository.reads, 0);
    expect(renders, 0);
  });
}
