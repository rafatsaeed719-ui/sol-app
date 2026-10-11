import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../core/app.dart';
import '../core/data.dart';
import 'invoice_pdf.dart';

/// كارت فاتورة صغير في القوائم
class InvoiceTile extends StatelessWidget {
  final String id;
  final Map<String, dynamic> d;
  final bool showCustomer;
  const InvoiceTile(this.id, this.d, {super.key, this.showCustomer = false});

  @override
  Widget build(BuildContext context) {
    final bal = toD(d['balance']);
    final overdue = isOverdue(d);
    Color c = kSuccess;
    String st = 'خالصة';
    if (bal > 0.009) {
      c = overdue ? kDanger : Colors.orange;
      st = overdue ? 'متأخرة ${daysLate(d)} يوم' : 'عليها ${money(bal)}';
    } else if (bal < -0.009) {
      c = Colors.blue;
      st = 'رصيد ليك ${money(-bal)}';
    }
    return Card(
      child: ListTile(
        onTap: () => Navigator.push(
            context, MaterialPageRoute(builder: (_) => InvoiceScreen(invoiceId: id))),
        leading: CircleAvatar(
          backgroundColor: c.withValues(alpha: 0.12),
          child: Icon(Icons.receipt_long, color: c),
        ),
        title: Text(
            showCustomer
                ? 'فاتورة ${d['number']} — ${d['customerName'] ?? ''}'
                : 'فاتورة رقم ${d['number']}',
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(
            '${fmtDate(d['createdAt'])} • الإجمالي ${money(d['total'])}\nالاستحقاق ${fmtDate(d['dueDate'])}'),
        isThreeLine: true,
        trailing: Text(st,
            style: TextStyle(color: c, fontWeight: FontWeight.bold, fontSize: 12)),
      ),
    );
  }
}

class InvoiceScreen extends StatefulWidget {
  final String invoiceId;
  final bool offerShare; // بعد إنشاء الفاتورة على طول
  const InvoiceScreen({super.key, required this.invoiceId, this.offerShare = false});
  @override
  State<InvoiceScreen> createState() => _InvoiceScreenState();
}

class _InvoiceScreenState extends State<InvoiceScreen> {
  String get invoiceId => widget.invoiceId;

  @override
  void initState() {
    super.initState();
    if (widget.offerShare) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        final go = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            icon: const Icon(Icons.check_circle, color: kSuccess, size: 48),
            title: const Text('الفاتورة جاهزة'),
            content: const Text('تبعت الفاتورة للعميل PDF (واتساب أو أي برنامج)؟'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('بعدين')),
              FilledButton.icon(
                onPressed: () => Navigator.pop(c, true),
                icon: const Icon(Icons.share),
                label: const Text('ابعت الفاتورة'),
              ),
            ],
          ),
        );
        if (go == true && mounted) await shareInvoicePdf(context, invoiceId);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: db.collection('invoices').doc(invoiceId).snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Scaffold(appBar: AppBar(), body: EmptyView('${snap.error}'));
        }
        if (!snap.hasData) return Scaffold(appBar: AppBar(), body: const Loading());
        final d = snap.data!.data();
        if (d == null) {
          return Scaffold(appBar: AppBar(), body: const EmptyView('الفاتورة مش موجودة'));
        }
        final items = List<Map<String, dynamic>>.from(
            (d['items'] as List? ?? []).map((e) => Map<String, dynamic>.from(e)));
        final bal = toD(d['balance']);
        return Scaffold(
          appBar: AppBar(
            title: Text('فاتورة رقم ${d['number']}'),
            actions: [
              IconButton(
                tooltip: 'طباعة / معاينة',
                onPressed: () => printInvoicePdf(context, invoiceId),
                icon: const Icon(Icons.print_outlined),
              ),
              IconButton(
                tooltip: 'ابعت الفاتورة PDF',
                onPressed: () => shareInvoicePdf(context, invoiceId),
                icon: const Icon(Icons.share),
              ),
            ],
          ),
          body: ListView(padding: const EdgeInsets.only(bottom: 100), children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    const Text('SOL',
                        style: TextStyle(
                            fontSize: 26, fontWeight: FontWeight.w900, color: kPrimary)),
                    const Spacer(),
                    Text('رقم ${d['number']}',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ]),
                  const Divider(),
                  _kv('العميل', d['customerName'] ?? ''),
                  _kv('التاريخ', fmtDate(d['createdAt'], time: true)),
                  if (toI(d['collectionDays']) > 0)
                    _kv('مدة التحصيل', '${d['collectionDays']} يوم'),
                  _kv('تاريخ الاستحقاق', fmtDate(d['dueDate'])),
                  if ((d['note'] ?? '').toString().isNotEmpty) _kv('ملاحظات', d['note']),
                ]),
              ),
            ),
            const SectionTitle('الأصناف'),
            ...items.map((it) => _itemCard(it)),
            const SectionTitle('الحساب'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(children: [
                  _kv('إجمالي سعر البيع', money(d['sellTotal'])),
                  _kv('إجمالي الخصم', '- ${money(d['discountTotal'])}', color: kSuccess),
                  _kv('إجمالي سعر الجملة', money(d['gross'] ?? d['wholesaleTotal'])),
                  if (toI(d['pointsRedeemed']) > 0)
                    _kv('خصم نقاط (${d['pointsRedeemed']} نقطة)', '- ${money(d['redeemValue'])}',
                        color: kSuccess),
                  const Divider(),
                  _kv('صافي الفاتورة', money(d['total']), bold: true),
                  _kv('المدفوع', money(d['paid']), color: kSuccess),
                  if (toD(d['returned']) > 0)
                    _kv('مرتجعات', money(d['returned']), color: Colors.blue),
                  const Divider(),
                  _kv(bal < -0.009 ? 'رصيد للعميل' : 'المتبقي', money(bal.abs()),
                      bold: true,
                      color: bal > 0.009
                          ? (isOverdue(d) ? kDanger : Colors.orange)
                          : kSuccess),
                  if (isOverdue(d))
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text('⚠️ متأخرة ${daysLate(d)} يوم عن ميعاد التحصيل',
                          style: const TextStyle(color: kDanger, fontWeight: FontWeight.bold)),
                    ),
                  if (toI(d['pointsEarned']) > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text('⭐ النقاط المكتسبة: ${d['pointsEarned']}',
                          style: const TextStyle(color: kAccent, fontWeight: FontWeight.bold)),
                    ),
                ]),
              ),
            ),
            _MovementList(invoiceId: invoiceId, customerId: d['customerId'] ?? ''),
          ]),
          bottomNavigationBar: isAdmin
              ? SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Row(children: [
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(backgroundColor: kSuccess),
                          onPressed: () => showPaymentDialog(context, invoiceId, bal),
                          icon: const Icon(Icons.payments),
                          label: const Text('تحصيل'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) =>
                                      ReturnScreen(invoiceId: invoiceId, invoice: d))),
                          icon: const Icon(Icons.assignment_return),
                          label: const Text('مرتجع'),
                        ),
                      ),
                      IconButton(
                        tooltip: 'تغيير ميعاد التحصيل',
                        onPressed: () async {
                          final cur = tsToDate(d['dueDate']) ?? DateTime.now();
                          final p = await showDatePicker(
                              context: context,
                              initialDate: cur,
                              firstDate: DateTime(2024),
                              lastDate: DateTime(2035));
                          if (p != null) {
                            await db
                                .collection('invoices')
                                .doc(invoiceId)
                                .update({'dueDate': Timestamp.fromDate(p)});
                          }
                        },
                        icon: const Icon(Icons.event),
                      ),
                    ]),
                  ),
                )
              : null,
        );
      },
    );
  }

  Widget _itemCard(Map<String, dynamic> it) {
    final q = toI(it['qty']);
    final r = toI(it['returnedQty']);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
                child: Text(it['name'] ?? '',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
            Text('× $q', style: const TextStyle(fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 6),
          Wrap(spacing: 14, runSpacing: 4, children: [
            _mini('سعر البيع', money(it['sellPrice'])),
            _mini('الخصم', '${toD(it['discount']).toStringAsFixed(1)}%'),
            _mini('سعر الجملة', money(it['unitNet'])),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            Text('الإجمالي: ${money(toD(it['unitNet']) * q)}',
                style: const TextStyle(color: kPrimary, fontWeight: FontWeight.bold)),
            const Spacer(),
            if (r > 0)
              Text('مرتجع: $r', style: const TextStyle(color: Colors.blue)),
          ]),
        ]),
      ),
    );
  }

  Widget _mini(String k, String v) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(k, style: const TextStyle(fontSize: 11, color: Colors.black54)),
          Text(v, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      );
}

Widget _kv(String k, String v, {bool bold = false, Color? color}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(children: [
      Expanded(child: Text(k, style: const TextStyle(color: Colors.black54))),
      Text(v,
          style: TextStyle(
              fontWeight: bold ? FontWeight.bold : FontWeight.w500,
              fontSize: bold ? 16 : 14,
              color: color)),
    ]),
  );
}

class _MovementList extends StatelessWidget {
  final String invoiceId, customerId;
  const _MovementList({required this.invoiceId, required this.customerId});

  Query<Map<String, dynamic>> _q(String col) => db
      .collection(col)
      .where('customerId', isEqualTo: customerId)
      .where('invoiceId', isEqualTo: invoiceId);

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      StreamBuilder(
        stream: _q('payments').snapshots(),
        builder: (context, s) {
          final docs = s.hasData
              ? sortByDate(s.data!.docs)
              : <QueryDocumentSnapshot<Map<String, dynamic>>>[];
          if (docs.isEmpty) return const SizedBox();
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const SectionTitle('الدفعات'),
            ...docs.map((p) {
              final d = p.data();
              return Card(
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.payments, color: kSuccess),
                  title: Text(money(d['amount']),
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(
                      '${fmtDate(d['createdAt'], time: true)}${(d['note'] ?? '').toString().isEmpty ? '' : ' • ${d['note']}'}'),
                ),
              );
            }),
          ]);
        },
      ),
      StreamBuilder(
        stream: _q('returns').snapshots(),
        builder: (context, s) {
          final docs = s.hasData
              ? sortByDate(s.data!.docs)
              : <QueryDocumentSnapshot<Map<String, dynamic>>>[];
          if (docs.isEmpty) return const SizedBox();
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const SectionTitle('المرتجعات'),
            ...docs.map((p) {
              final d = p.data();
              final items = (d['items'] as List? ?? [])
                  .map((e) => '${e['name']} × ${e['qty']}')
                  .join('، ');
              return Card(
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.assignment_return, color: Colors.blue),
                  title: Text(money(d['amount']),
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('${fmtDate(d['createdAt'], time: true)}\n$items'),
                ),
              );
            }),
          ]);
        },
      ),
    ]);
  }
}

Future<void> showPaymentDialog(BuildContext context, String invoiceId, double balance) async {
  final amount = TextEditingController(
      text: balance > 0 ? balance.toStringAsFixed(balance % 1 == 0 ? 0 : 2) : '');
  final note = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('تحصيل مبلغ'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('المتبقي على الفاتورة: ${money(balance)}'),
        const SizedBox(height: 12),
        TextField(
          controller: amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'المبلغ المحصّل'),
        ),
        const SizedBox(height: 8),
        TextField(controller: note, decoration: const InputDecoration(labelText: 'ملاحظة')),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('تسجيل')),
      ],
    ),
  );
  if (ok != true) return;
  try {
    await addPayment(invoiceId, toD(amount.text), note: note.text.trim());
    if (context.mounted) toast(context, 'اتسجل التحصيل ✔');
  } catch (e) {
    if (context.mounted) toast(context, '$e', error: true);
  }
}

class ReturnScreen extends StatefulWidget {
  final String invoiceId;
  final Map<String, dynamic> invoice;
  const ReturnScreen({super.key, required this.invoiceId, required this.invoice});
  @override
  State<ReturnScreen> createState() => _ReturnScreenState();
}

class _ReturnScreenState extends State<ReturnScreen> {
  late final List<Map<String, dynamic>> items;
  final Map<int, int> qty = {};
  final note = TextEditingController();
  bool busy = false;

  @override
  void initState() {
    super.initState();
    items = List<Map<String, dynamic>>.from(
        (widget.invoice['items'] as List).map((e) => Map<String, dynamic>.from(e)));
  }

  int avail(int i) => toI(items[i]['qty']) - toI(items[i]['returnedQty']);
  double get amount => round2(qty.entries
      .fold(0.0, (a, e) => a + toD(items[e.key]['unitNet']) * e.value));

  Future<void> save() async {
    setState(() => busy = true);
    try {
      final s = await getSettings();
      final a = await addReturn(widget.invoiceId, qty, s, note: note.text.trim());
      if (!mounted) return;
      toast(context, 'اتسجل مرتجع بقيمة ${money(a)}');
      Navigator.pop(context);
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('مرتجع فاتورة ${widget.invoice['number']}')),
      body: ListView(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(spacing: 8, children: [
            ActionChip(
              avatar: const Icon(Icons.select_all, size: 18),
              label: const Text('ترجيع الفاتورة كلها'),
              onPressed: () => setState(() {
                for (var i = 0; i < items.length; i++) {
                  if (avail(i) > 0) qty[i] = avail(i);
                }
              }),
            ),
            ActionChip(
              avatar: const Icon(Icons.clear, size: 18),
              label: const Text('مسح'),
              onPressed: () => setState(() => qty.clear()),
            ),
          ]),
        ),
        for (var i = 0; i < items.length; i++)
          Card(
            child: ListTile(
              title: Text(items[i]['name'] ?? ''),
              subtitle: Text(
                  'المتاح للترجيع: ${avail(i)} • جملة ${money(items[i]['unitNet'])}'),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                  onPressed: (qty[i] ?? 0) <= 0
                      ? null
                      : () => setState(() => qty[i] = (qty[i] ?? 0) - 1),
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                Text('${qty[i] ?? 0}',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                IconButton(
                  onPressed: (qty[i] ?? 0) >= avail(i)
                      ? null
                      : () => setState(() => qty[i] = (qty[i] ?? 0) + 1),
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ]),
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
              controller: note,
              decoration: const InputDecoration(labelText: 'سبب المرتجع / ملاحظة')),
        ),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton(
            onPressed: busy || amount <= 0 ? null : save,
            child: Text('تسجيل مرتجع بقيمة ${money(amount)}'),
          ),
        ),
      ),
    );
  }
}
