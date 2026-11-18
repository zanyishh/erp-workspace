# Flutter API and data-flow contracts

Captured from the unchanged audit baseline on 16 November 2026. The public method signature is the client input/output contract. Local UI/test/tool consumers identify where its data enters and leaves a feature. Full parameter signatures and call-site lines are retained in the [JSON inventory](2026-11-16-baseline-inventory.json). Method matching is static and cannot resolve every callback/dynamic call.

`_native` and `_industry` serialize non-string arguments as JSON in POST form fields, unwrap `message`, and share `_request` authentication, timeout, status and access-revision handling. Read and write endpoints both use this authenticated path. Methods without a direct endpoint are lifecycle helpers, value operations or compositions of private helpers. Overview reads use ERPNext resource/get-count helpers. Screen-level workflows and write recovery are described in [ARCHITECTURE.md](../../ARCHITECTURE.md).

| Public method | Source | Direct endpoint(s) | Local consumers |
| --- | --- | --- | --- |
| `invoiceDefaults` | `lib/invoice_api.dart:11` | `/api/method/erp_extensions.invoice_compose.defaults` | `lib/invoice_composer.dart` |
| `reviewInvoice` | `lib/invoice_api.dart:14` | `/api/method/erp_extensions.invoice_compose.preview` | `lib/invoice_composer.dart` |
| `saveInvoiceDraft` | `lib/invoice_api.dart:17` | `/api/method/erp_extensions.invoice_compose.save_draft` | `lib/invoice_composer.dart` |
| `salesInvoices` | `lib/invoice_api.dart:29` | `/api/method/erp_extensions.invoices.register` | `lib/invoice_hub.dart`, `tool/pilot_company_invoice_settings_test.dart`, `tool/pilot_invoice_gallery_test.dart` |
| `invoicePrintData` | `lib/invoice_api.dart:43` | `/api/method/erp_extensions.invoices.print_data` | `lib/invoice_preview.dart`, `tool/pilot_company_invoice_settings_test.dart`, `tool/pilot_invoice_gallery_test.dart` |
| `invoiceSettings` | `lib/invoice_api.dart:46` | `/api/method/erp_extensions.invoices.get_settings` | `lib/invoice_preview.dart`, `lib/invoice_settings.dart`, `tool/pilot_company_invoice_settings_test.dart` |
| `saveInvoiceSettings` | `lib/invoice_api.dart:49` | `/api/method/erp_extensions.invoices.save_settings` | `lib/invoice_settings.dart`, `tool/pilot_company_invoice_settings_test.dart` |
| `setInvoiceTemplate` | `lib/invoice_api.dart:59` | `/api/method/erp_extensions.invoices.set_template` | `lib/invoice_composer.dart`, `lib/invoice_preview.dart`, `tool/pilot_invoice_gallery_test.dart` |
| `importedHistorySummary` | `lib/imported_history_api.dart:11` | `/api/method/erp_extensions.migration.api.summary` | `lib/imported_history.dart` |
| `importedHistoryRecords` | `lib/imported_history_api.dart:14` | `/api/method/erp_extensions.migration.api.records` | `lib/imported_history.dart` |
| `originalProductionSummary` | `lib/imported_history_api.dart:30` | `/api/method/erp_extensions.migration.production_reports.summary` | `lib/original_production_report.dart`, `test/original_production_report_api_test.dart` |
| `importedHistoryDetail` | `lib/imported_history_api.dart:44` | `/api/method/erp_extensions.migration.api.detail` | `lib/imported_history.dart` |
| `importedSharedCash` | `lib/imported_history_api.dart:49` | `/api/method/erp_extensions.migration.api.shared_cash` | `lib/imported_history.dart` |
| `importedHistoryFilterOptions` | `lib/imported_history_api.dart:63` | `/api/method/erp_extensions.migration.api.filter_options` | `lib/history_filters.dart` |
| `importedRecordPrintData` | `lib/imported_history_api.dart:79` | `/api/method/erp_extensions.migration.printing.record_data` | `lib/imported_record_preview.dart`, `test/imported_record_api_test.dart` |
| `importedInvoicePrintData` | `lib/imported_history_api.dart:87` | `/api/method/erp_extensions.migration.api.invoice_print_data` | `lib/invoice_preview.dart`, `tool/pilot_customer_migration_test.dart` |
| `toString` | `lib/erp_api.dart:26` | Local lifecycle/composite |  |
| `toString` | `lib/erp_api.dart:33` | Local lifecycle/composite |  |
| `validateServiceOrigin` | `lib/erp_api.dart:37` | Local lifecycle/composite |  |
| `useLocalWorkspace` | `lib/erp_api.dart:75` | Local lifecycle/composite | `lib/local_workspace.dart`, `test/local_workspace_test.dart` |
| `useConfiguredLocalWorkspace` | `lib/erp_api.dart:100` | Local lifecycle/composite | `lib/local_workspace.dart` |
| `addAccessListener` | `lib/erp_api.dart:136` | Local lifecycle/composite | `lib/bank_statement_import.dart`, `lib/bank_statement_matching.dart`, `lib/document_editor.dart`, `lib/history_filters.dart`, `lib/invoice_composer.dart`, `lib/invoice_settings.dart`, `lib/knitting_forms.dart`, `lib/knitting_register.dart`, `lib/knitting_workflow_views.dart`, `lib/master_import_screen.dart`, `lib/mill_overview.dart`, `lib/payment_reconciliation.dart`, `lib/ui/access_gate.dart`, `test/access_refresh_test.dart`, `test/workspace_context_test.dart` |
| `removeAccessListener` | `lib/erp_api.dart:138` | Local lifecycle/composite | `lib/bank_statement_import.dart`, `lib/bank_statement_matching.dart`, `lib/document_editor.dart`, `lib/history_filters.dart`, `lib/invoice_composer.dart`, `lib/invoice_settings.dart`, `lib/knitting_forms.dart`, `lib/knitting_register.dart`, `lib/knitting_workflow_views.dart`, `lib/master_import_screen.dart`, `lib/mill_overview.dart`, `lib/payment_reconciliation.dart`, `lib/ui/access_gate.dart` |
| `contextFor` | `lib/erp_api.dart:140` | Local lifecycle/composite | `lib/imported_history.dart`, `lib/knitting_forms.dart`, `lib/knitting_reports.dart`, `lib/native_catalog.dart`, `lib/original_production_report.dart`, `test/access_refresh_test.dart` |
| `supportsOperationRecovery` | `lib/erp_api.dart:141` | Local lifecycle/composite | `lib/document_editor.dart`, `lib/invoice_composer.dart`, `lib/knitting_forms.dart`, `lib/main.dart`, `lib/payment_reconciliation.dart`, `test/operation_api_test.dart`, `tool/pilot_ux_test.dart` |
| `publishContext` | `lib/erp_api.dart:149` | Local lifecycle/composite | `test/bank_statement_matching_test.dart`, `test/document_interaction_test.dart`, `test/editor_access_test.dart`, `test/imported_history_test.dart`, `test/industry_home_test.dart`, `test/knitting_factory_masters_test.dart`, `test/knitting_job_filters_test.dart`, `test/knitting_production_machine_test.dart`, `test/knitting_production_rows_test.dart`, `test/knitting_reports_test.dart`, `test/knitting_screen_test.dart`, `test/knitting_workflow_destinations_test.dart`, `test/native_catalog_test.dart`, `test/operation_api_test.dart`, `test/payment_reconciliation_test.dart`, `test/workspace_context_test.dart` |
| `serviceOrigin` | `lib/erp_api.dart:172` | Local lifecycle/composite |  |
| `validateServer` | `lib/erp_api.dart:195` | Local lifecycle/composite | `test/erp_api_test.dart` |
| `login` | `lib/erp_api.dart:202` | `/api/method/login` | `lib/session_recovery.dart`, `test/access_refresh_test.dart`, `test/erp_api_test.dart`, `test/native_session_test.dart`, `tool/pilot_master_import_test.dart`, `tool/pilot_specialized_fields_test.dart`, `tool/pilot_ux_test.dart`, `tool/verify_connection.dart`, `tool/verify_knitting.dart`, `tool/verify_native.dart` |
| `verifyLogin` | `lib/erp_api.dart:211` | `/api/method/login` | `lib/session_recovery.dart`, `test/erp_api_test.dart` |
| `registerOwner` | `lib/erp_api.dart:560` | `/api/method/erp_extensions.onboarding.register_owner` | `lib/sign_in.dart` |
| `receiptInspectionItems` | `lib/erp_api.dart:576` | `/api/method/erp_extensions.operational_handoffs.receipt_items` | `lib/operational_handoffs.dart` |
| `inspectReceipt` | `lib/erp_api.dart:578` | `/api/method/erp_extensions.operational_handoffs.inspect_receipt` | `lib/operational_handoffs.dart` |
| `maintenanceLogs` | `lib/erp_api.dart:589` | `/api/method/erp_extensions.operational_handoffs.maintenance_logs` | `lib/operational_handoffs.dart` |
| `assetMaintenancePlan` | `lib/erp_api.dart:591` | `/api/method/erp_extensions.operational_handoffs.asset_plan` | `lib/operational_handoffs.dart` |
| `importBankCsv` | `lib/erp_api.dart:594` | `/api/method/erp_extensions.bank_csv.statement_csv` | `lib/bank_statement_import.dart` |
| `bankStatements` | `lib/erp_api.dart:610` | `/api/method/erp_extensions.bank_matching.entries` | `lib/bank_statement_import.dart`, `lib/bank_statement_matching.dart` |
| `bankMatches` | `lib/erp_api.dart:619` | `/api/method/erp_extensions.bank_matching.matches` | `lib/bank_statement_matching.dart` |
| `matchBankPayment` | `lib/erp_api.dart:632` | `/api/method/erp_extensions.bank_matching.match` | `lib/bank_statement_matching.dart` |
| `reconciliationEntries` | `lib/erp_api.dart:652` | `/api/method/erp_extensions.reconciliation.candidates` | `lib/payment_reconciliation.dart` |
| `beginOperation` | `lib/erp_api.dart:666` | `/api/method/erp_extensions.operations.begin_operation` | `lib/document_recovery.dart`, `lib/invoice_composer.dart`, `lib/knitting_forms.dart`, `lib/payment_reconciliation.dart`, `test/operation_api_test.dart` |
| `pendingOperations` | `lib/erp_api.dart:682` | `/api/method/erp_extensions.operations.pending_operations` | `lib/pending_operations.dart`, `test/operation_api_test.dart` |
| `operationStatus` | `lib/erp_api.dart:690` | `/api/method/erp_extensions.operations.operation_status` | `lib/document_recovery.dart`, `lib/invoice_composer.dart`, `lib/knitting_forms.dart`, `lib/payment_reconciliation.dart`, `lib/pending_operations.dart`, `test/operation_api_test.dart`, `tool/pilot_ux_test.dart` |
| `closeOperation` | `lib/erp_api.dart:698` | `/api/method/erp_extensions.operations.close_operation` | `lib/document_recovery.dart`, `lib/invoice_composer.dart`, `lib/knitting_forms.dart`, `lib/payment_reconciliation.dart`, `lib/pending_operations.dart`, `test/operation_api_test.dart` |
| `acknowledgeOperation` | `lib/erp_api.dart:706` | `/api/method/erp_extensions.operations.acknowledge_operation` | `lib/document_recovery.dart`, `lib/invoice_composer.dart`, `lib/knitting_forms.dart`, `lib/payment_reconciliation.dart`, `lib/pending_operations.dart`, `test/operation_api_test.dart` |
| `allocatePayment` | `lib/erp_api.dart:713` | `/api/method/erp_extensions.reconciliation.allocate` | `lib/payment_reconciliation.dart` |
| `redeemExistingInvitation` | `lib/erp_api.dart:735` | Local lifecycle/composite | `lib/sign_in.dart`, `test/erp_api_test.dart` |
| `acceptInvitation` | `lib/erp_api.dart:756` | `/api/method/erp_extensions.onboarding.accept_invite` | `lib/sign_in.dart` |
| `team` | `lib/erp_api.dart:770` | `/api/method/erp_extensions.onboarding.team` | `lib/team_access.dart` |
| `inviteMember` | `lib/erp_api.dart:773` | `/api/method/erp_extensions.onboarding.invite_member` | `lib/team_access.dart` |
| `revokeInvitation` | `lib/erp_api.dart:783` | `/api/method/erp_extensions.onboarding.revoke_invite` | `lib/team_access.dart` |
| `posConfigure` | `lib/erp_api.dart:790` | `/api/method/erp_extensions.pos_checkout.configure` | `lib/pos_checkout.dart` |
| `posRegister` | `lib/erp_api.dart:793` | `/api/method/erp_extensions.pos_checkout.register` | `lib/pos_checkout.dart` |
| `posOpenShift` | `lib/erp_api.dart:796` | `/api/method/erp_extensions.pos_checkout.open_shift` | `lib/pos_checkout.dart` |
| `posQuote` | `lib/erp_api.dart:806` | `/api/method/erp_extensions.pos_checkout.quote` | `lib/pos_checkout.dart` |
| `posCheckout` | `lib/erp_api.dart:818` | `/api/method/erp_extensions.pos_checkout.checkout` | `lib/pos_checkout.dart` |
| `posRefundReview` | `lib/erp_api.dart:834` | `/api/method/erp_extensions.pos_checkout.refund_review` | `lib/pos_checkout.dart` |
| `posRefund` | `lib/erp_api.dart:844` | `/api/method/erp_extensions.pos_checkout.refund` | `lib/pos_checkout.dart` |
| `posClosing` | `lib/erp_api.dart:858` | `/api/method/erp_extensions.pos_checkout.closing` | `lib/pos_checkout.dart` |
| `posCloseShift` | `lib/erp_api.dart:864` | `/api/method/erp_extensions.pos_checkout.close_shift` | `lib/pos_checkout.dart` |
| `workspaceContext` | `lib/erp_api.dart:876` | `/api/method/erp_extensions.workspace.context` | `lib/bank_statement_matching.dart`, `lib/knitting_screen.dart`, `lib/main.dart`, `lib/payment_reconciliation.dart`, `test/access_refresh_test.dart`, `tool/pilot_mill_test.dart`, `tool/pilot_ux_test.dart`, `tool/verify_knitting.dart` |
| `selectCompany` | `lib/erp_api.dart:884` | `/api/method/erp_extensions.workspace.select_company` | `lib/main.dart`, `tool/verify_knitting.dart` |
| `configureIndustry` | `lib/erp_api.dart:892` | `/api/method/erp_extensions.workspace.configure` | `lib/knitting_screen.dart` |
| `industrySettings` | `lib/erp_api.dart:906` | `/api/method/erp_extensions.workspace.settings` | `lib/knitting_screen.dart`, `tool/verify_knitting.dart` |
| `knittingSnapshot` | `lib/erp_api.dart:908` | `/api/method/erp_extensions.knitting.api.snapshot` | `lib/knitting_forms.dart`, `lib/knitting_screen.dart`, `lib/knitting_workflow_views.dart`, `test/access_refresh_test.dart`, `tool/pilot_mill_test.dart`, `tool/pilot_ux_test.dart`, `tool/verify_knitting.dart` |
| `knittingRegister` | `lib/erp_api.dart:917` | `/api/method/erp_extensions.knitting.api.register` | `lib/knitting_forms.dart`, `lib/knitting_register.dart`, `lib/knitting_workflow_views.dart`, `test/knitting_factory_masters_api_test.dart`, `test/knitting_job_filters_api_test.dart` |
| `knittingOverview` | `lib/erp_api.dart:942` | `/api/method/erp_extensions.knitting.api.overview` | `lib/mill_overview.dart` |
| `knittingRoll` | `lib/erp_api.dart:944` | `/api/method/erp_extensions.knitting.api.roll` | `lib/knitting_screen.dart` |
| `knittingCommand` | `lib/erp_api.dart:953` | `/api/method/erp_extensions.knitting.api.command` | `lib/knitting_forms.dart`, `tool/verify_knitting.dart` |
| `knittingInvoicePreview` | `lib/erp_api.dart:966` | `/api/method/erp_extensions.knitting.api.invoice_preview` | `lib/knitting_forms.dart` |
| `knittingCommandStatus` | `lib/erp_api.dart:975` | `/api/method/erp_extensions.knitting.api.command_status` | `lib/knitting_forms.dart`, `tool/verify_knitting.dart` |
| `knittingLookup` | `lib/erp_api.dart:982` | `/api/method/erp_extensions.knitting.api.lookup` | `lib/knitting_batch_rows.dart`, `lib/knitting_forms.dart`, `lib/knitting_workflow_views.dart`, `tool/verify_knitting.dart` |
| `knittingReport` | `lib/erp_api.dart:995` | `/api/method/erp_extensions.knitting.api.report` | `lib/knitting_reports.dart`, `tool/pilot_mill_test.dart` |
| `knittingExport` | `lib/erp_api.dart:1004` | `/api/method/erp_extensions.knitting.api.export` | `lib/knitting_reports.dart`, `lib/knitting_screen.dart` |
| `documentActivity` | `lib/erp_api.dart:1014` | `/api/method/erp_extensions.api.activity` | `lib/document_activity.dart`, `tool/verify_native.dart` |
| `comment` | `lib/erp_api.dart:1016` | `/api/method/erp_extensions.api.add_comment` | `lib/document_activity.dart`, `tool/verify_native.dart` |
| `assignDocument` | `lib/erp_api.dart:1024` | `/api/method/erp_extensions.api.assign` | `lib/document_activity.dart` |
| `unassignDocument` | `lib/erp_api.dart:1028` | `/api/method/erp_extensions.api.unassign` | `lib/document_activity.dart` |
| `uploadAttachment` | `lib/erp_api.dart:1032` | `/api/method/erp_extensions.api.upload_attachment` | `lib/document_activity.dart`, `tool/verify_native.dart` |
| `fieldAttachment` | `lib/erp_api.dart:1046` | `/api/method/erp_extensions.api.field_attachment` | `lib/document_editor.dart`, `tool/pilot_specialized_fields_test.dart` |
| `removeAttachment` | `lib/erp_api.dart:1066` | `/api/method/erp_extensions.api.remove_attachment` | `lib/document_activity.dart`, `tool/verify_native.dart` |
| `attachment` | `lib/erp_api.dart:1074` | `/api/method/erp_extensions.api.attachment` | `lib/document_activity.dart`, `tool/verify_native.dart` |
| `printOptions` | `lib/erp_api.dart:1090` | `/api/method/erp_extensions.api.print_options` | `lib/document_activity.dart`, `test/native_session_test.dart` |
| `printPdf` | `lib/erp_api.dart:1098` | `/api/method/erp_extensions.api.print_pdf` | `lib/document_activity.dart`, `tool/verify_knitting.dart`, `tool/verify_native.dart` |
| `nativeCatalog` | `lib/erp_api.dart:1114` | `/api/method/erp_extensions.api.catalog` | `lib/native_catalog.dart`, `test/native_catalog_test.dart`, `tool/pilot_master_import_test.dart`, `tool/pilot_mill_test.dart`, `tool/pilot_specialized_fields_test.dart`, `tool/pilot_trade_test.dart`, `tool/pilot_ux_test.dart`, `tool/profile_startup.dart`, `tool/verify_knitting.dart`, `tool/verify_native.dart` |
| `reportDefinition` | `lib/erp_api.dart:1117` | `/api/method/erp_extensions.api.report_definition` | `lib/report_screen.dart` |
| `runReport` | `lib/erp_api.dart:1121` | `/api/method/erp_extensions.api.run_report` | `lib/report_screen.dart` |
| `queueReport` | `lib/erp_api.dart:1127` | `/api/method/erp_extensions.api.queue_report` | `lib/report_screen.dart` |
| `reclassifyMasters` | `lib/erp_api.dart:1131` | `/api/method/erp_extensions.api.reclassify_masters` | `lib/native_catalog.dart` |
| `importMasters` | `lib/erp_api.dart:1146` | `/api/method/erp_extensions.api.import_masters` | `lib/master_import_screen.dart` |
| `changeTreeRecord` | `lib/erp_api.dart:1158` | `/api/method/erp_extensions.api.change_tree_record` | `lib/native_tree.dart` |
| `nativeSchema` | `lib/erp_api.dart:1176` | `/api/method/erp_extensions.api.schema` | `lib/document_editor.dart`, `tool/verify_native.dart` |
| `nativeTree` | `lib/erp_api.dart:1178` | `/api/method/erp_extensions.api.tree_children` | `lib/native_tree.dart`, `test/native_api_test.dart` |
| `nativeDocument` | `lib/erp_api.dart:1209` | `/api/method/erp_extensions.api.document` | `lib/document_editor.dart`, `lib/knitting_workflow_views.dart`, `test/native_api_test.dart`, `tool/pilot_master_import_test.dart`, `tool/pilot_mill_test.dart`, `tool/pilot_specialized_fields_test.dart`, `tool/pilot_trade_test.dart`, `tool/pilot_ux_test.dart`, `tool/verify_native.dart` |
| `saveNative` | `lib/erp_api.dart:1222` | `/api/method/erp_extensions.api.save` | `lib/document_editor.dart`, `test/native_api_test.dart`, `test/operation_api_test.dart`, `tool/verify_native.dart` |
| `partyDefaultsNative` | `lib/erp_api.dart:1236` | `/api/method/erp_extensions.api.party_defaults` | `lib/document_editor.dart` |
| `itemDefaultsNative` | `lib/erp_api.dart:1242` | `/api/method/erp_extensions.api.item_defaults` | `lib/document_editor.dart` |
| `newFromNative` | `lib/erp_api.dart:1254` | `/api/method/erp_extensions.api.new_from` | `lib/document_editor.dart` |
| `prepareNative` | `lib/erp_api.dart:1269` | `/api/method/erp_extensions.api.prepare` | `lib/document_editor.dart` |
| `transitionNative` | `lib/erp_api.dart:1275` | `/api/method/erp_extensions.api.transition` | `lib/document_editor.dart`, `test/native_api_test.dart`, `test/operation_api_test.dart` |
| `taskView` | `lib/erp_api.dart:1293` | `/api/method/erp_extensions.api.task_view` | `lib/task_planner.dart` |
| `nativeRecords` | `lib/erp_api.dart:1305` | `/api/method/erp_extensions.api.records` | `lib/native_catalog.dart`, `tool/pilot_master_import_test.dart` |
| `searchLinks` | `lib/erp_api.dart:1327` | `/api/method/erp_extensions.api.search_link` | `lib/bank_statement_matching.dart`, `lib/document_activity.dart`, `lib/document_editor.dart`, `lib/invoice_composer.dart`, `lib/native_catalog.dart`, `lib/payment_reconciliation.dart`, `lib/pos_checkout.dart`, `lib/report_screen.dart` |
| `records` | `lib/erp_api.dart:1393` | Local lifecycle/composite | `lib/main.dart`, `test/erp_api_test.dart`, `tool/verify_connection.dart` |
| `newRowNative` | `lib/erp_api.dart:1452` | `/api/method/erp_extensions.api.new_row` | `lib/document_editor.dart`, `tool/verify_native.dart` |
| `snapshot` | `lib/erp_api.dart:1463` | Local lifecycle/composite | `lib/main.dart`, `test/access_refresh_test.dart`, `test/erp_api_test.dart`, `tool/verify_connection.dart` |
| `signOut` | `lib/erp_api.dart:1592` | `/api/method/logout` | `lib/main.dart`, `test/erp_api_test.dart`, `tool/profile_startup.dart`, `tool/verify_connection.dart`, `tool/verify_knitting.dart`, `tool/verify_native.dart`, `tool/verify_pos.dart` |
| `close` | `lib/erp_api.dart:1600` | Local lifecycle/composite | `lib/local_workspace.dart`, `lib/main.dart`, `lib/sign_in.dart`, `test/access_refresh_test.dart`, `test/erp_api_test.dart`, `test/imported_record_api_test.dart`, `test/invoice_hub_test.dart`, `test/invoice_settings_test.dart`, `test/knitting_factory_masters_api_test.dart`, `test/knitting_job_filters_api_test.dart`, `test/knitting_screen_test.dart`, `test/native_api_test.dart`, `test/native_session_test.dart`, `test/native_tree_test.dart`, `test/operation_api_test.dart`, `test/original_production_report_api_test.dart`, `tool/pilot_master_import_test.dart`, `tool/pilot_specialized_fields_test.dart`, `tool/pilot_ux_test.dart`, `tool/verify_connection.dart`, `tool/verify_knitting.dart`, `tool/verify_native.dart`, `tool/verify_pos.dart` |
