import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../core/app.dart';

const List<String> kExpenseCats = [
  'بضاعة',
  'إيجار',
  'مرتبات',
  'نقل ومواصلات',
  'كهربا ومياه ونت',
  'دعاية وتسويق',
  'صيانة',
  'أخرى',
];

const List<String> kMonths = [
  'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
  'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'
];

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});
  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);
  String cat = '';
  String q = '';

  @override
  Widget build(BuildContext context) {
    final next = DateTime(month.year, month.month + 1);
    return Scaffold(
      appBar: AppBar(title: const Text('المصروفات')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () =>
            Navigator.push(context, MaterialPageRoute(builder: (_) => const ExpenseForm())),
        icon: const Icon(Icons.add),
        label: const Text('مصروف جديد'),
      ),
      body: StreamBuilder(
        stream: scoped('expenses').snapshots(),
        builder: (context, snap) {
          if (snap.hasError) return EmptyView('${snap.error}');
          if (!snap.hasData) return const Loading();
          final inMonth = snap.data!.docs.where((d) {
            final t = tsToDate(d.data()['date']) ?? DateTime.now();
            return !t.isBefore(month) && t.isBefore(next);
          }).toList()
            ..sort((a, b) => (tsToDate(b.data()['date']) ?? DateTime(2000))
                .compareTo(tsToDate(a.data()['date']) ?? DateTime(2000)));
          final byCat = <String, double>{};
          for (final d in inMonth) {
            final c = (d.data()['category'] ?? 'أخرى').toString();
            byCat[c] = (byCat[c] ?? 0) + toD(d.data()['amount']);
          }
          final total = inMonth.fold(0.0, (a, d) => a + toD(d.data()['amount']));
          final list = inMonth.where((d) {
            final m = d.data();
            if (cat.isNotEmpty && m['category'] != cat) return false;
            if (q.isNotEmpty &&
                !'${m['title']} ${m['to']} ${m['note']}'.toLowerCase().contains(q.toLowerCase())) {
              return false;
            }
            return true;
          }).toList();
          final cats = byCat.keys.toList()..sort((a, b) => byCat[b]!.compareTo(byCat[a]!));
          return ListView(padding: const EdgeInsets.only(bottom: 90), children: [
            // اختيار الشهر
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: Row(children: [
                IconButton(
                    onPressed: () =>
                        setState(() => month = DateTime(month.year, month.month - 1)),
                    icon: const Icon(Icons.chevron_right)),
                Expanded(
                  child: Text('${kMonths[month.month - 1]} ${month.year}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                ),
                IconButton(
                    onPressed: () =>
                        setState(() => month = DateTime(month.year, month.month + 1)),
                    icon: const Icon(Icons.chevron_left)),
              ]),
            ),
            Card(
              color: kPrimary,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  const Icon(Icons.account_balance_wallet, color: kAccent, size: 32),
                  const SizedBox(width: 12),
                  const Expanded(
                      child: Text('إجمالي المصروفات',
                          style: TextStyle(color: Colors.white70, fontSize: 15))),
                  Text(money(total),
                      style: const TextStyle(
                          color: kAccent, fontSize: 22, fontWeight: FontWeight.bold)),
                ]),
              ),
            ),
            if (cats.isNotEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(children: [
                    for (final c in cats)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          Row(children: [
                            Expanded(child: Text(c)),
                            Text(money(byCat[c]),
                                style: const TextStyle(fontWeight: FontWeight.bold)),
                          ]),
                          const SizedBox(height: 3),
                          LinearProgressIndicator(
                            value: total <= 0 ? 0 : byCat[c]! / total,
                            minHeight: 6,
                            borderRadius: BorderRadius.circular(6),
                            color: kAccent,
                          ),
                        ]),
                      ),
                  ]),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: TextField(
                decoration: const InputDecoration(
                    hintText: 'دوّر في المصروفات', prefixIcon: Icon(Icons.search)),
                onChanged: (v) => setState(() => q = v.trim()),
              ),
            ),
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(4),
                    child: ChoiceChip(
                        label: const Text('الكل'),
                        selected: cat.isEmpty,
                        onSelected: (_) => setState(() => cat = '')),
                  ),
                  for (final c in kExpenseCats)
                    Padding(
                      padding: const EdgeInsets.all(4),
                      child: ChoiceChip(
                          label: Text(c),
                          selected: cat == c,
                          onSelected: (_) => setState(() => cat = c)),
                    ),
                ],
              ),
            ),
            if (list.isEmpty) const EmptyView('مفيش مصروفات في الشهر ده', icon: Icons.money_off),
            for (final d in list)
              Card(
                child: ListTile(
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => ExpenseForm(id: d.id, data: d.data()))),
                  leading: CircleAvatar(
                    backgroundColor: kAccent.withValues(alpha: 0.15),
                    child: const Icon(Icons.receipt, color: kPrimary),
                  ),
                  title: Text((d.data()['title'] ?? '').toString(),
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text([
                    fmtDate(d.data()['date']),
                    d.data()['category'] ?? '',
                    if ((d.data()['to'] ?? '').toString().isNotEmpty) 'لـ ${d.data()['to']}',
                  ].join(' • ')),
                  trailing: Text(money(d.data()['amount']),
                      style: const TextStyle(fontWeight: FontWeight.bold, color: kDanger)),
                ),
              ),
          ]);
        },
      ),
    );
  }
}

class ExpenseForm extends StatefulWidget {
  final String? id;
  final Map<String, dynamic>? data;
  const ExpenseForm({super.key, this.id, this.data});
  @override
  State<ExpenseForm> createState() => _ExpenseFormState();
}

class _ExpenseFormState extends State<ExpenseForm> {
  final title = TextEditingController();
  final amount = TextEditingController();
  final to = TextEditingController();
  final note = TextEditingController();
  String category = kExpenseCats.first;
  DateTime date = DateTime.now();
  bool busy = false;

  @override
  void initState() {
    super.initState();
    final d = widget.data;
    if (d != null) {
      title.text = d['title'] ?? '';
      amount.text = toD(d['amount']) % 1 == 0
          ? toD(d['amount']).toStringAsFixed(0)
          : toD(d['amount']).toString();
      to.text = d['to'] ?? '';
      note.text = d['note'] ?? '';
      if (kExpenseCats.contains(d['category'])) category = d['category'];
      date = tsToDate(d['date']) ?? DateTime.now();
    }
  }

  Future<void> save() async {
    if (title.text.trim().isEmpty || toD(amount.text) <= 0) {
      toast(context, 'اكتب اتصرف في إيه والمبلغ', error: true);
      return;
    }
    setState(() => busy = true);
    final data = {
      'storeId': sid,
      'title': title.text.trim(),
      'amount': toD(amount.text),
      'to': to.text.trim(),
      'note': note.text.trim(),
      'category': category,
      'date': Timestamp.fromDate(date),
    };
    try {
      if (widget.id == null) {
        await db.collection('expenses').add({...data, 'createdAt': FieldValue.serverTimestamp()});
      } else {
        await db.collection('expenses').doc(widget.id).update(data);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.id == null ? 'مصروف جديد' : 'تعديل مصروف'),
        actions: [
          if (widget.id != null)
            IconButton(
              onPressed: () async {
                if (!await confirm(context, 'حذف المصروف', 'متأكد؟')) return;
                await db.collection('expenses').doc(widget.id).delete();
                if (context.mounted) Navigator.pop(context);
              },
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        _f(title, 'اتصرف في إيه؟ *', Icons.edit_note),
        _f(amount, 'المبلغ *', Icons.payments_outlined, number: true),
        _f(to, 'اتدفع لمين؟', Icons.person_outline),
        DropdownButtonFormField<String>(
          value: category,
          decoration: const InputDecoration(labelText: 'النوع', prefixIcon: Icon(Icons.category)),
          items: [for (final c in kExpenseCats) DropdownMenuItem(value: c, child: Text(c))],
          onChanged: (v) => setState(() => category = v ?? category),
        ),
        const SizedBox(height: 12),
        Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: const Icon(Icons.event),
            title: Text('التاريخ: ${fmtDate(date)}'),
            onTap: () async {
              final p = await showDatePicker(
                  context: context,
                  initialDate: date,
                  firstDate: DateTime(2024),
                  lastDate: DateTime(2035));
              if (p != null) setState(() => date = p);
            },
          ),
        ),
        _f(note, 'ملاحظات', Icons.notes, lines: 2),
        const SizedBox(height: 8),
        SizedBox(
          height: 48,
          child: FilledButton(onPressed: busy ? null : save, child: const Text('حفظ')),
        ),
      ]),
    );
  }

  Widget _f(TextEditingController c, String label, IconData icon,
          {bool number = false, int lines = 1}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c,
          maxLines: lines,
          keyboardType: number ? const TextInputType.numberWithOptions(decimal: true) : null,
          decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
        ),
      );
}
