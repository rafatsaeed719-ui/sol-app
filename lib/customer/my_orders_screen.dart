import 'package:flutter/material.dart';

import '../core/app.dart';
import '../core/data.dart';
import '../shared/invoice_view.dart';

class MyOrdersScreen extends StatelessWidget {
  const MyOrdersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: scoped('orders').where('customerId', isEqualTo: uid).snapshots(),
      builder: (context, snap) {
        if (snap.hasError) return EmptyView('حصلت مشكلة: ${snap.error}');
        if (!snap.hasData) return const Loading();
        final list = sortByDate(snap.data!.docs);
        if (list.isEmpty) {
          return const EmptyView('لسه مطلبتش حاجة', icon: Icons.receipt_outlined);
        }
        return ListView.builder(
          padding: const EdgeInsets.only(top: 8, bottom: 20),
          itemCount: list.length,
          itemBuilder: (c, i) => OrderCard(list[i].id, list[i].data()),
        );
      },
    );
  }
}

/// كارت الطلب — مستخدم عند العميل والمدير
class OrderCard extends StatelessWidget {
  final String id;
  final Map<String, dynamic> d;
  final Widget? adminActions;
  final bool showShop;
  const OrderCard(this.id, this.d, {super.key, this.adminActions, this.showShop = false});

  @override
  Widget build(BuildContext context) {
    final items = (d['items'] as List? ?? []);
    final status = d['status'] ?? 'new';
    return Card(
      child: ExpansionTile(
        shape: const Border(),
        title: Row(children: [
          Expanded(
            child: Text(
                showShop ? '${d['shopName'] ?? ''}' : 'طلب ${fmtDate(d['createdAt'])}',
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          statusChip(status),
        ]),
        subtitle: Text(
            '${showShop ? '${fmtDate(d['createdAt'], time: true)} • ' : ''}${items.length} صنف • ${money(d['total'])}'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final it in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(children: [
                Expanded(child: Text('${it['name']}')),
                Text('${it['qty']} × ${money(it['unitNet'])}',
                    style: const TextStyle(color: Colors.black54)),
              ]),
            ),
          if ((d['note'] ?? '').toString().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('📝 ${d['note']}', style: const TextStyle(color: Colors.black54)),
            ),
          if (d['invoiceId'] != null)
            TextButton.icon(
              onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => InvoiceScreen(invoiceId: d['invoiceId']))),
              icon: const Icon(Icons.receipt_long),
              label: Text('عرض الفاتورة رقم ${d['invoiceNumber'] ?? ''}'),
            ),
          if (!isAdmin && status == 'new')
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: kDanger),
              onPressed: () async {
                if (!await confirm(context, 'إلغاء الطلب', 'متأكد إنك عاوز تلغي الطلب؟')) {
                  return;
                }
                await db.collection('orders').doc(id).update({'status': 'cancelled'});
                await notify('admin', 'طلب اتلغى',
                    '${d['shopName'] ?? ''} لغى طلب بقيمة ${money(d['total'])}',
                    type: 'order', refId: id);
              },
              icon: const Icon(Icons.cancel_outlined),
              label: const Text('إلغاء الطلب'),
            ),
          if (adminActions != null) adminActions!,
        ],
      ),
    );
  }
}
