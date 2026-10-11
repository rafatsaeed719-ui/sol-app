import 'package:flutter/material.dart';

import '../core/app.dart';
import '../core/data.dart';
import 'catalog_screen.dart';

class CartScreen extends StatefulWidget {
  final Map<String, dynamic> me;
  const CartScreen({super.key, required this.me});
  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  final note = TextEditingController();
  bool busy = false;

  Future<void> order() async {
    final ok = await confirm(context, 'تأكيد الطلب',
        'هتطلب ${Cart.I.count} قطعة بإجمالي ${money(Cart.I.total)}؟');
    if (!ok) return;
    setState(() => busy = true);
    try {
      await placeOrder(widget.me, note: note.text.trim());
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (c) => AlertDialog(
          icon: const Icon(Icons.check_circle, color: kSuccess, size: 56),
          title: const Text('تم إرسال طلبك'),
          content: const Text('هنتواصل معاك ونوصّلك الطلب في أقرب وقت 🙏'),
          actions: [
            FilledButton(onPressed: () => Navigator.pop(c), child: const Text('تمام')),
          ],
        ),
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) toast(context, 'الطلب متبعتش: $e', error: true);
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('السلة')),
      body: ListenableBuilder(
        listenable: Cart.I,
        builder: (context, _) {
          final lines = Cart.I.lines.values.toList();
          if (lines.isEmpty) {
            return const EmptyView('السلة فاضية — ضيف أصناف من صفحة المنتجات',
                icon: Icons.shopping_cart_outlined);
          }
          return ListView(padding: const EdgeInsets.only(top: 8), children: [
            for (final l in lines)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: B64Image(l.image, width: 60, height: 60),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(l.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                        Text(
                            'سعر البيع ${money(l.sellPrice)} • خصم ${l.discount.toStringAsFixed(1)}%',
                            style: const TextStyle(fontSize: 12, color: Colors.black54)),
                        Text('جملة ${money(l.unitNet)} × ${l.qty} = ${money(l.lineTotal)}',
                            style: const TextStyle(color: kPrimary, fontWeight: FontWeight.w600)),
                      ]),
                    ),
                    Column(children: [
                      QtyStepper(
                          compact: true,
                          value: l.qty,
                          min: 0,
                          onChanged: (v) => Cart.I.setQty(l.key, v)),
                    ]),
                  ]),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: note,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'ملاحظات على الطلب (اختياري)'),
              ),
            ),
          ]);
        },
      ),
      bottomNavigationBar: ListenableBuilder(
        listenable: Cart.I,
        builder: (context, _) => Cart.I.lines.isEmpty
            ? const SizedBox()
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: SizedBox(
                    height: 50,
                    child: FilledButton.icon(
                      onPressed: busy ? null : order,
                      icon: const Icon(Icons.send),
                      label: Text('ابعت الطلب — ${money(Cart.I.total)}',
                          style: const TextStyle(fontSize: 16)),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}
