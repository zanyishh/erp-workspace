import 'dart:convert';

import 'package:flutter/material.dart';

/// ERPNext stores a FeatureCollection, including inherited geometry from child locations.
class LocationField extends StatelessWidget {
  const LocationField({
    super.key,
    required this.label,
    required this.value,
    required this.editable,
    required this.onChanged,
    this.error,
  });
  final String label;
  final Object? value;
  final bool editable;
  final String? error;
  final ValueChanged<dynamic> onChanged;

  Map<String, dynamic>? _collection() {
    if (value == null || value == '') {
      return {'type': 'FeatureCollection', 'features': <dynamic>[]};
    }
    try {
      final raw = value is String ? jsonDecode(value as String) : value;
      if (raw is! Map || raw['type'] != 'FeatureCollection') return null;
      final features = raw['features'] is String
          ? jsonDecode(raw['features'] as String)
          : raw['features'];
      if (features is! List || features.any((f) => f is! Map)) return null;
      return {
        ...Map<String, dynamic>.from(raw),
        'features': List<dynamic>.from(features),
      };
    } on FormatException {
      return null;
    }
  }

  Future<void> _edit(
    BuildContext context,
    Map<String, dynamic> collection,
    int? index,
  ) async {
    final features = collection['features'] as List;
    final current = index == null
        ? null
        : features[index]['geometry']['coordinates'] as List;
    String lat = current == null ? '' : current[1].toString(),
        lon = current == null ? '' : current[0].toString();
    String? problem;
    final coordinates = await showDialog<List<double>>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(
            index == null ? 'Add location point' : 'Edit location point',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  initialValue: lat,
                  decoration: const InputDecoration(
                    labelText: 'Latitude',
                    hintText: '−90 to 90',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  onChanged: (v) => lat = v,
                ),
                TextFormField(
                  initialValue: lon,
                  decoration: const InputDecoration(
                    labelText: 'Longitude',
                    hintText: '−180 to 180',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  onChanged: (v) => lon = v,
                ),
                if (problem != null)
                  Semantics(liveRegion: true, child: Text(problem!)),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final latitude = double.tryParse(lat.trim()),
                    longitude = double.tryParse(lon.trim());
                if (latitude == null ||
                    longitude == null ||
                    !latitude.isFinite ||
                    !longitude.isFinite ||
                    latitude.abs() > 90 ||
                    longitude.abs() > 180) {
                  update(
                    () => problem = 'Enter a latitude from −90 to 90 and a longitude from −180 to 180.',
                  );
                  return;
                }
                Navigator.pop(dialog, [longitude, latitude]);
              },
              child: const Text('Use point'),
            ),
          ],
        ),
      ),
    );
    if (coordinates == null || !context.mounted) return;
    if (index == null) {
      features.add({
        'type': 'Feature',
        'properties': <String, dynamic>{},
        'geometry': {'type': 'Point', 'coordinates': coordinates},
      });
    } else {
      final original = features[index] as Map;
      features[index] = {
        ...original,
        'geometry': {
          ...original['geometry'] as Map,
          'coordinates': [...coordinates, ...current!.skip(2)],
        },
      };
    }
    onChanged(jsonEncode(collection));
  }

  @override
  Widget build(BuildContext context) {
    final collection = _collection();
    final features = collection?['features'] as List? ?? [];
    return InputDecorator(
      decoration: InputDecoration(labelText: label, errorText: error),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (collection == null)
            const Text('This location uses a different map format.')
          else if (features.isEmpty)
            const Text('No location points.'),
          for (final (i, raw) in features.indexed)
            Builder(
              builder: (context) {
                final feature = raw as Map,
                    geometry = feature['geometry'],
                    props = feature['properties'];
                final coords = geometry is Map ? geometry['coordinates'] : null;
                final point =
                    geometry is Map &&
                    geometry['type'] == 'Point' &&
                    coords is List &&
                    coords.length >= 2;
                final inherited =
                    props is Map && props['child_feature'] == true;
                return Wrap(
                  spacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      point
                          ? 'Latitude ${coords[1]} · Longitude ${coords[0]}'
                          : geometry is Map
                          ? '${geometry['type']} geometry'
                          : 'Map feature',
                    ),
                    if (inherited) const Text('From child location'),
                    if (editable && point && !inherited)
                      IconButton(
                        tooltip: 'Edit point ${i + 1}',
                        onPressed: () => _edit(context, collection!, i),
                        icon: const Icon(Icons.edit_location_alt_outlined),
                      ),
                    if (editable && point && !inherited)
                      IconButton(
                        tooltip: 'Remove point ${i + 1}',
                        onPressed: () {
                          features.removeAt(i);
                          onChanged(jsonEncode(collection));
                        },
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                  ],
                );
              },
            ),
          if (editable && collection != null)
            TextButton.icon(
              onPressed: () => _edit(context, collection, null),
              icon: const Icon(Icons.add_location_alt_outlined),
              label: const Text('Add point'),
            ),
        ],
      ),
    );
  }
}
