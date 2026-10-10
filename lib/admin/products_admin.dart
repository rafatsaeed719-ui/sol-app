import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../core/app.dart';
import 'reports_screen.dart';

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
        stream: db.collection('products').snapshots(),
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
          return Column(children: [
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
                        final net = netUnit(toD(p['wholesalePrice']), toD(p['discount']));
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
                                'بيع ${money(p['sellPrice'])} • جملة ${money(p['wholesalePrice'])} • خصم ${toD(p['discount']).toStringAsFixed(1)}%\nالصافي ${money(net)}${active ? '' : ' • مخفي'}'),
                            isThreeLine: true,
                            trailing: IconButton(
                              tooltip: 'حركة الصنف',
                              icon: const Icon(Icons.timeline, color: kPrimary),
                              onPressed: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) => ProductMovement(
                                          productId: list[i].id, name: p['name'] ?? ''))),
                            ),
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
  final wholesale = TextEditingController();
  final discount = TextEditingController(text: '0');
  String? image;
  bool active = true;
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
      wholesale.text = _n(toD(d['wholesalePrice']));
      discount.text = _n(toD(d['discount']));
      image = d['image'];
      active = d['active'] != false;
    }
    for (final c in [sell, wholesale, discount]) {
      c.addListener(() => setState(() {}));
    }
  }

  String _n(double v) => v % 1 == 0 ? v.toStringAsFixed(0) : v.toString();

  Future<void> save() async {
    if (name.text.trim().isEmpty || toD(wholesale.text) <= 0) {
      toast(context, 'اكتب اسم الصنف وسعر الجملة', error: true);
      return;
    }
    setState(() => busy = true);
    final data = {
      'name': name.text.trim(),
      'category': category.text.trim(),
      'description': desc.text.trim(),
      'sellPrice': toD(sell.text),
      'wholesalePrice': toD(wholesale.text),
      'discount': toD(discount.text).clamp(0, 100).toDouble(),
      'image': image ?? '',
      'active': active,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    try {
      if (widget.id == null) {
        await db.collection('products').add({...data, 'createdAt': FieldValue.serverTimestamp()});
      } else {
        await db.collection('products').doc(widget.id).update(data);
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
    final net = netUnit(toD(wholesale.text), toD(discount.text));
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
          Expanded(child: _f(sell, 'سعر البيع', number: true)),
          const SizedBox(width: 8),
          Expanded(child: _f(wholesale, 'سعر الجملة *', number: true)),
        ]),
        _f(discount, 'نسبة الخصم %', number: true),
        Card(
          margin: const EdgeInsets.only(bottom: 12),
          color: kPrimary.withValues(alpha: 0.05),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Expanded(
                  child: Text('سعر المحل الصافي: ${money(net)}',
                      style: const TextStyle(fontWeight: FontWeight.bold))),
              Text('مكسب المحل ${money(margin)}',
                  style: TextStyle(color: margin >= 0 ? kSuccess : kDanger)),
            ]),
          ),
        ),
        _f(desc, 'وصف (اختياري)', lines: 3),
        SwitchListTile(
          value: active,
          onChanged: (v) => setState(() => active = v),
          title: const Text('ظاهر للعملاء'),
          subtitle: const Text('اقفله لو الصنف خلصان مؤقتاً'),
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
