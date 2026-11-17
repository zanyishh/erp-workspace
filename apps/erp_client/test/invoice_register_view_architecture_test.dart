import 'dart:async';

import 'package:erp_client/features/invoices/models/invoice_templates.dart';
import 'package:erp_client/features/invoices/presentation/invoice_register_view.dart';
import 'package:erp_client/features/invoices/presentation/invoice_register_view_model.dart';
import 'package:erp_client/features/invoices/data/invoice_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'invoice_register_architecture_test.dart'
    show MemoryInvoiceRepository, invoiceRegisterData;

void main() {
  testWidgets(
    'template creation survives a same-company refresh completing during selection',
    (t) async {
      final repository = MemoryInvoiceRepository();
      final model = InvoiceRegisterViewModel(repository);
      addTearDown(model.dispose);
      await model.result;
      final choice = Completer<InvoiceTemplate?>();
      InvoiceRegisterPage? opened;
      await t.pumpWidget(
        MaterialApp(
          home: InvoiceRegisterView(
            model: model,
            company: 'A',
            canCreate: true,
            gallery: (selected, onChoose) => TextButton(
              onPressed: () => onChoose(invoiceTemplateById('canopy')),
              child: const Text('Choose template'),
            ),
            sample: (page, template, canCreate) => choice.future,
            openEditor: (page, name, template) async {
              opened = page;
              return null;
            },
            preview: (page, name) async {},
            settings: (page) async => false,
            protect: (child, reload) => child,
          ),
        ),
      );
      await t.pumpAndSettle();
      final refresh = Completer<InvoiceRegisterPage>();
      repository.pending = refresh;
      await t.tap(find.byTooltip('Refresh invoices'));
      await t.pump();
      await t.tap(find.text('Templates'));
      await t.pumpAndSettle();
      await t.tap(find.text('Choose template'));
      final refreshed = InvoiceRegisterPage.fromJson(
        invoiceRegisterData(name: 'INV-2'),
        company: 'A',
        pageSize: 25,
      );
      refresh.complete(refreshed);
      await t.pumpAndSettle();
      expect(model.loadedPage, same(refreshed));
      repository.pending = null;
      choice.complete(invoiceTemplateById('canopy'));
      await t.pumpAndSettle();
      expect(opened, same(refreshed));
      expect(t.takeException(), isNull);
    },
  );
}
