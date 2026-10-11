import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../core/app.dart';
import '../core/data.dart';
import '../customer/offers_screen.dart';

class OffersAdmin extends StatelessWidget {
  const OffersAdmin({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('العروض')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () =>
            Navigator.push(context, MaterialPageRoute(builder: (_) => const OfferForm())),
        icon: const Icon(Icons.add),
        label: const Text('عرض جديد'),
      ),
      body: StreamBuilder(
        stream: scoped('offers').snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) return const Loading();
          final docs = sortByDate(snap.data!.docs);
          if (docs.isEmpty) {
            return const EmptyView('اعمل أول عرض — هيوصل إشعار لكل العملاء',
                icon: Icons.local_offer_outlined);
          }
          return ListView(padding: const EdgeInsets.only(bottom: 90, top: 8), children: [
            for (final d in docs)
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Opacity(
                  opacity: d.data()['active'] == true ? 1 : 0.5,
                  child: OfferCard(d.id, d.data()),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(children: [
                    const Text('مفعّل'),
                    Switch(
                      value: d.data()['active'] == true,
                      onChanged: (v) =>
                          db.collection('offers').doc(d.id).update({'active': v}),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () => notify('all', '🔥 ${d.data()['title']}',
                              (d.data()['description'] ?? 'عرض جديد من $storeName').toString(),
                              type: 'offer', refId: d.id)
                          .then((_) {
                        if (context.mounted) toast(context, 'اتبعت الإشعار لكل العملاء');
                      }),
                      icon: const Icon(Icons.campaign),
                      label: const Text('ابعت تاني'),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: kDanger),
                      onPressed: () async {
                        if (await confirm(context, 'حذف العرض', 'متأكد؟')) {
                          await db.collection('offers').doc(d.id).delete();
                        }
                      },
                    ),
                  ]),
                ),
                const Divider(),
              ]),
          ]);
        },
      ),
    );
  }
}

class OfferForm extends StatefulWidget {
  const OfferForm({super.key});
  @override
  State<OfferForm> createState() => _OfferFormState();
}

class _OfferFormState extends State<OfferForm> {
  final title = TextEditingController();
  final desc = TextEditingController();
  final discount = TextEditingController();
  final minQty = TextEditingController(text: '1');
  String? image;
  String? productId;
  String productName = '';
  DateTime? endsAt = DateTime.now().add(const Duration(days: 7));
  bool busy = false;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> products = [];

  @override
  void initState() {
    super.initState();
    scoped('products').get().then((s) {
      if (!mounted) return;
      setState(() {
        products = [...s.docs]
          ..sort((a, b) => (a.data()['name'] ?? '').toString().compareTo(
              (b.data()['name'] ?? '').toString()));
      });
    });
  }

  Future<void> save() async {
    if (title.text.trim().isEmpty) {
      toast(context, 'اكتب عنوان العرض', error: true);
      return;
    }
    setState(() => busy = true);
    try {
      final ref = await db.collection('offers').add({
        'storeId': sid,
        'title': title.text.trim(),
        'description': desc.text.trim(),
        'image': image ?? '',
        'productId': productId,
        'productName': productName,
        'discount': toD(discount.text).clamp(0, 100).toDouble(),
        'minQty': toI(minQty.text) < 1 ? 1 : toI(minQty.text),
        'endsAt': endsAt == null ? null : Timestamp.fromDate(endsAt!),
        'active': true,
        'createdAt': FieldValue.serverTimestamp(),
      });
      await notify('all', '🔥 عرض جديد: ${title.text.trim()}',
          desc.text.trim().isEmpty ? 'افتح العروض واطلب قبل ما يخلص' : desc.text.trim(),
          type: 'offer', refId: ref.id);
      if (!mounted) return;
      toast(context, 'العرض نزل واتبعت إشعار لكل العملاء ✔');
      Navigator.pop(context);
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    Map<String, dynamic>? p;
    for (final d in products) {
      if (d.id == productId) p = d.data();
    }
    return Scaffold(
      appBar: AppBar(title: const Text('عرض جديد')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        GestureDetector(
          onTap: () async {
            final x = await pickImageB64(context, maxWidth: 800);
            if (x != null) setState(() => image = x);
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
                height: 160, child: B64Image(image, placeholder: Icons.add_a_photo_outlined)),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
            controller: title, decoration: const InputDecoration(labelText: 'عنوان العرض *')),
        const SizedBox(height: 12),
        TextField(
            controller: desc,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'تفاصيل العرض')),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: productId,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'الصنف (عشان العميل يطلبه)'),
          items: [
            const DropdownMenuItem<String>(value: null, child: Text('بدون صنف (إعلان بس)')),
            for (final d in products)
              DropdownMenuItem<String>(value: d.id, child: Text(d.data()['name'] ?? '')),
          ],
          onChanged: (v) => setState(() {
            productId = v;
            productName = '';
            for (final d in products) {
              if (d.id == v) {
                productName = d.data()['name'] ?? '';
                if (discount.text.isEmpty || toD(discount.text) == 0) {
                  discount.text = toD(d.data()['discount']).toString();
                }
              }
            }
          }),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: TextField(
              controller: discount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'خصم العرض %'),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: minQty,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'أقل كمية'),
            ),
          ),
        ]),
        if (p != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
                'سعر البيع ${money(p['sellPrice'])} ← سعر العرض للمحل ${money(netUnit(toD(p['sellPrice']), toD(discount.text), toD(p['wholesalePrice'])))}',
                style: const TextStyle(color: kPrimary, fontWeight: FontWeight.bold)),
          ),
        const SizedBox(height: 8),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.event),
          title: Text(endsAt == null ? 'من غير تاريخ انتهاء' : 'ينتهي ${fmtDate(endsAt)}'),
          trailing: endsAt == null
              ? null
              : IconButton(
                  onPressed: () => setState(() => endsAt = null), icon: const Icon(Icons.clear)),
          onTap: () async {
            final d = await showDatePicker(
                context: context,
                initialDate: endsAt ?? DateTime.now(),
                firstDate: DateTime.now(),
                lastDate: DateTime(2035));
            if (d != null) setState(() => endsAt = DateTime(d.year, d.month, d.day, 23, 59));
          },
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 48,
          child: FilledButton.icon(
            onPressed: busy ? null : save,
            icon: const Icon(Icons.campaign),
            label: const Text('انشر العرض وابعت إشعار'),
          ),
        ),
      ]),
    );
  }
}
