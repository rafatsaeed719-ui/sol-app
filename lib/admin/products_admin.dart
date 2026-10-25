import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../core/app.dart';
import '../core/data.dart';
import 'warehouse_screen.dart';

class ProductsAdmin extends StatefulWidget {
  const ProductsAdmin({super.key});
  @override
  State<ProductsAdmin> createState() => _ProductsAdminState();
}

class _ProductsAdminState extends State<ProductsAdmin> {
  String q = '';
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'addProduct',
        onPressed: () => Navigator.push(
            context, MaterialPageRoute(builder: (_) => const ProductForm())),
        icon: const Icon(Icons.add),
        label: const Text('صنف جديد'),
      ),
      body: StreamBuilder(
        stream: scoped('products').snapshots(),
        builder: (context, snap) {
          if (snap.hasError) return EmptyView('حصلت مشكلة: ${snap.error}');
          if (!snap.hasData) return const Loading();
          final list = snap.data!.docs.where((d) {
            if (q.isEmpty) return true;
            return '${d.data()['name']} ${d.data()['category']}'
                .toLowerCase()
                .contains(q.toLowerCase());
          }).toList()
            ..sort((a, b) => (a.data()['name'] ?? '')
                .toString()
                .compareTo((b.data()['name'] ?? '').toString()));
          final all = snap.data!.docs;
          final tracked = all.where((d) => stockOf(d.data()) != null).toList();
          final pieces = tracked.fold(0, (a, d) => a + stockOf(d.data())!);
          final stockValue = tracked.fold(
              0.0,
              (a, d) =>
                  a +
                  stockOf(d.data())! *
                      netUnit(toD(d.data()['sellPrice']), toD(d.data()['discount']),
                          toD(d.data()['wholesalePrice'])));
          final low = tracked
              .where((d) =>
                  stockOf(d.data())! <=
                  (d.data()['lowStock'] == null ? 5 : toI(d.data()['lowStock'])))
              .length;
          return Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: Row(children: [
                Expanded(child: StatTile('قطع في المخزن', '$pieces', icon: Icons.warehouse)),
                Expanded(
                    child: StatTile('قيمة المخزن (جملة)', money(stockValue),
                        icon: Icons.payments, color: kSuccess)),
                Expanded(
                    child: StatTile('قرب يخلص', '$low',
                        icon: Icons.warning_amber, color: low > 0 ? kDanger : kPrimary)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                decoration: const InputDecoration(
                    hintText: 'دوّر على صنف', prefixIcon: Icon(Icons.search)),
                onChanged: (v) => setState(() => q = v.trim()),
              ),
            ),
            Expanded(
              child: list.isEmpty
                  ? const EmptyView('ضيف أول صنف من الزرار تحت',
                      icon: Icons.inventory_2_outlined)
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 90),
                      itemCount: list.length,
                      itemBuilder: (c, i) {
                        final p = list[i].data();
                        final active = p['active'] != false;
                        final net = netUnit(toD(p['sellPrice']), toD(p['discount']),
                            toD(p['wholesalePrice']));
                        final stock = stockOf(p);
                        return Card(
                          child: ListTile(
                            onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => ProductForm(id: list[i].id, data: p))),
                            leading: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: B64Image(p['image'], width: 54, height: 54),
                            ),
                            title: Text(p['name'] ?? '',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: active ? null : Colors.grey,
                                    decoration: active ? null : TextDecoration.lineThrough)),
                            subtitle: Text(
                                'بيع ${money(p['sellPrice'])} • خصم ${toD(p['discount']).toStringAsFixed(1)}%\nجملة ${money(net)}${active ? '' : ' • مخفي'}'),
                            isThreeLine: true,
                            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                              _StockBadge(stock,
                                  low: p['lowStock'] == null ? 5 : toI(p['lowStock'])),
                              IconButton(
                              tooltip: 'حركة الصنف',
                              icon: const Icon(Icons.timeline, color: kPrimary),
                              onPressed: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) => ProductMovesScreen(
                                          productId: list[i].id, product: p))),
                              ),
                            ]),
                          ),
                        );
                      },
                    ),
            ),
          ]);
        },
      ),
    );
  }
}

class ProductForm extends StatefulWidget {
  final String? id;
  final Map<String, dynamic>? data;
  const ProductForm({super.key, this.id, this.data});
  @override
  State<ProductForm> createState() => _ProductFormState();
}

class _ProductFormState extends State<ProductForm> {
  final name = TextEditingController();
  final category = TextEditingController();
  final desc = TextEditingController();
  final sell = TextEditingController();
  final discount = TextEditingController(text: '0');
  final stock = TextEditingController();
  final addStock = TextEditingController();
  final supplier = TextEditingController();
  final lowStock = TextEditingController(text: '5');
  double oldWholesale = 0;
  String? image;
  bool active = true;
  bool featured = false;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    final d = widget.data;
    if (d != null) {
      name.text = d['name'] ?? '';
      category.text = d['category'] ?? '';
      desc.text = d['description'] ?? '';
      sell.text = _n(toD(d['sellPrice']));
      oldWholesale = toD(d['wholesalePrice']);
      discount.text = _n(toD(d['discount']));
      if (d['stock'] != null) stock.text = '${toI(d['stock'])}';
      if (d['lowStock'] != null) lowStock.text = '${toI(d['lowStock'])}';
      image = d['image'];
      active = d['active'] != false;
      featured = d['featured'] == true;
    }
    for (final c in [sell, discount, addStock]) {
      c.addListener(() => setState(() {}));
    }
  }

  String _n(double v) => v % 1 == 0 ? v.toStringAsFixed(0) : v.toString();

  Future<void> save() async {
    if (name.text.trim().isEmpty || toD(sell.text) <= 0) {
      toast(context, 'اكتب اسم الصنف وسعر البيع', error: true);
      return;
    }
    final disc = toD(discount.text).clamp(0, 100).toDouble();
    setState(() => busy = true);
    final data = {
      'name': name.text.trim(),
      'category': category.text.trim(),
      'description': desc.text.trim(),
      'sellPrice': toD(sell.text),
      'wholesalePrice': netUnit(toD(sell.text), disc),
      'discount': disc,
      if (widget.id == null && stock.text.trim().isNotEmpty) 'stock': toI(stock.text),
      'lowStock': toI(lowStock.text),
      'image': image ?? '',
      'active': active,
      'featured': featured,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    try {
      if (widget.id == null) {
        final ref = await db.collection('products').add(
            {...data, 'storeId': sid, 'createdAt': FieldValue.serverTimestamp()});
        if (toI(stock.text) != 0) {
          await db.collection('stockMoves').add({
            'storeId': sid,
            'productId': ref.id,
            'productName': name.text.trim(),
            'qty': toI(stock.text),
            'type': 'open',
            'party': supplier.text.trim(),
            'note': 'رصيد أول المدة',
            'after': toI(stock.text),
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
      } else {
        final ref = db.collection('products').doc(widget.id);
        await ref.update(data);
        final add = toI(addStock.text);
        if (add != 0) {
          if (widget.data?['stock'] == null) await ref.update({'stock': 0});
          await adjustStock({widget.id!: add},
              type: add > 0 ? 'in' : 'adjust',
              party: supplier.text.trim(),
              names: {widget.id!: name.text.trim()});
        }
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> delete() async {
    if (!await confirm(context, 'حذف الصنف',
        'الأفضل تخفيه بدل ما تحذفه عشان تقارير الحركة. تحذفه برضه؟')) {
      return;
    }
    await db.collection('products').doc(widget.id).delete();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final net = netUnit(toD(sell.text), toD(discount.text), oldWholesale);
    final margin = toD(sell.text) - net;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.id == null ? 'صنف جديد' : 'تعديل صنف'),
        actions: [
          if (widget.id != null)
            IconButton(onPressed: delete, icon: const Icon(Icons.delete_outline)),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        GestureDetector(
          onTap: () async {
            final p = await pickImageB64(context);
            if (p != null) setState(() => image = p);
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              height: 180,
              child: Stack(fit: StackFit.expand, children: [
                B64Image(image, placeholder: Icons.add_a_photo_outlined),
                const Positioned(
                  bottom: 8,
                  left: 8,
                  child: Chip(avatar: Icon(Icons.camera_alt, size: 16), label: Text('صورة الصنف')),
                ),
              ]),
            ),
          ),
        ),
        const SizedBox(height: 14),
        _f(name, 'اسم الصنف *'),
        _f(category, 'القسم / النوع (اختياري)'),
        Row(children: [
          Expanded(child: _f(sell, 'سعر البيع *', number: true)),
          const SizedBox(width: 8),
          Expanded(child: _f(discount, 'نسبة الخصم %', number: true)),
        ]),
        Card(
          margin: const EdgeInsets.only(bottom: 12),
          color: kAccent.withValues(alpha: 0.12),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(children: [
              Row(children: [
                const Text('سعر الجملة', style: TextStyle(fontSize: 15)),
                const Spacer(),
                Text(money(net),
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              ]),
              const SizedBox(height: 4),
              Row(children: [
                Text('= ${money(toD(sell.text))} − ${toD(discount.text).toStringAsFixed(toD(discount.text) % 1 == 0 ? 0 : 1)}%',
                    style: const TextStyle(color: Colors.black54)),
                const Spacer(),
                Text('مكسب المحل ${money(margin)}',
                    style: TextStyle(color: margin >= 0 ? kSuccess : kDanger)),
              ]),
            ]),
          ),
        ),
        const Text('📦 المخزن', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        const SizedBox(height: 8),
        if (widget.id == null) ...[
          _f(stock, 'الكمية الموجودة في المخزن', number: true),
          _f(supplier, 'جاية من مين؟ (المورد — اختياري)'),
        ] else ...[
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: const Icon(Icons.warehouse),
              title: Text(widget.data?['stock'] == null
                  ? 'المخزن مش متسجل للصنف ده'
                  : 'في المخزن دلوقتي: ${toI(widget.data?['stock'])} قطعة'),
              subtitle: toI(addStock.text) == 0 || widget.data?['stock'] == null
                  ? null
                  : Text('هيبقى: ${toI(widget.data?['stock']) + toI(addStock.text)} قطعة'),
            ),
          ),
          _f(addStock,
              widget.data?['stock'] == null
                  ? 'اكتب الكمية الموجودة'
                  : 'زوّد كمية (بضاعة جديدة) — أو اكتب بالسالب للخصم',
              number: true),
          if (toI(addStock.text) > 0) _f(supplier, 'جاية من مين؟ (المورد — اختياري)'),
        ],
        _f(lowStock, '🔔 نبّهني لما الكمية توصل لـ', number: true),
        _f(desc, 'وصف (اختياري)', lines: 3),
        SwitchListTile(
          value: active,
          onChanged: (v) => setState(() => active = v),
          title: const Text('ظاهر للعملاء'),
          subtitle: const Text('اقفله لو الصنف خلصان مؤقتاً'),
        ),
        SwitchListTile(
          value: featured,
          onChanged: (v) => setState(() => featured = v),
          title: const Text('⭐ صنف مميز'),
          subtitle: const Text('يظهر في "المختارات" على الصفحة الرئيسية للعملاء'),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 48,
          child: FilledButton(
              onPressed: busy ? null : save, child: const Text('حفظ', style: TextStyle(fontSize: 16))),
        ),
      ]),
    );
  }

  Widget _f(TextEditingController c, String label, {bool number = false, int lines = 1}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c,
          maxLines: lines,
          keyboardType:
              number ? const TextInputType.numberWithOptions(decimal: true) : null,
          decoration: InputDecoration(labelText: label),
        ),
      );
}


class _StockBadge extends StatelessWidget {
  final int? stock;
  final int low;
  const _StockBadge(this.stock, {this.low = 5});
  @override
  Widget build(BuildContext context) {
    if (stock == null) return const SizedBox();
    final c = stock! <= 0 ? kDanger : (stock! <= low ? Colors.orange : kSuccess);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
          color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('${stock!}', style: TextStyle(color: c, fontWeight: FontWeight.bold, fontSize: 16)),
        Text('مخزن', style: TextStyle(color: c, fontSize: 10)),
      ]),
    );
  }
}
