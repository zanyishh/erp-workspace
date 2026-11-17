import 'package:flutter/material.dart';

import '../../../core/ui/access_scope.dart';
import 'access_gate_view_model.dart';

class AccessGateView extends StatelessWidget {
  const AccessGateView({
    super.key,
    required this.model,
    required this.child,
    this.fullPage = true,
  });
  final AccessGateViewModel model;
  final Widget child;
  final bool fullPage;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: model,
    builder: (context, _) {
      final notice = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline),
              const SizedBox(height: 12),
              Semantics(
                liveRegion: true,
                child: Text(
                  model.error ?? 'Refreshing your access…',
                  textAlign: TextAlign.center,
                ),
              ),
              if (model.error != null) ...[
                const SizedBox(height: 12),
                TextButton(
                  onPressed: model.refresh,
                  child: const Text('Check access again'),
                ),
              ],
            ],
          ),
        ),
      );
      return Stack(
        fit: fullPage ? StackFit.expand : StackFit.loose,
        children: [
          Offstage(
            offstage: !model.valid,
            child: AccessScope(
              api: model.source,
              account: model.account,
              revision: model.revision,
              ready: model.ready && model.valid,
              child: child,
            ),
          ),
          if (!model.valid)
            fullPage
                ? Scaffold(
                    appBar: AppBar(title: const Text('Access check')),
                    body: notice,
                  )
                : SizedBox(height: 260, child: notice),
        ],
      );
    },
  );
}
