import 'package:flutter/material.dart';

import '../core/app.dart';
import '../core/data.dart';
import '../shared/invoice_view.dart';

class InvoiceForm extends StatefulWidget {
  final String customerId;
  final String customerName;
  final String? orderId;
  final List<Map<String, dynamic>>? orderItems;
  const InvoiceForm({
    super.key,
    required this.customerId,
    required this.customerName,
    this.orderId,
    this.orderItems,
  });
  @override
  State<InvoiceForm> createState() => _InvoiceFormState();
}

class _InvoiceFormState extends State<InvoiceForm> {
  final lines = <InvLine>[];
  AppSettings settings = const AppSettings();
  DateTime? due;
  final days = TextEditingController();
  Map<String, int?> stocks = {};
  int customerPoints = 0;
  int redeem = 0;
  final paidNow = TextEditingController();
  final note = TextEditingController();
  bool busy = false;
  bool loaded = false;

  @override
  void initState() {
    super.initState();
    for (final it in widget.orderItems ?? <Map<String, dynamic>>[]) {
      lines.add(InvLine(
        productId: it['productId'] ?? '',
        name: it['name'] ?? '',
        qty: toI(it['qty']),
        sellPrice: toD(it['sellPrice']),
        wholesalePrice: toD(it['wholesalePrice']),
        discount: toD(it['discount']),
      ));
    }
    _load();
  }

  Future<void> _load() async {
    final s = await getSettings();
    final u = await db.collection('users').doc(widget.customerId).get();
    final ps = await db.collection('products').get();
    if (!mounted) return;
    setState(() {
      settings = s;
      customerPoints = toI(u.data()?['points']);
      final d = u.data()?['collectionDays'] != null
          ? toI(u.data()?['collectionDays'])
          : s.collectionDays;
      days.text = '$d';
      due = _dueFor(d);
      stocks = {for (final p in ps.docs) p.id: stockOf(p.data())};
      loaded = true;
    });
  }

  DateTime _dueFor(int d) {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day).add(Duration(days: d));
  }

  /// كمية الصنف في الفاتورة كلها (لو متكرر)
  int _qtyOf(String pid) =>
      lines.where((l) => l.productId == pid).fold(0, (a, l) => a + l.qty);

  String? _stockWarn(InvLine l) {
    final st = stocks[l.productId];
    if (st == null) return null;
    final need = _qtyOf(l.productId);
    if (need > st) return '⚠️ المخزن فيه $st بس';
    return 'المخزن: $st';
  }

  double get gross => round2(lines.fold(0.0, (a, l) => a + l.lineTotal));
  double get redeemValue => settings.valueOf(redeem);
  double get total => round2((gross - redeemValue) < 0 ? 0 : gross - redeemValue);

  Future<void> addProduct() async {
    final snap = await db.collection('products').get();
    if (!mounted) return;
    final docs = [...snap.docs]
      ..sort((a, b) => (a.data()['name'] ?? '').toString().compareTo(
          (b.data()['name'] ?? '').toString()));
    final picked = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (c) => _ProductPicker(names: [
        for (final d in docs)
          '${d.data()['name']} — جملة ${money(netUnit(toD(d.data()['sellPrice']), toD(d.data()['discount']), toD(d.data()['wholesalePrice'])))}${stockOf(d.data()) == null ? '' : ' • مخزن ${stockOf(d.data())}'}'
      ]),
    );
    if (picked == null) return;
    final p = docs[picked].data();
    setState(() {
      lines.add(InvLine(
        productId: docs[picked].id,
        name: p['name'] ?? '',
        qty: 1,
        sellPrice: toD(p['sellPrice']),
        wholesalePrice: toD(p['wholesalePrice']),
        discount: toD(p['discount']),
      ));
    });
  }

  Future<void> editLine(int i) async {
    final l = lines[i];
    final q = TextEditingController(text: '${l.qty}');
    final sp = TextEditingController(text: _n(l.sellPrice));
    final dc = TextEditingController(text: _n(l.discount));
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(l.name),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _num(q, 'الكمية'),
            _num(sp, 'سعر البيع'),
            _num(dc, 'نسبة الخصم %'),
            const Text('سعر الجملة بيتحسب لوحده = سعر البيع − الخصم',
                style: TextStyle(fontSize: 12, color: Colors.black54)),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () {
                setState(() => lines.removeAt(i));
                Navigator.pop(c, false);
              },
              style: TextButton.styleFrom(foregroundColor: kDanger),
              child: const Text('حذف الصنف')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('حفظ')),
        ],
      ),
    );
    if (ok == true) {
      setState(() {
        l.qty = toI(q.text) < 1 ? 1 : toI(q.text);
        l.sellPrice = toD(sp.text);
        l.wholesalePrice = netUnit(toD(sp.text), toD(dc.text), l.wholesalePrice);
        l.discount = toD(dc.text).clamp(0, 100).toDouble();
      });
    }
  }

  String _n(double v) => v % 1 == 0 ? v.toStringAsFixed(0) : v.toString();

  Widget _num(TextEditingController c, String label) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: label),
        ),
      );

  Future<void> save() async {
    if (lines.isEmpty) {
      toast(context, 'ضيف أصناف للفاتورة', error: true);
      return;
    }
    setState(() => busy = true);
    try {
      final (id, n) = await createInvoice(
        customerId: widget.customerId,
        customerName: widget.customerName,
        lines: lines,
        dueDate: due ?? DateTime.now(),
        settings: settings,
        collectionDays: toI(days.text),
        orderId: widget.orderId,
        redeemPoints: redeem,
        paidNow: toD(paidNow.text),
        note: note.text.trim(),
      );
      if (!mounted) return;
      Navigator.pushReplacement(
          context,
          MaterialPageRoute(
              builder: (_) => InvoiceScreen(invoiceId: id, offerShare: true)));
      toast(context, 'اتعملت الفاتورة رقم $n ✔');
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final maxRedeem = settings.pointsForReward <= 0
        ? 0
        : (customerPoints ~/ settings.pointsForReward) * settings.pointsForReward;
    return Scaffold(
      appBar: AppBar(title: Text('فاتورة — ${widget.customerName}')),
      body: !loaded
          ? const Loading()
          : ListView(padding: const EdgeInsets.only(bottom: 120), children: [
              SectionTitle('الأصناف (${lines.length})',
                  trailing: TextButton.icon(
                      onPressed: addProduct,
                      icon: const Icon(Icons.add),
                      label: const Text('إضافة صنف'))),
              if (lines.isEmpty) const EmptyView('ضيف أصناف'),
              for (var i = 0; i < lines.length; i++)
                Card(
                  child: ListTile(
                    onTap: () => editLine(i),
                    title: Text(lines[i].name,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(
                        'بيع ${money(lines[i].sellPrice)} • خصم ${lines[i].discount.toStringAsFixed(1)}% • جملة ${money(lines[i].unitNet)}\n${lines[i].qty} × ${money(lines[i].unitNet)} = ${money(lines[i].lineTotal)}${_stockWarn(lines[i]) == null ? '' : '   ${_stockWarn(lines[i])}'}'),
                    isThreeLine: true,
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        onPressed: () => setState(() {
                          if (lines[i].qty > 1) {
                            lines[i].qty--;
                          } else {
                            lines.removeAt(i);
                          }
                        }),
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        onPressed: () => setState(() => lines[i].qty++),
                        icon: const Icon(Icons.add_circle_outline),
                      ),
                    ]),
                  ),
                ),
              const SectionTitle('التحصيل'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(children: [
                  Expanded(
                    child: TextField(
                      controller: days,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                          labelText: 'عدد أيام التحصيل',
                          prefixIcon: Icon(Icons.timer_outlined)),
                      onChanged: (v) => setState(() => due = _dueFor(toI(v))),
                    ),
                  ),
                  const SizedBox(width: 8),
                  for (final d in const [7, 15, 30])
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: ChoiceChip(
                        label: Text('$d'),
                        selected: toI(days.text) == d,
                        onSelected: (_) => setState(() {
                          days.text = '$d';
                          due = _dueFor(d);
                        }),
                      ),
                    ),
                ]),
              ),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.event, color: kPrimary),
                  title: Text('ميعاد التحصيل: ${fmtDate(due)}'),
                  subtitle: const Text('دوس لو عاوز تختار تاريخ معيّن'),
                  onTap: () async {
                    final p = await showDatePicker(
                        context: context,
                        initialDate: due ?? DateTime.now(),
                        firstDate: DateTime.now().subtract(const Duration(days: 1)),
                        lastDate: DateTime(2035));
                    if (p != null) {
                      setState(() {
                        due = p;
                        days.text = '${p.difference(_dueFor(0)).inDays}';
                      });
                    }
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: TextField(
                  controller: paidNow,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'المدفوع دلوقتي (اختياري)',
                      prefixIcon: Icon(Icons.payments_outlined)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: TextField(
                    controller: note, decoration: const InputDecoration(labelText: 'ملاحظات')),
              ),
              if (maxRedeem > 0) ...[
                const SectionTitle('استبدال نقاط'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('العميل معاه $customerPoints نقطة (يقدر يستبدل $maxRedeem = ${money(settings.valueOf(maxRedeem))})'),
                      Wrap(spacing: 8, children: [
                        ChoiceChip(
                            label: const Text('بدون'),
                            selected: redeem == 0,
                            onSelected: (_) => setState(() => redeem = 0)),
                        for (var p = settings.pointsForReward;
                            p <= maxRedeem;
                            p += settings.pointsForReward)
                          ChoiceChip(
                              label: Text('$p نقطة = ${money(settings.valueOf(p))}'),
                              selected: redeem == p,
                              onSelected: (_) => setState(() => redeem = p)),
                      ]),
                    ]),
                  ),
                ),
              ],
            ]),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.white, boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 8)
          ]),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              const Text('الإجمالي'),
              const Spacer(),
              if (redeemValue > 0)
                Text('${money(gross)} - ${money(redeemValue)} = ',
                    style: const TextStyle(color: Colors.black54)),
              Text(money(total),
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold, color: kPrimary)),
            ]),
            Text('هيكسب ${settings.pointsFor(total)} نقطة',
                style: const TextStyle(color: kAccent, fontSize: 12)),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: FilledButton.icon(
                onPressed: busy || !loaded ? null : save,
                icon: const Icon(Icons.save),
                label: const Text('حفظ الفاتورة'),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _ProductPicker extends StatefulWidget {
  final List<String> names;
  const _ProductPicker({required this.names});
  @override
  State<_ProductPicker> createState() => _ProductPickerState();
}

class _ProductPickerState extends State<_ProductPicker> {
  String q = '';
  @override
  Widget build(BuildContext context) {
    final idx = [
      for (var i = 0; i < widget.names.length; i++)
        if (widget.names[i].toLowerCase().contains(q.toLowerCase())) i
    ];
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
                12, 12, 12, MediaQuery.of(context).viewInsets.bottom > 0 ? 4 : 12),
            child: TextField(
              autofocus: true,
              decoration:
                  const InputDecoration(hintText: 'دوّر على صنف', prefixIcon: Icon(Icons.search)),
              onChanged: (v) => setState(() => q = v),
            ),
          ),
          Expanded(
            child: idx.isEmpty
                ? const EmptyView('مفيش أصناف — ضيف من صفحة الأصناف')
                : ListView.builder(
                    itemCount: idx.length,
                    itemBuilder: (c, i) => ListTile(
                      title: Text(widget.names[idx[i]]),
                      onTap: () => Navigator.pop(context, idx[i]),
                    ),
                  ),
          ),
        ]),
      ),
    );
  }
}
