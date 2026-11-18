import 'package:flutter/material.dart';

import '../models/erp_exception.dart';

/// Retain a successful read only inside the caller's exact access/view scope.
class RetainedFutureBuilder<T> extends StatefulWidget {
  const RetainedFutureBuilder({
    super.key,
    required this.future,
    required this.scope,
    required this.builder,
  });
  final Future<T>? future;
  final Object scope;
  final Widget Function(BuildContext, RetainedLoad<T>) builder;
  @override
  State<RetainedFutureBuilder<T>> createState() =>
      _RetainedFutureBuilderState<T>();
}

class RetainedLoad<T> {
  const RetainedLoad(this.data, this.error, this.loading);
  final T? data;
  final Object? error;
  final bool loading;
  bool get hasData => data != null;
  bool get hasError => error != null;
}

class _RetainedFutureBuilderState<T> extends State<RetainedFutureBuilder<T>> {
  T? _data;
  Object? _error;
  bool _loading = false;
  int _request = 0;
  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didUpdateWidget(covariant RetainedFutureBuilder<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scope != widget.scope) _data = null;
    if (oldWidget.scope != widget.scope || oldWidget.future != widget.future) {
      _listen();
    }
  }

  void _listen() {
    final request = ++_request;
    final future = widget.future;
    _error = null;
    _loading = future != null;
    if (future == null) _data = null;
    future?.then(
      (data) {
        if (!mounted || request != _request) return;
        setState(() {
          _data = data;
          _loading = false;
        });
      },
      onError: (Object error, StackTrace _) {
        if (!mounted || request != _request) return;
        setState(() {
          if (error is ErpException &&
              (error.permissionDenied || error.sessionExpired)) {
            _data = null;
          }
          _error = error;
          _loading = false;
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, RetainedLoad(_data, _error, _loading));
}

class RetainedLoadNotice extends StatelessWidget {
  const RetainedLoadNotice({
    super.key,
    required this.loading,
    this.error,
    required this.onRetry,
  });
  final bool loading;
  final Object? error;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SizedBox(
        height: 4,
        child: loading
            ? const LinearProgressIndicator(
                semanticsLabel: 'Refreshing; showing previously loaded results',
              )
            : null,
      ),
      if (error != null)
        Semantics(
          liveRegion: true,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Showing previously loaded results. Refresh failed: $error',
                  ),
                ),
                TextButton(onPressed: onRetry, child: const Text('Retry')),
              ],
            ),
          ),
        ),
    ],
  );
}
