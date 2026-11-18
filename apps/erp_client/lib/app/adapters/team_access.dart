import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../erp_api.dart';
import '../../features/team/data/erp_team_repository.dart';
import '../../features/team/presentation/team_access_view.dart';
import '../../features/team/presentation/team_access_view_model.dart';
import '../../ui/access_gate.dart';

class TeamAccessScreen extends StatefulWidget {
  const TeamAccessScreen({
    super.key,
    required this.api,
    required this.company,
    this.knitting = false,
  });
  final ErpApi api;
  final String company;
  final bool knitting;
  @override
  State<TeamAccessScreen> createState() => _TeamAccessState();
}

class _TeamAccessState extends State<TeamAccessScreen> {
  late TeamAccessViewModel _model = _createModel();
  TeamAccessViewModel _createModel() => TeamAccessViewModel(
    ErpTeamRepository(api: widget.api, company: widget.company),
  );
  @override
  void didUpdateWidget(covariant TeamAccessScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.api != widget.api || oldWidget.company != widget.company) {
      _model.dispose();
      _model = _createModel();
    }
  }

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TeamAccessView(
    model: _model,
    company: widget.company,
    knitting: widget.knitting,
    copyCode: (code) => Clipboard.setData(ClipboardData(text: code)),
    shareInvitation: (text, origin) async {
      await SharePlus.instance.share(
        ShareParams(text: text, sharePositionOrigin: origin),
      );
    },
    protect: (child, reload) => AccessGate(
      key: ValueKey(widget.company),
      api: widget.api,
      revalidate: reload,
      child: child,
    ),
  );
}
