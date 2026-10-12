import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../auth/location_picker.dart';
import '../core/app.dart';
import '../core/data.dart';
import '../customer/my_orders_screen.dart';
import '../shared/chat_screen.dart';
import '../shared/invoice_view.dart';
import 'customer_accounts.dart';
import 'dashboard_screen.dart';
import 'invoice_form.dart';

class CustomerDetail extends StatelessWidget {
  final String customerId;
  const CustomerDetail({super.key, required this.customerId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: db.collection('users').doc(customerId).snapshots(),
      builder: (context, us) {
        final m = us.data?.data();
        if (m == null) {
          return Scaffold(
              appBar: AppBar(),
              body: us.hasData ? const EmptyView('العميل مش موجود') : const Loading());
        }
        final name = (m['shopName'] ?? '').toString();
        return DefaultTabController(
          length: 3,
          child: Scaffold(
            appBar: AppBar(
              title: Text(name),
              actions: [
                IconButton(
                  tooltip: 'شات',
                  onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => ChatScreen(customerId: customerId, title: name))),
                  icon: const Icon(Icons.chat),
                ),
              ],
              bottom: const TabBar(
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white70,
                indicatorColor: kAccent,
                tabs: [Tab(text: 'البيانات'), Tab(text: 'الفواتير'), Tab(text: 'الطلبات')],
              ),
            ),
            floatingActionButton: FloatingActionButton.extended(
              onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) =>
                          InvoiceForm(customerId: customerId, customerName: name))),
              icon: const Icon(Icons.add),
              label: const Text('فاتورة جديدة'),
            ),
            body: TabBarView(children: [
              _Profile(customerId: customerId, m: m),
              _Invoices(customerId: customerId),
              _Orders(customerId: customerId),
            ]),
          ),
        );
      },
    );
  }
}

class _Profile extends StatelessWidget {
  final String customerId;
  final Map<String, dynamic> m;
  const _Profile({required this.customerId, required this.m});

  Future<void> setDays(BuildContext context) async {
    final c = TextEditingController(
        text: m['collectionDays'] == null ? '' : '${toI(m['collectionDays'])}');
    final r = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('أيام التحصيل للعميل ده'),
        content: TextField(
          controller: c,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
              labelText: 'عدد الأيام', helperText: 'سيبها فاضية عشان ياخد الافتراضي'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(d, c.text), child: const Text('حفظ')),
        ],
      ),
    );
    if (r == null) return;
    await db.collection('users').doc(customerId).update(
        {'collectionDays': r.trim().isEmpty ? FieldValue.delete() : toI(r)});
  }

  Future<void> adjustPoints(BuildContext context) async {
    final c = TextEditingController(text: '${toI(m['points'])}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('تعديل النقاط'),
        content: TextField(
          controller: c,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'عدد النقاط'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('حفظ')),
        ],
      ),
    );
    if (ok == true) {
      await db.collection('users').doc(customerId).update({'points': toI(c.text)});
    }
  }

  @override
  Widget build(BuildContext context) {
    final phone = (m['phone'] ?? '').toString();
    return ListView(padding: const EdgeInsets.only(bottom: 90), children: [
      const SizedBox(height: 12),
      Center(child: Avatar(m['photo'], radius: 50)),
      const SizedBox(height: 8),
      Center(
        child: Text(m['shopName'] ?? '',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      ),
      Center(child: Text(m['ownerName'] ?? '')),
      const SizedBox(height: 8),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        FilledButton.tonalIcon(
            onPressed: () => callPhone(phone),
            icon: const Icon(Icons.call),
            label: const Text('اتصال')),
        const SizedBox(width: 8),
        FilledButton.tonalIcon(
            onPressed: () => whatsapp(phone, 'أهلاً ${m['ownerName'] ?? ''}، معاك SOL'),
            icon: const Icon(Icons.message),
            label: const Text('واتساب')),
      ]),
      Card(
        margin: const EdgeInsets.all(12),
        child: Column(children: [
          ListTile(
              leading: const Icon(Icons.phone),
              title: Text(phone, textDirection: TextDirection.ltr)),
          if (m['createdByAdmin'] != true)
            ListTile(leading: const Icon(Icons.email), title: Text(m['email'] ?? '')),
          if ((m['address'] ?? '').toString().isNotEmpty)
            ListTile(leading: const Icon(Icons.home), title: Text(m['address'])),
          ListTile(
            leading: const Icon(Icons.stars, color: kAccent),
            title: Text('النقاط: ${toI(m['points'])}'),
            trailing: TextButton(
                onPressed: () => adjustPoints(context), child: const Text('تعديل')),
          ),
          ListTile(
            leading: const Icon(Icons.timer_outlined),
            title: Text(m['collectionDays'] == null
                ? 'أيام التحصيل: الافتراضي من الإعدادات'
                : 'أيام التحصيل: ${toI(m['collectionDays'])} يوم'),
            trailing: TextButton(
                onPressed: () => setDays(context), child: const Text('تعديل')),
          ),
          ListTile(
              leading: const Icon(Icons.calendar_today),
              title: Text('مسجّل من ${fmtDate(m['createdAt'])}')),
        ]),
      ),
      CredentialsCard(customerId: customerId, m: m),
      Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: SwitchListTile(
          value: m['disabled'] != true,
          activeColor: kSuccess,
          title: Text(m['disabled'] == true ? 'الحساب موقوف' : 'الحساب شغال',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: m['disabled'] == true ? kDanger : kSuccess)),
          subtitle: const Text('لو وقفته مش هيقدر يدخل التطبيق'),
          onChanged: (v) =>
              db.collection('users').doc(customerId).update({'disabled': !v}),
        ),
      ),
      StreamBuilder(
        stream: scoped('invoices').where('customerId', isEqualTo: customerId).snapshots(),
        builder: (context, s) {
          final sum = summarize((s.data?.docs ??
                  <QueryDocumentSnapshot<Map<String, dynamic>>>[])
              .map((e) => e.data()));
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 2.1,
              children: [
                StatTile('إجمالي المشتريات', money(sum.total), icon: Icons.receipt_long),
                StatTile('المدفوع', money(sum.paid),
                    color: kSuccess, icon: Icons.check_circle_outline),
                StatTile('المرتجعات', money(sum.returned),
                    color: Colors.blue, icon: Icons.assignment_return),
                StatTile('عليه', money(sum.balance),
                    color: sum.balance > 0 ? Colors.orange : kSuccess,
                    icon: Icons.account_balance_wallet),
                if (sum.overdueCount > 0)
                  StatTile('متأخر', money(sum.overdue),
                      color: kDanger, icon: Icons.warning_amber),
              ],
            ),
          );
        },
      ),
      if (m['lat'] != null) ...[
        const SectionTitle('موقع المحل'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: ShopMap(lat: toD(m['lat']), lng: toD(m['lng'])),
        ),
      ],
    ]);
  }
}

class _Invoices extends StatelessWidget {
  final String customerId;
  const _Invoices({required this.customerId});
  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: scoped('invoices').where('customerId', isEqualTo: customerId).snapshots(),
      builder: (context, s) {
        if (!s.hasData) return const Loading();
        final docs = sortByDate(s.data!.docs);
        if (docs.isEmpty) return const EmptyView('مفيش فواتير');
        return ListView(
          padding: const EdgeInsets.only(top: 8, bottom: 90),
          children: docs.map((d) => InvoiceTile(d.id, d.data())).toList(),
        );
      },
    );
  }
}

class _Orders extends StatelessWidget {
  final String customerId;
  const _Orders({required this.customerId});
  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: scoped('orders').where('customerId', isEqualTo: customerId).snapshots(),
      builder: (context, s) {
        if (!s.hasData) return const Loading();
        final docs = sortByDate(s.data!.docs);
        if (docs.isEmpty) return const EmptyView('مفيش طلبات');
        return ListView(
          padding: const EdgeInsets.only(top: 8, bottom: 90),
          children: docs.map((d) => OrderCard(d.id, d.data())).toList(),
        );
      },
    );
  }
}
