import 'package:erp_client/native_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Read Only field types are locked and excluded from writes', () {
    final schema = NativeSchema.fromJson({
      'doctype': 'Example',
      'fields': [
        {'fieldname': 'display', 'fieldtype': 'Read Only'},
      ],
    });
    expect(schema.fields.single.readOnly, true);
    expect(schema.payload({'display': 'forged'}), {'doctype': 'Example'});
  });
}
