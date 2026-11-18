import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:erp_client/location_field.dart';

void main() {
  testWidgets(
    'validated location point keeps the polygon and inherited points',
    (tester) async {
      const ring = {
        'type': 'Feature',
        'properties': {},
        'geometry': {
          'type': 'Polygon',
          'coordinates': [
            [
              [10, 20],
              [11, 20],
              [11, 21],
              [10, 20],
            ],
          ],
        },
      };
      const child = {
        'type': 'Feature',
        'properties': {'child_feature': true},
        'geometry': {
          'type': 'Point',
          'coordinates': [12, 23],
        },
      };
      String? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LocationField(
              label: 'Depot',
              editable: true,
              value: jsonEncode({
                'type': 'FeatureCollection',
                'features': [ring, child],
              }),
              onChanged: (v) => saved = v as String,
            ),
          ),
        ),
      );
      expect(find.byTooltip('Remove point 2'), findsNothing);
      await tester.tap(find.text('Add point'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Latitude'),
        '91',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Longitude'),
        '77',
      );
      await tester.tap(find.text('Use point'));
      await tester.pumpAndSettle();
      expect(saved, isNull);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Latitude'),
        '11.25',
      );
      await tester.tap(find.text('Use point'));
      await tester.pumpAndSettle();
      final features = jsonDecode(saved!)['features'] as List;
      expect(features.take(2), [ring, child]);
      expect(features.last['geometry']['coordinates'], [77, 11.25]);
    },
  );
}
