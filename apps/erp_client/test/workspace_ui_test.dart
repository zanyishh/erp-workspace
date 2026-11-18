import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:erp_client/design.dart';
import 'package:erp_client/ui/workspace_ui.dart';

void main() {
  testWidgets(
    'changing the Apple Reduce Motion preference updates mounted controls',
    (tester) async {
      final dispatcher = tester.platformDispatcher;
      addTearDown(dispatcher.clearAccessibilityFeaturesTestValue);
      await tester.pumpWidget(
        MaterialApp(
          home: WorkspaceMotionScope(
            child: WorkspaceSelection(
              labels: const ['Jobs'],
              selected: 'Jobs',
              onSelected: (_) {},
            ),
          ),
        ),
      );
      Duration duration() => tester
          .widget<AnimatedContainer>(find.byType(AnimatedContainer))
          .duration;
      expect(duration(), isNot(Duration.zero));
      dispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(reduceMotion: true);
      await tester.pump();
      expect(duration(), Duration.zero);
      dispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(reduceMotion: false);
      await tester.pump();
      expect(duration(), isNot(Duration.zero));
    },
  );

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
