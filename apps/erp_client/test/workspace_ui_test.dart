import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:erp_client/design.dart';
import 'package:erp_client/ui/workspace_ui.dart';

void main() {
  testWidgets('reduced motion preserves selection and accessible labels', (
    tester,
  ) async {
    String selected = 'Jobs';
    await tester.pumpWidget(
      MaterialApp(
        theme: WorkspaceTheme.theme,
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: StatefulBuilder(
            builder: (context, setState) => Scaffold(
              body: WorkspaceSelection(
                labels: const ['Jobs', 'Production'],
                selected: selected,
                onSelected: (v) => setState(() => selected = v),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Production'));
    await tester.pump();
    expect(selected, 'Production');
    expect(find.text('Jobs'), findsOneWidget);
    final containers = tester.widgetList<AnimatedContainer>(
      find.byType(AnimatedContainer),
    );
    expect(containers.every((c) => c.duration == Duration.zero), true);
    expect(tester.takeException(), isNull);
  });
}
