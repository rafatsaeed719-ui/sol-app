import 'package:flutter/material.dart';

import '../core/app.dart';
import '../core/data.dart';

class OffersScreen extends StatelessWidget {
  const OffersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: scoped('offers').where('active', isEqualTo: true).snapshots(),
      builder: (context, snap) {
        if (snap.hasError) return EmptyView('حصلت مشكلة: ${snap.error}');
        if (!snap.hasData) return const Loading();
        final now = DateTime.now();
        final list = sortByDate(snap.data!.docs).where((d) {
          final e = tsToDate(d.data()['endsAt']);
          return e == null || e.isAfter(now);
        }).toList();
        if (list.isEmpty) {
          return const EmptyView('مفيش عروض دلوقتي — هيوصلك إشعار أول ما ينزل عرض جديد',
              icon: Icons.local_offer_outlined);
        }
        return ListView.builder(
          padding: const EdgeInsets.only(top: 8, bottom: 90),
          itemCount: list.length,
          itemBuilder: (c, i) => OfferCard(list[i].id, list[i].data()),
        );
      },
    );
  }
}

class OfferCard extends StatelessWidget {
  final String id;
  final Map<String, dynamic> o;
  const OfferCard(this.id, this.o, {super.key});

  Future<void> order(BuildContext context) async {
    final pid = (o['productId'] ?? '').toString();
    if (pid.isEmpty) {
      toast(context, 'العرض ده للعلم بس — كلّمنا من الشات للطلب');
      return;
    }
    final p = await db.collection('products').doc(pid).get();
    if (!context.mounted) return;
    if (!p.exists) {
      toast(context, 'الصنف ده مبقاش متاح', error: true);
      return;
    }
    Cart.I.addOffer(id, o, p.data()!);
    toast(context, 'اتضاف العرض للسلة ✔');
  }

  @override
  Widget build(BuildContext context) {
    final disc = toD(o['discount']);
    final minQ = toI(o['minQty']);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if ((o['image'] ?? '').toString().isNotEmpty)
          AspectRatio(aspectRatio: 16 / 9, child: B64Image(o['image'])),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.local_fire_department, color: kDanger),
              const SizedBox(width: 4),
              Expanded(
                child: Text(o['title'] ?? '',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              ),
              if (disc > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color: kDanger, borderRadius: BorderRadius.circular(10)),
                  child: Text('خصم ${disc.toStringAsFixed(disc % 1 == 0 ? 0 : 1)}%',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
            ]),
            if ((o['description'] ?? '').toString().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(o['description']),
              ),
            const SizedBox(height: 6),
            if ((o['productName'] ?? '').toString().isNotEmpty)
              Text('الصنف: ${o['productName']}${minQ > 1 ? ' • أقل كمية $minQ' : ''}',
                  style: const TextStyle(color: Colors.black54)),
            if (o['endsAt'] != null)
              Text('ينتهي: ${fmtDate(o['endsAt'])}',
                  style: const TextStyle(color: kDanger, fontSize: 12)),
            if (!isAdmin && (o['productId'] ?? '').toString().isNotEmpty) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: kAccent),
                  onPressed: () => order(context),
                  icon: const Icon(Icons.add_shopping_cart),
                  label: const Text('اطلب العرض'),
                ),
              ),
            ],
          ]),
        ),
      ]),
    );
  }
}
