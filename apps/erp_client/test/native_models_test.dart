import 'package:flutter_test/flutter_test.dart';
import 'package:erp_client/native_models.dart';

void main() {
  test(
    'multiselect report filters require arrays rather than accidental text',
    () {
      final field = NativeField.fromJson({
        'fieldname': 'account',
        'fieldtype': 'MultiSelectList',
        'options': 'Account',
      });
      expect(() => field.parse('Cash'), throwsFormatException);
      expect(field.parse(['Cash', 'Sales']), ['Cash', 'Sales']);
    },
  );
  test('submitted save only includes fields allowed after submission', () {
    final schema = NativeSchema.fromJson({
      'doctype': 'Invoice',
      'fields': [
        {'fieldname': 'items', 'fieldtype': 'Table', 'options': 'Line'},
        {'fieldname': 'letter_head', 'fieldtype': 'Link', 'allow_on_submit': 1},
      ],
      'children': {
        'Line': {
          'doctype': 'Line',
          'fields': [
            {'fieldname': 'qty', 'fieldtype': 'Float'},
          ],
        },
      },
    });
    expect(
      schema.payload({
        'doctype': 'Invoice',
        'name': 'INV-1',
        'modified': '2026-11-12 10:00:00',
        'docstatus': 1,
        'items': [
          {'doctype': 'Line', 'name': 'ROW-1', 'qty': 1},
        ],
        'letter_head': 'Standard',
      }),
      {
        'doctype': 'Invoice',
        'name': 'INV-1',
        'modified': '2026-11-12 10:00:00',
        'letter_head': 'Standard',
      },
    );
  });
  final schemaData = <String, dynamic>{
    'doctype': 'Example',
    'fields': [
      {'fieldname': 'title', 'fieldtype': 'Data', 'label': 'Title', 'reqd': 1},
      {'fieldname': 'qty', 'fieldtype': 'Float', 'label': 'Quantity'},
      {'fieldname': 'total', 'fieldtype': 'Currency', 'read_only': 1},
      {'fieldname': 'secret', 'fieldtype': 'Data', 'hidden': 1},
      {'fieldname': 'rows', 'fieldtype': 'Table', 'options': 'Example Row'},
    ],
    'children': {
      'Example Row': {
        'doctype': 'Example Row',
        'fields': [
          {'fieldname': 'description', 'fieldtype': 'Data'},
        ],
      },
    },
  };

  test('native edit copies do not modify original child data', () {
    final original = NativeDocument.fromJson({
      'doc': {
        'doctype': 'Example',
        'name': 'A',
        'rows': [
          {'name': 'ROW-1', 'description': 'Original'},
        ],
      },
    });
    final editable = original.editCopy();
    (editable['rows'] as List).first['description'] = 'Changed';
    expect((original.data['rows'] as List).first['description'], 'Original');
  });

  test(
    'native save excludes restricted values and preserves child identity',
    () {
      final schema = NativeSchema.fromJson(schemaData);
      final payload = schema.payload({
        'doctype': 'Example',
        'name': 'A',
        'modified': '2026-11-12 10:00:00',
        'title': 'Edited',
        'qty': '1.25',
        'total': 100,
        'secret': 'hidden',
        'rows': [
          {'doctype': 'Example Row', 'name': 'ROW-1', 'description': 'First'},
        ],
      });
      expect(payload, {
        'doctype': 'Example',
        'name': 'A',
        'modified': '2026-11-12 10:00:00',
        'title': 'Edited',
        'qty': 1.25,
        'rows': [
          {'doctype': 'Example Row', 'name': 'ROW-1', 'description': 'First'},
        ],
      });
    },
  );

  test('required and invalid numeric values block native save', () {
    final schema = NativeSchema.fromJson(schemaData);
    expect(schema.validate({'qty': 'NaN'}).keys, containsAll(['title', 'qty']));
    expect(schema.validate({'title': 'Valid', 'qty': '-2.5'}), isEmpty);
    expect(
      schema.validate({'title': 'Valid', 'qty': 'oops'}).keys,
      contains('qty'),
    );
  });
}
