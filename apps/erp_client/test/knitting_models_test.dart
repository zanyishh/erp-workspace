import 'package:flutter_test/flutter_test.dart';
import 'package:erp_client/knitting_models.dart';

void main() {
  test('kg remain exact and reject rounding, exponent and nonfinite input', () {
    expect((Kg.parse('0.1') + Kg.parse('0.2')).toString(), '0.300');
    expect(Kg.parse('999999999.999').toString(), '999999999.999');
    expect(Kg.parse('1000000000.000').toString(), '1000000000.000');
    expect(() => Kg.parse('1000000000.001'), throwsFormatException);
    for (final v in ['NaN', 'Infinity', '1e3', '0.0001', '', '-1']) {
      expect(() => Kg.parse(v), throwsFormatException);
    }
  });
  test(
    'uncertain commands retain identity and cannot post twice automatically',
    () async {
      final draft = KnittingDraft('produce', {
        'job': 'J1',
      }, requestId: 'request-123');
      var writes = 0;
      Future<Map<String, dynamic>> post() async {
        writes++;
        throw Exception('offline');
      }

      await draft.submit(post);
      expect(draft.state, CommandState.uncertain);
      expect(draft.requestId, 'request-123');
      expect(draft.values['job'], 'J1');
      await draft.submit(post);
      expect(writes, 1);
      await draft.check(
        () async => {
          'event': 'EVT1',
          'data': {
            'rolls': ['R1'],
          },
        },
      );
      expect(draft.state, CommandState.confirmed);
      expect(draft.result?['event'], 'EVT1');
    },
  );
}
