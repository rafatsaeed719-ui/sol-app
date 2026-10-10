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
      stream: db.collection('products').where('active', isEqualTo: true).snapshots(),
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
    final net = netUnit(toD(p['wholesalePrice']), disc);
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
              Text('للجمهور: ${money(p['sellPrice'])}',
                  style: const TextStyle(fontSize: 11, color: Colors.black54)),
              Row(children: [
                if (disc > 0)
                  Text(money(p['wholesalePrice']),
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
                onPressed: () {
                  Cart.I.addProduct(id, p);
                  toast(context, 'اتضاف ${p['name']} للسلة');
                },
                icon: const Icon(Icons.add_shopping_cart, size: 18),
                label: const Text('أضف'),
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
    final net = netUnit(toD(p['wholesalePrice']), disc);
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
                  _row('سعر الجملة', money(p['wholesalePrice'])),
                  _row('نسبة الخصم', '${disc.toStringAsFixed(1)}%'),
                  const Divider(),
                  _row('سعرك الصافي', money(net), bold: true),
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
            IconButton.outlined(
                onPressed: qty > 1 ? () => setState(() => qty--) : null,
                icon: const Icon(Icons.remove)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text('$qty',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            IconButton.outlined(
                onPressed: () => setState(() => qty++), icon: const Icon(Icons.add)),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: () {
                  Cart.I.addProduct(widget.id, p, qty: qty);
                  toast(context, 'اتضاف للسلة');
                  Navigator.pop(context);
                },
                child: Text('أضف للسلة (${money(net * qty)})'),
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
