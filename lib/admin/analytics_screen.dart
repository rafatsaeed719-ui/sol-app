import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../core/app.dart';
import 'expenses_screen.dart' show kMonths;

typedef _Docs = List<QueryDocumentSnapshot<Map<String, dynamic>>>;

// ألوان الرسومات (متناسقة مع البراند)
const Color cSales = Color(0xFFC9A54C); // دهبي
const Color cPaid = Color(0xFF1E8449); // أخضر
const Color cExpense = Color(0xFFC0392B); // أحمر
const List<Color> kPieColors = [
  Color(0xFFC9A54C),
  Color(0xFF141414),
  Color(0xFF8C6D2C),
  Color(0xFF5D6D7E),
  Color(0xFFE5C877),
  Color(0xFFBFC9CA),
];

String shortMoney(double v) {
  if (v.abs() >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}م';
  if (v.abs() >= 1000) return '${(v / 1000).toStringAsFixed(v.abs() >= 10000 ? 0 : 1)}ك';
  return v.toStringAsFixed(0);
}

/// رسم أعمدة بسيط (قيمة لكل خانة)
class BarsChart extends StatelessWidget {
  final List<double> values;
  final List<String> labels;
  final List<double>? values2; // عمود تاني جنب الأول (للمقارنة)
  final Color color;
  final Color color2;
  final double height;
  final int labelEvery;
  const BarsChart({
    super.key,
    required this.values,
    required this.labels,
    this.values2,
    this.color = cSales,
    this.color2 = cExpense,
    this.height = 200,
    this.labelEvery = 1,
  });

  @override
  Widget build(BuildContext context) {
    final all = [...values, ...?values2];
    final maxY = all.isEmpty ? 1.0 : math.max(1.0, all.reduce(math.max)) * 1.15;
    final pair = values2 != null;
    final w = pair ? 7.0 : (values.length > 20 ? 6.0 : 14.0);
    return SizedBox(
      height: height,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: BarChart(
          BarChartData(
            maxY: maxY,
            alignment: BarChartAlignment.spaceAround,
            gridData: FlGridData(
              drawVerticalLine: false,
              horizontalInterval: maxY / 4,
              getDrawingHorizontalLine: (_) =>
                  FlLine(color: Colors.grey.shade200, strokeWidth: 1),
            ),
            borderData: FlBorderData(show: false),
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipColor: (_) => kPrimary,
                getTooltipItem: (g, gi, rod, ri) => BarTooltipItem(
                  '${labels[g.x]}\n${money(rod.toY)}',
                  const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 38,
                  interval: maxY / 4,
                  getTitlesWidget: (v, m) => Text(shortMoney(v),
                      style: const TextStyle(fontSize: 10, color: Colors.black54)),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 24,
                  getTitlesWidget: (v, m) {
                    final i = v.toInt();
                    if (i < 0 || i >= labels.length || i % labelEvery != 0) {
                      return const SizedBox();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(labels[i],
                          style: const TextStyle(fontSize: 10, color: Colors.black54)),
                    );
                  },
                ),
              ),
            ),
            barGroups: [
              for (var i = 0; i < values.length; i++)
                BarChartGroupData(x: i, barsSpace: 2, barRods: [
                  BarChartRodData(
                      toY: values[i],
                      color: color,
                      width: w,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(4))),
                  if (pair)
                    BarChartRodData(
                        toY: values2![i],
                        color: color2,
                        width: w,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(4))),
                ]),
            ],
          ),
        ),
      ),
    );
  }
}

/// رسم خطي
class TrendLine extends StatelessWidget {
  final List<double> values;
  final List<String> labels;
  final Color color;
  final double height;
  final int labelEvery;
  const TrendLine(
      {super.key,
      required this.values,
      required this.labels,
      this.color = cSales,
      this.height = 180,
      this.labelEvery = 1});

  @override
  Widget build(BuildContext context) {
    final maxY = values.isEmpty ? 1.0 : math.max(1.0, values.reduce(math.max)) * 1.15;
    return SizedBox(
      height: height,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: LineChart(LineChartData(
          minY: 0,
          maxY: maxY,
          gridData: FlGridData(
            drawVerticalLine: false,
            horizontalInterval: maxY / 4,
            getDrawingHorizontalLine: (_) => FlLine(color: Colors.grey.shade200, strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => kPrimary,
              getTooltipItems: (spots) => [
                for (final s in spots)
                  LineTooltipItem('${labels[s.x.toInt()]}\n${s.y.toStringAsFixed(0)}',
                      const TextStyle(color: Colors.white, fontSize: 12)),
              ],
            ),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 32,
                interval: maxY / 4,
                getTitlesWidget: (v, m) => Text(shortMoney(v),
                    style: const TextStyle(fontSize: 10, color: Colors.black54)),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                interval: 1,
                getTitlesWidget: (v, m) {
                  final i = v.toInt();
                  if (i < 0 || i >= labels.length || i % labelEvery != 0) return const SizedBox();
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(labels[i],
                        style: const TextStyle(fontSize: 10, color: Colors.black54)),
                  );
                },
              ),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: [for (var i = 0; i < values.length; i++) FlSpot(i.toDouble(), values[i])],
              isCurved: true,
              preventCurveOverShooting: true,
              color: color,
              barWidth: 3,
              dotData: FlDotData(show: values.length <= 14),
              belowBarData: BarAreaData(show: true, color: color.withValues(alpha: 0.15)),
            ),
          ],
        )),
      ),
    );
  }
}

/// دايرة توزيع (مع مفتاح الألوان)
class SharePie extends StatelessWidget {
  final Map<String, double> data;
  const SharePie({super.key, required this.data});
  @override
  Widget build(BuildContext context) {
    final total = data.values.fold(0.0, (a, b) => a + b);
    if (total <= 0) return const EmptyView('مفيش بيانات');
    final entries = data.entries.toList();
    return Row(children: [
      SizedBox(
        width: 150,
        height: 150,
        child: PieChart(PieChartData(
          sectionsSpace: 2,
          centerSpaceRadius: 34,
          sections: [
            for (var i = 0; i < entries.length; i++)
              PieChartSectionData(
                value: entries[i].value,
                color: kPieColors[i % kPieColors.length],
                radius: 38,
                title: '${(entries[i].value / total * 100).round()}%',
                titleStyle: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: i == 1 ? Colors.white : Colors.black87),
              ),
          ],
        )),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (var i = 0; i < entries.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                        color: kPieColors[i % kPieColors.length],
                        borderRadius: BorderRadius.circular(3))),
                const SizedBox(width: 6),
                Expanded(
                    child: Text(entries[i].key,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12))),
                Text(shortMoney(entries[i].value),
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              ]),
            ),
        ]),
      ),
    ]);
  }
}

class _ChartCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;
  final List<Widget> legend;
  const _ChartCard({required this.title, this.subtitle, required this.child, this.legend = const []});
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          if (subtitle != null)
            Text(subtitle!, style: const TextStyle(color: Colors.black54, fontSize: 12)),
          if (legend.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(spacing: 12, children: legend),
          ],
          const SizedBox(height: 12),
          child,
        ]),
      ),
    );
  }
}

Widget legendDot(Color c, String t) => Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 10, height: 10, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
      const SizedBox(width: 4),
      Text(t, style: const TextStyle(fontSize: 12)),
    ]);

/// تجميع قيم على أيام
List<double> perDay(_Docs docs, String dateField, double Function(Map<String, dynamic>) val, int days) {
  final now = DateTime.now();
  final start = DateTime(now.year, now.month, now.day).subtract(Duration(days: days - 1));
  final out = List<double>.filled(days, 0);
  for (final d in docs) {
    final t = tsToDate(d.data()[dateField]);
    if (t == null || t.isBefore(start)) continue;
    final i = DateTime(t.year, t.month, t.day).difference(start).inDays;
    if (i >= 0 && i < days) out[i] += val(d.data());
  }
  return out;
}

/// تجميع قيم على شهور
List<double> perMonth(_Docs docs, String dateField, double Function(Map<String, dynamic>) val, int months) {
  final now = DateTime.now();
  final start = DateTime(now.year, now.month - months + 1);
  final out = List<double>.filled(months, 0);
  for (final d in docs) {
    final t = tsToDate(d.data()[dateField]);
    if (t == null || t.isBefore(start)) continue;
    final i = (t.year - start.year) * 12 + t.month - start.month;
    if (i >= 0 && i < months) out[i] += val(d.data());
  }
  return out;
}

List<String> dayLabels(int days) {
  final now = DateTime.now();
  final start = DateTime(now.year, now.month, now.day).subtract(Duration(days: days - 1));
  return [for (var i = 0; i < days; i++) '${start.add(Duration(days: i)).day}'];
}

List<String> monthLabels(int months) {
  final now = DateTime.now();
  return [
    for (var i = months - 1; i >= 0; i--)
      kMonths[(DateTime(now.year, now.month - i).month - 1)].substring(0, 3)
  ];
}

double _net(Map<String, dynamic> m) => toD(m['total']) - toD(m['returned']);

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});
  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  bool loading = true;
  _Docs invoices = [], payments = [], expenses = [], orders = [], visits = [];
  int days = 30;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() => loading = true);
    final r = await Future.wait([
      scoped('invoices').get(),
      scoped('payments').get(),
      scoped('expenses').get(),
      scoped('orders').get(),
      scoped('visits').get(),
    ]);
    if (!mounted) return;
    setState(() {
      invoices = r[0].docs;
      payments = r[1].docs;
      expenses = r[2].docs;
      orders = r[3].docs;
      visits = r[4].docs;
      loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('الرسومات البيانية'),
        actions: [IconButton(onPressed: load, icon: const Icon(Icons.refresh))],
      ),
      body: loading ? const Loading() : _body(),
    );
  }

  Widget _body() {
    final sales = perDay(invoices, 'createdAt', _net, days);
    final dLabels = dayLabels(days);
    final every = days > 14 ? 5 : 1;
    final totalSales = sales.fold(0.0, (a, b) => a + b);
    final ordersPerDay = perDay(orders, 'createdAt', (_) => 1, days);

    const months = 6;
    final mPaid = perMonth(payments, 'createdAt', (m) => toD(m['amount']), months);
    final mExp = perMonth(expenses, 'date', (m) => toD(m['amount']), months);
    final mSales = perMonth(invoices, 'createdAt', _net, months);
    final mLabels = monthLabels(months);

    // توزيع المبيعات على الأصناف والعملاء في الفترة
    final from = DateTime.now().subtract(Duration(days: days));
    final byProduct = <String, double>{};
    final byCustomer = <String, double>{};
    for (final d in invoices) {
      final m = d.data();
      if ((tsToDate(m['createdAt']) ?? DateTime.now()).isBefore(from)) continue;
      final c = (m['customerName'] ?? '').toString();
      byCustomer[c] = (byCustomer[c] ?? 0) + _net(m);
      for (final it in (m['items'] as List? ?? [])) {
        final n = (it['name'] ?? '').toString();
        final q = toI(it['qty']) - toI(it['returnedQty']);
        byProduct[n] = (byProduct[n] ?? 0) + q * toD(it['unitNet']);
      }
    }
    Map<String, double> top(Map<String, double> m) {
      final e = m.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      final out = <String, double>{for (final x in e.take(5)) x.key: x.value};
      final rest = e.skip(5).fold(0.0, (a, x) => a + x.value);
      if (rest > 0) out['الباقي'] = rest;
      return out;
    }

    final expByCat = <String, double>{};
    for (final d in expenses) {
      final m = d.data();
      if ((tsToDate(m['date']) ?? DateTime.now()).isBefore(from)) continue;
      final c = (m['category'] ?? 'أخرى').toString();
      expByCat[c] = (expByCat[c] ?? 0) + toD(m['amount']);
    }
    final visitsPerDay = perDay(visits, 'createdAt', (_) => 1, days);

    return ListView(padding: const EdgeInsets.only(bottom: 30), children: [
      SizedBox(
        height: 50,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.all(6),
          children: [
            for (final p in const [
              [7, 'آخر أسبوع'],
              [30, 'آخر شهر'],
              [90, 'آخر 3 شهور'],
            ])
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ChoiceChip(
                    label: Text(p[1] as String),
                    selected: days == p[0],
                    onSelected: (_) => setState(() => days = p[0] as int)),
              ),
          ],
        ),
      ),
      _ChartCard(
        title: 'المبيعات اليومية',
        subtitle: 'الإجمالي ${money(totalSales)} • متوسط اليوم ${money(totalSales / days)}',
        child: days > 30
            ? TrendLine(values: sales, labels: dLabels, labelEvery: 15)
            : BarsChart(values: sales, labels: dLabels, labelEvery: every),
      ),
      _ChartCard(
        title: 'التحصيل قصاد المصروفات (آخر 6 شهور)',
        legend: [legendDot(cPaid, 'التحصيل'), legendDot(cExpense, 'المصروفات')],
        child: BarsChart(
            values: mPaid, values2: mExp, labels: mLabels, color: cPaid, color2: cExpense),
      ),
      _ChartCard(
        title: 'المبيعات بالشهر',
        child: TrendLine(values: mSales, labels: mLabels),
      ),
      _ChartCard(
        title: 'أكتر الأصناف مبيعاً',
        subtitle: 'بقيمة الجملة في الفترة',
        child: SharePie(data: top(byProduct)),
      ),
      _ChartCard(
        title: 'أكتر العملاء شراءً',
        child: SharePie(data: top(byCustomer)),
      ),
      if (expByCat.isNotEmpty)
        _ChartCard(
          title: 'المصروفات على إيه',
          child: SharePie(data: top(expByCat)),
        ),
      _ChartCard(
        title: 'عدد الطلبات من التطبيق',
        subtitle: 'الإجمالي ${ordersPerDay.fold(0.0, (a, b) => a + b).toInt()} طلب',
        child: TrendLine(
            values: ordersPerDay, labels: dLabels, color: kPrimary, labelEvery: days > 14 ? 5 : 1),
      ),
      _ChartCard(
        title: 'الزيارات',
        subtitle: 'الإجمالي ${visitsPerDay.fold(0.0, (a, b) => a + b).toInt()} زيارة',
        child: BarsChart(
            values: visitsPerDay, labels: dLabels, color: kPrimary, labelEvery: every, height: 150),
      ),
    ]);
  }
}

/// رسم صغير لمبيعات آخر 7 أيام (للوحة الرئيسية)
class WeekSalesCard extends StatelessWidget {
  const WeekSalesCard({super.key});
  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: scoped('invoices').snapshots(),
      builder: (context, s) {
        final docs = s.data?.docs ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        final v = perDay(docs, 'createdAt', _net, 7);
        final now = DateTime.now();
        const names = ['اثنين', 'ثلاثاء', 'أربعاء', 'خميس', 'جمعة', 'سبت', 'أحد'];
        final labels = [
          for (var i = 6; i >= 0; i--) names[now.subtract(Duration(days: i)).weekday - 1]
        ];
        return Card(
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const AnalyticsScreen())),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  const Text('مبيعات آخر 7 أيام',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const Spacer(),
                  Text(money(v.fold(0.0, (a, b) => a + b)),
                      style: const TextStyle(fontWeight: FontWeight.bold, color: kSuccess)),
                  const Icon(Icons.chevron_left, color: Colors.black38),
                ]),
                const SizedBox(height: 8),
                BarsChart(values: v, labels: labels, height: 140),
              ]),
            ),
          ),
        );
      },
    );
  }
}
