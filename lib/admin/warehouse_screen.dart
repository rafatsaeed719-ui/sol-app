import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../core/app.dart';
import '../core/data.dart';
import '../shared/invoice_view.dart';
import 'products_admin.dart';

typedef _Docs = List<QueryDocumentSnapshot<Map<String, dynamic>>>;

int lowOf(Map<String, dynamic> p) => p['lowStock'] == null ? 5 : toI(p['lowStock']);

double unitOf(Map<String, dynamic> p) =>
    netUnit(toD(p['sellPrice']), toD(p['discount']), toD(p['wholesalePrice']));

/// لوحة المخزن: الأرصدة + كل حركة (وارد وصادر ومرتجع) واتحركت لمين
class WarehouseScreen extends StatelessWidget {
  const WarehouseScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('المخزن'),
          bottom: const TabBar(
            labelColor: kAccent,
            unselectedLabelColor: Colors.white70,
            indicatorColor: kAccent,
            tabs: [Tab(text: 'الأرصدة'), Tab(text: 'حركة المخزن')],
          ),
        ),
        floatingActionButton: Builder(
          builder: (context) => FloatingActionButton.extended(
            onPressed: () => showStockDialog(context),
            icon: const Icon(Icons.move_to_inbox),
            label: const Text('وارد / تسوية'),
          ),
        ),
        body: const TabBarView(children: [_Balances(), MovesList()]),
      ),
    );
  }
}

// ======================== الأرصدة ========================

class _Balances extends StatefulWidget {
  const _Balances();
  @override
  State<_Balances> createState() => _BalancesState();
}

class _BalancesState extends State<_Balances> {
  String q = '';
  String filter = 'all';

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: scoped('products').snapshots(),
      builder: (context, snap) {
        if (snap.hasError) return EmptyView('${snap.error}');
        if (!snap.hasData) return const Loading();
        final all = snap.data!.docs;
        final tracked = all.where((d) => stockOf(d.data()) != null).toList();
        final pieces = tracked.fold(0, (a, d) => a + stockOf(d.data())!);
        final value = tracked.fold(0.0, (a, d) => a + stockOf(d.data())! * unitOf(d.data()));
        final out = tracked.where((d) => stockOf(d.data())! <= 0).toList();
        final low = tracked
            .where((d) => stockOf(d.data())! > 0 && stockOf(d.data())! <= lowOf(d.data()))
            .toList();
        var list = all.where((d) {
          final p = d.data();
          final st = stockOf(p);
          if (filter == 'low' && !(st != null && st > 0 && st <= lowOf(p))) return false;
          if (filter == 'out' && !(st != null && st <= 0)) return false;
          if (filter == 'none' && st != null) return false;
          if (q.isNotEmpty && !(p['name'] ?? '').toString().toLowerCase().contains(q.toLowerCase())) {
            return false;
          }
          return true;
        }).toList()
          ..sort((a, b) {
            final sa = stockOf(a.data()) ?? 1 << 30;
            final sb = stockOf(b.data()) ?? 1 << 30;
            return sa.compareTo(sb);
          });
        return ListView(padding: const EdgeInsets.only(bottom: 90), children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 2.1,
              children: [
                StatTile('قطع في المخزن', '$pieces', icon: Icons.warehouse),
                StatTile('قيمة المخزن (جملة)', money(value),
                    icon: Icons.payments, color: kSuccess),
                StatTile('قرب يخلص', '${low.length}',
                    icon: Icons.warning_amber,
                    color: low.isEmpty ? kPrimary : Colors.orange,
                    onTap: () => setState(() => filter = 'low')),
                StatTile('خلص', '${out.length}',
                    icon: Icons.remove_shopping_cart,
                    color: out.isEmpty ? kPrimary : kDanger,
                    onTap: () => setState(() => filter = 'out')),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: TextField(
              decoration:
                  const InputDecoration(hintText: 'دوّر على صنف', prefixIcon: Icon(Icons.search)),
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
                  ['all', 'الكل'],
                  ['low', 'قرب يخلص'],
                  ['out', 'خلص'],
                  ['none', 'مش متتبع'],
                ])
                  Padding(
                    padding: const EdgeInsets.all(4),
                    child: ChoiceChip(
                        label: Text(f[1]),
                        selected: filter == f[0],
                        onSelected: (_) => setState(() => filter = f[0])),
                  ),
              ],
            ),
          ),
          if (list.isEmpty) const EmptyView('مفيش أصناف هنا'),
          for (final d in list) _BalanceTile(d.id, d.data()),
        ]);
      },
    );
  }
}

class _BalanceTile extends StatelessWidget {
  final String id;
  final Map<String, dynamic> p;
  const _BalanceTile(this.id, this.p);

  @override
  Widget build(BuildContext context) {
    final st = stockOf(p);
    final low = lowOf(p);
    final c = st == null
        ? Colors.grey
        : st <= 0
            ? kDanger
            : st <= low
                ? Colors.orange
                : kSuccess;
    return Card(
      child: ListTile(
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => ProductMovesScreen(productId: id, product: p))),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: B64Image(p['image'], width: 48, height: 48),
        ),
        title: Text((p['name'] ?? '').toString(),
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(st == null
            ? 'المخزن مش متتبع — دوس عشان تشوف الحركة'
            : 'التنبيه عند $low • القيمة ${money(st * unitOf(p))}'),
        trailing: Container(
          constraints: const BoxConstraints(minWidth: 56),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
              color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(st == null ? '—' : '$st',
                style: TextStyle(color: c, fontWeight: FontWeight.bold, fontSize: 18)),
            Text(st == null ? '' : (st <= 0 ? 'خلص' : (st <= low ? 'قرب يخلص' : 'قطعة')),
                style: TextStyle(color: c, fontSize: 10)),
          ]),
        ),
      ),
    );
  }
}

// ======================== حركة المخزن ========================

Color moveColor(String type, int qty) {
  if (type == 'sale') return kDanger;
  if (type == 'return' || type == 'in' || type == 'open' || type == 'invoice_delete') {
    return kSuccess;
  }
  return qty < 0 ? kDanger : Colors.blue;
}

IconData moveIcon(String type) {
  switch (type) {
    case 'sale':
      return Icons.north_east;
    case 'return':
      return Icons.assignment_return;
    case 'in':
    case 'open':
      return Icons.move_to_inbox;
    case 'invoice_delete':
      return Icons.delete_sweep;
    case 'invoice_edit':
      return Icons.edit_note;
  }
  return Icons.tune;
}

class MovesList extends StatefulWidget {
  final String? productId;
  const MovesList({super.key, this.productId});
  @override
  State<MovesList> createState() => _MovesListState();
}

class _MovesListState extends State<MovesList> {
  String type = '';
  int days = 30;
  String q = '';

  @override
  Widget build(BuildContext context) {
    Query<Map<String, dynamic>> query = scoped('stockMoves');
    if (widget.productId != null) {
      query = query.where('productId', isEqualTo: widget.productId);
    }
    return StreamBuilder(
      stream: query.snapshots(),
      builder: (context, snap) {
        if (snap.hasError) return EmptyView('${snap.error}');
        if (!snap.hasData) return const Loading();
        final from = DateTime.now().subtract(Duration(days: days));
        final _Docs all = sortByDate(snap.data!.docs);
        final list = all.where((d) {
          final m = d.data();
          if (days > 0 && (tsToDate(m['createdAt']) ?? DateTime.now()).isBefore(from)) {
            return false;
          }
          if (type.isNotEmpty) {
            if (type == 'in' && !(m['type'] == 'in' || m['type'] == 'open')) return false;
            if (type != 'in' && m['type'] != type) return false;
          }
          if (q.isNotEmpty &&
              !'${m['productName']} ${m['party']}'.toLowerCase().contains(q.toLowerCase())) {
            return false;
          }
          return true;
        }).toList();
        final inQty = list.where((d) => toI(d.data()['qty']) > 0).fold(0, (a, d) => a + toI(d.data()['qty']));
        final outQty = list.where((d) => toI(d.data()['qty']) < 0).fold(0, (a, d) => a - toI(d.data()['qty']));
        // أكتر ناس اتباع لهم
        final parties = <String, int>{};
        for (final d in list) {
          if (d.data()['type'] != 'sale') continue;
          final p = (d.data()['party'] ?? '').toString();
          parties[p] = (parties[p] ?? 0) - toI(d.data()['qty']);
        }
        final topParties = parties.keys.toList()..sort((a, b) => parties[b]!.compareTo(parties[a]!));
        return ListView(padding: const EdgeInsets.only(bottom: 90), children: [
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                for (final p in const [
                  [7, 'أسبوع'],
                  [30, 'شهر'],
                  [90, '3 شهور'],
                  [0, 'الكل'],
                ])
                  Padding(
                    padding: const EdgeInsets.all(4),
                    child: ChoiceChip(
                        label: Text(p[1] as String),
                        selected: days == p[0],
                        onSelected: (_) => setState(() => days = p[0] as int)),
                  ),
              ],
            ),
          ),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                for (final t in const [
                  ['', 'كل الحركات'],
                  ['sale', 'صادر (بيع)'],
                  ['in', 'وارد'],
                  ['return', 'مرتجع'],
                  ['adjust', 'تسوية'],
                ])
                  Padding(
                    padding: const EdgeInsets.all(4),
                    child: ChoiceChip(
                        label: Text(t[1]),
                        selected: type == t[0],
                        onSelected: (_) => setState(() => type = t[0])),
                  ),
              ],
            ),
          ),
          if (widget.productId == null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: TextField(
                decoration: const InputDecoration(
                    hintText: 'دوّر باسم الصنف أو العميل', prefixIcon: Icon(Icons.search)),
                onChanged: (v) => setState(() => q = v.trim()),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(children: [
              Expanded(
                  child: StatTile('دخل المخزن', '$inQty',
                      icon: Icons.south_west, color: kSuccess)),
              Expanded(
                  child: StatTile('خرج من المخزن', '$outQty',
                      icon: Icons.north_east, color: kDanger)),
            ]),
          ),
          if (topParties.isNotEmpty) ...[
            const SectionTitle('اتباع لمين أكتر'),
            for (final p in topParties.take(5))
              Card(
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.storefront),
                  title: Text(p.isEmpty ? '—' : p),
                  trailing: Text('${parties[p]} قطعة',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
          ],
          SectionTitle('الحركات (${list.length})'),
          if (list.isEmpty) const EmptyView('مفيش حركة في الفترة دي', icon: Icons.swap_vert),
          for (final d in list) MoveTile(d.data(), showProduct: widget.productId == null),
        ]);
      },
    );
  }
}

class MoveTile extends StatelessWidget {
  final Map<String, dynamic> m;
  final bool showProduct;
  const MoveTile(this.m, {super.key, this.showProduct = true});

  @override
  Widget build(BuildContext context) {
    final t = (m['type'] ?? '').toString();
    final qty = toI(m['qty']);
    final c = moveColor(t, qty);
    final party = (m['party'] ?? '').toString();
    final details = <String>[
      kMoveTypes[t] ?? t,
      if (party.isNotEmpty) (t == 'in' || t == 'open') ? 'من: $party' : 'لـ: $party',
      if (m['refNumber'] != null) 'فاتورة ${m['refNumber']}',
      fmtDate(m['createdAt'], time: true),
    ];
    return Card(
      child: ListTile(
        dense: true,
        onTap: m['refId'] == null || !(t == 'sale' || t == 'return' || t == 'invoice_edit')
            ? null
            : () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => InvoiceScreen(invoiceId: m['refId']))),
        leading: CircleAvatar(
          backgroundColor: c.withValues(alpha: 0.12),
          child: Icon(moveIcon(t), color: c, size: 20),
        ),
        title: Text(showProduct ? (m['productName'] ?? '').toString() : (kMoveTypes[t] ?? t),
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text([
          ...(showProduct ? details : details.skip(1)),
          if ((m['note'] ?? '').toString().isNotEmpty) m['note'],
        ].join(' • ')),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('${qty > 0 ? '+' : ''}$qty',
                textDirection: TextDirection.ltr,
                style: TextStyle(color: c, fontWeight: FontWeight.bold, fontSize: 16)),
            if (m['after'] != null)
              Text('الرصيد ${m['after']}', style: const TextStyle(fontSize: 10)),
          ],
        ),
      ),
    );
  }
}

class ProductMovesScreen extends StatelessWidget {
  final String productId;
  final Map<String, dynamic> product;
  const ProductMovesScreen({super.key, required this.productId, required this.product});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text((product['name'] ?? '').toString()),
        actions: [
          IconButton(
            tooltip: 'تعديل الصنف',
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => ProductForm(id: productId, data: product))),
            icon: const Icon(Icons.edit),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showStockDialog(context, productId: productId, product: product),
        icon: const Icon(Icons.move_to_inbox),
        label: const Text('وارد / تسوية'),
      ),
      body: StreamBuilder(
        stream: db.collection('products').doc(productId).snapshots(),
        builder: (context, s) {
          final p = s.data?.data() ?? product;
          final st = stockOf(p);
          return Column(children: [
            Card(
              color: kPrimary,
              child: ListTile(
                leading: const Icon(Icons.warehouse, color: kAccent),
                title: Text(st == null ? 'المخزن مش متتبع' : 'الرصيد الحالي: $st قطعة',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                subtitle: Text('التنبيه لما يوصل ${lowOf(p)}',
                    style: const TextStyle(color: Colors.white70)),
              ),
            ),
            Expanded(child: MovesList(productId: productId)),
          ]);
        },
      ),
    );
  }
}

/// وارد بضاعة أو تسوية (جرد) لصنف
Future<void> showStockDialog(BuildContext context,
    {String? productId, Map<String, dynamic>? product}) async {
  var pid = productId;
  var p = product;
  if (pid == null) {
    final snap = await scoped('products').get();
    if (!context.mounted) return;
    final docs = [...snap.docs]
      ..sort((a, b) => (a.data()['name'] ?? '').toString().compareTo((b.data()['name'] ?? '').toString()));
    if (docs.isEmpty) {
      toast(context, 'ضيف أصناف الأول', error: true);
      return;
    }
    final i = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(c).size.height * 0.7,
          child: Column(children: [
            const Padding(
              padding: EdgeInsets.all(14),
              child: Text('اختار الصنف', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: docs.length,
                itemBuilder: (c, i) => ListTile(
                  title: Text((docs[i].data()['name'] ?? '').toString()),
                  trailing: Text(stockOf(docs[i].data()) == null
                      ? '—'
                      : '${stockOf(docs[i].data())}'),
                  onTap: () => Navigator.pop(c, i),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
    if (i == null) return;
    pid = docs[i].id;
    p = docs[i].data();
  }
  if (!context.mounted || p == null) return;
  final cur = stockOf(p);
  var mode = 'in';
  final qty = TextEditingController();
  final party = TextEditingController();
  final note = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => AlertDialog(
        title: Text((p!['name'] ?? '').toString()),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(cur == null ? 'المخزن مش متتبع لسه' : 'الرصيد الحالي: $cur',
                style: const TextStyle(color: Colors.black54)),
            const SizedBox(height: 10),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'in', label: Text('وارد'), icon: Icon(Icons.add)),
                ButtonSegment(value: 'count', label: Text('جرد'), icon: Icon(Icons.fact_check)),
              ],
              selected: {mode},
              onSelectionChanged: (v) => set(() => mode = v.first),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: qty,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                  labelText: mode == 'in' ? 'الكمية اللي دخلت' : 'العدد الفعلي في المخزن'),
            ),
            const SizedBox(height: 8),
            if (mode == 'in')
              TextField(
                  controller: party,
                  decoration: const InputDecoration(labelText: 'جاية من مين؟ (المورد)')),
            const SizedBox(height: 8),
            TextField(controller: note, decoration: const InputDecoration(labelText: 'ملاحظة')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('تسجيل')),
        ],
      ),
    ),
  );
  if (ok != true || qty.text.trim().isEmpty) return;
  try {
    final ref = db.collection('products').doc(pid);
    if (cur == null) await ref.update({'stock': 0});
    final n = toI(qty.text);
    final change = mode == 'in' ? n : n - (cur ?? 0);
    if (change == 0) {
      if (context.mounted) toast(context, 'الرصيد مظبوط — مفيش فرق');
      return;
    }
    await adjustStock({pid!: change},
        type: mode == 'in' ? 'in' : 'adjust',
        party: party.text.trim(),
        note: mode == 'count' ? 'جرد: العدد الفعلي $n${note.text.trim().isEmpty ? '' : ' — ${note.text.trim()}'}' : note.text.trim(),
        names: {pid: (p['name'] ?? '').toString()});
    if (context.mounted) toast(context, 'اتسجلت الحركة ✔');
  } catch (e) {
    if (context.mounted) toast(context, '$e', error: true);
  }
}
