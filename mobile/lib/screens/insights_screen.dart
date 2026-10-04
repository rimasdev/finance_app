import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../format.dart';
import '../icons.dart';
import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';
import 'entry_screens.dart';

class InsightsScreen extends StatelessWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<FolioStore>();
    final data = store.insights;
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          color: FolioColors.green,
          onRefresh: store.refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
            children: [
              MonthSwitcher(
                label: data?.label ?? monthTitle(store.month),
                onPrevious: () => store.shiftMonth(-1),
                onNext: () => store.shiftMonth(1),
              ),
              const SizedBox(height: 12),
              if (data == null || data.slices.isEmpty)
                const EmptyBlock(
                  icon: Icons.pie_chart_outline,
                  title: 'No expenses yet',
                  body: 'This month is empty. Add a transaction or paste a bank SMS.',
                )
              else ...[
                SizedBox(height: 240, child: DonutChart(slices: data.slices)),
                const SizedBox(height: 8),
                for (final slice in data.slices) ...[
                  const SizedBox(height: 10),
                  FolioCard(
                    onTap: slice.name == 'Bank charges'
                        ? null
                        : () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => CategorySpendScreen(
                                name: slice.name,
                                categoryId: slice.categoryId,
                                icon: slice.icon,
                                color: slice.color,
                              ),
                            ),
                          ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            IconBubble(
                              icon: iconFor(slice.icon),
                              color: colorFromHex(slice.color),
                              size: 36,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    slice.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    '${slice.percent.toStringAsFixed(0)}% of expenses',
                                    style: const TextStyle(
                                      color: FolioColors.muted,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          money(slice.amount),
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: (slice.percent / 100).clamp(0, 1),
                            minHeight: 6,
                            backgroundColor: FolioColors.line,
                            color: colorFromHex(slice.color),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class CategorySpendScreen extends StatelessWidget {
  const CategorySpendScreen({
    super.key,
    required this.name,
    required this.categoryId,
    required this.icon,
    required this.color,
  });

  final String name;
  final String? categoryId;
  final String icon;
  final String color;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<FolioStore>();
    final items = [
      for (final day in store.timeline?.days ?? <TimelineDay>[])
        for (final txn in day.items)
          if (_inCategory(txn)) txn,
    ];
    return Scaffold(
      appBar: AppBar(title: Text(name)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          FolioCard(
            child: Row(
              children: [
                IconBubble(
                  icon: iconFor(icon),
                  color: colorFromHex(color),
                  size: 42,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        '${items.length} this month',
                        style: const TextStyle(
                          color: FolioColors.muted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  money(items.fold(0.0, (sum, txn) => sum + txn.amount)),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Open a transaction to give it a category.',
            style: TextStyle(color: FolioColors.muted, fontSize: 13),
          ),
          const SizedBox(height: 12),
          if (items.isEmpty)
            const EmptyBlock(
              icon: Icons.category_outlined,
              title: 'Nothing here',
              body:
                  'No expenses in this category for the month you are viewing.',
            )
          else
            for (final txn in items) ...[
              TxnTile(
                txn: txn,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => TransactionFormScreen(existing: txn),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
        ],
      ),
    );
  }

  bool _inCategory(TxnModel txn) {
    if (txn.hidden || txn.direction != 'expense') return false;
    final id = txn.categoryId ?? '';
    if (categoryId == null || categoryId!.isEmpty) return id.isEmpty;
    return id == categoryId;
  }
}

class MonthSwitcher extends StatelessWidget {
  const MonthSwitcher({
    super.key,
    required this.label,
    required this.onPrevious,
    required this.onNext,
  });

  final String label;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(onPressed: onPrevious, icon: const Icon(Icons.chevron_left)),
        Expanded(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        IconButton(onPressed: onNext, icon: const Icon(Icons.chevron_right)),
      ],
    );
  }
}

class DonutChart extends StatelessWidget {
  const DonutChart({super.key, required this.slices});
  final List<Slice> slices;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = math.min(constraints.maxWidth, constraints.maxHeight);
        final center = Offset(
          constraints.maxWidth / 2,
          constraints.maxHeight / 2,
        );
        final radius = size * 0.34;
        var start = -math.pi / 2;
        final markers = <Widget>[];
        for (var i = 0; i < slices.length && i < 4; i++) {
          final sweep = (slices[i].percent / 100) * math.pi * 2;
          final angle = start + sweep / 2;
          final offset =
              center +
              Offset(math.cos(angle) * radius, math.sin(angle) * radius);
          markers.add(
            Positioned(
              left: offset.dx - 16,
              top: offset.dy - 16,
              child: IconBubble(
                icon: iconFor(slices[i].icon),
                color: colorFromHex(slices[i].color),
                size: 32,
              ),
            ),
          );
          start += sweep;
        }
        return Stack(
          children: [
            CustomPaint(
              size: Size(constraints.maxWidth, constraints.maxHeight),
              painter: _DonutPainter(slices),
            ),
            ...markers,
          ],
        );
      },
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter(this.slices);
  final List<Slice> slices;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) * 0.34;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 28
      ..strokeCap = StrokeCap.butt;
    if (slices.isEmpty) {
      paint.color = FolioColors.line;
      canvas.drawArc(rect, 0, math.pi * 2, false, paint);
      return;
    }
    var start = -math.pi / 2;
    for (final slice in slices) {
      final sweep = (slice.percent / 100) * math.pi * 2;
      paint.color = colorFromHex(slice.color);
      canvas.drawArc(rect, start, math.max(sweep - 0.03, 0.01), false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) =>
      oldDelegate.slices != slices;
}
