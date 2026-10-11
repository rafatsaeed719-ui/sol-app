import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app.dart';
import '../core/data.dart';
import '../shared/invoice_view.dart';
import 'customer_detail.dart';
import 'expenses_screen.dart';
import 'warehouse_screen.dart';

class DashboardScreen extends StatelessWidget {
  final void Function(int tab) onGo;
  const DashboardScreen({super.key, required this.onGo});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: scoped('invoices').snapshots(),
      builder: (context, inv) {
        if (inv.hasError) return EmptyView('حصلت مشكلة: ${inv.error}');
        if (!inv.hasData) return const Loading();
        final invoices = inv.data!.docs;
        final s = summarize(invoices.map((e) => e.data()));
        final overdue = invoices.where((d) => isOverdue(d.data())).toList()
          ..sort((a, b) => daysLate(b.data()).compareTo(daysLate(a.data())));
        final now = DateTime.now();
        final monthStart = DateTime(now.year, now.month);
        final monthSales = invoices
            .where((d) => (tsToDate(d.data()['createdAt']) ?? now).isAfter(monthStart))
            .fold(0.0, (a, d) => a + toD(d.data()['total']));
        return ListView(padding: const EdgeInsets.only(bottom: 30), children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: StreamBuilder(
              stream: scoped('orders').where('status', isEqualTo: 'new').snapshots(),
              builder: (context, o) {
                final newOrders = o.data?.docs.length ?? 0;
                return StreamBuilder(
                  stream: scoped('users').snapshots(),
                  builder: (context, u) {
                    final customers = (u.data?.docs ?? [])
                        .where((d) => d.data()['role'] != 'owner')
                        .length;
                    return GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      childAspectRatio: 2.0,
                      children: [
                        StatTile('طلبات جديدة', '$newOrders',
                            color: newOrders > 0 ? kAccent : kPrimary,
                            icon: Icons.shopping_cart,
                            onTap: () => onGo(1)),
                        StatTile('العملاء', '$customers',
                            icon: Icons.storefront, onTap: () => onGo(2)),
                        StatTile('مبيعات الشهر', money(monthSales),
                            color: kSuccess, icon: Icons.trending_up),
                        StatTile('فلوس برّه (على العملاء)', money(s.balance),
                            color: Colors.orange, icon: Icons.account_balance_wallet),
                        StatTile('متأخرات', money(s.overdue),
                            color: kDanger, icon: Icons.warning_amber),
                        StatTile('إجمالي المحصّل', money(s.paid),
                            color: kSuccess, icon: Icons.payments),
                      ],
                    );
                  },
                );
              },
            ),
          ),
          // المصروفات والتحصيل الشهر ده
          StreamBuilder(
            stream: scoped('expenses').snapshots(),
            builder: (context, ex) {
              final monthExp = (ex.data?.docs ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[])
                  .where((d) => (tsToDate(d.data()['date']) ?? now).isAfter(monthStart))
                  .fold(0.0, (a, d) => a + toD(d.data()['amount']));
              return StreamBuilder(
                stream: scoped('payments').snapshots(),
                builder: (context, ps) {
                  final monthPaid = (ps.data?.docs ??
                          <QueryDocumentSnapshot<Map<String, dynamic>>>[])
                      .where((d) => (tsToDate(d.data()['createdAt']) ?? now).isAfter(monthStart))
                      .fold(0.0, (a, d) => a + toD(d.data()['amount']));
                  final net = monthPaid - monthExp;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(children: [
                      Expanded(
                        child: StatTile('مصروفات الشهر', money(monthExp),
                            color: kDanger,
                            icon: Icons.account_balance_wallet,
                            onTap: () => Navigator.push(context,
                                MaterialPageRoute(builder: (_) => const ExpensesScreen()))),
                      ),
                      Expanded(
                        child: StatTile('تحصيل − مصروفات', money(net),
                            color: net >= 0 ? kSuccess : kDanger, icon: Icons.savings),
                      ),
                    ]),
                  );
                },
              );
            },
          ),
          // أصناف قربت تخلص
          StreamBuilder(
            stream: scoped('products').snapshots(),
            builder: (context, ps) {
              final low = (ps.data?.docs ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[])
                  .where((d) {
                final st = stockOf(d.data());
                return st != null && st <= lowOf(d.data());
              }).toList()
                ..sort((a, b) => stockOf(a.data())!.compareTo(stockOf(b.data())!));
              if (low.isEmpty) return const SizedBox();
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                SectionTitle('📦 أصناف قربت تخلص (${low.length})',
                    trailing: TextButton(
                        onPressed: () => Navigator.push(context,
                            MaterialPageRoute(builder: (_) => const WarehouseScreen())),
                        child: const Text('المخزن'))),
                for (final d in low.take(8))
                  Card(
                    color: stockOf(d.data())! <= 0 ? const Color(0xFFFDECEA) : const Color(0xFFFFF4E0),
                    child: ListTile(
                      dense: true,
                      onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  ProductMovesScreen(productId: d.id, product: d.data()))),
                      leading: Icon(
                          stockOf(d.data())! <= 0 ? Icons.remove_shopping_cart : Icons.warning_amber,
                          color: stockOf(d.data())! <= 0 ? kDanger : Colors.orange),
                      title: Text((d.data()['name'] ?? '').toString()),
                      trailing: Text(
                          stockOf(d.data())! <= 0 ? 'خلص' : 'باقي ${stockOf(d.data())}',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
              ]);
            },
          ),
          SectionTitle('⚠️ عملاء عليهم فلوس متأخرة (${overdue.length})'),
          if (overdue.isEmpty)
            const Card(
              child: ListTile(
                leading: Icon(Icons.check_circle, color: kSuccess),
                title: Text('مفيش متأخرات — كله تمام 👌'),
              ),
            ),
          ...overdue.take(30).map((d) {
            final m = d.data();
            return Card(
              color: const Color(0xFFFDF1F0),
              child: ListTile(
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => InvoiceScreen(invoiceId: d.id))),
                leading: const CircleAvatar(
                    backgroundColor: kDanger,
                    child: Icon(Icons.priority_high, color: Colors.white)),
                title: Text('${m['customerName']} عليه ${money(m['balance'])}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(
                    'فاتورة ${m['number']} • متأخرة ${daysLate(m)} يوم (الميعاد ${fmtDate(m['dueDate'])})'),
                trailing: IconButton(
                  tooltip: 'صفحة العميل',
                  icon: const Icon(Icons.person_search, color: kPrimary),
                  onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => CustomerDetail(customerId: m['customerId']))),
                ),
              ),
            );
          }),
          const SectionTitle('آخر الطلبات'),
          StreamBuilder(
            stream: scoped('orders').where('status', isEqualTo: 'new').snapshots(),
            builder: (context, o) {
              final docs = o.hasData
                  ? sortByDate(o.data!.docs)
                  : <QueryDocumentSnapshot<Map<String, dynamic>>>[];
              if (docs.isEmpty) {
                return const Card(
                    child: ListTile(title: Text('مفيش طلبات جديدة مستنية')));
              }
              return Column(
                children: [
                  for (final d in docs.take(5))
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.shopping_cart, color: kAccent),
                        title: Text('${d.data()['shopName']}'),
                        subtitle: Text(
                            '${fmtDate(d.data()['createdAt'], time: true)} • ${money(d.data()['total'])}'),
                        trailing: const Icon(Icons.chevron_left),
                        onTap: () => onGo(1),
                      ),
                    ),
                ],
              );
            },
          ),
        ]);
      },
    );
  }
}

Future<void> callPhone(String phone) =>
    launchUrl(Uri.parse('tel:$phone'), mode: LaunchMode.externalApplication);

Future<void> whatsapp(String phone, [String text = '']) {
  var p = phone.replaceAll(RegExp(r'[^0-9]'), '');
  if (p.startsWith('0')) p = '2$p';
  return launchUrl(Uri.parse('https://wa.me/$p?text=${Uri.encodeComponent(text)}'),
      mode: LaunchMode.externalApplication);
}
