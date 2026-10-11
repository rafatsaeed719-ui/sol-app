import 'package:flutter/material.dart';

import '../core/app.dart';
import '../core/data.dart';
import '../customer/my_orders_screen.dart';
import 'customer_detail.dart';
import 'invoice_form.dart';

class OrdersAdmin extends StatelessWidget {
  const OrdersAdmin({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Column(children: [
        const TabBar(
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            Tab(text: 'جديدة'),
            Tab(text: 'مقبولة'),
            Tab(text: 'اتفوترت'),
            Tab(text: 'ملغية'),
          ],
        ),
        Expanded(
          child: StreamBuilder(
            stream: scoped('orders').snapshots(),
            builder: (context, snap) {
              if (snap.hasError) return EmptyView('حصلت مشكلة: ${snap.error}');
              if (!snap.hasData) return const Loading();
              final all = sortByDate(snap.data!.docs);
              Widget list(String status) {
                final l = all.where((d) => (d.data()['status'] ?? 'new') == status).toList();
                if (l.isEmpty) return const EmptyView('مفيش طلبات هنا');
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: l.length,
                  itemBuilder: (c, i) => OrderCard(
                    l[i].id,
                    l[i].data(),
                    showShop: true,
                    adminActions: _actions(context, l[i].id, l[i].data()),
                  ),
                );
              }

              return TabBarView(children: [
                list('new'),
                list('accepted'),
                list('invoiced'),
                list('cancelled'),
              ]);
            },
          ),
        ),
      ]),
    );
  }

  Widget _actions(BuildContext context, String id, Map<String, dynamic> d) {
    final status = d['status'] ?? 'new';
    return Wrap(spacing: 8, runSpacing: 4, children: [
      if (status == 'new')
        OutlinedButton.icon(
          onPressed: () async {
            await db.collection('orders').doc(id).update({'status': 'accepted'});
            await notify(d['customerId'], 'طلبك اتقبل ✔',
                'طلبك بقيمة ${money(d['total'])} اتقبل وهنوصّله قريب',
                type: 'order', refId: id);
          },
          icon: const Icon(Icons.check),
          label: const Text('قبول'),
        ),
      if (status == 'new' || status == 'accepted')
        FilledButton.icon(
          onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => InvoiceForm(
                        customerId: d['customerId'],
                        customerName: d['shopName'] ?? d['customerName'] ?? '',
                        orderId: id,
                        orderItems: List<Map<String, dynamic>>.from(
                            (d['items'] as List).map((e) => Map<String, dynamic>.from(e))),
                      ))),
          icon: const Icon(Icons.receipt_long),
          label: const Text('اعمل فاتورة'),
        ),
      OutlinedButton.icon(
        onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => CustomerDetail(customerId: d['customerId']))),
        icon: const Icon(Icons.storefront),
        label: const Text('العميل'),
      ),
      if (status == 'new' || status == 'accepted')
        TextButton.icon(
          style: TextButton.styleFrom(foregroundColor: kDanger),
          onPressed: () async {
            if (!await confirm(context, 'إلغاء الطلب', 'متأكد؟')) return;
            await db.collection('orders').doc(id).update({'status': 'cancelled'});
            await notify(d['customerId'], 'طلبك اتلغى',
                'للأسف طلبك بقيمة ${money(d['total'])} اتلغى — كلّمنا لو محتاج حاجة',
                type: 'order', refId: id);
          },
          icon: const Icon(Icons.cancel_outlined),
          label: const Text('إلغاء'),
        ),
    ]);
  }
}
