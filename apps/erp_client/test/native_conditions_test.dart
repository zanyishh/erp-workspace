import 'package:erp_client/native_conditions.dart';
import 'package:erp_client/native_models.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> literal(Object? value) => {
  'op': 'literal',
  'value': value,
};
Map<String, dynamic> get(String key, {String scope = 'doc'}) => {
  'op': 'get',
  'object': {'op': 'context', 'name': scope},
  'key': literal(key),
};
void main() {
  test(
    'rows, CSV import and per-company stock settings follow current values',
    () {
      final linked = {
        'op': 'row_test',
        'method': 'every',
        'object': get('items'),
        'field': 'pr_detail',
        'negate': true,
      };
      expect(evaluateCondition(linked, {'items': []}), isTrue);
      expect(
        evaluateCondition(linked, {
          'items': [
            {'pr_detail': ''},
            {'pr_detail': 'PR-1'},
          ],
        }),
        isFalse,
      );
      final supplier = {
        'op': 'row_test',
        'method': 'some',
        'object': get('suppliers'),
        'field': 'send_email',
        'negate': false,
      };
      expect(
        evaluateCondition(supplier, {
          'suppliers': [
            {'send_email': 0},
            {'send_email': 1},
          ],
        }),
        isTrue,
      );
      final csv = {
        'op': '===',
        'args': [
          {
            'op': 'method',
            'method': 'toLowerCase',
            'object': {
              'op': 'method',
              'method': 'pop',
              'object': {
                'op': 'method',
                'method': 'split',
                'object': get('file'),
                'args': [literal('.')],
              },
            },
          },
          literal('csv'),
        ],
      };
      expect(
        evaluateCondition(csv, {'file': '/private/files/items.CSV'}),
        isTrue,
      );
      expect(evaluateCondition(csv, {'file': 'items.csv.xlsx'}), isFalse);
      final company = {
        'op': 'get',
        'object': literal({'Factory': 1, 'Store': 0}),
        'key': get('company', scope: 'parent'),
      };
      expect(
        evaluateCondition(company, {}, parent: {'company': 'Factory'}),
        isTrue,
      );
      expect(
        evaluateCondition(company, {}, parent: {'company': 'Store'}),
        isFalse,
      );
    },
  );
  test('hidden sections and conditional required fields follow the current document', () {
    final schema = NativeSchema.fromJson({
      'doctype': 'Example',
      'fields': [
        {
          'fieldname': 'hidden_section',
          'fieldtype': 'Section Break',
          'conditions': {
            'depends_on': {'op': 'field', 'name': 'enabled'},
          },
        },
        {'fieldname': 'secret', 'fieldtype': 'Data', 'reqd': 1},
        {'fieldname': 'next_section', 'fieldtype': 'Section Break'},
        {
          'fieldname': 'reason',
          'fieldtype': 'Data',
          'conditions': {
            'mandatory_depends_on': {'op': 'field', 'name': 'enabled'},
          },
        },
      ],
    });
    expect(schema.visibleFields({'enabled': 0}).map((f) => f.name), [
      'next_section',
      'reason',
    ]);
    expect(schema.validate({'enabled': 0}), isEmpty);
    expect(
      schema.validate({'enabled': 1}).keys,
      containsAll(['secret', 'reason']),
    );
  });
  test('non-numbers are false in conditional calculations', () {
    expect(
      evaluateCondition({
        'op': '+',
        'args': [literal('not-a-number')],
      }, {}),
      false,
    );
  });

  test('conditions follow numeric flags, parent values, optional fields and strict comparisons', () {
    expect(
      evaluateCondition(
        {
          'op': '&&',
          'args': [
            get('enabled'),
            {
              'op': '===',
              'args': [get('status', scope: 'parent'), literal('Open')],
            },
          ],
        },
        {'enabled': 1},
        parent: {'status': 'Open'},
      ),
      true,
    );
    expect(
      evaluateCondition(
        {
          'op': '===',
          'args': [get('flag'), literal('1')],
        },
        {'flag': 1},
      ),
      false,
    );
    expect(
      evaluateCondition(
        {
          'op': '==',
          'args': [get('flag'), literal('1')],
        },
        {'flag': 1},
      ),
      true,
    );
    expect(
      evaluateCondition({
        'op': '!',
        'args': [get('missing')],
      }, {}),
      true,
    );
    expect(
      evaluateCondition({'op': 'field', 'name': 'rows'}, {'rows': []}),
      false,
    );
    expect(evaluateCondition(get('rows'), {'rows': []}), true);
    expect(evaluateCondition({'op': 'unsupported'}, {}), null);
  });
  test('membership and comparison rules do not dispatch arbitrary methods', () {
    expect(
      evaluateCondition(
        {
          'op': 'method',
          'method': 'includes',
          'object': {
            'op': 'array',
            'values': [literal('Draft'), literal('Open')],
          },
          'args': [get('status')],
        },
        {'status': 'Open'},
      ),
      true,
    );
    expect(
      evaluateCondition(
        {
          'op': '>',
          'args': [get('amount'), literal(0)],
        },
        {'amount': '10'},
      ),
      true,
    );
    expect(
      evaluateCondition(
        {
          'op': 'call',
          'method': 'cint',
          'args': [get('flag')],
        },
        {'flag': '0'},
      ),
      false,
    );
    expect(
      evaluateCondition({
        'op': 'method',
        'method': 'fetch',
        'object': literal('x'),
      }, {}),
      null,
    );
  });
}
