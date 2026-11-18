import 'package:flutter/material.dart';

import '../../../core/ui/widgets.dart';
import '../../../core/ui/workspace_art.dart';
import '../../../core/ui/workspace_ui.dart';
import '../../../core/ui/record_icon.dart';
import '../models/team_snapshot.dart';
import 'team_access_view_model.dart';

class TeamAccessView extends StatefulWidget {
  const TeamAccessView({
    super.key,
    required this.model,
    required this.company,
    required this.protect,
    required this.copyCode,
    required this.shareInvitation,
    this.knitting = false,
  });
  final TeamAccessViewModel model;
  final String company;
  final bool knitting;
  final Widget Function(Widget child, Future<void> Function() reload) protect;
  final Future<void> Function(String code) copyCode;
  final Future<void> Function(String text, Rect origin) shareInvitation;
  @override
  State<TeamAccessView> createState() => _TeamAccessViewState();
}

class _TeamAccessViewState extends State<TeamAccessView> {
  final _email = TextEditingController();
  final _scroll = ScrollController();
  final _form = GlobalKey<FormState>();
  bool _copied = false;
  String? get _role => widget.model.role;
  set _role(String? value) => widget.model.role = value;
  String? get _error => widget.model.error;
  bool get _busy => widget.model.busy;
  IssuedInvitation? get _issued => widget.model.issued;
  @override
  void didUpdateWidget(covariant TeamAccessView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.model, widget.model)) {
      _email.clear();
      _copied = false;
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _refresh() => setState(() {
    widget.model.refresh();
  });
  Future<void> _revalidate() async {
    final next = widget.model.revalidate();
    setState(() {});
    await next;
  }

  Future<void> _invite() async {
    if (!_form.currentState!.validate()) return;
    final model = widget.model;
    final next = model.invite(_email.text);
    setState(() {});
    final success = await next;
    if (!mounted || !identical(model, widget.model)) return;
    setState(() {});
    final issued = model.issued;
    if (!success || issued == null) return;
    FocusManager.instance.primaryFocus?.unfocus();
    _email.clear();
    _copied = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_scroll.hasClients ||
          !model.isCurrentInvitation(issued)) {
        return;
      }
      final duration = workspaceMotion(context);
      if (duration == Duration.zero) {
        _scroll.jumpTo(0);
      } else {
        _scroll.animateTo(0, duration: duration, curve: Curves.easeOutCubic);
      }
    });
  }

  Future<void> _revoke(TeamInvitation invitation) async {
    final model = widget.model;
    if (model.busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        scrollable: true,
        title: const Text('Revoke invitation?'),
        content: Text('The code for ${invitation.email} will stop working.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Keep invitation'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || !identical(model, widget.model)) {
      return;
    }
    final next = model.revoke(invitation);
    setState(() {});
    await next;
    if (mounted && identical(model, widget.model)) setState(() {});
  }

  Future<void> _share(BuildContext origin, {required bool copy}) async {
    final model = widget.model, issued = model.issued;
    if (issued == null) return;
    try {
      if (copy) {
        await widget.copyCode(issued.token);
        if (mounted &&
            identical(model, widget.model) &&
            model.isCurrentInvitation(issued)) {
          setState(() => _copied = true);
        }
      } else {
        final box = origin.findRenderObject() as RenderBox;
        await widget.shareInvitation(
          'Join ${widget.company} in ERP Workspace. Open the app, choose “Join with invitation”, and use ${issued.email} with this invitation code:\n${issued.token}',
          box.localToGlobal(Offset.zero) & box.size,
        );
      }
    } catch (_) {
      model.reportShareFailure(issued);
      if (mounted && identical(model, widget.model)) setState(() {});
    }
  }

  Widget _invitationCard(IssuedInvitation issued) {
    return Panel(
      border: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            liveRegion: true,
            child: const Display('Invitation ready', size: 26),
          ),
          const SizedBox(height: 8),
          Text(
            'Share this code with ${issued.email}. They can enter it under “Join with invitation” in the app.',
          ),
          const SizedBox(height: 12),
          SelectableText(
            issued.token,
            key: const ValueKey('invitation-code'),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          if (issued.expiresAt != null) Text('Expires ${issued.expiresAt}'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => _share(context, copy: true),
                icon: const Icon(Icons.copy),
                label: Text(_copied ? 'Code copied' : 'Copy code'),
              ),
              Builder(
                builder: (c) => OutlinedButton.icon(
                  onPressed: () => _share(c, copy: false),
                  icon: const Icon(Icons.share_outlined),
                  label: const Text('Share invitation'),
                ),
              ),
              TextButton(
                onPressed: () => setState(() {
                  widget.model.inviteAnother();
                  _copied = false;
                }),
                child: const Text('Invite another'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _invitationForm(Map<String, String> roles) {
    return Panel(
      border: true,
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Display('Invite a teammate', size: 26),
            const SizedBox(height: 12),
            TextFormField(
              controller: _email,
              enabled: !_busy,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Staff email',
                prefixIcon: Icon(Icons.alternate_email),
              ),
              validator: TeamAccessViewModel.validateEmail,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: roles.containsKey(_role) ? _role : null,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Staff role',
                prefixIcon: Icon(Icons.badge_outlined),
              ),
              validator: widget.model.validateRole,
              items: [
                for (final role in roles.entries)
                  DropdownMenuItem(value: role.key, child: Text(role.value)),
              ],
              onChanged: _busy ? null : (v) => setState(() => _role = v),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy ? null : _invite,
              icon: const Icon(Icons.person_add_alt_1_outlined),
              label: const Text('Create invitation'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _teamMembers(TeamSnapshot data) {
    final members = data.members;
    final invites = data.invitations;
    return Panel(
      border: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Display('Members · ${members.length}', size: 24),
          for (final member in members)
            ListTile(
              leading: RecordIcon(
                member.role == 'owner'
                    ? Icons.manage_accounts_outlined
                    : Icons.person_outline,
              ),
              title: Text(member.fullName ?? member.email),
              subtitle: Text(
                "${member.email} · ${widget.model.roleName(member.role)}",
              ),
            ),
          const SizedBox(height: 16),
          Display('Pending invitations · ${invites.length}', size: 24),
          if (invites.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('No pending invitations.'),
            ),
          for (final inv in invites)
            ListTile(
              leading: const RecordIcon(Icons.mark_email_unread_outlined),
              title: Text(inv.email),
              subtitle: Text(
                "${widget.model.roleName(inv.role)} · Expires ${inv.expiresAt}",
              ),
              trailing: IconButton(
                tooltip: 'Revoke invitation',
                icon: const Icon(Icons.cancel_outlined),
                onPressed: _busy ? null : () => _revoke(inv),
              ),
            ),
        ],
      ),
    );
  }

  Widget _teamContent(TeamSnapshot data) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (_issued == null) _invitationForm(data.roles),
      const SizedBox(height: 20),
      _teamMembers(data),
    ],
  );

  Widget _companyHeader() {
    return Panel(
      dark: true,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      child: Row(
        children: [
          Expanded(child: Display(widget.company, size: 30, light: true)),
          const SizedBox(width: 12),
          WorkspaceArt(
            widget.knitting ? ArtObject.machine : ArtObject.warehouse,
            width: 86,
            height: 55,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.protect(
    Scaffold(
      appBar: AppBar(title: const Text('Team access')),
      body: WorkspaceBackdrop(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: ListView(
                controller: _scroll,
                padding: const EdgeInsets.all(20),
                children: [
                  if (_issued == null) _companyHeader(),
                  const SizedBox(height: 16),
                  if (_issued case final issued?) ...[
                    _invitationCard(issued),
                    const SizedBox(height: 16),
                  ],
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Semantics(liveRegion: true, child: Text(_error!)),
                    ),
                  FutureBuilder<TeamSnapshot>(
                    future: widget.model.result,
                    builder: (context, state) {
                      if (state.connectionState != ConnectionState.done &&
                          !widget.model.accepts(state.data)) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (state.hasError || !widget.model.accepts(state.data)) {
                        return MessagePanel(
                          title: 'Could not load team',
                          message: state.error?.toString() ?? 'Try again.',
                          label: 'Retry',
                          action: _refresh,
                        );
                      }
                      return _teamContent(state.requireData);
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
    _revalidate,
  );
}
