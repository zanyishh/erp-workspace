class WorkspaceContext {
  WorkspaceContext.fromJson(Map<String, dynamic> json)
    : company = json['company'] as String?,
      companies = List.unmodifiable(
        (json['companies'] as List? ?? []).map(
          (e) => Map<String, dynamic>.unmodifiable(e as Map),
        ),
      ),
      enabled = json['knitting_enabled'] == true,
      needsIndustrySelection = json['needs_industry_selection'] == true,
      state = json['setup_state'] as String? ?? 'General ERP',
      revision = (json['revision'] as num? ?? 0).toInt(),
      accessFingerprint = json['access_fingerprint'] as String? ?? '',
      canConfigure = json['can_configure'] == true,
      capabilities = Set.unmodifiable(
        List<String>.from(json['capabilities'] as List? ?? []),
      );
  final String? company;
  final List<Map<String, dynamic>> companies;
  final String state, accessFingerprint;
  final int revision;
  final bool enabled, canConfigure, needsIndustrySelection;
  final Set<String> capabilities;
  bool allows(String capability) =>
      enabled && capabilities.contains(capability);
  List<String> get destinations => [
    if (allows('overview') && allows('jobs')) 'Overview',
    if (allows('jobs')) 'Jobs',
    if (allows('materials')) 'Yarn',
    if (allows('planning')) 'Planning',
    if (allows('production')) 'Production',
    if (allows('quality')) 'Quality',
    if (allows('delivery')) 'Delivery',
    if (allows('billing')) 'Billing',
    if (allows('factory')) 'Factory',
    if (allows('reports')) 'Reports',
    if (canConfigure) 'Setup',
  ];
}
