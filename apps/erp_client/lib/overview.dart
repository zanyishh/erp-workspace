import 'package:flutter/material.dart';
import 'design.dart';
import 'erp_models.dart';
import 'widgets.dart';

class OverviewScreen extends StatelessWidget {
  const OverviewScreen({
    super.key,
    required this.data,
    required this.onModule,
    required this.onNew,
  });
  final ErpSnapshot data;
  final ValueChanged<ErpModule> onModule;
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final wide = box.maxWidth >= 1180, medium = box.maxWidth >= 780;
      final left = Column(
        children: [_summary(), const SizedBox(height: 16), _flow()],
      );
      final centre = Column(
        children: [
          _stage(context),
          const SizedBox(height: 16),
          _salesPanel(),
          const SizedBox(height: 16),
          _activity(),
        ],
      );
      final right = _workspaces(horizontal: medium && !wide);
      return SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          medium ? 24 : 16,
          16,
          medium ? 24 : 16,
          24,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 238, child: left),
                  const SizedBox(width: 16),
                  Expanded(child: centre),
                  const SizedBox(width: 16),
                  SizedBox(width: 276, child: right),
                ],
              )
            else if (medium) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 232, child: left),
                  const SizedBox(width: 16),
                  Expanded(child: centre),
                ],
              ),
              const SizedBox(height: 16),
              right,
            ] else ...[
              _summary(),
              const SizedBox(height: 16),
              _stage(context),
              const SizedBox(height: 16),
              _salesPanel(),
              const SizedBox(height: 16),
              _flow(),
              const SizedBox(height: 16),
              _activity(),
              const SizedBox(height: 16),
              right,
            ],
            const SizedBox(height: 20),
            const Text(
              'ERPNext connected · — means this account has no access',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10, color: WorkspaceTheme.muted),
            ),
          ],
        ),
      );
    },
  );

  Widget _summary() => Panel(
    dark: true,
    padding: const EdgeInsets.all(18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Company',
              style: TextStyle(fontSize: 11, color: Color(0xFFC2C7BD)),
            ),
            StatusChip('Connected', dark: true),
          ],
        ),
        const SizedBox(height: 14),
        Display(data.company, size: 31, light: true),
        const SizedBox(height: 10),
        Text(
          'BUSINESS OVERVIEW',
          style: TextStyle(
            fontSize: 10,
            letterSpacing: 1.3,
            color: WorkspaceTheme.light.withValues(alpha: .62),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(child: _darkValue('Customers', tally(data.customers))),
            Container(width: 1, height: 34, color: const Color(0xFF4A4E46)),
            const SizedBox(width: 15),
            Expanded(child: _darkValue('Suppliers', tally(data.suppliers))),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Warehouses',
              style: TextStyle(fontSize: 11, color: Color(0xFFB9BFB5)),
            ),
            Text(
              tally(data.warehouses),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: MetricTile(
                label: 'Billed',
                value: money(data.billed, data.currency),
                footer: data.invoicesAvailable
                    ? 'Posted invoices'
                    : 'No invoice access',
                icon: Icons.receipt_long_outlined,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: MetricTile(
                label: 'Unpaid',
                value: tally(data.unpaidInvoices),
                footer: data.invoicesAvailable
                    ? 'Unpaid invoices'
                    : 'No invoice access',
                icon: Icons.schedule_outlined,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: Pill(
            'View accounts',
            icon: Icons.arrow_outward,
            onPressed: () => onModule(ErpModule.accounts),
            light: true,
          ),
        ),
      ],
    ),
  );
  Widget _darkValue(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(fontSize: 10, color: Color(0xFFB9BFB5)),
      ),
      const SizedBox(height: 5),
      Text(
        value,
        style: const TextStyle(
          fontSize: 25,
          fontWeight: FontWeight.w500,
          color: WorkspaceTheme.light,
        ),
      ),
    ],
  );

  Widget _flow() => Panel(
    dark: true,
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Display('BUSINESS FLOW', size: 22, light: true),
        const SizedBox(height: 5),
        const Text(
          'From the first order to the final bill.',
          style: TextStyle(fontSize: 10, color: Color(0xFFB9BFB5)),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 150,
          child: LayoutBuilder(
            builder: (context, b) {
              const positions = [
                Offset(.13, .55),
                Offset(.38, .24),
                Offset(.64, .65),
                Offset(.88, .30),
              ];
              const modules = [
                ErpModule.buying,
                ErpModule.stock,
                ErpModule.selling,
                ErpModule.accounts,
              ];
              const labels = ['BUY', 'STORE', 'SELL', 'BILL'];
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(child: CustomPaint(painter: _FlowPainter())),
                  for (var i = 0; i < 4; i++)
                    Positioned(
                      left: positions[i].dx * (b.maxWidth - 40),
                      top: positions[i].dy * 85,
                      child: Column(
                        children: [
                          SizedBox(
                            width: 40,
                            height: 44,
                            child: IconButton(
                              tooltip: 'Open ${modules[i].label}',
                              onPressed: () => onModule(modules[i]),
                              padding: EdgeInsets.zero,
                              icon: Container(
                                width: 27,
                                height: 27,
                                decoration: BoxDecoration(
                                  color: WorkspaceTheme.charcoal,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: i == 1
                                        ? WorkspaceTheme.peach
                                        : const Color(0xFF6C7568),
                                  ),
                                ),
                                child: Icon(
                                  moduleIcon(modules[i]),
                                  size: 13,
                                  color: WorkspaceTheme.light,
                                ),
                              ),
                            ),
                          ),
                          Text(
                            labels[i],
                            style: const TextStyle(
                              fontSize: 8,
                              color: Color(0xFFC1C7BA),
                              letterSpacing: .6,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        const Row(
          children: [
            Icon(Icons.hub_outlined, size: 12, color: WorkspaceTheme.palePeach),
            SizedBox(width: 5),
            Expanded(
              child: Text(
                'One connected business',
                style: TextStyle(fontSize: 10, color: Color(0xFFC1C7BA)),
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _stage(BuildContext context) => Column(
    children: [
      Row(
        children: [
          Pill('New document', icon: Icons.add, onPressed: onNew),
          const SizedBox(width: 4),
          CircleControl(
            icon: Icons.receipt_long_outlined,
            label: 'Open invoices',
            onPressed: () => onModule(ErpModule.accounts),
          ),
          const Spacer(),
          CircleControl(
            icon: Icons.open_in_full,
            label: 'Expand business illustration',
            onPressed: () => showDialog<void>(
              context: context,
              builder: (c) => Dialog(
                backgroundColor: WorkspaceTheme.canvas,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 1100,
                    maxHeight: 650,
                  ),
                  child: Stack(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(30),
                        child: Center(
                          child: Image.asset('assets/images/warehouse.png'),
                        ),
                      ),
                      Positioned(
                        right: 12,
                        top: 12,
                        child: CircleControl(
                          icon: Icons.close,
                          label: 'Close illustration',
                          onPressed: () => Navigator.pop(c),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Container(
        height: 330,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          border: Border.all(color: WorkspaceTheme.border),
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFE8E9E5), Color(0xFFF0F0EC)],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              left: 18,
              top: 17,
              child: Row(
                children: [
                  const StatusChip('Operations'),
                  const SizedBox(width: 8),
                  Text(
                    '${tally(data.warehouses)} locations',
                    style: const TextStyle(
                      fontSize: 10,
                      color: WorkspaceTheme.muted,
                    ),
                  ),
                ],
              ),
            ),
            Positioned.fill(
              top: 36,
              bottom: 26,
              left: 8,
              right: 8,
              child: Image.asset(
                'assets/images/warehouse.png',
                fit: BoxFit.contain,
                excludeFromSemantics: true,
              ),
            ),
            const Positioned(
              left: 18,
              bottom: 16,
              child: Text(
                'YOUR BUSINESS, IN VIEW',
                style: TextStyle(
                  fontSize: 9,
                  letterSpacing: 1.5,
                  color: WorkspaceTheme.muted,
                ),
              ),
            ),
            const Positioned(
              right: 18,
              bottom: 16,
              child: Tooltip(
                message:
                    'Illustrative 3D scene, not a model of your actual premises',
                child: Icon(
                  Icons.info_outline,
                  size: 14,
                  color: WorkspaceTheme.muted,
                ),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: _smallMetric(
              'SALES ORDERS',
              tally(data.count(ErpModule.selling)),
              Icons.north_east,
              () => onModule(ErpModule.selling),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _smallMetric(
              'PURCHASE ORDERS',
              tally(data.count(ErpModule.buying)),
              Icons.south_west,
              () => onModule(ErpModule.buying),
            ),
          ),
        ],
      ),
    ],
  );
  Widget _smallMetric(
    String label,
    String value,
    IconData icon,
    VoidCallback action,
  ) => Material(
    color: WorkspaceTheme.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: const BorderSide(color: WorkspaceTheme.border),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: action,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 9,
                      color: WorkspaceTheme.muted,
                      letterSpacing: .5,
                    ),
                  ),
                ),
                Icon(icon, size: 15, color: WorkspaceTheme.muted),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.end,
                spacing: 12,
                runSpacing: 8,
                children: [
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w500,
                      height: 1,
                    ),
                  ),
                  const StatusChip('Selected period'),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _salesPanel() => Panel(
    border: true,
    padding: const EdgeInsets.all(17),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(child: Display('SALES PULSE', size: 24)),
            Text(
              money(data.billed, data.currency),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                letterSpacing: -.7,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          'Posted invoices across the selected period',
          style: TextStyle(fontSize: 10, color: WorkspaceTheme.muted),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 114,
          child: !data.invoicesAvailable
              ? const Center(
                  child: Text(
                    'Invoice access unavailable',
                    style: TextStyle(color: WorkspaceTheme.muted),
                  ),
                )
              : data.sales.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.show_chart,
                        size: 27,
                        color: WorkspaceTheme.border,
                      ),
                      SizedBox(height: 8),
                      Text(
                        'No posted invoices yet',
                        style: TextStyle(
                          fontSize: 12,
                          color: WorkspaceTheme.muted,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Your first posted invoice will appear here.',
                        style: TextStyle(
                          fontSize: 10,
                          color: WorkspaceTheme.muted,
                        ),
                      ),
                    ],
                  ),
                )
              : CustomPaint(
                  size: const Size(double.infinity, 114),
                  painter: _SalesPainter(data.sales),
                ),
        ),
      ],
    ),
  );

  Widget _activity() => Panel(
    border: true,
    padding: const EdgeInsets.all(17),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(child: Display('RECENT ACTIVITY', size: 22)),
            IconButton(
              tooltip: 'Open invoice activity',
              onPressed: () => onModule(ErpModule.accounts),
              icon: const Icon(Icons.arrow_outward, size: 17),
            ),
          ],
        ),
        if (data.activity.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 7),
            child: Text(
              data.invoicesAvailable
                  ? 'A quiet start. Your invoices will appear here.'
                  : 'Invoice access unavailable for this account.',
              style: const TextStyle(fontSize: 11, color: WorkspaceTheme.muted),
            ),
          )
        else
          for (final record in data.activity.take(3))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  const Icon(
                    Icons.receipt_long_outlined,
                    size: 17,
                    color: WorkspaceTheme.muted,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      record.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    money(record.amount ?? 0, record.currency ?? data.currency),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
      ],
    ),
  );

  Widget _workspaces({required bool horizontal}) {
    const modules = [ErpModule.stock, ErpModule.selling, ErpModule.buying];
    final cards = [for (final m in modules) _workspaceCard(m)];
    return Panel(
      dark: true,
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(9, 9, 9, 17),
            child: Row(
              children: [
                Expanded(child: Display('WORKSPACES', size: 24, light: true)),
                Icon(Icons.tune, size: 16, color: WorkspaceTheme.light),
              ],
            ),
          ),
          if (horizontal)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < cards.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(child: cards[i]),
                ],
              ],
            )
          else
            for (var i = 0; i < cards.length; i++) ...[
              if (i > 0) const SizedBox(height: 9),
              cards[i],
            ],
          const Padding(
            padding: EdgeInsets.fromLTRB(9, 16, 9, 9),
            child: Text(
              'A place for every part of your business.',
              style: TextStyle(
                fontSize: 10,
                color: Color(0xFFB9BFB5),
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _workspaceCard(ErpModule module) {
    final image = switch (module) {
      ErpModule.stock => 'warehouse',
      ErpModule.selling => 'sales',
      _ => 'purchasing',
    };
    return Semantics(
      button: true,
      label: 'Open ${module.label}',
      excludeSemantics: true,
      onTap: () => onModule(module),
      child: Material(
        color: WorkspaceTheme.surface,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => onModule(module),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 82,
                  width: double.infinity,
                  child: Image.asset(
                    'assets/images/$image.png',
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Expanded(
                      child: Display(module.label.toUpperCase(), size: 25),
                    ),
                    Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: WorkspaceTheme.border),
                      ),
                      child: const Icon(Icons.arrow_outward, size: 13),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                Text(
                  module.description,
                  style: const TextStyle(
                    fontSize: 10,
                    color: WorkspaceTheme.muted,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text(
                      tally(data.count(module)),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      data.count(module) == null
                          ? 'No access'
                          : module == ErpModule.stock
                          ? 'catalog items'
                          : 'orders',
                      style: const TextStyle(
                        fontSize: 10,
                        color: WorkspaceTheme.muted,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      width: 36,
                      height: 3,
                      decoration: BoxDecoration(
                        color: WorkspaceTheme.peach,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SalesPainter extends CustomPainter {
  _SalesPainter(this.days);
  final List<SalesDay> days;
  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = WorkspaceTheme.border.withValues(alpha: .55)
      ..strokeWidth = .6;
    for (var i = 1; i < 4; i++) {
      canvas.drawLine(
        Offset(0, size.height * i / 4),
        Offset(size.width, size.height * i / 4),
        grid,
      );
    }
    final scale = SalesScale(days.map((d) => d.amount));
    double y(double amount) =>
        size.height - 10 - scale.fraction(amount) * (size.height - 22);
    final zero = y(0);
    canvas.drawLine(Offset(0, zero), Offset(size.width, zero), grid);
    final points = [
      for (var i = 0; i < days.length; i++)
        Offset(
          days.length == 1
              ? size.width / 2
              : i / (days.length - 1) * size.width,
          y(days[i].amount),
        ),
    ];
    if (points.length == 1) {
      canvas.drawCircle(points.first, 4, Paint()..color = WorkspaceTheme.peach);
      return;
    }
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final p in points.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    final fill = Path.from(path)
      ..lineTo(points.last.dx, zero)
      ..lineTo(points.first.dx, zero)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [WorkspaceTheme.palePeach, Color(0x00F4D7C3)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = WorkspaceTheme.peach
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_SalesPainter old) => old.days != days;
}

class _FlowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final grid = Paint()
      ..color = const Color(0xFF3B473A)
      ..strokeWidth = .5;
    for (var x = -100.0; x < size.width + 100; x += 22) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x + size.height * .45, size.height),
        grid,
      );
    }
    for (var y = 0.0; y < size.height; y += 19) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y - 20), grid);
    }
    final path = Path()
      ..moveTo(24, 70)
      ..cubicTo(
        size.width * .35,
        100,
        size.width * .17,
        10,
        size.width * .40,
        39,
      )
      ..cubicTo(
        size.width * .60,
        65,
        size.width * .45,
        118,
        size.width * .67,
        96,
      )
      ..cubicTo(
        size.width * .84,
        80,
        size.width * .72,
        20,
        size.width - 12,
        48,
      );
    canvas.drawPath(
      path,
      Paint()
        ..color = WorkspaceTheme.peach.withValues(alpha: .85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FlowPainter old) => false;
}
