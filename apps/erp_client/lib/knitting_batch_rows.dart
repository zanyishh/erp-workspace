part of 'knitting_forms.dart';

extension _ProductionRows on _KnittingCommandFormState {
  List<Map<String, dynamic>> get _productionRows =>
      (values['entries'] ??= <Map<String, dynamic>>[])
          .cast<Map<String, dynamic>>();

  Map<String, dynamic>? _productionRowSource(Map row) {
    final direct = productionRowSources[row];
    if (direct != null) return direct;
    for (final entry in productionRowSources.entries) {
      if (jsonEncode(entry.key) == jsonEncode(row)) return entry.value;
    }
    final source = references['job:${row['job']}'];
    return source == null ? null : {'job': source};
  }

  String _productionJobLabel(Map row) {
    final source = _productionRowSource(row)?['job'];
    return source is Map
        ? _recordTitle(source, 'Job')
        : recordLabels[('Job', row['job'].toString())] ?? 'Job · ${row['job']}';
  }

  String _productionFabricLabel(Map row) {
    final source = _productionRowSource(row)?['job'];
    final lines = source is Map ? source['programme'] as List? ?? [] : [];
    for (final (i, line) in lines.indexed) {
      if (line['id'] == row['programme_line']) return _programmeName(line, i);
    }
    return 'Programme · ${row['programme_line']}';
  }

  String _productionPersonLabel(Map row) {
    final id = row['production_operator'];
    if (id == null || id == '') return 'Unrecorded';
    final source = _productionRowSource(row)?['references'];
    final person = source is Map ? source['production_operator'] : null;
    return recordLabels[('ProductionOperator', id.toString())] ??
        (person is Map && person['name'] == id
            ? knittingProductionOperatorTitle(person)
            : null) ??
        'Original employee · select again to verify';
  }

  String _productionMachineLabel(Map row) {
    final id = row['production_machine'];
    if (id == null || id == '') return 'Unrecorded';
    final source = _productionRowSource(row)?['references'];
    final machine = source is Map ? source['production_machine'] : null;
    return recordLabels[('ProductionMachine', id.toString())] ??
        (machine is Map && machine['name'] == id
            ? knittingProductionMachineTitle(machine)
            : 'Original machine · select again to verify');
  }

  Widget _productionRowSummary(
    Map row,
    int index, {
    Widget? actions,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: _LineSheet(
      title: 'Production row ${index + 1}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _productionJobLabel(row),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(_productionFabricLabel(row)),
          Text(
            '${row['quantity_kg']} kg · ${row['rolls']} recorded rolls / pieces',
          ),
          Text('Production operator · ${_productionPersonLabel(row)}'),
          Text('Shift · ${row['shift'] ?? 'Unrecorded'}'),
          Text('Godown · ${row['warehouse'] ?? 'Configured default'}'),
          if (row['machine'] != null)
            Text(
              'Configured machine · ${recordLabels[('Machine', row['machine'].toString())] ?? row['machine']}',
            ),
          if (row['production_machine'] != null)
            Text('Original machine · ${_productionMachineLabel(row)}'),
          const SizedBox(height: 8),
          for (final input in row['inputs'] as List? ?? [])
            Text(
              'Yarn · ${recordLabels[('Lot', input['lot'].toString())] ?? input['lot']} · ${input['quantity_kg']} kg · ${input['units'] == null || input['units'].toString().isEmpty ? 'bag/cone count not entered' : '${input['units']} bags / cones'}',
            ),
          Text('Declared loss · ${row['loss_kg'] ?? '0'} kg'),
          if (row['remarks'] != null) Text('Remarks · ${row['remarks']}'),
          if (actions != null) ...[const SizedBox(height: 8), actions],
        ],
      ),
    ),
  );

  Widget _productionRowsReview(List rows) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: 16),
      const Text(
        'All production rows post together at the current date and time. Recorded by the signed-in account.',
      ),
      if (rows.any(
        (row) => (row['inputs'] as List? ?? []).any(
          (input) =>
              input['units'] == null || input['units'].toString().isEmpty,
        ),
      ))
        const Text(
          'Whole-lot consumption uses the remaining recorded count when the bag/cone count is not entered.',
        ),
      const SizedBox(height: 12),
      for (final (index, row) in rows.indexed)
        _productionRowSummary(row as Map, index),
    ],
  );

  String? _productionRowsDiscrepancy() {
    final rows = _productionRows;
    if (rows.isEmpty || rows.length > 50) {
      return 'Review between one and 50 production rows.';
    }
    final versions = <String, String>{};
    for (final (index, row) in rows.indexed) {
      final prefix = 'Production row ${index + 1}';
      final name = row['job'];
      final modified = row['modified'];
      if (name is! String ||
          name.isEmpty ||
          modified is! String ||
          modified.isEmpty ||
          row['programme_line'] is! String ||
          (row['programme_line'] as String).isEmpty) {
        return '$prefix: select the current job and fabric programme.';
      }
      if (versions[name] != null && versions[name] != modified) {
        return '$prefix: this job has different versions across rows. Remove its older rows and select the current job again.';
      }
      if (_hasValue(row['machine']) && _hasValue(row['production_machine'])) {
        return '$prefix: Choose either a configured machine or an original machine.';
      }
      versions[name] = modified;
      try {
        final fabric = Kg.parse(row['quantity_kg'].toString());
        final loss = Kg.parse((row['loss_kg'] ?? '0').toString());
        if (fabric.milli == BigInt.zero ||
            !RegExp(r'^\d+$').hasMatch(row['rolls'].toString())) {
          return '$prefix: enter positive fabric kg and a nonnegative whole recorded count.';
        }
        final inputs = row['inputs'];
        if (inputs is! List || inputs.isEmpty) {
          return '$prefix: select actual yarn consumption.';
        }
        var yarn = Kg.parse('0');
        final lots = <String>{};
        for (final input in inputs) {
          final lot = input['lot'];
          if (lot is! String || lot.isEmpty || !lots.add(lot)) {
            return '$prefix: choose distinct yarn lots.';
          }
          yarn = yarn + Kg.parse(input['quantity_kg'].toString());
        }
        if (yarn.compareTo(fabric + loss) != 0) {
          return '$prefix uses $yarn kg of yarn. Match it to $fabric kg of fabric plus $loss kg of loss before review.';
        }
      } on FormatException {
        return '$prefix: use valid kg with up to three decimal places.';
      }
    }
    return null;
  }

  Future<void> _editProductionRow(
    FormFieldState<int> field,
    Map<String, dynamic>? current,
  ) async {
    final api = widget.api;
    final revision = api.accessRevision;
    final company = workspace.company!;
    if (!widget.api.accessReady || !widget.action.availableIn(workspace)) {
      return;
    }
    try {
      var source = current == null ? null : _productionRowSource(current);
      if (current != null && source?['job'] == null) {
        final page = await widget.api.knittingLookup(
          company,
          'Job',
          current['job'].toString(),
        );
        final selected = (page['rows'] as List)
            .whereType<Map>()
            .where((row) => row['name'] == current['job'])
            .firstOrNull;
        if (selected == null || selected['modified'] != current['modified']) {
          throw const ErpException(
            'This job changed or is unavailable. Remove its old rows and select it again.',
          );
        }
        source = {'job': Map<String, dynamic>.from(selected)};
      }
      if (!mounted ||
          !identical(api, widget.api) ||
          company != workspace.company ||
          revision != widget.api.accessRevision ||
          !widget.api.accessReady) {
        return;
      }
      final prepared = await Navigator.push<Map<String, dynamic>>(
        context,
        MaterialPageRoute(
          builder: (_) => KnittingCommandForm(
            api: widget.api,
            workspace: workspace,
            action: knitActions.firstWhere(
              (action) => action.id == 'produce_batch',
            ),
            prepareOnly: true,
            initial: Map<String, dynamic>.from(current ?? const {})
              ..remove('modified'),
            initialReferences: {
              if (source?['references'] is Map)
                for (final entry in (source!['references'] as Map).entries)
                  entry.key.toString(): Map<String, dynamic>.from(
                    entry.value as Map,
                  ),
              if (source?['job'] is Map)
                'job': Map<String, dynamic>.from(source!['job'] as Map),
            },
          ),
        ),
      );
      if (prepared == null ||
          !mounted ||
          !identical(api, widget.api) ||
          company != workspace.company ||
          revision != widget.api.accessRevision ||
          !widget.api.accessReady) {
        return;
      }
      final rows = _productionRows;
      final index = current == null ? -1 : rows.indexOf(current);
      if (current != null && index < 0) return;
      final row = Map<String, dynamic>.from(prepared['values'] as Map)
        ..['modified'] = prepared['modified'];
      _updateProductionRows(() {
        if (current == null) {
          if (rows.length < 50) rows.add(row);
        } else {
          rows[index] = row;
          productionRowSources.remove(current);
        }
        productionRowSources[row] = prepared;
        recordLabels.addAll(
          Map<(String, String), String>.from(prepared['labels'] as Map),
        );
        changed = true;
        field.didChange(rows.length);
      });
    } catch (error) {
      if (mounted &&
          identical(api, widget.api) &&
          company == workspace.company &&
          widget.api.accessReady &&
          revision == widget.api.accessRevision) {
        _updateProductionRows(() => validation = error.toString());
      }
    }
  }

  Widget _productionRowsField(
    KnitField descriptor,
    Map<String, dynamic> target,
  ) {
    final rows = _productionRows;
    return FormField<int>(
      initialValue: rows.length,
      validator: (_) =>
          rows.isEmpty ? 'Add at least one production row.' : null,
      builder: (field) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (index, row) in rows.indexed)
            KeyedSubtree(
              key: ObjectKey(row),
              child: _productionRowSummary(
                row,
                index,
                actions: Wrap(
                  spacing: 8,
                  children: [
                    TextButton.icon(
                      onPressed: () => _editProductionRow(field, row),
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Edit row'),
                    ),
                    IconButton(
                      tooltip: 'Remove production row ${index + 1}',
                      onPressed: () => _updateProductionRows(() {
                        rows.remove(row);
                        productionRowSources.remove(row);
                        changed = true;
                        field.didChange(rows.length);
                      }),
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                  ],
                ),
              ),
            ),
          OutlinedButton.icon(
            onPressed: rows.length >= 50
                ? null
                : () => _editProductionRow(field, null),
            icon: const Icon(Icons.add),
            label: const Text('Add production row'),
          ),
          if (rows.length >= 50)
            const Text('The maximum is 50 production rows per entry.'),
          if (field.hasError)
            Text(
              field.errorText!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    );
  }
}
