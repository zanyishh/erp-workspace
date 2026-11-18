import 'package:flutter_test/flutter_test.dart';
import 'package:erp_client/workspace_context.dart';
import 'package:erp_client/erp_api.dart';

void main() {
  test('enabling knitting-only navigation invalidates cached client views', () {
    final api = ErpApi(Uri.parse('http://127.0.0.1:8082'));
    addTearDown(api.close);
    api.publishContext(WorkspaceContext.fromJson({'company': 'Mill'}));
    var changes = 0;
    api.addAccessListener(() => changes++);
    api.publishContext(
      WorkspaceContext.fromJson({'company': 'Mill', 'knitting_only': true}),
    );
    expect(changes, 1);
    expect(api.accessRevision, 1);
  });
  test('revoking imported history access invalidates cached client views', () {
    final api = ErpApi(Uri.parse('http://127.0.0.1:8082'));
    addTearDown(api.close);
    api.publishContext(
      WorkspaceContext.fromJson({
        'company': 'Archive One',
        'can_read_imported_history': true,
      }),
    );
    var changes = 0;
    api.addAccessListener(() => changes++);
    api.publishContext(
      WorkspaceContext.fromJson({
        'company': 'Archive One',
        'can_read_imported_history': false,
      }),
    );
    expect(changes, 1);
    expect(api.accessRevision, 1);
  });
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
