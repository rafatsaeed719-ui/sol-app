import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../core/app.dart';
import '../shared/invoice_view.dart';
import 'customer_detail.dart';

typedef Docs = List<QueryDocumentSnapshot<Map<String, dynamic>>>;

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  int days = 30; // 0 = الكل
  Docs invoices = [];
  Docs orders = [];
  Docs products = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() => loading = true);
    final r = await Future.wait([
      scoped('invoices').get(),
      scoped('orders').get(),
      scoped('products').get(),
    ]);
    if (!mounted) return;
    setState(() {
      invoices = r[0].docs;
      orders = r[1].docs;
      products = r[2].docs;
      loading = false;
    });
  }

  bool inRange(dynamic ts) {
    if (days == 0) return true;
    final d = tsToDate(ts);
    if (d == null) return true;
    return d.isAfter(DateTime.now().subtract(Duration(days: days)));
  }

  @override
  Widget build(BuildContext context) {
    // ---------- تجميع ----------
    final prodQty = <String, int>{};
    final prodValue = <String, double>{};
    final prodName = <String, String>{};
    final custValue = <String, double>{};
    final custName = <String, String>{};
    final custInvoices = <String, int>{};
    double sales = 0, profitForShops = 0;
    for (final d in invoices) {
      final m = d.data();
      if (!inRange(m['createdAt'])) continue;
      sales += toD(m['total']) - toD(m['returned']);
      final cid = (m['customerId'] ?? '').toString();
      custValue[cid] = (custValue[cid] ?? 0) + toD(m['total']) - toD(m['returned']);
      custName[cid] = (m['customerName'] ?? '').toString();
      custInvoices[cid] = (custInvoices[cid] ?? 0) + 1;
      for (final it in (m['items'] as List? ?? [])) {
        final pid = (it['productId'] ?? '').toString();
        final q = toI(it['qty']) - toI(it['returnedQty']);
        prodQty[pid] = (prodQty[pid] ?? 0) + q;
        prodValue[pid] = (prodValue[pid] ?? 0) + q * toD(it['unitNet']);
        prodName[pid] = (it['name'] ?? '').toString();
        profitForShops += q * (toD(it['sellPrice']) - toD(it['unitNet']));
      }
    }
    final custOrders = <String, int>{};
    for (final d in orders) {
      final m = d.data();
      if (!inRange(m['createdAt']) || m['status'] == 'cancelled') continue;
      final cid = (m['customerId'] ?? '').toString();
      custOrders[cid] = (custOrders[cid] ?? 0) + 1;
      custName.putIfAbsent(cid, () => (m['shopName'] ?? '').toString());
    }
    final topProducts = prodQty.keys.toList()
      ..sort((a, b) => prodQty[b]!.compareTo(prodQty[a]!));
    final topCustomers = custValue.keys.toList()
      ..sort((a, b) => custValue[b]!.compareTo(custValue[a]!));
    final topOrderers = custOrders.keys.toList()
      ..sort((a, b) => custOrders[b]!.compareTo(custOrders[a]!));
    final stale = products.where((p) => (prodQty[p.id] ?? 0) == 0).toList();
    final maxQ = topProducts.isEmpty ? 1 : prodQty[topProducts.first]!.clamp(1, 1 << 30);

    return Scaffold(
      appBar: AppBar(
        title: const Text('التقارير'),
        actions: [IconButton(onPressed: load, icon: const Icon(Icons.refresh))],
      ),
      body: loading
          ? const Loading()
          : ListView(padding: const EdgeInsets.only(bottom: 30), children: [
              SizedBox(
                height: 52,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.all(8),
                  children: [
                    for (final p in const [
                      [7, 'آخر أسبوع'],
                      [30, 'آخر شهر'],
                      [90, 'آخر 3 شهور'],
                      [365, 'آخر سنة'],
                      [0, 'الكل'],
                    ])
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: ChoiceChip(
                          label: Text(p[1] as String),
                          selected: days == p[0],
                          onSelected: (_) => setState(() => days = p[0] as int),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  childAspectRatio: 2.1,
                  children: [
                    StatTile('صافي المبيعات', money(sales), color: kSuccess, icon: Icons.trending_up),
                    StatTile('عدد الفواتير', '${custInvoices.values.fold(0, (a, b) => a + b)}',
                        icon: Icons.receipt_long),
                    StatTile('قطع اتباعت', '${prodQty.values.fold(0, (a, b) => a + b)}',
                        icon: Icons.inventory),
                    StatTile('مكسب المحلات المتوقع', money(profitForShops),
                        color: kAccent, icon: Icons.storefront),
                  ],
                ),
              ),
              const SectionTitle('🏆 أكتر الأصناف طلباً'),
              if (topProducts.isEmpty) const EmptyView('مفيش مبيعات في الفترة دي'),
              for (final pid in topProducts.take(10))
                Card(
                  child: ListTile(
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) =>
                                ProductMovement(productId: pid, name: prodName[pid] ?? ''))),
                    title: Text(prodName[pid] ?? ''),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: LinearProgressIndicator(
                        value: prodQty[pid]! / maxQ,
                        minHeight: 8,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('${prodQty[pid]} قطعة',
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                        Text(money(prodValue[pid]), style: const TextStyle(fontSize: 11)),
                      ],
                    ),
                  ),
                ),
              const SectionTitle('💰 أكتر العملاء شراءً'),
              for (final (i, cid) in topCustomers.take(10).indexed)
                Card(
                  child: ListTile(
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => CustomerDetail(customerId: cid))),
                    leading: CircleAvatar(
                      backgroundColor: i < 3 ? kAccent : kPrimary.withValues(alpha: 0.1),
                      child: Text('${i + 1}'),
                    ),
                    title: Text(custName[cid] ?? ''),
                    subtitle: Text('${custInvoices[cid] ?? 0} فاتورة'),
                    trailing: Text(money(custValue[cid]),
                        style: const TextStyle(fontWeight: FontWeight.bold, color: kSuccess)),
                  ),
                ),
              const SectionTitle('🛒 أكتر العملاء طلباً من التطبيق'),
              if (topOrderers.isEmpty) const EmptyView('مفيش طلبات في الفترة دي'),
              for (final cid in topOrderers.take(10))
                Card(
                  child: ListTile(
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => CustomerDetail(customerId: cid))),
                    leading: const Icon(Icons.shopping_cart, color: kAccent),
                    title: Text(custName[cid] ?? ''),
                    trailing: Text('${custOrders[cid]} طلب',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              SectionTitle('😴 أصناف ماتحركتش (${stale.length})'),
              for (final p in stale.take(20))
                Card(
                  child: ListTile(
                    dense: true,
                    leading: const Icon(Icons.inventory_2_outlined, color: Colors.grey),
                    title: Text(p.data()['name'] ?? ''),
                  ),
                ),
            ]),
    );
  }
}

/// حركة صنف: كل الفواتير والمرتجعات اللي فيها الصنف
class ProductMovement extends StatelessWidget {
  final String productId;
  final String name;
  const ProductMovement({super.key, required this.productId, required this.name});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('حركة: $name')),
      body: FutureBuilder(
        future: Future.wait([
          scoped('invoices').get(),
          scoped('returns').get(),
        ]),
        builder: (context, snap) {
          if (snap.hasError) return EmptyView('${snap.error}');
          if (!snap.hasData) return const Loading();
          final rows = <Map<String, dynamic>>[];
          for (final d in snap.data![0].docs) {
            final m = d.data();
            for (final it in (m['items'] as List? ?? [])) {
              if (it['productId'] != productId) continue;
              rows.add({
                'type': 'out',
                'date': tsToDate(m['createdAt']) ?? DateTime.now(),
                'customer': m['customerName'],
                'customerId': m['customerId'],
                'qty': toI(it['qty']),
                'price': toD(it['unitNet']),
                'invoiceId': d.id,
                'number': m['number'],
              });
            }
          }
          for (final d in snap.data![1].docs) {
            final m = d.data();
            for (final it in (m['items'] as List? ?? [])) {
              if (it['productId'] != productId) continue;
              rows.add({
                'type': 'ret',
                'date': tsToDate(m['createdAt']) ?? DateTime.now(),
                'customer': m['customerName'],
                'customerId': m['customerId'],
                'qty': toI(it['qty']),
                'price': toD(it['unitNet']),
                'invoiceId': m['invoiceId'],
                'number': m['invoiceNumber'],
              });
            }
          }
          rows.sort((a, b) => (b['date'] as DateTime).compareTo(a['date'] as DateTime));
          final out = rows.where((r) => r['type'] == 'out').fold(0, (a, r) => a + (r['qty'] as int));
          final ret = rows.where((r) => r['type'] == 'ret').fold(0, (a, r) => a + (r['qty'] as int));
          final buyers = <String, int>{};
          final buyerName = <String, String>{};
          for (final r in rows) {
            final sign = r['type'] == 'out' ? 1 : -1;
            final cid = (r['customerId'] ?? '').toString();
            buyers[cid] = (buyers[cid] ?? 0) + sign * (r['qty'] as int);
            buyerName[cid] = (r['customer'] ?? '').toString();
          }
          final topBuyers = buyers.keys.toList()
            ..sort((a, b) => buyers[b]!.compareTo(buyers[a]!));
          if (rows.isEmpty) return const EmptyView('الصنف ده ماتحركش لسه');
          return ListView(padding: const EdgeInsets.only(bottom: 30), children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(children: [
                Expanded(child: StatTile('اتباع', '$out', icon: Icons.north_east, color: kSuccess)),
                Expanded(child: StatTile('مرتجع', '$ret', icon: Icons.south_west, color: Colors.blue)),
                Expanded(child: StatTile('الصافي', '${out - ret}', icon: Icons.inventory)),
              ]),
            ),
            const SectionTitle('أكتر محلات بتطلبه'),
            for (final cid in topBuyers.take(5))
              Card(
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.storefront),
                  title: Text(buyerName[cid] ?? ''),
                  trailing: Text('${buyers[cid]} قطعة',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            const SectionTitle('الحركة بالتفصيل'),
            for (final r in rows)
              Card(
                child: ListTile(
                  dense: true,
                  onTap: r['invoiceId'] == null
                      ? null
                      : () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => InvoiceScreen(invoiceId: r['invoiceId']))),
                  leading: Icon(
                    r['type'] == 'out' ? Icons.north_east : Icons.south_west,
                    color: r['type'] == 'out' ? kSuccess : Colors.blue,
                  ),
                  title: Text(
                      '${r['type'] == 'out' ? 'بيع' : 'مرتجع'} ${r['qty']} قطعة — ${r['customer']}'),
                  subtitle: Text(
                      '${fmtDate(r['date'])} • فاتورة ${r['number']} • ${money(r['price'])} للقطعة'),
                ),
              ),
          ]);
        },
      ),
    );
  }
}
