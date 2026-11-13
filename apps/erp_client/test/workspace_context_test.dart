import 'package:flutter_test/flutter_test.dart';
import 'package:erp_client/workspace_context.dart';

void main() {
  test('company and role determine available industry destinations', () {
    final c = WorkspaceContext.fromJson({
      'version': 1,
      'companies': [
        {'name': 'One'},
      ],
      'company': 'One',
      'knitting_enabled': true,
      'capabilities': ['jobs', 'production'],
      'setup_state': 'Active',
      'revision': 1,
    });
    expect(c.allows('production'), true);
    expect(c.allows('billing'), false);
    expect(c.destinations, contains('Production'));
    expect(c.destinations, isNot(contains('Billing')));
    final general = WorkspaceContext.fromJson({
      'version': 1,
      'companies': [
        {'name': 'Two'},
      ],
      'company': 'Two',
      'knitting_enabled': false,
      'capabilities': [],
      'setup_state': 'General ERP',
      'revision': 0,
    });
    expect(general.destinations, isEmpty);
  });
}
