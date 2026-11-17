import 'dart:async';

import 'package:flutter/material.dart';

/// A query owns its results. Previous matches stay visible but cannot be chosen.
class DocumentLinkSearch extends StatefulWidget {
  const DocumentLinkSearch({
    super.key,
    required this.label,
    required this.search,
  });
  final String label;
  final Future<List<Map<String, dynamic>>> Function(String query) search;
  @override
  State<DocumentLinkSearch> createState() => _DocumentLinkSearchState();
}

class _DocumentLinkSearchState extends State<DocumentLinkSearch> {
  Timer? _debounce;
  int _request = 0;
  String _query = '';
  String? _error;
  bool _loading = true;
  List<Map<String, dynamic>> _rows = [];

  @override
  void initState() {
    super.initState();
    _search(++_request);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _changed(String query) {
    _debounce?.cancel();
    final request = ++_request;
    setState(() {
      _query = query;
      _loading = true;
      _error = null;
    });
    _debounce = Timer(
      const Duration(milliseconds: 280),
      () => _search(request),
    );
  }

  Future<void> _search(int request) async {
    try {
      final rows = await widget.search(_query);
      if (!mounted || request != _request) return;
      setState(() {
        _rows = rows;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted || request != _request) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  void _submit(String text) {
    if (_loading || _error != null || _rows.isEmpty) return;
    final exact = _rows.where(
      (row) =>
          row['value']?.toString().toLowerCase() == text.trim().toLowerCase(),
    );
    final match = exact.length == 1
        ? exact.single
        : _rows.length == 1
        ? _rows.single
        : null;
    if (match != null) Navigator.pop(context, match['value']?.toString());
  }

  @override
  Widget build(BuildContext context) => Dialog(
    child: SizedBox(
      width: 520,
      height: 480,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Choose ${widget.label}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Close search',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Search records…',
                prefixIcon: Icon(Icons.search),
              ),
              textInputAction: TextInputAction.search,
              onEditingComplete: () {},
              onSubmitted: _submit,
              onChanged: _changed,
            ),
            SizedBox(
              height: 4,
              child: _loading ? const LinearProgressIndicator() : null,
            ),
            const SizedBox(height: 8),
            Semantics(
              liveRegion: true,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _loading
                      ? 'Searching… Previous matches are unavailable.'
                      : _error != null
                      ? 'Search failed. Retry to choose a record.'
                      : '${_rows.length} matching records',
                ),
              ),
            ),
            if (_error != null) ...[
              Text(_error!, maxLines: 2, overflow: TextOverflow.ellipsis),
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _loading = true;
                    _error = null;
                  });
                  _search(++_request);
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Retry search'),
              ),
            ],
            Expanded(
              child: _rows.isEmpty
                  ? Center(
                      child: Text(
                        _loading
                            ? 'Searching records…'
                            : _error != null
                            ? 'No current results available.'
                            : 'No matching records.',
                      ),
                    )
                  : ListView.builder(
                      itemCount: _rows.length,
                      itemBuilder: (_, index) {
                        final row = _rows[index];
                        final ready = !_loading && _error == null;
                        return ListTile(
                          enabled: ready,
                          title: Text(row['value']?.toString() ?? ''),
                          subtitle: Text(
                            (row['description'] ?? row['label'] ?? '')
                                .toString()
                                .replaceAll(RegExp(r'<[^>]*>'), ''),
                          ),
                          onTap: ready
                              ? () => Navigator.pop(
                                  context,
                                  row['value']?.toString(),
                                )
                              : null,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    ),
  );
}
