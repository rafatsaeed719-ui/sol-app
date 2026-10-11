import 'package:flutter/material.dart';

import '../core/app.dart';
import '../core/data.dart';

class CatalogScreen extends StatefulWidget {
  const CatalogScreen({super.key});
  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  String search = '';
  String category = '';

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: scoped('products').where('active', isEqualTo: true).snapshots(),
      builder: (context, snap) {
        if (snap.hasError) return EmptyView('حصلت مشكلة: ${snap.error}');
        if (!snap.hasData) return const Loading();
        final all = [...snap.data!.docs]
          ..sort((a, b) =>
              (a.data()['name'] ?? '').toString().compareTo((b.data()['name'] ?? '').toString()));
        final cats = <String>{
          for (final d in all)
            if ((d.data()['category'] ?? '').toString().isNotEmpty) d.data()['category']
        }.toList();
        final list = all.where((d) {
          final p = d.data();
          if (category.isNotEmpty && p['category'] != category) return false;
          if (search.isNotEmpty &&
              !(p['name'] ?? '').toString().toLowerCase().contains(search.toLowerCase())) {
            return false;
          }
          return true;
        }).toList();
        return Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: TextField(
              decoration: const InputDecoration(
                  hintText: 'دوّر على صنف...', prefixIcon: Icon(Icons.search)),
              onChanged: (v) => setState(() => search = v.trim()),
            ),
          ),
          if (cats.isNotEmpty)
            SizedBox(
              height: 46,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(4),
                    child: ChoiceChip(
                        label: const Text('الكل'),
                        selected: category.isEmpty,
                        onSelected: (_) => setState(() => category = '')),
                  ),
                  for (final c in cats)
                    Padding(
                      padding: const EdgeInsets.all(4),
                      child: ChoiceChip(
                          label: Text(c),
                          selected: category == c,
                          onSelected: (_) => setState(() => category = c)),
                    ),
                ],
              ),
            ),
          Expanded(
            child: list.isEmpty
                ? const EmptyView('مفيش أصناف', icon: Icons.inventory_2_outlined)
                : GridView.builder(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 90),
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 220,
                      childAspectRatio: 0.62,
                      crossAxisSpacing: 4,
                      mainAxisSpacing: 4,
                    ),
                    itemCount: list.length,
                    itemBuilder: (c, i) => ProductCard(list[i].id, list[i].data()),
                  ),
          ),
        ]);
      },
    );
  }
}

class ProductCard extends StatelessWidget {
  final String id;
  final Map<String, dynamic> p;
  const ProductCard(this.id, this.p, {super.key});

  @override
  Widget build(BuildContext context) {
    final disc = toD(p['discount']);
    final net = netUnit(toD(p['sellPrice']), disc, toD(p['wholesalePrice']));
    final st = stockOf(p);
    final out = st != null && st <= 0;
    return Card(
      margin: const EdgeInsets.all(2),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(
            context, MaterialPageRoute(builder: (_) => ProductDetail(id: id, p: p))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            child: Stack(fit: StackFit.expand, children: [
              B64Image(p['image']),
              if (disc > 0)
                Positioned(
                  top: 6,
                  left: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                        color: kDanger, borderRadius: BorderRadius.circular(8)),
                    child: Text('خصم ${disc.toStringAsFixed(disc % 1 == 0 ? 0 : 1)}%',
                        style: const TextStyle(color: Colors.white, fontSize: 11)),
                  ),
                ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p['name'] ?? '',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              Row(children: [
                if (disc > 0)
                  Text(money(p['sellPrice']),
                      style: const TextStyle(
                          fontSize: 11,
                          color: Colors.black45,
                          decoration: TextDecoration.lineThrough)),
                if (disc > 0) const SizedBox(width: 4),
                Flexible(
                  child: Text(money(net),
                      style: const TextStyle(
                          color: kPrimary, fontWeight: FontWeight.bold, fontSize: 15)),
                ),
              ]),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(6),
            child: SizedBox(
              height: 34,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(padding: EdgeInsets.zero),
                onPressed: out
                    ? null
                    : () async {
                        final q = await pickQty(context, p['name'] ?? '', net);
                        if (q == null || !context.mounted) return;
                        Cart.I.addProduct(id, p, qty: q);
                        toast(context, 'اتضاف $q × ${p['name']} للسلة');
                      },
                icon: Icon(out ? Icons.block : Icons.add_shopping_cart, size: 18),
                label: Text(out ? 'نفذت الكمية' : 'أضف'),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class ProductDetail extends StatefulWidget {
  final String id;
  final Map<String, dynamic> p;
  const ProductDetail({super.key, required this.id, required this.p});
  @override
  State<ProductDetail> createState() => _ProductDetailState();
}

class _ProductDetailState extends State<ProductDetail> {
  int qty = 1;
  @override
  Widget build(BuildContext context) {
    final p = widget.p;
    final disc = toD(p['discount']);
    final net = netUnit(toD(p['sellPrice']), disc, toD(p['wholesalePrice']));
    final st = stockOf(p);
    final out = st != null && st <= 0;
    return Scaffold(
      appBar: AppBar(title: Text(p['name'] ?? '')),
      body: ListView(children: [
        AspectRatio(aspectRatio: 1.2, child: B64Image(p['image'], fit: BoxFit.contain)),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p['name'] ?? '',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            if ((p['category'] ?? '').toString().isNotEmpty)
              Text(p['category'], style: const TextStyle(color: Colors.black54)),
            const SizedBox(height: 12),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(children: [
                  _row('سعر البيع للجمهور', money(p['sellPrice'])),
                  _row('نسبة الخصم', '${disc.toStringAsFixed(1)}%'),
                  const Divider(),
                  _row('سعر الجملة (سعرك)', money(net), bold: true),
                  _row('مكسبك في القطعة', money(toD(p['sellPrice']) - net),
                      color: kSuccess),
                ]),
              ),
            ),
            if ((p['description'] ?? '').toString().isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(p['description']),
            ],
          ]),
        ),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            QtyStepper(value: qty, onChanged: (v) => setState(() => qty = v)),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: out
                    ? null
                    : () {
                  Cart.I.addProduct(widget.id, p, qty: qty);
                  toast(context, 'اتضاف للسلة');
                  Navigator.pop(context);
                },
                child: Text(out ? 'نفذت الكمية' : 'أضف للسلة (${money(net * qty)})'),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _row(String k, String v, {bool bold = false, Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Expanded(child: Text(k, style: const TextStyle(color: Colors.black54))),
          Text(v,
              style: TextStyle(
                  fontWeight: bold ? FontWeight.bold : FontWeight.w500,
                  fontSize: bold ? 17 : 14,
                  color: color ?? (bold ? kPrimary : null))),
        ]),
      );
}


/// عدّاد كمية: - رقم + ، ودوسة على الرقم تكتب الكمية بإيدك
class QtyStepper extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;
  final int min;
  final bool compact;
  const QtyStepper(
      {super.key,
      required this.value,
      required this.onChanged,
      this.min = 1,
      this.compact = false});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      compact
          ? IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: value > min ? () => onChanged(value - 1) : null,
              icon: const Icon(Icons.remove_circle_outline))
          : IconButton.outlined(
              onPressed: value > min ? () => onChanged(value - 1) : null,
              icon: const Icon(Icons.remove)),
      InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () async {
          final c = TextEditingController(text: '$value');
          final r = await showDialog<int>(
            context: context,
            builder: (d) => AlertDialog(
              title: const Text('اكتب الكمية'),
              content: TextField(
                controller: c,
                autofocus: true,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 22),
                onSubmitted: (v) => Navigator.pop(d, toI(v)),
              ),
              actions: [
                FilledButton(
                    onPressed: () => Navigator.pop(d, toI(c.text)), child: const Text('تمام')),
              ],
            ),
          );
          if (r != null && r >= min) onChanged(r);
        },
        child: Container(
          constraints: BoxConstraints(minWidth: compact ? 32 : 56),
          padding: EdgeInsets.symmetric(horizontal: compact ? 4 : 10, vertical: 8),
          alignment: Alignment.center,
          child: Text('$value',
              style: TextStyle(fontSize: compact ? 16 : 20, fontWeight: FontWeight.bold)),
        ),
      ),
      compact
          ? IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: () => onChanged(value + 1),
              icon: const Icon(Icons.add_circle_outline))
          : IconButton.outlined(
              onPressed: () => onChanged(value + 1), icon: const Icon(Icons.add)),
    ]);
  }
}

/// نافذة اختيار الكمية قبل الإضافة للسلة
Future<int?> pickQty(BuildContext context, String name, double unit) {
  var q = 1;
  return showModalBottomSheet<int>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text('سعر القطعة ${money(unit)}', style: const TextStyle(color: Colors.black54)),
            const SizedBox(height: 16),
            QtyStepper(value: q, onChanged: (v) => set(() => q = v)),
            const SizedBox(height: 10),
            Wrap(spacing: 8, children: [
              for (final n in const [6, 12, 24, 50])
                ActionChip(label: Text('$n'), onPressed: () => set(() => q = n)),
            ]),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                onPressed: () => Navigator.pop(c, q),
                icon: const Icon(Icons.add_shopping_cart),
                label: Text('أضف $q للسلة — ${money(unit * q)}'),
              ),
            ),
          ]),
        ),
      ),
    ),
  );
}
