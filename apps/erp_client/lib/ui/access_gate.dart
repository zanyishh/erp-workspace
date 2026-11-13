import 'package:flutter/material.dart';
import '../erp_api.dart';

/// Keep drafts mounted while hiding every cached view until fresh access and
/// fresh source data have been checked. A recovery never replays a write.
class AccessGate extends StatefulWidget {
  const AccessGate({
    super.key,
    required this.api,
    required this.revalidate,
    required this.child,
    this.fullPage = true,
  });
  final ErpApi api;
  final Future<void> Function() revalidate;
  final Widget child;
  final bool fullPage;
  @override
  State<AccessGate> createState() => _AccessGateState();
}

class _AccessGateState extends State<AccessGate> {
  late int revision;
  late bool ready, valid;
  String? error;
  @override
  void initState() {
    super.initState();
    revision = widget.api.accessRevision;
    ready = widget.api.accessReady;
    valid = ready;
    widget.api.addAccessListener(changed);
  }

  @override
  void dispose() {
    widget.api.removeAccessListener(changed);
    super.dispose();
  }

  void changed() {
    if (!mounted ||
        revision == widget.api.accessRevision &&
            ready == widget.api.accessReady) {
      return;
    }
    revision = widget.api.accessRevision;
    ready = widget.api.accessReady;
    setState(() {
      valid = false;
      error = null;
    });
    if (ready) refresh();
  }

  Future<void> refresh() async {
    final atStart = widget.api.accessRevision;
    try {
      await widget.revalidate();
      if (mounted &&
          atStart == widget.api.accessRevision &&
          widget.api.accessReady) {
        setState(() {
          valid = true;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final notice = Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline),
            const SizedBox(height: 12),
            Text(
              error ?? 'Refreshing your access…',
              textAlign: TextAlign.center,
            ),
            if (error != null) ...[
              const SizedBox(height: 12),
              TextButton(
                onPressed: refresh,
                child: const Text('Check access again'),
              ),
            ],
          ],
        ),
      ),
    );
    return Stack(
      fit: widget.fullPage ? StackFit.expand : StackFit.loose,
      children: [
        Offstage(offstage: !valid, child: widget.child),
        if (!valid)
          widget.fullPage
              ? Scaffold(
                  appBar: AppBar(title: const Text('Access check')),
                  body: notice,
                )
              : SizedBox(height: 260, child: notice),
      ],
    );
  }
}
