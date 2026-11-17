import 'package:flutter/material.dart';

import '../../../core/ui/design.dart';
import '../models/invoice_templates.dart';

/// Contact sheet of the first page of each actual print format.
class InvoiceGallery extends StatelessWidget {
  const InvoiceGallery({
    super.key,
    required this.onChoose,
    this.selectedId,
    this.companyDefault = false,
    this.transitionScope,
  });
  final ValueChanged<InvoiceTemplate> onChoose;
  final String? selectedId;
  final bool companyDefault;
  final Object? transitionScope;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      final pad = box.maxWidth >= 700 ? 26.0 : 14.0;
      final width = box.maxWidth - pad * 2;
      final columns = width < 300 || (scale > 1.45 && width < 550)
          ? 1
          : (width / 205).floor().clamp(2, 5);
      const gap = 16.0;
      final cell = (width - (columns - 1) * gap) / columns;
      return GridView.builder(
        key: const PageStorageKey('invoice-format-pages'),
        padding: EdgeInsets.fromLTRB(pad, 12, pad, 24),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          mainAxisSpacing: gap,
          crossAxisSpacing: gap,
          mainAxisExtent: cell * 1.18 + 66 * scale.clamp(1, 2.2),
        ),
        itemCount: invoiceTemplates.length,
        itemBuilder: (context, i) {
          final t = invoiceTemplates[i];
          final chosen = t.id == selectedId;
          return Semantics(
            button: true,
            selected: chosen,
            label: chosen && companyDefault
                ? '${t.name}, company default'
                : t.name,
            excludeSemantics: true,
            child: Material(
              color: WorkspaceTheme.surface,
              shape: RoundedRectangleBorder(
                side: BorderSide(
                  color: chosen ? WorkspaceTheme.ink : WorkspaceTheme.border,
                  width: chosen ? 2 : 1,
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => onChoose(t),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: ColoredBox(
                        color: Color.alphaBlend(
                          Color(t.accent).withValues(alpha: .09),
                          const Color(0xffebeae6),
                        ),
                        child: Padding(
                          padding: EdgeInsets.all(cell < 175 ? 12 : 17),
                          child: Center(
                            child: AspectRatio(
                              aspectRatio: 210 / 297,
                              child: InvoicePaperContinuity(
                                tag: transitionScope == null
                                    ? null
                                    : (transitionScope, t.id),
                                template: t,
                                child: DecoratedBox(
                                  decoration: const BoxDecoration(
                                    color: Colors.white,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Color(0x26000000),
                                        blurRadius: 9,
                                        offset: Offset(0, 3),
                                      ),
                                    ],
                                  ),
                                  child: Image.asset(
                                    t.thumbnailAsset,
                                    fit: BoxFit.contain,
                                    filterQuality: FilterQuality.medium,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 9, 10, 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  t.name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                  ),
                                ),
                                Text(
                                  chosen && companyDefault
                                      ? 'Company default'
                                      : t.category,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          if (chosen)
                            const Icon(Icons.check_circle, size: 19)
                          else
                            Icon(
                              Icons.arrow_outward,
                              size: 15,
                              color: WorkspaceTheme.muted,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );
}

/// A paper identity moves from the template gallery into its larger preview.
/// The flight uses the public sample thumbnail and respects reduced motion.
class InvoicePaperContinuity extends StatelessWidget {
  const InvoicePaperContinuity({
    super.key,
    required this.tag,
    required this.template,
    required this.child,
  });
  final Object? tag;
  final InvoiceTemplate template;
  final Widget child;
  @override
  Widget build(BuildContext context) =>
      tag == null || workspaceReduceMotion(context)
      ? child
      : Hero(
          tag: tag!,
          flightShuttleBuilder: (_, animation, direction, from, to) =>
              Image.asset(
                template.thumbnailAsset,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.medium,
              ),
          child: child,
        );
}

Future<InvoiceTemplate?> chooseInvoiceTemplate(
  BuildContext context,
  String selected,
) => showModalBottomSheet<InvoiceTemplate>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  constraints: const BoxConstraints(maxWidth: 1080),
  builder: (sheet) => FractionallySizedBox(
    heightFactor: .88,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 0, 8, 8),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Choose invoice template',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20),
                ),
              ),
              IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.pop(sheet),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        Expanded(
          child: InvoiceGallery(
            selectedId: selected,
            onChoose: (t) => Navigator.pop(sheet, t),
          ),
        ),
      ],
    ),
  ),
);
