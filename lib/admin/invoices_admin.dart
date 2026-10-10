import 'package:flutter/material.dart';

import '../core/app.dart';
import '../core/data.dart';
import '../shared/invoice_view.dart';

class InvoicesAdmin extends StatefulWidget {
  final bool standalone;
  const InvoicesAdmin({super.key, this.standalone = false});
  @override
  State<InvoicesAdmin> createState() => _InvoicesAdminState();
}

class _InvoicesAdminState extends State<InvoicesAdmin> {
  String filter = 'due';
  String q = '';

  @override
  Widget build(BuildContext context) {
    final body = StreamBuilder(
      stream: db.collection('invoices').snapshots(),
      builder: (context, snap) {
        if (snap.hasError) return EmptyView('حصلت مشكلة: ${snap.error}');
        if (!snap.hasData) return const Loading();
        final all = sortByDate(snap.data!.docs);
        final list = all.where((d) {
          final m = d.data();
          final bal = toD(m['balance']);
          if (filter == 'due' && bal <= 0.009) return false;
          if (filter == 'late' && !isOverdue(m)) return false;
          if (filter == 'paid' && bal > 0.009) return false;
          if (q.isNotEmpty &&
              !'${m['customerName']} ${m['number']}'.toLowerCase().contains(q.toLowerCase())) {
            return false;
          }
          return true;
        }).toList();
        final s = summarize(list.map((e) => e.data()));
        return Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: TextField(
              decoration: const InputDecoration(
                  hintText: 'دوّر باسم العميل أو رقم الفاتورة', prefixIcon: Icon(Icons.search)),
              onChanged: (v) => setState(() => q = v.trim()),
            ),
          ),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                for (final f in const [
                  ['due', 'عليها فلوس'],
                  ['late', 'متأخرة'],
                  ['paid', 'خالصة'],
                  ['all', 'الكل'],
                ])
                  Padding(
                    padding: const EdgeInsets.all(4),
                    child: ChoiceChip(
                      label: Text(f[1]),
                      selected: filter == f[0],
                      onSelected: (_) => setState(() => filter = f[0]),
                    ),
                  ),
              ],
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: kPrimary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10)),
            child: Row(children: [
              Expanded(child: Text('${list.length} فاتورة • إجمالي ${money(s.total)}')),
              Text('متبقي ${money(s.balance)}',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
            ]),
          ),
          Expanded(
            child: list.isEmpty
                ? const EmptyView('مفيش فواتير هنا')
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 20),
                    itemCount: list.length,
                    itemBuilder: (c, i) =>
                        InvoiceTile(list[i].id, list[i].data(), showCustomer: true),
                  ),
          ),
        ]);
      },
    );
    if (!widget.standalone) return body;
    return Scaffold(
      appBar: AppBar(
        title: const Text('الفواتير والتحصيل'),
        actions: [
          IconButton(
            tooltip: 'سجل التحصيلات',
            onPressed: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const PaymentsLog())),
            icon: const Icon(Icons.history),
          ),
        ],
      ),
      body: body,
    );
  }
}

class PaymentsLog extends StatelessWidget {
  const PaymentsLog({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('سجل التحصيلات')),
      body: StreamBuilder(
        stream: db.collection('payments').snapshots(),
        builder: (context, s) {
          if (!s.hasData) return const Loading();
          final docs = sortByDate(s.data!.docs);
          if (docs.isEmpty) return const EmptyView('مفيش تحصيلات لسه');
          final today = fmtDate(DateTime.now());
          final todaySum = docs
              .where((d) => fmtDate(d.data()['createdAt']) == today)
              .fold(0.0, (a, d) => a + toD(d.data()['amount']));
          return ListView(children: [
            Card(
              color: const Color(0xFFE9F7EF),
              child: ListTile(
                leading: const Icon(Icons.today, color: kSuccess),
                title: Text('تحصيل النهارده: ${money(todaySum)}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
            ...docs.map((d) {
              final m = d.data();
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.payments, color: kSuccess),
                  title: Text('${m['customerName']} — ${money(m['amount'])}'),
                  subtitle: Text(
                      'فاتورة ${m['invoiceNumber']} • ${fmtDate(m['createdAt'], time: true)}'),
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => InvoiceScreen(invoiceId: m['invoiceId']))),
                ),
              );
            }),
          ]);
        },
      ),
    );
  }
}
