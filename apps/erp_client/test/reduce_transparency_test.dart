import 'package:erp_client/core/ui/reduce_transparency.dart';
import 'package:erp_client/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _channel = EventChannel('org.localerp.workspace/reduceTransparency');

Widget _probe() => ReduceTransparencyScope(
  child: MediaQuery(
    data: const MediaQueryData(),
    child: Builder(
      builder: (context) => Panel(
        frosted: true,
        child: Text(
          ReduceTransparencyScope.of(context) ? 'opaque' : 'transparent',
          textDirection: TextDirection.ltr,
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets(
    'Apple screens start opaque and follow native changes until disposal',
    (tester) async {
      late MockStreamHandlerEventSink events;
      var cancelled = false;
      tester.binding.defaultBinaryMessenger.setMockStreamHandler(
        _channel,
        MockStreamHandler.inline(
          onListen: (_, sink) {
            events = sink;
          },
          onCancel: (_) {
            cancelled = true;
          },
        ),
      );

      await tester.pumpWidget(_probe());
      expect(find.text('opaque'), findsOneWidget);
      expect(find.byType(BackdropFilter), findsNothing);
      events.success(false);
      await tester.pumpAndSettle();
      expect(find.text('transparent'), findsOneWidget);
      expect(find.byType(BackdropFilter), findsOneWidget);
      events.success(true);
      await tester.pumpAndSettle();
      expect(find.text('opaque'), findsOneWidget);
      expect(find.byType(BackdropFilter), findsNothing);

      await tester.pumpWidget(const SizedBox());
      expect(cancelled, isTrue);
    },
    variant: TargetPlatformVariant({TargetPlatform.iOS, TargetPlatform.macOS}),
  );

  testWidgets(
    'Android and Windows retain their normal surfaces without an Apple channel',
    (tester) async {
      await tester.pumpWidget(_probe());
      expect(find.text('transparent'), findsOneWidget);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.windows,
    }),
  );
}
