import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'erp_api.dart';
import 'ui/access_gate.dart';
import 'ui/workspace_art.dart';
import 'ui/workspace_ui.dart';
import 'ui/record_icon.dart';
import 'widgets.dart';

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
  State<TeamAccessScreen> createState() => _TeamAccessScreenState();
}

class _TeamAccessScreenState extends State<TeamAccessScreen> {
  final _email = TextEditingController();
  final _scroll = ScrollController();
  final _form = GlobalKey<FormState>();
  late Future<Map<String, dynamic>> _team;
  String? _role, _error;
  bool _busy = false, _copied = false;
  Map<String, dynamic>? _issued;

  @override
  void initState() {
    super.initState();
    _team = widget.api.team(widget.company);
  }

  @override
  void dispose() {
    _email.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _refresh() {
    final current = widget.api.team(widget.company);
    setState(() {
      _team = current;
    });
  }

  Future<void> _revalidate() async {
    setState(() {
      _issued = null;
      _error = null;
      _team = widget.api.team(widget.company);
    });
    await _team;
  }

  Future<void> _invite() async {
    if (_busy || !_form.currentState!.validate()) return;
    final email = _email.text.trim();
    setState(() {
      _busy = true;
      _error = null;
      _issued = null;
    });
    try {
      final issued = await widget.api.inviteMember(
        widget.company,
        email,
        _role!,
      );
      if (!mounted) return;
      if (issued['token'] is! String || (issued['token'] as String).isEmpty) {
        throw const ErpException(
          'The invitation code could not be read. Revoke the invitation and create a new one.',
        );
      }
      FocusManager.instance.primaryFocus?.unfocus();
      _email.clear();
      setState(() {
        _issued = issued;
        _copied = false;
      });
      _refresh();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scroll.hasClients || _issued != issued) return;
        final duration = workspaceMotion(context);
        if (duration == Duration.zero) {
          _scroll.jumpTo(0);
        } else {
          _scroll.animateTo(0, duration: duration, curve: Curves.easeOutCubic);
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _revoke(Map invitation) async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        scrollable: true,
        title: const Text('Revoke invitation?'),
        content: Text('The code for ${invitation['email']} will stop working.'),
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
    if (confirmed != true || !mounted || !widget.api.accessReady) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.revokeInvitation(
        widget.company,
        invitation['name'] as String,
      );
      if (!mounted) return;
      if (_issued?['email'] == invitation['email']) _issued = null;
      _refresh();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share(BuildContext origin, {required bool copy}) async {
    final issued = _issued;
    if (issued == null) return;
    try {
      if (copy) {
        await Clipboard.setData(ClipboardData(text: issued['token'] as String));
        if (mounted && identical(_issued, issued)) {
          setState(() => _copied = true);
        }
      } else {
        final box = origin.findRenderObject() as RenderBox;
        await SharePlus.instance.share(
          ShareParams(
            text:
                'Join ${widget.company} in ERP Workspace. Open the app, choose “Join with invitation”, and use ${issued['email']} with this invitation code:\n${issued['token']}',
            sharePositionOrigin: box.localToGlobal(Offset.zero) & box.size,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Select the invitation code and copy it to share it with your teammate.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => AccessGate(
    api: widget.api,
    revalidate: _revalidate,
    child: Scaffold(
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
                  if (_issued == null)
                    Panel(
                      dark: true,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Display(
                              widget.company,
                              size: 30,
                              light: true,
                            ),
                          ),
                          const SizedBox(width: 12),
                          WorkspaceArt(
                            widget.knitting
                                ? ArtObject.machine
                                : ArtObject.warehouse,
                            width: 86,
                            height: 55,
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 16),
                  if (_issued case final issued?) ...[
                    Panel(
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
                            'Share this code with ${issued['email']}. They can enter it under “Join with invitation” in the app.',
                          ),
                          const SizedBox(height: 12),
                          SelectableText(
                            issued['token'] as String,
                            key: const ValueKey('invitation-code'),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          if (issued['expires_at'] != null)
                            Text('Expires ${issued['expires_at']}'),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            children: [
                              OutlinedButton.icon(
                                onPressed: () => _share(context, copy: true),
                                icon: const Icon(Icons.copy),
                                label: Text(
                                  _copied ? 'Code copied' : 'Copy code',
                                ),
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
                                  _issued = null;
                                  _copied = false;
                                  _role = null;
                                }),
                                child: const Text('Invite another'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Semantics(liveRegion: true, child: Text(_error!)),
                    ),
                  FutureBuilder<Map<String, dynamic>>(
                    future: _team,
                    builder: (context, state) {
                      if (state.connectionState != ConnectionState.done &&
                          !state.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (state.hasError || !state.hasData) {
                        return MessagePanel(
                          title: 'Could not load team',
                          message: state.error?.toString() ?? 'Try again.',
                          label: 'Retry',
                          action: _refresh,
                        );
                      }
                      final data = state.requireData;
                      final roles = {
                        for (final row in data['roles'] as List)
                          row['key'] as String: row['label'] as String,
                      };
                      final members = data['members'] as List;
                      final invites = data['invitations'] as List;
                      String roleName(Map row) =>
                          roles[row['role']] ??
                          (row['role'] == 'owner'
                              ? 'Owner'
                              : row['role'].toString());
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_issued == null)
                            Panel(
                              border: true,
                              child: Form(
                                key: _form,
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    const Display(
                                      'Invite a teammate',
                                      size: 26,
                                    ),
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
                                      validator: (v) =>
                                          RegExp(
                                            r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                                          ).hasMatch((v ?? '').trim())
                                          ? null
                                          : 'Enter a valid email address.',
                                    ),
                                    const SizedBox(height: 12),
                                    DropdownButtonFormField<String>(
                                      initialValue: roles.containsKey(_role)
                                          ? _role
                                          : null,
                                      isExpanded: true,
                                      decoration: const InputDecoration(
                                        labelText: 'Staff role',
                                        prefixIcon: Icon(Icons.badge_outlined),
                                      ),
                                      validator: (v) => roles.containsKey(v)
                                          ? null
                                          : 'Choose a role for this invitation.',
                                      items: [
                                        for (final role in roles.entries)
                                          DropdownMenuItem(
                                            value: role.key,
                                            child: Text(role.value),
                                          ),
                                      ],
                                      onChanged: _busy
                                          ? null
                                          : (v) => setState(() => _role = v),
                                    ),
                                    const SizedBox(height: 12),
                                    FilledButton.icon(
                                      onPressed: _busy ? null : _invite,
                                      icon: const Icon(
                                        Icons.person_add_alt_1_outlined,
                                      ),
                                      label: const Text('Create invitation'),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          const SizedBox(height: 20),
                          Panel(
                            border: true,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Display(
                                  'Members · ${members.length}',
                                  size: 24,
                                ),
                                for (final member in members)
                                  ListTile(
                                    leading: RecordIcon(
                                      member['role'] == 'owner'
                                          ? Icons.manage_accounts_outlined
                                          : Icons.person_outline,
                                    ),
                                    title: Text(
                                      member['full_name'] ?? member['email'],
                                    ),
                                    subtitle: Text(
                                      "${member['email']} · ${roleName(member)}",
                                    ),
                                  ),
                                const SizedBox(height: 16),
                                Display(
                                  'Pending invitations · ${invites.length}',
                                  size: 24,
                                ),
                                if (invites.isEmpty)
                                  const Padding(
                                    padding: EdgeInsets.only(top: 8),
                                    child: Text('No pending invitations.'),
                                  ),
                                for (final inv in invites)
                                  ListTile(
                                    leading: const RecordIcon(
                                      Icons.mark_email_unread_outlined,
                                    ),
                                    title: Text(inv['email']),
                                    subtitle: Text(
                                      "${roleName(inv)} · Expires ${inv['expires_at']}",
                                    ),
                                    trailing: IconButton(
                                      tooltip: 'Revoke invitation',
                                      icon: const Icon(Icons.cancel_outlined),
                                      onPressed: _busy
                                          ? null
                                          : () => _revoke(inv),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
