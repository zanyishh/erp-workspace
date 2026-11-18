# Flutter audit baseline inventory

Captured 16 November 2026 before application edits. The [machine-readable inventory](2026-11-16-baseline-inventory.json) contains every parsed declaration, public member signature, method location, call target, test declaration, import, export, part and source hash. These are static references; Dart callbacks, inherited methods, generated plugin registration and runtime dispatch are not a complete dynamic call graph.

74 source files; 37,786 lines; 84 test files; 470 statically declared unit/widget tests (parameterized loops can produce more runtime cases); 16 tool Dart files with 12 test declarations. All 174 files parsed with zero syntax diagnostics.

## Feature and dependency map

Paths are relative to `apps/erp_client/`. `part` files share their owning library and are not independent components. Every source file has exactly one owner below. Test links are inferred from direct package imports; tests can exercise additional features transitively.

### app

| Source | Lines | Local dependencies | Direct test/tool consumers |
| --- | ---: | --- | --- |
| `lib/main.dart` | 1393 | `pending_operations.dart`, `retained_load.dart`, `design.dart`, `document_editor.dart`, `native_catalog.dart`, `erp_api.dart`, `erp_models.dart`, `module_browser.dart`, `payment_reconciliation.dart`, `bank_statement_matching.dart`, `pos_checkout.dart`, `overview.dart`, `invoice_hub.dart`, `imported_history.dart`, `sign_in.dart`, `local_workspace.dart`, `team_access.dart`, `session_recovery.dart`, `widgets.dart`, `workspace_picker.dart`, `workspace_context.dart`, `knitting_screen.dart`, `ui/access_gate.dart` | `test/industry_home_test.dart`, `test/local_workspace_test.dart`, `test/navigation_retention_test.dart`, `tool/pilot_company_invoice_settings_test.dart`, `tool/pilot_customer_migration_test.dart`, `tool/pilot_invoice_gallery_test.dart`, `tool/pilot_local_launch_test.dart`, `tool/pilot_mill_test.dart`, `tool/pilot_onboarding_test.dart`, `tool/pilot_trade_test.dart`, `tool/pilot_ux_test.dart`, `tool/profile_startup.dart`, `tool/profile_workspace.dart` |

### authentication

| Source | Lines | Local dependencies | Direct test/tool consumers |
| --- | ---: | --- | --- |
| `lib/session_recovery.dart` | 206 | `erp_api.dart` | `test/session_recovery_test.dart` |
| `lib/sign_in.dart` | 493 | `design.dart`, `erp_api.dart`, `session_recovery.dart`, `ui/workspace_art.dart`, `ui/workspace_ui.dart`, `widgets.dart` | `test/industry_home_test.dart`, `test/layout_test.dart`, `test/local_workspace_test.dart`, `test/onboarding_test.dart`, `tool/pilot_customer_migration_test.dart`, `tool/pilot_local_launch_test.dart`, `tool/pilot_onboarding_test.dart`, `tool/profile_workspace.dart` |

### team

| Source | Lines | Local dependencies | Direct test/tool consumers |
| --- | ---: | --- | --- |
| `lib/team_access.dart` | 440 | `erp_api.dart`, `ui/access_gate.dart`, `ui/workspace_art.dart`, `ui/workspace_ui.dart`, `ui/record_icon.dart`, `widgets.dart` | `test/onboarding_test.dart`, `tool/pilot_onboarding_test.dart` |

### workspace

| Source | Lines | Local dependencies | Direct test/tool consumers |
| --- | ---: | --- | --- |
| `lib/local_workspace.dart` | 187 | `erp_api.dart` | `test/local_workspace_test.dart`, `test/navigation_retention_test.dart`, `tool/pilot_company_invoice_settings_test.dart`, `tool/pilot_customer_migration_test.dart`, `tool/pilot_local_launch_test.dart` |
| `lib/workspace_context.dart` | 73 |  | `test/bank_statement_matching_test.dart`, `test/document_interaction_test.dart`, `test/editor_access_test.dart`, `test/imported_history_test.dart`, `test/industry_home_test.dart`, `test/knitting_batch_production_test.dart`, `test/knitting_batches_test.dart`, `test/knitting_commercial_revision_test.dart`, `test/knitting_confirmation_test.dart`, `test/knitting_customer_labels_test.dart`, `test/knitting_diameter_display_test.dart`, `test/knitting_factory_masters_test.dart`, `test/knitting_form_entry_test.dart`, `test/knitting_imported_programme_guard_test.dart`, `test/knitting_job_filters_test.dart`, `test/knitting_pagination_test.dart`, `test/knitting_presentation_test.dart`, `test/knitting_production_machine_test.dart`, `test/knitting_production_rows_test.dart`, `test/knitting_recovery_test.dart`, `test/knitting_reports_test.dart`, `test/knitting_roll_operator_test.dart`, `test/knitting_running_yarn_overview_test.dart`, `test/knitting_screen_test.dart`, `test/knitting_workflow_destinations_test.dart`, `test/local_workspace_test.dart`, `test/mill_batch_sources_test.dart`, `test/mill_navigation_pilot_test.dart`, `test/mill_register_scroll_test.dart`, `test/native_catalog_test.dart`, `test/navigation_retention_test.dart`, `test/operation_api_test.dart`, `test/original_production_report_test.dart`, `test/payment_reconciliation_test.dart`, `test/sdk_migration_test.dart`, `test/workspace_context_test.dart`, `tool/profile_workspace.dart` |
| `lib/workspace_picker.dart` | 106 | `ui/record_icon.dart`, `design.dart`, `erp_models.dart`, `widgets.dart` | `test/workspace_picker_test.dart` |

### overview

| Source | Lines | Local dependencies | Direct test/tool consumers |
| --- | ---: | --- | --- |
| `lib/erp_models.dart` | 228 |  | `test/access_refresh_test.dart`, `test/erp_api_test.dart`, `test/erp_models_test.dart`, `test/industry_home_test.dart`, `test/layout_test.dart`, `test/local_workspace_test.dart`, `test/module_browser_test.dart`, `test/navigation_retention_test.dart`, `test/overview_chart_test.dart`, `test/sdk_migration_test.dart`, `test/workspace_picker_test.dart`, `tool/profile_workspace.dart`, `tool/verify_connection.dart` |
| `lib/module_browser.dart` | 614 | `retained_load.dart`, `ui/record_icon.dart`, `ui/workspace_art.dart`, `design.dart`, `erp_models.dart`, `widgets.dart` | `test/module_browser_test.dart`, `test/navigation_retention_test.dart`, `test/sdk_migration_test.dart` |
| `lib/overview.dart` | 466 | `design.dart`, `erp_models.dart`, `sales_chart.dart`, `widgets.dart`, `ui/workspace_art.dart` | `test/industry_home_test.dart`, `test/layout_test.dart`, `test/local_workspace_test.dart`, `test/navigation_retention_test.dart`, `test/overview_chart_test.dart`, `test/sdk_migration_test.dart`, `tool/pilot_company_invoice_settings_test.dart`, `tool/pilot_customer_migration_test.dart`, `tool/pilot_local_launch_test.dart`, `tool/pilot_onboarding_test.dart` |
| `lib/sales_chart.dart` | 506 | `design.dart`, `erp_models.dart`, `ui/workspace_ui.dart`, `ui/workspace_art.dart`, `widgets.dart` | `test/overview_chart_test.dart` |

### catalog

| Source | Lines | Local dependencies | Direct test/tool consumers |
| --- | ---: | --- | --- |
| `lib/master_import_screen.dart` | 375 | `erp_api.dart`, `document_dialogs.dart`, `file_actions.dart`, `ui/access_gate.dart` | `test/master_import_test.dart` |
| `lib/native_catalog.dart` | 1161 | `retained_load.dart`, `ui/workspace_ui.dart`, `ui/record_icon.dart`, `ui/access_gate.dart`, `design.dart`, `document_editor.dart`, `erp_api.dart`, `native_models.dart`, `report_screen.dart`, `native_tree.dart`, `task_planner.dart`, `master_import_screen.dart`, `document_fields.dart`, `widgets.dart` | `test/industry_home_test.dart`, `test/native_catalog_test.dart`, `test/native_tree_test.dart`, `test/sdk_migration_test.dart`, `tool/pilot_master_import_test.dart` |
| `lib/native_tree.dart` | 317 | `ui/record_icon.dart`, `ui/access_gate.dart`, `design.dart`, `document_editor.dart`, `erp_api.dart`, `native_models.dart`, `widgets.dart` |  |

### documents

| Source | Lines | Local dependencies | Direct test/tool consumers |
| --- | ---: | --- | --- |
| `lib/document_activity.dart` | 494 | `ui/workspace_art.dart`, `ui/access_gate.dart`, `erp_api.dart`, `file_actions.dart`, `invoice_preview.dart`, `native_models.dart`, `native_reports.dart`, `widgets.dart` | `test/document_activity_test.dart` |
| `lib/document_editor.dart` | 1298 | `ui/record_icon.dart`, `ui/workspace_ui.dart`, `design.dart`, `document_activity.dart`, `invoice_preview.dart`, `document_fields.dart`, `document_review.dart`, `document_dialogs.dart`, `document_recovery.dart`, `specialized_fields.dart`, `file_actions.dart`, `erp_api.dart`, `native_models.dart`, `operational_handoffs.dart`, `widgets.dart`, `ui/access_gate.dart` | `test/document_editor_test.dart`, `test/document_interaction_test.dart`, `test/document_recovery_test.dart`, `test/editor_access_test.dart`, `test/navigation_retention_test.dart`, `tool/pilot_specialized_fields_test.dart`, `tool/pilot_ux_test.dart` |
| `lib/document_fields.dart` | 1297 | `formatted_text.dart`, `document_lookup.dart`, `document_dialogs.dart`, `ui/workspace_ui.dart`, `ui/access_gate.dart`, `ui/record_icon.dart`, `ui/workspace_art.dart`, `design.dart`, `native_models.dart`, `native_barcode.dart`, `specialized_fields.dart`, `location_field.dart`, `widgets.dart` | `test/document_editor_test.dart`, `test/document_interaction_test.dart`, `test/formatted_text_test.dart`, `test/native_multiselect_test.dart`, `test/native_row_safety_test.dart`, `test/specialized_fields_test.dart`, `tool/pilot_onboarding_test.dart`, `tool/pilot_specialized_fields_test.dart`, `tool/pilot_trade_test.dart`, `tool/pilot_ux_test.dart` |
| `lib/document_lookup.dart` | 172 |  |  |
| `lib/document_recovery.dart` | 130 | `erp_api.dart`, `native_models.dart` | `test/document_recovery_test.dart` |
| `lib/document_review.dart` | 83 | `native_models.dart` |  |
| `lib/formatted_text.dart` | 313 |  |  |
| `lib/location_field.dart` | 210 |  | `test/location_field_test.dart` |
| `lib/native_barcode.dart` | 69 |  | `tool/pilot_specialized_fields_test.dart` |
| `lib/native_conditions.dart` | 182 |  | `test/native_conditions_test.dart` |
| `lib/native_models.dart` | 262 | `native_conditions.dart`, `native_barcode.dart` | `test/document_editor_test.dart`, `test/document_interaction_test.dart`, `test/document_recovery_test.dart`, `test/editor_access_test.dart`, `test/formatted_text_test.dart`, `test/industry_home_test.dart`, `test/knitting_workflow_destinations_test.dart`, `test/native_api_test.dart`, `test/native_catalog_test.dart`, `test/native_conditions_test.dart`, `test/native_models_test.dart`, `test/native_multiselect_test.dart`, `test/native_readonly_type_test.dart`, `test/native_row_safety_test.dart`, `test/native_tree_test.dart`, `test/navigation_retention_test.dart`, `test/operation_api_test.dart`, `test/sdk_migration_test.dart`, `test/specialized_fields_test.dart`, `tool/pilot_ux_test.dart` |
| `lib/operational_handoffs.dart` | 140 | `erp_api.dart`, `native_models.dart` | `test/operational_handoffs_test.dart` |
| `lib/specialized_fields.dart` | 401 | `design.dart`, `file_actions.dart`, `native_barcode.dart` |  |

### tasks

| Source | Lines | Local dependencies | Direct test/tool consumers |
| --- | ---: | --- | --- |
| `lib/task_planner.dart` | 491 | `document_editor.dart`, `erp_api.dart`, `native_models.dart`, `ui/access_gate.dart`, `widgets.dart` | `test/task_planner_test.dart` |

### reports

| Source | Lines | Local dependencies | Direct test/tool consumers |
| --- | ---: | --- | --- |
| `lib/native_reports.dart` | 172 | `native_models.dart` | `test/native_reports_test.dart`, `test/report_screen_test.dart` |
| `lib/report_chart.dart` | 218 | `design.dart`, `native_reports.dart`, `widgets.dart` |  |
| `lib/report_screen.dart` | 617 | `retained_load.dart`, `ui/record_icon.dart`, `ui/workspace_art.dart`, `ui/access_gate.dart`, `design.dart`, `document_editor.dart`, `file_actions.dart`, `document_fields.dart`, `erp_api.dart`, `native_models.dart`, `native_reports.dart`, `report_chart.dart`, `widgets.dart` | `test/report_screen_test.dart` |

### invoices

| Source | Lines | Local dependencies | Direct test/tool consumers |
| --- | ---: | --- | --- |
| `lib/invoice_api.dart` | 70 |  |  |
| `lib/invoice_art_direction.dart` | 593 |  |  |
| `lib/invoice_composer.dart` | 988 | `document_editor.dart`, `document_fields.dart`, `erp_api.dart`, `invoice_templates.dart`, `native_models.dart`, `ui/access_gate.dart`, `ui/workspace_ui.dart` | `test/invoice_composer_test.dart`, `test/invoice_ux_test.dart`, `tool/pilot_ux_test.dart` |
| `lib/invoice_gallery.dart` | 224 | `design.dart`, `invoice_templates.dart` | `test/invoice_hub_test.dart`, `test/ux_accessibility_test.dart`, `tool/pilot_invoice_gallery_test.dart` |
| `lib/invoice_hub.dart` | 872 | `retained_load.dart`, `design.dart`, `document_editor.dart`, `erp_api.dart`, `invoice_gallery.dart`, `invoice_composer.dart`, `invoice_preview.dart`, `invoice_settings.dart`, `invoice_templates.dart`, `ui/access_gate.dart`, `widgets.dart` | `test/invoice_hub_test.dart`, `test/invoice_settings_test.dart`, `test/local_workspace_test.dart`, `test/sdk_migration_test.dart`, `tool/pilot_company_invoice_settings_test.dart`, `tool/pilot_customer_migration_test.dart`, `tool/pilot_invoice_gallery_test.dart`, `tool/pilot_local_launch_test.dart` |
| `lib/invoice_pdf.dart` | 972 | `invoice_templates.dart`, `invoice_art_direction.dart` | `test/imported_invoice_preview_test.dart`, `test/invoice_pdf_test.dart`, `tool/pilot_company_invoice_settings_test.dart`, `tool/pilot_customer_migration_test.dart`, `tool/pilot_invoice_gallery_test.dart` |
| `lib/invoice_preview.dart` | 397 | `design.dart`, `erp_api.dart`, `file_actions.dart`, `invoice_gallery.dart`, `invoice_pdf.dart`, `invoice_templates.dart`, `ui/access_gate.dart` | `test/imported_invoice_preview_test.dart`, `tool/pilot_invoice_gallery_test.dart` |
| `lib/invoice_settings.dart` | 699 | `design.dart`, `erp_api.dart`, `document_dialogs.dart`, `invoice_gallery.dart`, `invoice_templates.dart`, `ui/access_gate.dart`, `widgets.dart` | `test/invoice_settings_test.dart`, `tool/pilot_company_invoice_settings_test.dart` |
| `lib/invoice_templates.dart` | 30 |  | `test/invoice_hub_test.dart`, `test/invoice_pdf_test.dart`, `test/ux_accessibility_test.dart`, `tool/pilot_company_invoice_settings_test.dart`, `tool/pilot_customer_migration_test.dart`, `tool/pilot_invoice_gallery_test.dart` |

### banking

| Source | Lines | Local dependencies | Direct test/tool consumers |
| --- | ---: | --- | --- |
| `lib/bank_statement_import.dart` | 431 | `erp_api.dart`, `document_dialogs.dart`, `ui/access_gate.dart` | `test/bank_statement_import_test.dart` |
| `lib/bank_statement_matching.dart` | 509 | `document_fields.dart`, `document_editor.dart`, `document_dialogs.dart`, `bank_statement_import.dart`, `erp_api.dart`, `native_models.dart`, `ui/access_gate.dart` | `test/bank_statement_matching_test.dart`, `test/industry_home_test.dart` |
| `lib/payment_reconciliation.dart` | 685 | `document_fields.dart`, `erp_api.dart`, `native_models.dart`, `ui/access_gate.dart` | `test/industry_home_test.dart`, `test/payment_reconciliation_test.dart` |

### point_of_sale

| Source | Lines | Local dependencies | Direct test/tool consumers |
| --- | ---: | --- | --- |
| `lib/pos_checkout.dart` | 935 | `design.dart`, `document_fields.dart`, `erp_api.dart`, `native_models.dart`, `ui/access_gate.dart`, `widgets.dart` | `test/pos_checkout_test.dart` |

### operations

| Source | Lines | Local dependencies | Direct test/tool consumers |
| --- | ---: | --- | --- |
| `lib/pending_operations.dart` | 323 | `document_editor.dart`, `erp_api.dart`, `native_models.dart`, `ui/access_gate.dart` | `test/pending_operations_test.dart`, `tool/pilot_ux_test.dart` |

### imported_history

| Source | Lines | Local dependencies | Direct test/tool consumers |
| --- | ---: | --- | --- |
| `lib/history_filters.dart` | 506 | `erp_api.dart` |  |
| `lib/imported_history.dart` | 1004 | `design.dart`, `erp_api.dart`, `history_filters.dart`, `original_production_report.dart`, `invoice_preview.dart`, `imported_record_preview.dart`, `document_editor.dart`, `ui/access_gate.dart` | `test/imported_history_test.dart`, `test/imported_record_preview_test.dart`, `test/original_production_report_test.dart`, `tool/pilot_customer_migration_test.dart` |
| `lib/imported_history_api.dart` | 94 |  |  |
| `lib/imported_record_pdf.dart` | 202 |  | `test/imported_record_pdf_test.dart` |
| `lib/imported_record_preview.dart` | 242 | `erp_api.dart`, `imported_record_pdf.dart`, `ui/access_gate.dart` | `test/imported_record_preview_test.dart` |
| `lib/original_production_report.dart` | 461 | `design.dart`, `erp_api.dart`, `history_filters.dart`, `imported_history.dart`, `ui/access_gate.dart` | `test/original_production_job_filter_test.dart`, `test/original_production_report_test.dart` |

### knitting

| Source | Lines | Local dependencies | Direct test/tool consumers |
| --- | ---: | --- | --- |
| `lib/knitting_batch_rows.dart` | 332 |  |  |
| `lib/knitting_entry_layout.dart` | 676 |  |  |
| `lib/knitting_forms.dart` | 3308 | `ui/workspace_art.dart`, `design.dart`, `erp_api.dart`, `knitting_models.dart`, `native_models.dart`, `workspace_context.dart`, `widgets.dart`, `ui/workspace_ui.dart`, `ui/access_gate.dart`, `ui/date_entry.dart`, `document_editor.dart`, `knitting_entry_layout.dart`, `knitting_batch_rows.dart` | `test/knitting_batch_production_test.dart`, `test/knitting_batches_test.dart`, `test/knitting_commercial_revision_test.dart`, `test/knitting_confirmation_test.dart`, `test/knitting_customer_labels_test.dart`, `test/knitting_diameter_display_test.dart`, `test/knitting_factory_masters_test.dart`, `test/knitting_form_entry_test.dart`, `test/knitting_imported_programme_guard_test.dart`, `test/knitting_pagination_test.dart`, `test/knitting_production_machine_test.dart`, `test/knitting_production_rows_test.dart`, `test/knitting_recovery_test.dart`, `test/knitting_roll_operator_test.dart`, `test/knitting_screen_test.dart`, `test/knitting_workflow_destinations_test.dart`, `test/mill_navigation_pilot_test.dart`, `tool/pilot_onboarding_test.dart`, `tool/pilot_ux_test.dart` |
| `lib/knitting_job_workflow.dart` | 471 |  |  |
| `lib/knitting_models.dart` | 141 | `erp_api.dart` | `test/industry_home_test.dart`, `test/knitting_commercial_revision_test.dart`, `test/knitting_diameter_display_test.dart`, `test/knitting_factory_masters_test.dart`, `test/knitting_form_entry_test.dart`, `test/knitting_job_filters_test.dart`, `test/knitting_models_test.dart`, `test/knitting_pagination_test.dart`, `test/knitting_presentation_test.dart`, `test/knitting_production_machine_test.dart`, `test/knitting_production_rows_test.dart`, `test/knitting_running_yarn_overview_test.dart`, `test/knitting_screen_test.dart`, `test/knitting_workflow_destinations_test.dart`, `test/local_workspace_test.dart`, `test/mill_batch_sources_test.dart`, `test/mill_navigation_pilot_test.dart`, `test/mill_register_scroll_test.dart`, `tool/profile_workspace.dart` |
| `lib/knitting_register.dart` | 326 | `erp_api.dart`, `knitting_models.dart` | `test/knitting_job_filters_test.dart`, `test/knitting_pagination_test.dart` |
| `lib/knitting_reports.dart` | 897 | `ui/workspace_art.dart`, `design.dart`, `document_editor.dart`, `erp_api.dart`, `file_actions.dart`, `knitting_forms.dart`, `original_production_report.dart`, `widgets.dart`, `ui/access_gate.dart` | `test/knitting_production_machine_test.dart`, `test/knitting_production_operator_report_test.dart`, `test/knitting_reports_test.dart`, `test/original_production_report_test.dart` |
| `lib/knitting_screen.dart` | 2026 | `ui/access_gate.dart`, `knitting_workspace_layout.dart`, `mill_overview.dart`, `file_actions.dart`, `design.dart`, `document_editor.dart`, `erp_api.dart`, `erp_models.dart`, `knitting_forms.dart`, `knitting_models.dart`, `knitting_register.dart`, `native_models.dart`, `knitting_reports.dart`, `workspace_context.dart`, `widgets.dart`, `ui/workspace_ui.dart`, `ui/workspace_art.dart`, `knitting_job_workflow.dart`, `knitting_workflow_views.dart` | `test/industry_home_test.dart`, `test/knitting_diameter_display_test.dart`, `test/knitting_factory_masters_test.dart`, `test/knitting_job_filters_test.dart`, `test/knitting_pagination_test.dart`, `test/knitting_presentation_test.dart`, `test/knitting_screen_test.dart`, `test/knitting_workflow_destinations_test.dart`, `test/local_workspace_test.dart`, `test/mill_navigation_pilot_test.dart`, `test/mill_register_scroll_test.dart`, `tool/pilot_company_invoice_settings_test.dart`, `tool/pilot_customer_migration_test.dart`, `tool/pilot_local_launch_test.dart`, `tool/pilot_onboarding_test.dart`, `tool/profile_workspace.dart` |
| `lib/knitting_workflow_views.dart` | 988 |  |  |
| `lib/knitting_workspace_layout.dart` | 426 | `design.dart`, `erp_models.dart`, `ui/workspace_ui.dart`, `widgets.dart`, `workspace_context.dart` | `test/mill_navigation_pilot_test.dart`, `test/sdk_migration_test.dart` |
| `lib/mill_overview.dart` | 1021 | `design.dart`, `knitting_models.dart`, `knitting_register.dart`, `erp_api.dart`, `ui/workspace_ui.dart`, `ui/workspace_art.dart`, `widgets.dart`, `workspace_context.dart`, `mill_production.dart` | `test/knitting_customer_labels_test.dart`, `test/knitting_pagination_test.dart`, `test/knitting_running_yarn_overview_test.dart`, `test/mill_batch_sources_test.dart`, `tool/profile_startup.dart` |
| `lib/mill_production.dart` | 462 |  |  |

### core

| Source | Lines | Local dependencies | Direct test/tool consumers |
| --- | ---: | --- | --- |
| `lib/design.dart` | 210 | `erp_models.dart` | `test/erp_models_test.dart`, `test/imported_history_test.dart`, `test/imported_invoice_preview_test.dart`, `test/industry_home_test.dart`, `test/knitting_diameter_display_test.dart`, `test/knitting_factory_masters_test.dart`, `test/knitting_form_entry_test.dart`, `test/knitting_job_filters_test.dart`, `test/knitting_pagination_test.dart`, `test/knitting_presentation_test.dart`, `test/knitting_reports_test.dart`, `test/knitting_running_yarn_overview_test.dart`, `test/knitting_screen_test.dart`, `test/layout_test.dart`, `test/local_workspace_test.dart`, `test/mill_navigation_pilot_test.dart`, `test/onboarding_test.dart`, `test/original_production_job_filter_test.dart`, `test/original_production_report_test.dart`, `test/overview_chart_test.dart`, `test/pos_checkout_test.dart`, `test/ux_accessibility_test.dart`, `test/workspace_ui_test.dart`, `tool/pilot_master_import_test.dart`, `tool/pilot_mill_test.dart`, `tool/pilot_onboarding_test.dart`, `tool/pilot_specialized_fields_test.dart`, `tool/pilot_trade_test.dart`, `tool/pilot_ux_test.dart`, `tool/profile_startup.dart`, `tool/profile_workspace.dart` |
| `lib/document_dialogs.dart` | 9 |  |  |
| `lib/erp_api.dart` | 1601 | `erp_models.dart`, `native_models.dart`, `native_reports.dart`, `workspace_context.dart`, `knitting_models.dart`, `invoice_api.dart`, `imported_history_api.dart` | `test/access_refresh_test.dart`, `test/bank_statement_import_test.dart`, `test/bank_statement_matching_test.dart`, `test/document_activity_test.dart`, `test/document_editor_test.dart`, `test/document_interaction_test.dart`, `test/document_recovery_test.dart`, `test/editor_access_test.dart`, `test/erp_api_test.dart`, `test/imported_history_test.dart`, `test/imported_invoice_preview_test.dart`, `test/imported_record_api_test.dart`, `test/imported_record_preview_test.dart`, `test/industry_home_test.dart`, `test/invoice_composer_test.dart`, `test/invoice_hub_test.dart`, `test/invoice_settings_test.dart`, `test/invoice_ux_test.dart`, `test/knitting_batch_production_test.dart`, `test/knitting_batches_test.dart`, `test/knitting_commercial_revision_test.dart`, `test/knitting_confirmation_test.dart`, `test/knitting_customer_labels_test.dart`, `test/knitting_diameter_display_test.dart`, `test/knitting_factory_masters_api_test.dart`, `test/knitting_factory_masters_test.dart`, `test/knitting_form_entry_test.dart`, `test/knitting_imported_programme_guard_test.dart`, `test/knitting_job_filters_api_test.dart`, `test/knitting_job_filters_test.dart`, `test/knitting_pagination_test.dart`, `test/knitting_presentation_test.dart`, `test/knitting_production_machine_test.dart`, `test/knitting_production_operator_report_test.dart`, `test/knitting_production_rows_test.dart`, `test/knitting_recovery_test.dart`, `test/knitting_reports_test.dart`, `test/knitting_roll_operator_test.dart`, `test/knitting_running_yarn_overview_test.dart`, `test/knitting_screen_test.dart`, `test/knitting_workflow_destinations_test.dart`, `test/local_workspace_test.dart`, `test/master_import_test.dart`, `test/mill_batch_sources_test.dart`, `test/mill_navigation_pilot_test.dart`, `test/native_api_test.dart`, `test/native_catalog_test.dart`, `test/native_session_test.dart`, `test/native_tree_test.dart`, `test/navigation_retention_test.dart`, `test/onboarding_test.dart`, `test/operation_api_test.dart`, `test/operational_handoffs_test.dart`, `test/original_production_report_api_test.dart`, `test/original_production_report_test.dart`, `test/payment_reconciliation_test.dart`, `test/pending_operations_test.dart`, `test/pos_checkout_test.dart`, `test/report_screen_test.dart`, `test/sdk_migration_test.dart`, `test/session_recovery_test.dart`, `test/task_planner_test.dart`, `test/ux_accessibility_test.dart`, `test/workspace_context_test.dart`, `tool/pilot_master_import_test.dart`, `tool/pilot_mill_test.dart`, `tool/pilot_onboarding_test.dart`, `tool/pilot_specialized_fields_test.dart`, `tool/pilot_trade_test.dart`, `tool/pilot_ux_test.dart`, `tool/profile_startup.dart`, `tool/profile_workspace.dart`, `tool/verify_connection.dart`, `tool/verify_knitting.dart`, `tool/verify_native.dart`, `tool/verify_pos.dart` |
| `lib/file_actions.dart` | 111 | `erp_api.dart`, `ui/access_gate.dart` |  |
| `lib/retained_load.dart` | 123 | `erp_api.dart` |  |
| `lib/ui/access_gate.dart` | 185 | `erp_api.dart` | `test/document_interaction_test.dart`, `test/ux_accessibility_test.dart` |
| `lib/ui/date_entry.dart` | 111 |  | `test/ux_accessibility_test.dart` |
| `lib/ui/record_icon.dart` | 287 | `erp_models.dart`, `design.dart`, `ui/workspace_art.dart` |  |
| `lib/ui/workspace_art.dart` | 177 |  | `test/document_editor_test.dart`, `test/module_browser_test.dart`, `test/onboarding_test.dart`, `test/overview_chart_test.dart`, `tool/pilot_onboarding_test.dart` |
| `lib/ui/workspace_ui.dart` | 158 | `design.dart`, `widgets.dart` | `test/workspace_ui_test.dart` |
| `lib/widgets.dart` | 389 | `design.dart` | `test/knitting_pagination_test.dart`, `test/ux_accessibility_test.dart`, `tool/pilot_trade_test.dart` |

## Import cycles

Cycles exclude `part of` ownership links.

- `lib/knitting_models.dart` ↔ `lib/erp_api.dart`
- `lib/imported_history.dart` ↔ `lib/original_production_report.dart`

## Dependencies

All resolved packages are mapped, including transitive platform implementations. No provider, Riverpod, Bloc, GetX or other state-management package is present.

| Package | Version | Relationship | Source |
| --- | --- | --- | --- |
| `archive` | 4.0.9 | transitive | hosted |
| `args` | 2.7.0 | transitive | hosted |
| `async` | 2.13.1 | transitive | hosted |
| `barcode` | 2.2.9 | direct main | hosted |
| `bidi` | 2.0.13 | transitive | hosted |
| `boolean_selector` | 2.1.2 | transitive | hosted |
| `characters` | 1.4.1 | transitive | hosted |
| `clock` | 1.1.2 | transitive | hosted |
| `code_assets` | 1.2.1 | transitive | hosted |
| `collection` | 1.19.1 | transitive | hosted |
| `cross_file` | 0.3.5+5 | transitive | hosted |
| `crypto` | 3.0.8 | transitive | hosted |
| `csslib` | 1.0.2 | transitive | hosted |
| `fake_async` | 1.3.3 | transitive | hosted |
| `ffi` | 2.2.0 | transitive | hosted |
| `file` | 7.0.1 | transitive | hosted |
| `file_selector` | 1.1.0 | direct main | hosted |
| `file_selector_android` | 0.5.2+6 | transitive | hosted |
| `file_selector_ios` | 0.5.3+6 | transitive | hosted |
| `file_selector_linux` | 0.9.4+1 | transitive | hosted |
| `file_selector_macos` | 0.9.5+1 | transitive | hosted |
| `file_selector_platform_interface` | 2.7.0 | transitive | hosted |
| `file_selector_web` | 0.9.5 | transitive | hosted |
| `file_selector_windows` | 0.9.3+6 | transitive | hosted |
| `fixnum` | 1.1.1 | transitive | hosted |
| `flutter` | 0.0.0 | direct main | sdk |
| `flutter_lints` | 6.0.0 | direct dev | hosted |
| `flutter_test` | 0.0.0 | direct dev | sdk |
| `flutter_web_plugins` | 0.0.0 | transitive | sdk |
| `hooks` | 2.0.2 | transitive | hosted |
| `html` | 0.15.6 | direct main | hosted |
| `http` | 1.6.0 | transitive | hosted |
| `http_parser` | 4.1.2 | transitive | hosted |
| `image` | 4.5.4 | transitive | hosted |
| `intl` | 0.20.2 | direct main | hosted |
| `jni` | 1.1.2 | transitive | hosted |
| `jni_flutter` | 1.0.4+1 | transitive | hosted |
| `jni_util` | 1.0.0 | transitive | hosted |
| `leak_tracker` | 11.0.2 | transitive | hosted |
| `leak_tracker_flutter_testing` | 3.0.10 | transitive | hosted |
| `leak_tracker_testing` | 3.0.2 | transitive | hosted |
| `lints` | 6.1.0 | transitive | hosted |
| `logging` | 1.3.0 | transitive | hosted |
| `matcher` | 0.12.20 | transitive | hosted |
| `material_color_utilities` | 0.13.0 | transitive | hosted |
| `meta` | 1.19.0 | transitive | hosted |
| `mime` | 2.1.0 | transitive | hosted |
| `objective_c` | 9.5.0 | transitive | hosted |
| `package_config` | 2.2.0 | transitive | hosted |
| `path` | 1.9.1 | transitive | hosted |
| `path_parsing` | 1.1.0 | transitive | hosted |
| `path_provider` | 2.1.6 | transitive | hosted |
| `path_provider_android` | 2.3.1 | transitive | hosted |
| `path_provider_foundation` | 2.6.0 | transitive | hosted |
| `path_provider_linux` | 2.2.2 | transitive | hosted |
| `path_provider_platform_interface` | 2.1.3 | transitive | hosted |
| `path_provider_windows` | 2.3.0 | transitive | hosted |
| `pdf` | 3.12.0 | direct main | hosted |
| `pdf_widget_wrapper` | 1.0.4 | transitive | hosted |
| `petitparser` | 7.0.2 | transitive | hosted |
| `platform` | 3.1.6 | transitive | hosted |
| `plugin_platform_interface` | 2.1.8 | transitive | hosted |
| `posix` | 6.5.4 | transitive | hosted |
| `printing` | 5.14.2 | direct main | hosted |
| `pub_semver` | 2.2.1 | transitive | hosted |
| `qr` | 3.0.3 | transitive | hosted |
| `record_use` | 0.6.0 | transitive | hosted |
| `share_plus` | 12.0.1 | direct main | hosted |
| `share_plus_platform_interface` | 6.1.0 | transitive | hosted |
| `sky_engine` | 0.0.0 | transitive | sdk |
| `source_span` | 1.10.2 | transitive | hosted |
| `stack_trace` | 1.12.1 | transitive | hosted |
| `stream_channel` | 2.1.4 | transitive | hosted |
| `string_scanner` | 1.4.1 | transitive | hosted |
| `term_glyph` | 1.2.2 | transitive | hosted |
| `test_api` | 0.7.12 | transitive | hosted |
| `typed_data` | 1.4.0 | transitive | hosted |
| `url_launcher` | 6.3.2 | direct main | hosted |
| `url_launcher_android` | 6.3.30 | transitive | hosted |
| `url_launcher_ios` | 6.4.2 | transitive | hosted |
| `url_launcher_linux` | 3.2.3 | transitive | hosted |
| `url_launcher_macos` | 3.2.6 | transitive | hosted |
| `url_launcher_platform_interface` | 2.3.2 | transitive | hosted |
| `url_launcher_web` | 2.4.3 | transitive | hosted |
| `url_launcher_windows` | 3.1.6 | transitive | hosted |
| `uuid` | 4.6.0 | transitive | hosted |
| `vector_math` | 2.4.4 | transitive | hosted |
| `vm_service` | 15.4.0 | transitive | hosted |
| `web` | 1.1.1 | transitive | hosted |
| `win32` | 5.15.0 | transitive | hosted |
| `xdg_directories` | 1.1.0 | transitive | hosted |
| `xml` | 6.6.1 | direct main | hosted |
| `yaml` | 3.1.4 | transitive | hosted |

## Existing tests

Each test file below lists its statically declared test names; see JSON for locations, imports and nested groups. Files without test declarations are fixtures or executable verification tools.

### `test/access_refresh_test.dart`

- L8 test: 'explicit selected company is queried directly and never falls back'
- L52 test: 'session recovery quarantines cached access and publishes fresh permissions'

### `test/bank_statement_import_test.dart`

- L103 testWidgets: 'bank import cannot be abandoned while the write is pending'
- L123 testWidgets: 'lost bank import response checks existing lines without importing again'
- L143 testWidgets: 'bank CSV is mapped and previewed before explicit import'

### `test/bank_statement_matching_test.dart`

- L128 testWidgets: 'bank match prevents leaving during a pending write'
- L140 testWidgets: 'an uncertain bank match retains source identifiers for inspection'
- L153 testWidgets: 'changed bank access removes an open financial review'

### `test/document_activity_test.dart`

- L32 testWidgets: 'posting a comment refreshes activity without a framework error'

### `test/document_editor_test.dart`

- L28 testWidgets: 'a new prompt-named document requests and saves its name once'
- L76 testWidgets: 'saving identifies the child row that needs correction'
- L142 testWidgets: 'back immediately after typing protects the draft before the next frame'
- L179 testWidgets: 'item defaults populate a row and are kept only after Done'
- L246 testWidgets: 'read only child rows open for viewing without changing data'
- L298 testWidgets: 'workflow actions require saving dirty changes first'
- L332 testWidgets: 'cancelled records cannot be edited or saved'
- L367 testWidgets: 'back navigation keeps a dirty draft until discard is chosen'
- L412 testWidgets: 'create stays native and replaces draft with persisted name after save'
- L443 testWidgets: 'server rejection preserves entered values'
- L465 testWidgets: 'pending save disables duplicate writes'

### `test/document_interaction_test.dart`

- L54 testWidgets: 'access revocation before the $type picker builds closes it'
- L102 testWidgets: 'access revocation closes a generic lookup without an explicit scope key'
- L156 testWidgets: 'optional sections disclose retained values without exposing hidden fields'
- L179 testWidgets: 'explicit save reveals and focuses an invalid optional section'
- L221 testWidgets: 'removing a row can restore the same identity and order'
- L266 testWidgets: 'lookup debounces, disables previous matches, ignores old responses and retries the query'
- L341 testWidgets: 'a changed linked-record type closes its stale chooser'
- L381 testWidgets: 'posting review uses only permitted server fields and invalidates changed revisions'

### `test/document_recovery_test.dart`

- L131 test: 'a response arriving after changed access keeps its unresolved reference'
- L158 testWidgets: 'company round trip during preparation prevents the old write'
- L195 testWidgets: 'explicit non-atomic documents use legacy save and inspect unknown outcomes before editing'
- L217 testWidgets: 'lost save response reconciles original request without duplicate write'
- L233 testWidgets: 'prepared uncertainty stays locked until explicit close seals it'
- L252 testWidgets: 'confirmed rejection retains editable input and never reports success'
- L267 testWidgets: 'failed preparation never sends the write'

### `test/editor_access_test.dart`

- L103 testWidgets: 'stale save can recover in place and only discards edits after the fresh version loads'
- L143 testWidgets: 'core editor refreshes permissions and keeps only allowed draft input'
- L198 testWidgets: 'access refresh regenerates linked drafts from their original source'

### `test/erp_api_test.dart`

- L19 test: 'service origin uses the build setting or local development default'
- L44 test: 'service origin policy for Android=$android in $mode'
- L85 test: 'unpaid invoice drilldown applies the posted balance and company filters on every page'
- L112 test: 'rejected credentials tell a signed-out user how to retry'
- L137 test: 'sign-in gives the ERPNext next step for ${entry.key}'
- L156 test: 'verification uses the same temporary ID, preserves a leading zero, and only accepts a real session'
- L213 test: 'an authenticated portal user can redeem an invitation before a fresh system login'
- L254 test: 'authenticated reads send the login session and scoped query'
- L299 test: 'expired sessions produce authentication errors instead of empty data'
- L317 test: 'malformed record responses are errors rather than invented zero rows'
- L331 test: 'dashboard totals use company currency rather than mixing invoice currencies'
- L378 test: 'sign-out revokes the server session with POST and drops its cookie'
- L407 test: 'denied $deniedType does not block authorized modules'
- L446 test: 'invalid amounts fail at the API boundary before rendering'

### `test/erp_models_test.dart`

- L6 test: 'record amounts retain currency precision, including credits'
- L12 test: 'sales scale keeps returns and positive totals inside the chart'
- L20 test: 'calendar boundaries survive daylight-saving changes'
- L26 test: 'reporting periods include timestamped records on the final day'
- L39 test: 'original document links safely encode record names and retain origin'
- L52 test: 'records keep real labels and search without hiding original names'

### `test/formatted_text_test.dart`

- L7 testWidgets: 'new heading is escaped, cancellation preserves the draft, and read-only notes have no edit action'
- L66 testWidgets: 'a text editor previews formatting locally and preserves unsupported markup while editing a text run'

### `test/imported_history_test.dart`

- L190 testWidgets: 'original production exposes saved columns and opens its record'
- L238 testWidgets: 'production shift filter submits the exact saved shift'
- L268 testWidgets: 'production dimensions expose exact saved employee filters'
- L294 testWidgets: 'history choice search rejects stale results and access revocation clears choices'
- L351 testWidgets: 'history company and family changes clear applied filters and absent fields stay hidden'
- L392 testWidgets: 'history filters apply exact original values and keep paging scoped'
- L436 testWidgets: 'history filters fit a short phone and no-original date clears ranges'
- L479 testWidgets: 'shared source controls show exact signed totals once with their review status'
- L504 testWidgets: 'missing shared cash controls stay unavailable instead of becoming zero'
- L517 testWidgets: 'an older search response cannot restore stale original records'
- L544 testWidgets: 'a preserved empty source table does not hide its header'
- L556 testWidgets: 'original detail preserves unknown dates and returns to searched register'
- L586 testWidgets: 'pagination is bounded and shared cash is one workspace destination'
- L605 testWidgets: 'mismatched company page is rejected without showing its records'
- L614 testWidgets: 'financial family omitted by server is never requested'
- L627 testWidgets: 'narrow history detail keeps quantities and back navigation reachable'

### `test/imported_invoice_preview_test.dart`

- L46 testWidgets: 'original invoice opens from its immutable identity without a display-name argument'
- L67 testWidgets: 'original PDF has no save action and rechecks permission before export'
- L100 testWidgets: 'wrong original invoice scope never exposes PDF export'

### `test/imported_record_api_test.dart`

- L8 test: 'operational print API uses exact reviewed route and company/name'

### `test/imported_record_pdf_test.dart`

- L53 test: 'source copy preserves dates, zero, null, blank and exact decimals'
- L75 test: 'long wide source tables keep every cell and repeat page identification'
- L91 test: 'long notes and cell content paginate without cutting the final words'
- L117 test: 'matching effective date is not repeated and long headers fit'
- L132 test: 'short multiline source cells span pages and retain following rows'
- L158 test: 'fully masked rows remain printable without revealing values'
- L173 test: 'renderer refuses an unmarked or malformed source copy'

### `test/imported_record_preview_test.dart`

- L67 testWidgets: 'source preview fetches its immutable identity and revocation blocks export'
- L84 testWidgets: 'scope mismatch $companyMismatch exposes no export'
- L98 testWidgets: 'access change during pending export blocks stale side effects'
- L116 testWidgets: 'original detail print visibility follows server permission $allowed'
- L137 testWidgets: 'revoked permission while save dialog is pending writes no file'
- L180 testWidgets: 'company and record changes discard the old pending preview'
- L211 testWidgets: 'fully masked tables keep original detail and print action reachable'
- L241 testWidgets: 'unreviewed nonempty rows without columns remain rejected'

### `test/industry_home_test.dart`

- L182 testWidgets: 'first sign-in opens the workspace only after code verification'
- L227 testWidgets: 'customer mill keeps masters and accounts without general navigation'
- L250 testWidgets: 'customer accounting tools remain reachable from mill records'
- L273 testWidgets: 'customer selection returns a general session to the mill'
- L287 testWidgets: 'missing knitting capabilities never open a customer general home'
- L299 testWidgets: 'old general navigation cannot leave a customer mill'
- L318 testWidgets: 'mill accounting clerk can open permitted business records from the same navigation'
- L349 testWidgets: 'configured mill opens directly into knitting and switches to general by company'
- L382 testWidgets: 'company switching recovers when the current company is revoked'
- L400 testWidgets: 'workspace picker offers readable modules even with zero records'
- L411 testWidgets: 'renewal stays recoverable when the first access check is offline'
- L443 testWidgets: 'a new account with no assigned company can recover without signing out'
- L459 testWidgets: 'a general module goes back to ERP overview and keeps its workspace on company selection'
- L491 testWidgets: 'switching companies in General ERP stays in General ERP'
- L504 testWidgets: 'general shell exposes its module browser at compact widths'
- L518 testWidgets: 'choosing Knitting opens the mill without loading the general dashboard'
- L542 testWidgets: 'new company manager chooses the home during setup'

### `test/invoice_composer_test.dart`

- L50 testWidgets: 'review edits, retain the selected style, retry the exact save and return the created invoice'
- L122 testWidgets: 'ordinary drafts follow the company default and can explicitly choose Trade Ledger'

### `test/invoice_hub_test.dart`

- L78 testWidgets: 'invoice refresh retains rows and labels a failed refresh'
- L95 testWidgets: 'invoice register searches, filters, pages and formats posted amounts'
- L121 testWidgets: 'all 15 stationery previews are reachable on a phone and posting permissions are respected'
- L151 testWidgets: 'a short phone can still reach the templates and search without overflow'

### `test/invoice_pdf_test.dart`

- L27 test: 'each style embeds the logo and the exact payable invoice link'
- L45 test: 'only eligible payable INR invoices include a UPI request'
- L66 test: 'source invoice copies never create a payment request'
- L74 test: 'source invoice printing refuses an unknown unit rate'
- L88 test: 'an explicitly blank original zero line stays printable without invented description'
- L125 test: 'all invoice designs render actual A4 documents from the same safe sample'
- L142 test: 'tax, addresses, purchase references and verified server e-invoice payload fit the named layouts'
- L182 test: 'long return carries all named rows and long terms to following pages'

### `test/invoice_settings_test.dart`

- L107 testWidgets: 'lost settings save response verifies saved values before reporting success'
- L122 testWidgets: 'company default and payment details save together; bank information can be cleared'
- L147 testWidgets: 'owner can remove the stored logo on a phone and stale writes offer reload'
- L171 testWidgets: 'staff receive no settings editor button'
- L177 testWidgets: 'logo picker rejects an unreadable file and saves the selected PNG'

### `test/invoice_ux_test.dart`

- L119 testWidgets: 'review waits for an invoice date while defaults are delayed'
- L137 testWidgets: 'late preparation cannot post a replacement draft after a company round trip'
- L174 testWidgets: 'a lost invoice response is checked without a second save'
- L194 testWidgets: 'prepared invoice cannot be edited until closure is confirmed'
- L223 testWidgets: 'failed invoice preparation never sends a business write'
- L241 testWidgets: 'invoice Back preserves changes until explicit discard'
- L260 testWidgets: 'a print-template-only edit is protected on Back'
- L271 testWidgets: 'invoice in-flight save cannot be abandoned by Back'
- L288 testWidgets: 'removing and undoing an invoice line restores exact values'
- L307 testWidgets: 'invoice validation identifies the actual invalid fields'

### `test/knitting_batch_production_test.dart`

- L34 test: 'batch entry captures measured totals without individual weights'
- L43 testWidgets: mismatch ? 'batch conservation rejects a 0.001 kg mismatch' : 'zero-count measured batch posts exact reviewed input and job version'

### `test/knitting_batches_test.dart`

- L157 testWidgets: 'batch selector preserves negative source counts and bounded paging'
- L172 testWidgets: 'batch return choices retain exact uncancelled event identity'
- L183 testWidgets: 'batch selector rejects a response from another company'
- L192 testWidgets: 'batch inspection requires an explicit decision'
- L204 testWidgets: 'negative source batch cannot be released from the form'
- L233 testWidgets: '$action retains independent weight, count and current job version'

### `test/knitting_commercial_revision_test.dart`

- L41 test: 'commercial revision has a distinct action identity and permission gates'
- L81 testWidgets: 'rate-only review preserves imported programme; stale=$stale'

### `test/knitting_confirmation_test.dart`

- L47 testWidgets: 'inspection requires the checker to choose a quality decision'
- L72 testWidgets: 'rejected posting returns to editable fields and keeps entered values'
- L107 test: 'both general and job material forms capture physical counts'
- L126 testWidgets: 'confirmed entry shows the outcome without internal allocation data'

### `test/knitting_customer_labels_test.dart`

- L51 testWidgets: 'job register shows verified full reference and retains raw identity'
- L80 testWidgets: 'job register shows party names and retains source identity at $width'
- L124 testWidgets: 'job picker uses readable customer without replacing record ID'
- L154 testWidgets: 'entry heading shows party name and submits the original job'

### `test/knitting_diameter_display_test.dart`

- L72 testWidgets: '$name programme shows its measured diameter without converting source IDs'
- L110 testWidgets: 'imported revision protects source dimensions before any submission'
- L161 testWidgets: 'native revision edits the physical diameter without stale projection fields'
- L198 testWidgets: 'programme selectors use the displayed diameter and retain line identity'

### `test/knitting_factory_masters_api_test.dart`

- L8 test: 'master register transmits its exact category with an independent page'

### `test/knitting_factory_masters_test.dart`

- L249 testWidgets: 'Factory category pages only masters and retains machine register state'
- L294 testWidgets: 'direct master editing rereads its version and preserves complete settings'
- L326 testWidgets: 'name-only master edit retains unshown keys and zero or false types'
- L343 testWidgets: 'master description edit applies without replacing hidden settings: $description'
- L368 testWidgets: 'changing from a master with hidden settings to an empty master cannot copy those settings'
- L408 testWidgets: 'cleared master settings stay cleared after editing and reviewing again'
- L434 testWidgets: 'a master with no saved settings still opens for a name-only edit'
- L454 testWidgets: 'read-only Factory users see master detail without edit'
- L468 testWidgets: 'master detail never edits a different lookup result'
- L479 testWidgets: 'old category responses and mismatched category echoes stay hidden'
- L507 testWidgets: 'access change hides cached master detail and requires a fresh form source'
- L527 testWidgets: 'master review requires a fresh definition after access refresh'
- L551 testWidgets: 'company change resets the Factory category before loading masters'
- L570 testWidgets: 'Factory categories and saved settings fit a short phone with larger text'
- L625 testWidgets: 'stale master reload cannot turn an update into new-master creation'

### `test/knitting_form_entry_test.dart`

- L12 testWidgets: 'empty customer picker respects create permission $permitted'
- L38 testWidgets: 'stale invoice preview offers source reload before any write'
- L70 testWidgets: 'typing a roll code hides old choices until its search resolves'
- L100 testWidgets: 'stale revision reloads the current programme and retains the reason before review'
- L188 testWidgets: 'new job posts the chosen order date and separate bill-to party'
- L245 testWidgets: 'programme revision loads the selected job and preserves its agreed rates'
- L268 testWidgets: 'changing dispatch job removes rolls selected on the previous job'
- L290 testWidgets: 'production review reconciles measured roll kg against actual yarn and loss'
- L335 testWidgets: 'fabric specifications are readable in entry and review at $width'
- L395 testWidgets: 'back immediately after typing protects the knitting draft'
- L448 testWidgets: '$id reviews the source job and posts its selected version'
- L494 testWidgets: 'bulk production cannot be reviewed without line-specific consumption'

### `test/knitting_imported_programme_guard_test.dart`

- L20 testWidgets: 'generic programme form guards selected $kind job'

### `test/knitting_job_filters_api_test.dart`

- L8 test: 'Jobs register transmits exact customer identity and applied job-date bounds'

### `test/knitting_job_filters_test.dart`

- L191 testWidgets: 'job customer and date drafts apply together and clear the paged view'
- L240 testWidgets: 'applied job filters and page survive detail Back and action refresh'
- L279 testWidgets: 'date-only drafts can be cleared before applying filters'
- L304 testWidgets: 'invalid or reversed job dates leave applied criteria unchanged'
- L338 testWidgets: 'old filtered page cannot replace a cleared job view'
- L358 testWidgets: 'mismatched applied job filter echo fails closed'
- L371 testWidgets: 'company and access changes clear applied job criteria'
- L397 testWidgets: 'a filtered Jobs request never reuses the unfiltered snapshot page'
- L439 testWidgets: 'an older company filtered request cannot restore its customer or rows'
- L462 testWidgets: 'a customer chosen after access changes cannot apply the old picker result'
- L492 testWidgets: 'job filters fit short phone large text and preserve search/status criteria'

### `test/knitting_models_test.dart`

- L5 test: 'unconfirmed and malformed status cannot become a confirmed save'
- L23 test: 'kg remain exact and reject rounding, exponent and nonfinite input'
- L32 test: 'uncertain commands retain identity and cannot post twice automatically'

### `test/knitting_pagination_test.dart`

- L184 testWidgets: 'restricted reconciliation suppresses suggestions but keeps permitted QC entry available'
- L232 testWidgets: 'unavailable company production never falls back to a partial page'
- L285 testWidgets: 'all 501 records are reachable with bounded independent pages'
- L340 testWidgets: 'advancing one register preserves the sibling register page'
- L394 testWidgets: 'search and queue state find an older match before pagination'
- L423 testWidgets: 'Back restores the job register page and status search resets it'
- L468 testWidgets: 'a previous company page cannot replace the new company'
- L513 testWidgets: 'an older roll opens from its exact source even outside the job first page'
- L549 testWidgets: 'overview totals and production sources include records beyond the first page'

### `test/knitting_presentation_test.dart`

- L53 testWidgets: 'company is visible and switchable above content at $width'
- L84 testWidgets: 'original production remains reachable when new production is empty'
- L119 testWidgets: 'module original-record links preserve family'
- L154 testWidgets: 'job detail distinguishes original order date from due date'

### `test/knitting_production_machine_test.dart`

- L184 test: 'aggregate and individual production expose separate configured and original machine choices'
- L200 testWidgets: 'two machine identities cannot be reviewed together'
- L225 testWidgets: '$action preserves original machine identity despite duplicate codes'
- L254 testWidgets: 'configured machine selection clears preserved machine attribution'
- L272 testWidgets: 'report filters and groups original machines by identity while showing name and code'
- L348 testWidgets: 'bulk production keeps each original machine in its own measured-roll row'
- L385 testWidgets: 'prepared batch rows retain original machine name code and opaque request identity'
- L434 testWidgets: 'company changes discard an existing original machine selection'
- L461 testWidgets: 'original machine picker remains usable on small enlarged-text screen'
- L517 test: 'machine labels preserve leading-zero codes and do not invent missing codes'
- L536 testWidgets: 'an old machine picker result cannot restore attribution after access refresh'
- L581 testWidgets: 'clearing an original machine keeps the attribution absent from the reviewed payload'
- L609 testWidgets: 'company-level production row validation rejects both machine kinds'
- L649 testWidgets: 'old report machine picker cannot populate a replaced $replacement scope'
- L722 testWidgets: 'fixed job name replacement clears production attribution and quantities'
- L755 testWidgets: 'same fixed job refresh preserves production draft selections'
- L787 testWidgets: 'pending stale production reload cannot overwrite new $replacement selections'
- L857 testWidgets: 'replaced $screen API revocation hides current production content'
- L922 testWidgets: 'pending access revalidation cannot replace a new production $replacement context'

### `test/knitting_production_operator_report_test.dart`

- L74 testWidgets: '$report original employee filter and grouping preserve opaque identity and readable label'
- L168 testWidgets: 'shared original identities survive Production and Fabric switching and clear on Jobs'

### `test/knitting_production_rows_test.dart`

- L140 test: 'measured row production is available beside existing roll and batch actions'
- L148 test: 'single batch offers original employee attribution separate from signer'
- L160 testWidgets: 'production rows can be reviewed and removed independently'
- L187 testWidgets: 'a mismatched production row is rejected before atomic review'
- L202 testWidgets: 'adding a production row opens its own job form without posting'
- L217 testWidgets: 'preparing an attributed row returns exact local data without a command'
- L278 testWidgets: 'different expected versions of the same job cannot be reviewed together'
- L296 testWidgets: 'access refresh removes prepared row identities before another review'
- L322 testWidgets: 'editing one row job clears its sources and leaves other rows intact'
- L354 testWidgets: 'late row job lookup cannot reopen a row after access changes'
- L383 testWidgets: 'production rows review and clear stay reachable on a small large-font screen'
- L422 testWidgets: 'duplicate original employee names retain distinct saved numbers through review and post'
- L480 testWidgets: 'changing company discards prepared row sources and expected versions'
- L506 testWidgets: 'numbered original employee choices remain tappable on a small large-font screen'
- L574 testWidgets: 'review distinguishes unentered yarn unit count from explicit zero'
- L597 testWidgets: 'removing an earlier row does not move another rows cached job or programme'
- L628 testWidgets: 'late lookup errors from a previous company cannot replace current row validation'

### `test/knitting_recovery_test.dart`

- L63 testWidgets: 'a changed knitting job cannot dispatch an older prepared entry'
- L127 testWidgets: 'knitting uncertain request stays locked until explicit close'
- L143 testWidgets: 'knitting recovers the original event without another posting'

### `test/knitting_reports_test.dart`

- L65 testWidgets: 'pending save dialog $replacement context writes only when still authorized'
- L170 testWidgets: 'late export $outcome is ignored after $replacement context changes'
- L270 testWidgets: 'late roll label choice cannot export into a replacement API and job'
- L327 testWidgets: 'dimension drafts do not change paging or exports until Run'
- L367 testWidgets: 'report dimensions are applicable and embedded order stays fixed'
- L416 testWidgets: 'exports use the visible report until the operator runs the edited dates'
- L450 testWidgets: 'short phone fits report rows and gives the first row its correct number'
- L478 testWidgets: 'removing report access hides cached results without reopening the route'
- L522 testWidgets: 'reports stay readable and permission-scoped at $width'

### `test/knitting_roll_operator_test.dart`

- L125 test: 'individual roll operator is an optional preserved-employee selector'
- L137 testWidgets: '$action keeps original employee identities and exact numbers separate from signer'
- L179 testWidgets: '$action explicitly reviews unrecorded original employee without inventing signer attribution'
- L200 testWidgets: 'clearing individual original employee reviews and posts unrecorded'

### `test/knitting_running_yarn_overview_test.dart`

- L99 testWidgets: 'running yarn uses the complete total and keeps the all-job total labelled'
- L121 testWidgets: 'recent snapshot running balance and drilldown exclude completed jobs'
- L154 testWidgets: 'missing running-job total is unavailable rather than the all-job amount'
- L173 testWidgets: 'an original negative fractional balance keeps its sign and decimals'
- L189 testWidgets: 'running stock drilldown rejects a response for another job state'

### `test/knitting_screen_test.dart`

- L11 testWidgets: 'operator finds the 201st job through paged search and opens a versioned production entry'
- L57 testWidgets: 'setup and report shortcuts open role-allowed work with page-specific controls'
- L153 testWidgets: 'job route selects the next eligible step and only unambiguous sources'
- L339 testWidgets: 'opened job carries its version and single QC source into the real entry'
- L377 testWidgets: 'quality queue opens the selected roll with its current job version'
- L411 testWidgets: 'factory search matches company machines within an open job'
- L454 testWidgets: 'Done opens the new job after recovery of an uncertain save'
- L523 testWidgets: 'access refresh retains allowed draft fields and removes private inputs'
- L559 testWidgets: 'mill overview uses confirmed output and exact source identities'
- L650 testWidgets: '$page fits $width without overflow'
- L682 testWidgets: 'company switch clears job detail and cached amounts'
- L720 testWidgets: 'failed command keeps reviewed input and checks status before retry'
- L753 testWidgets: 'invoice review shows ERP totals before any write'
- L789 testWidgets: 'invoice requires an explicit tax decision before preview or posting'
- L824 testWidgets: 'selected company sales tax template reaches the reviewed invoice unchanged'
- L868 testWidgets: 'original delivery activity shows its date without inventing a native time'
- L919 testWidgets: 'invoice picker reads billing references scoped to the selected job'

### `test/knitting_workflow_destinations_test.dart`

- L20 test: 'estimate and subcontract navigation follows read and operation access'
- L39 testWidgets: 'operational choices are visible without opening More entries'
- L69 testWidgets: 'dedicated destinations open operational registers and create entry'
- L115 testWidgets: 'original programme revision explains its limit and keeps rate available'
- L177 testWidgets: 'estimate controls and list fit a short phone with larger text'
- L226 testWidgets: 'estimate date range and page survive job Back and action refresh'
- L302 testWidgets: 'estimate reader sees neither totals nor commercial write actions'
- L334 testWidgets: 'estimate dates filter the server register and reject reversed ranges'
- L388 testWidgets: 'subcontract register opens a job-versioned scoped issue'
- L425 testWidgets: 'estimate detail selects current version and hides invalid state actions'

### `test/layout_test.dart`

- L10 testWidgets: 'compact sign-in supports larger text without clipping'
- L38 testWidgets: 'first sign-in asks only for credentials and identifies missing fields'
- L73 testWidgets: 'a long company name leaves the primary action reachable at phone text scale'
- L110 testWidgets: 'overview works at $width without overflow and opens the selected module'
- L149 testWidgets: 'empty invoices show a truthful empty state instead of a made-up chart'

### `test/local_workspace_test.dart`

- L103 testWidgets: 'explicit local opt-out uses the normal sign-in entry'
- L113 testWidgets: 'local launch retries without credentials and opens the General company'
- L157 testWidgets: 'company selection changes local account, industry and invoice company together'
- L233 testWidgets: 'unavailable local company leaves the current company and invoices usable'
- L275 testWidgets: 'configured workspace uses authenticated multi-company access without requiring manager rights'
- L310 testWidgets: 'configured companies and demo profiles switch without mixing account scope'
- L363 group: 'private local company access'
- L407 test: 'opens a separate configured local profile without trusting file company choices'
- L441 test: 'configured credentials reject remote origins and duplicate workspace ids'
- L470 test: 'opens the selected company with its own account and no secrets in picker data'
- L490 test: 'rejects an account belonging to a different company'
- L497 test: 'rejects a foreign site or duplicate company in the selector'
- L510 test: 'rejects companies that have not been provisioned locally'
- L518 test: 'keeps an existing single company credential usable'
- L530 test: 'local credential refuses all other origins and ports'

### `test/location_field_test.dart`

- L7 testWidgets: 'validated location point keeps the polygon and inherited points'

### `test/master_import_test.dart`

- L96 testWidgets: 'master import blocks Back until the pending write completes'
- L111 testWidgets: 'master import checks its existing digest receipt after a lost response'
- L126 testWidgets: 'file is previewed before confirmation and can only be posted once from its receipt'

### `test/mill_batch_sources_test.dart`

- L46 testWidgets: 'overview opens separate exact signed fabric balances'

### `test/mill_navigation_pilot_test.dart`

- L68 test: 'actions that operators choose between have different, task-specific symbols'
- L123 testWidgets: 'General ERP switch is reachable on a short desktop without scrolling the mill rail'
- L167 testWidgets: 'factory menu hides tasks blocked by native permissions and retains permitted upkeep'
- L202 testWidgets: 'phone progress follows server acknowledgement (reduced motion $reduced)'
- L259 testWidgets: 'phone drawer back leaves the current knitting page open'
- L293 testWidgets: 'mill menu, visible Back and system Back preserve the workflow and guard changes'

### `test/mill_register_scroll_test.dart`

- L8 testWidgets: 'the live job register builds rows on demand and opens the last job'

### `test/module_browser_test.dart`

- L23 testWidgets: 'same-view refresh keeps rows and scroll through a failed read'
- L63 testWidgets: 'superseded search results cannot replace the latest query'
- L91 testWidgets: 'read-only module offers a way back to records without creation prompts'
- L115 testWidgets: 'manufacturing quantities use the item unit from the work order'
- L150 testWidgets: 'search reloads the current module after typing settles'
- L172 testWidgets: 'an empty next page offers a path back to the first page'
- L194 testWidgets: 'empty-state action can scroll into a short compact viewport'

### `test/native_api_test.dart`

- L8 test: 'stale record responses are distinguishable from field validation'
- L42 test: 'malformed hierarchy data is rejected before it reaches the screen'
- L60 test: 'hierarchy requests preserve company, branch and page; child drafts preserve parent'
- L101 test: 'workflow approval carries the reviewed modification timestamp'
- L124 test: 'native save posts editable values once and returns the saved name'
- L168 test: 'server validation is readable and failed writes are never retried'

### `test/native_catalog_test.dart`

- L54 testWidgets: 'replacing the API clears query and rows even with the same company and account'
- L89 testWidgets: 'record refresh retains rows but permission denial clears them'
- L116 testWidgets: 'multiple-record selection posts only after group confirmation'
- L153 testWidgets: 'plain-language task searches keep the selected module and create permissions'
- L186 testWidgets: 'long custom names remain legible and distinct reports do not repeat a generic chart'
- L242 testWidgets: 'accounting records are distinguishable by their leading symbols'
- L280 testWidgets: 'catalog searches the full permitted list and opens the selected type'
- L316 testWidgets: 'a module filter narrows records and reports together'
- L359 testWidgets: 'record list recovers from an empty search without changing module'
- L384 testWidgets: 'record list removes New when create permission is revoked'

### `test/native_conditions_test.dart`

- L15 test: 'rows, CSV import and per-company stock settings follow current values'
- L91 test: 'hidden sections and conditional required fields follow the current document'
- L126 test: 'non-numbers are false in conditional calculations'
- L136 test: 'conditions follow numeric flags, parent values, optional fields and strict comparisons'
- L191 test: 'membership and comparison rules do not dispatch arbitrary methods'

### `test/native_models_test.dart`

- L5 test: 'multiselect report filters require arrays rather than accidental text'
- L17 test: 'submitted save only includes fields allowed after submission'
- L71 test: 'native edit copies do not modify original child data'
- L86 test: 'native save excludes restricted values and preserves child identity'
- L115 test: 'required and invalid numeric values block native save'

### `test/native_multiselect_test.dart`

- L7 testWidgets: 'multiselect adds a linked record without replacing earlier choices'

### `test/native_readonly_type_test.dart`

- L5 test: 'Read Only field types are locked and excluded from writes'

### `test/native_reports_test.dart`

- L5 test: 'charts preserve negative values and gaps and combine ageing totals by label'
- L48 test: 'hidden report columns retain positional alignment without appearing in the table or CSV'
- L71 test: 'reports preserve numeric values and support map and positional rows'
- L94 test: 'CSV quotes special text and neutralises spreadsheet formulas'
- L110 test: 'prepared reports are not misrepresented as empty data'

### `test/native_row_safety_test.dart`

- L87 testWidgets: 'a failed row defaults request can be retried in place'
- L110 testWidgets: 'the date picker opens for manually typed years outside its range'
- L124 testWidgets: 'rapid Add clicks open only one row draft'
- L158 testWidgets: 'new row accepts against the latest parent rows'
- L182 testWidgets: 'editing finds the same row after its position changes'
- L205 testWidgets: 'Close asks before discarding a changed row'
- L230 testWidgets: 'system back asks before discarding a changed row'
- L250 testWidgets: 'untouched editable and read only rows close without a warning'
- L268 testWidgets: 'row defaults remain guarded until the request finishes'
- L298 testWidgets: 'loaded item changes are guarded after a pending request'
- L323 testWidgets: 'changing a datetime date preserves its existing time'
- L339 testWidgets: '$type picker selects time without changing the date'

### `test/native_session_test.dart`

- L7 test: 'Guest-style forbidden native responses recover without confusing real permission denials'
- L65 test: 'expired native writes renew once and wait for a manual retry'

### `test/native_tree_test.dart`

- L129 testWidgets: 'hierarchy keeps company and parent while paging and opens a leaf natively'
- L157 testWidgets: 'destructive tree action requires confirmation for the selected record'
- L182 testWidgets: 'new child opens a native draft with the selected parent'
- L198 testWidgets: 'hierarchy failure can be retried and unavailable creation stays hidden'

### `test/navigation_retention_test.dart`

- L108 testWidgets: 'opening a record preserves query page and scroll while shell refreshes'
- L182 testWidgets: '$platform command shortcut opens picker and Escape restores focus'

### `test/onboarding_test.dart`

- L56 testWidgets: 'workspace choice selects the studio illustration at width $width'
- L95 testWidgets: 'after inviting from a short phone the confirmation is in view'
- L151 testWidgets: owner ? 'a created company can sign in again if its first login fails' : 'joined staff can retry login without redeeming the invitation twice'

### `test/operation_api_test.dart`

- L20 test: 'recovery is scoped to an advertised workspace and revoked with access'
- L39 test: 'reference APIs use scoped POSTs without sending draft financial values'
- L94 test: 'native writes carry the same operation reference without implicit replay'

### `test/operational_handoffs_test.dart`

- L54 testWidgets: 'receipt inspection binds sample to the selected source row; maintenance opens due log'

### `test/original_production_job_filter_test.dart`

- L99 testWidgets: 'job chooser pagination stays reachable on a short phone with larger text'
- L141 testWidgets: 'report and drilldown show verified job label while carrying exact saved identity'
- L167 testWidgets: 'job selection keeps its label and resets paging without replacing legacy filters'
- L194 testWidgets: 'job choices page and clear only the source identity selector'
- L214 testWidgets: 'late source-job choices cannot survive revoked history access'
- L233 testWidgets: 'malformed job display labels fail closed without exposing identity or totals'
- L245 testWidgets: 'company changes discard selected source-job label and identity'

### `test/original_production_report_api_test.dart`

- L8 test: 'production summary calls only the scoped original report route'

### `test/original_production_report_test.dart`

- L188 testWidgets: 'original totals preserve exact signed zero and missing counts'
- L208 testWidgets: 'grouping resets pagination and drilldown preserves exact filters'
- L246 testWidgets: 'missing labels without an exact selector cannot drill down'
- L266 testWidgets: 'unrecorded dates drill into only originals without dates'
- L282 testWidgets: 'access removal clears already displayed original sums'
- L298 testWidgets: 'applying original date filters resets page and keeps selected group'
- L324 testWidgets: 'access removal hides results and cannot accept late responses'
- L347 testWidgets: 'company changes reject an older company response and reset filters'
- L377 testWidgets: 'wrong report scope never exposes cached totals'
- L385 testWidgets: 'report fits a short phone with large text and exposes pagination'
- L413 testWidgets: 'original history and native reports expose scoped report entry'

### `test/overview_chart_test.dart`

- L28 testWidgets: 'chart handles missing days, credit notes and selection with reduced motion $reduced'
- L103 testWidgets: 'refresh keeps the inspected date within the same reporting period'
- L125 testWidgets: 'single credit note stays selectable on a large-text phone'
- L168 testWidgets: 'year range aggregates months and denied invoice access removes previously loaded values'

### `test/payment_reconciliation_test.dart`

- L221 testWidgets: 'company roundtrip cannot submit a delayed old preparation'
- L245 testWidgets: 'company roundtrip cannot adopt a delayed old status'
- L272 testWidgets: 'failed preparation never submits a payment allocation'
- L284 testWidgets: 'in-flight allocation prevents Back from losing its result'
- L305 testWidgets: 'access change dismisses an open review and clears protected selections'
- L334 testWidgets: 'lost response locks allocation until its saved receipt is checked'
- L357 testWidgets: 'prepared status remains locked until a close confirms nothing posted'
- L379 testWidgets: 'invalid amount focuses its field without posting'
- L398 testWidgets: 'confirm a partial payment and reload the remaining balances'

### `test/pending_operations_test.dart`

- L65 testWidgets: 'offline paging retains a recovery action without an unhandled error'
- L79 testWidgets: 'pending recovery never replays and prepared is not called failed'
- L102 testWidgets: 'a completion arriving before close is shown as completed'

### `test/pos_checkout_test.dart`

- L178 testWidgets: 'checkout blocks Back in flight and Account after an uncertain response'
- L215 testWidgets: 'uncertain refund retains its token and cannot be abandoned with Back'
- L244 testWidgets: 'cart removal can be undone and Back protects the entry'
- L301 testWidgets: 'owner creates a register from the empty state'
- L315 testWidgets: 'cashier reviews and recovers the same sale before counting the drawer'

### `test/report_screen_test.dart`

- L111 testWidgets: 'prepared report uses the requested filters while retaining the applied result'
- L148 testWidgets: 'a superseded report cannot replace the newer applied result'
- L186 testWidgets: 'failed rerun keeps the prior applied result and filter summary'
- L221 testWidgets: 'order analysis plots its chart, selects statuses and clears stale party choices'
- L257 testWidgets: 'hiding a conditional filter drops its invalid value and keeps fixed defaults'
- L282 testWidgets: 'report links open native records and preserve displayed amounts'
- L318 testWidgets: 'editing report filters retains applied rows and exports until successful rerun'

### `test/sdk_migration_test.dart`

- L81 testWidgets: '$screen keeps row identity after reorder at width $width'
- L123 testWidgets: '$title exposes a level-one heading to mobile readers'

### `test/session_recovery_test.dart`

- L38 testWidgets: 'recovery keeps the draft and offers retry for a mistyped verification code'
- L81 testWidgets: 'system back cannot sign out and discard a draft from recovery'
- L109 testWidgets: 'sign-in recovery keeps the underlying draft and uses the same account'

### `test/specialized_fields_test.dart`

- L7 testWidgets: 'field editor shows private file controls and a drawable signature'

### `test/task_planner_test.dart`

- L35 testWidgets: 'board pages and filters tasks, and the monthly calendar shows a spanning task on each covered day'

### `test/ux_accessibility_test.dart`

- L30 testWidgets: 'replacement service access is rechecked and old listeners detach'
- L65 testWidgets: 'shared button hit areas remain at least 48 logical pixels'
- L98 testWidgets: 'sample paper keeps shared identity and becomes static for reduced motion'
- L118 test: 'date entry rejects normalized impossible dates and incomplete times'
- L129 testWidgets: 'large metrics preserve text scaling without shrinking value'
- L155 testWidgets: 'date picker keeps direct typing and updates the same form value'

### `test/workspace_context_test.dart`

- L6 test: 'enabling knitting-only navigation invalidates cached client views'
- L18 test: 'revoking imported history access invalidates cached client views'
- L38 test: 'company and role determine available industry destinations'

### `test/workspace_picker_test.dart`

- L7 testWidgets: 'workspace search stays usable above a phone keyboard at large text sizes'
- L59 testWidgets: 'search, select and dismiss module menu without a disposed controller'

### `test/workspace_ui_test.dart`

- L7 testWidgets: 'reduced motion preserves selection and accessible labels'

### `tool/pilot_company_invoice_settings_test.dart`

- L26 testWidgets: 'save General company branding once, keep Knitting branding separate, and restore it on company return'

### `tool/pilot_customer_migration_test.dart`

- L41 testWidgets: 'fresh customer launch, all four companies, original records, shared cash and General ERP'
- L145 test: 'original invoice PDFs preserve saved dates and amounts, including blank descriptions'

### `tool/pilot_invoice_gallery_test.dart`

- L82 testWidgets: 'direct workspace opens invoices, previews all formats, and preserves the chosen style'

### `tool/pilot_local_launch_test.dart`

- L23 testWidgets: 'fresh local launches keep General and Knitting companies separate without authentication screens'

### `tool/pilot_master_import_test.dart`

- L20 testWidgets: 'owner previews, imports and reopens a customer from the record list'

### `tool/pilot_mill_test.dart`

- L17 testWidgets: 'New mill user completes a customer-material job through the connected Flutter UI'

### `tool/pilot_onboarding_test.dart`

- L42 testWidgets: 'owner creates $industry and invites a scoped staff member'

### `tool/pilot_specialized_fields_test.dart`

- L22 testWidgets: 'draw, attach, scan, save, reopen and preview on native-test'

### `tool/pilot_trade_test.dart`

- L20 testWidgets: 'new clerk purchases stock, delivers an order and settles invoices'

### `tool/pilot_ux_test.dart`

- L177 testWidgets: 'synthetic mill entry reconciles a committed command without replay'
- L304 testWidgets: 'synthetic native-test UI preserves and recovers real committed work'

### `tool/profile_startup.dart`

Executable/fixture; no `test` or `testWidgets` declaration.

### `tool/profile_workspace.dart`

Executable/fixture; no `test` or `testWidgets` declaration.

### `tool/verify_connection.dart`

Executable/fixture; no `test` or `testWidgets` declaration.

### `tool/verify_knitting.dart`

Executable/fixture; no `test` or `testWidgets` declaration.

### `tool/verify_native.dart`

Executable/fixture; no `test` or `testWidgets` declaration.

### `tool/verify_pos.dart`

Executable/fixture; no `test` or `testWidgets` declaration.

