import 'package:flutter/material.dart';
import '../erp_models.dart';

/// Original studio renders share a camera, lighting and palette. Pre-sized
/// variants keep table headers from decoding full-width hero art.
enum ArtObject {
  warehouse,
  purchasing,
  sales,
  yarn,
  machine,
  fabric,
  inspection,
  dispatch,
  invoice,
}

class WorkspaceArt extends StatelessWidget {
  const WorkspaceArt(
    this.object, {
    super.key,
    this.width = 40,
    this.height = 32,
    this.alignment = Alignment.center,
  });
  final ArtObject object;
  final double width, height;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    height: height,
    child: LayoutBuilder(
      builder: (context, box) {
        // BoxFit.contain can be height-limited in a wide stage. Use the
        // actual rendered width to avoid decoding the next larger variant.
        final aspect = object == ArtObject.warehouse ? 2.0 : 1.5;
        final drawnWidth = box.maxWidth.clamp(0.0, box.maxHeight * aspect);
        final pixels = drawnWidth * MediaQuery.devicePixelRatioOf(context);
        final tier = pixels <= 144
            ? 144
            : pixels <= 448
            ? 448
            : 960;
        return Image.asset(
          'assets/studio/${object.name}-$tier.webp',
          fit: BoxFit.contain,
          alignment: alignment,
          excludeFromSemantics: true,
          cacheWidth: tier,
          filterQuality: FilterQuality.low,
        );
      },
    ),
  );
}

ArtObject moduleArt(ErpModule module) => switch (module) {
  ErpModule.accounts || ErpModule.projects => ArtObject.invoice,
  ErpModule.stock || ErpModule.assets => ArtObject.warehouse,
  ErpModule.buying => ArtObject.purchasing,
  ErpModule.selling => ArtObject.sales,
  ErpModule.manufacturing => ArtObject.machine,
  ErpModule.quality => ArtObject.inspection,
};

ArtObject recordArt(String type) {
  final name = type.toLowerCase();
  if (name.contains('invoice') ||
      name.contains('payment') ||
      name.contains('account') ||
      name.contains('ledger')) {
    return ArtObject.invoice;
  }
  if (name.contains('quality') || name.contains('inspect')) {
    return ArtObject.inspection;
  }
  if (name.contains('delivery') ||
      name.contains('dispatch') ||
      name.contains('ship')) {
    return ArtObject.dispatch;
  }
  if (name.contains('purchase') || name.contains('supplier')) {
    return ArtObject.purchasing;
  }
  if (name.contains('customer') ||
      name.contains('sales') ||
      name.contains('selling') ||
      name.contains('quotation')) {
    return ArtObject.sales;
  }
  if (name.contains('warehouse') ||
      name.contains('stock') ||
      name.contains('item') ||
      name.contains('asset')) {
    return ArtObject.warehouse;
  }
  if (name.contains('machine') ||
      name.contains('manufactur') ||
      name.contains('production') ||
      name.contains('work order')) {
    return ArtObject.machine;
  }
  if (name.contains('yarn') || name.contains('lot')) return ArtObject.yarn;
  if (name.contains('fabric') || name.contains('roll')) return ArtObject.fabric;
  return ArtObject.invoice;
}

/// A single compact symbol in each column header keeps repeated values quiet.
class ColumnCaption extends StatelessWidget {
  const ColumnCaption(
    this.label, {
    super.key,
    this.icon,
    this.alignEnd = false,
    this.fieldtype,
    this.dark = false,
  });
  final String label;
  final IconData? icon;
  final String? fieldtype;
  final bool alignEnd, dark;
  IconData get symbol {
    final name = label.toLowerCase();
    if (fieldtype == 'Date' ||
        fieldtype == 'Datetime' ||
        name.contains('date') ||
        name.contains('modified') ||
        name.contains('due')) {
      return Icons.calendar_today_outlined;
    }
    if (fieldtype == 'Currency' ||
        name.contains('amount') ||
        name.contains('rate') ||
        name.contains('total')) {
      return Icons.payments_outlined;
    }
    if (name.contains('status') ||
        name.contains('decision') ||
        name.contains('state')) {
      return Icons.adjust_outlined;
    }
    if (name.contains('kg') ||
        name.contains('weight') ||
        name.contains('qty') ||
        name.contains('quantity')) {
      return Icons.scale_outlined;
    }
    if (name.contains('customer') ||
        name.contains('supplier') ||
        name.contains('party')) {
      return Icons.business_outlined;
    }
    if (name.contains('number') || name.contains('reference') || name == 'id') {
      return Icons.tag;
    }
    if (name.contains('time') || name.contains('shift')) {
      return Icons.schedule_outlined;
    }
    if (name.contains('warehouse') || name.contains('godown')) {
      return Icons.warehouse_outlined;
    }
    if (fieldtype == 'Int' || fieldtype == 'Float') return Icons.numbers;
    return Icons.description_outlined;
  }

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    mainAxisAlignment: alignEnd
        ? MainAxisAlignment.end
        : MainAxisAlignment.start,
    children: [
      ExcludeSemantics(
        child: Icon(
          icon ?? symbol,
          size: 14,
          color: dark ? const Color(0xFFDFDDDA) : const Color(0xFF58585A),
        ),
      ),
      const SizedBox(width: 5),
      Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
    ],
  );
}

/// Field groups may be ERPNext-defined. Resolve their standard concepts to
/// vector symbols so long documents have one small glyph per named section.
IconData sectionSymbol(String text) {
  final name = text.toLowerCase();
  if (name.contains('account') ||
      name.contains('tax') ||
      name.contains('pay') ||
      name.contains('price') ||
      name.contains('total')) {
    return Icons.payments_outlined;
  }
  if (name.contains('address') || name.contains('contact')) {
    return Icons.contact_page_outlined;
  }
  if (name.contains('shipping') ||
      name.contains('delivery') ||
      name.contains('transport')) {
    return Icons.local_shipping_outlined;
  }
  if (name.contains('time') ||
      name.contains('date') ||
      name.contains('schedule')) {
    return Icons.event_outlined;
  }
  if (name.contains('item') ||
      name.contains('stock') ||
      name.contains('material')) {
    return Icons.inventory_2_outlined;
  }
  if (name.contains('quality') || name.contains('inspection')) {
    return Icons.fact_check_outlined;
  }
  if (name.contains('file')) return Icons.attach_file_outlined;
  if (name.contains('assign')) return Icons.people_outline;
  if (name.contains('history') || name.contains('activity')) {
    return Icons.history;
  }
  return Icons.subject;
}
