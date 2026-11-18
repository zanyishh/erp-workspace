class WorkspaceContext {
  WorkspaceContext.fromJson(Map<String, dynamic> json)
    : company = json['company'] as String?,
      companies = List.unmodifiable(
        (json['companies'] as List? ?? []).map(
          (e) => Map<String, dynamic>.unmodifiable(e as Map),
        ),
      ),
      enabled = json['knitting_enabled'] == true,
      knittingOnly = json['knitting_only'] == true,
      needsIndustrySelection = json['needs_industry_selection'] == true,
      state = json['setup_state'] as String? ?? 'General ERP',
      revision = (json['revision'] as num? ?? 0).toInt(),
      operationRecoveryVersion =
          (json['operation_recovery_version'] as num? ?? 0).toInt(),
      accessFingerprint = json['access_fingerprint'] as String? ?? '',
      canConfigure = json['can_configure'] == true,
      canManageTeam = json['can_manage_team'] == true,
      cashierHome = json['cashier_home'] == true,
      canOperatePos = json['can_operate_pos'] == true,
      canMatchBankStatements = json['can_match_bank_statements'] == true,
      canReconcilePayments = json['can_reconcile_payments'] == true,
      canOpenDesk = json['can_open_desk'] != false,
      canReadImportedHistory = json['can_read_imported_history'] == true,
      readableRecords = Set.unmodifiable(
        List<String>.from(json['readable_records'] as List? ?? []),
      ),
      creatableRecords = Set.unmodifiable(
        List<String>.from(json['creatable_records'] as List? ?? []),
      ),
      unavailableKnittingActions = Set.unmodifiable(
        List<String>.from(json['unavailable_knitting_actions'] as List? ?? []),
      ),
      capabilities = Set.unmodifiable(
        List<String>.from(json['capabilities'] as List? ?? []),
      );
  final String? company;
  final List<Map<String, dynamic>> companies;
  final String state, accessFingerprint;
  final int revision, operationRecoveryVersion;
  final bool enabled,
      knittingOnly,
      canConfigure,
      canManageTeam,
      canReconcilePayments,
      cashierHome,
      canOperatePos,
      canMatchBankStatements,
      canOpenDesk,
      canReadImportedHistory,
      needsIndustrySelection;
  final Set<String> readableRecords;
  final Set<String> capabilities, creatableRecords, unavailableKnittingActions;
  bool allows(String capability) =>
      enabled && capabilities.contains(capability);
  List<String> get destinations => [
    if (allows('overview') && allows('jobs')) 'Overview',
    if (allows('jobs')) 'Jobs',
    if (allows('jobs') && readableRecords.contains('Quotation')) 'Estimation',
    if (allows('jobs') &&
        ['materials', 'factory', 'billing', 'lifecycle'].any(allows))
      'Subcontracting',
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
