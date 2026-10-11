import 'package:flutter/material.dart';

import '../auth/location_picker.dart';
import '../auth/register_screen.dart';
import '../core/app.dart';
import '../core/data.dart';
import '../shared/invoice_view.dart';

class AccountScreen extends StatelessWidget {
  final Map<String, dynamic> me;
  const AccountScreen({super.key, required this.me});

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.only(bottom: 30), children: [
      Container(
        padding: const EdgeInsets.all(18),
        color: kPrimary,
        child: Row(children: [
          Avatar(me['photo'], radius: 36),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(me['shopName'] ?? '',
                  style: const TextStyle(
                      color: Colors.white, fontSize: 19, fontWeight: FontWeight.bold)),
              Text(me['ownerName'] ?? '', style: const TextStyle(color: Colors.white70)),
              Text(me['phone'] ?? '',
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(color: Colors.white70)),
            ]),
          ),
          IconButton(
            tooltip: 'تعديل البيانات',
            color: Colors.white,
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => RegisterScreen(existing: me))),
            icon: const Icon(Icons.edit),
          ),
        ]),
      ),
      // ---------- النقاط ----------
      StreamBuilder<AppSettings>(
        stream: settingsStream(),
        builder: (context, s) {
          final st = s.data ?? const AppSettings();
          final pts = toI(me['points']);
          final toNext = st.pointsForReward <= 0
              ? 0
              : st.pointsForReward - (pts % st.pointsForReward);
          final progress =
              st.pointsForReward <= 0 ? 0.0 : (pts % st.pointsForReward) / st.pointsForReward;
          return Card(
            margin: const EdgeInsets.all(12),
            color: const Color(0xFFFFF6E6),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.stars_rounded, color: kAccent, size: 34),
                  const SizedBox(width: 8),
                  Text('$pts نقطة',
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
                  const Spacer(),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    const Text('قيمتها دلوقتي', style: TextStyle(fontSize: 11)),
                    Text(money(st.valueOf(pts)),
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, color: kSuccess, fontSize: 16)),
                  ]),
                ]),
                const SizedBox(height: 10),
                LinearProgressIndicator(
                  value: progress,
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(8),
                  color: kAccent,
                  backgroundColor: Colors.white,
                ),
                const SizedBox(height: 6),
                Text('فاضلك $toNext نقطة وتكسب ${money(st.rewardValue)} خصم 🔥',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(st.rulesText, style: const TextStyle(fontSize: 12, color: Colors.black54)),
              ]),
            ),
          );
        },
      ),
      // ---------- الحساب والفواتير ----------
      StreamBuilder(
        stream: scoped('invoices').where('customerId', isEqualTo: uid).snapshots(),
        builder: (context, snap) {
          if (snap.hasError) return EmptyView('${snap.error}');
          if (!snap.hasData) return const Loading();
          final docs = sortByDate(snap.data!.docs);
          final s = summarize(docs.map((e) => e.data()));
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const SectionTitle('حسابي'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 2.1,
                children: [
                  StatTile('إجمالي الفواتير', money(s.total), icon: Icons.receipt_long),
                  StatTile('اللي دفعته', money(s.paid),
                      color: kSuccess, icon: Icons.check_circle_outline),
                  StatTile('المرتجعات', money(s.returned),
                      color: Colors.blue, icon: Icons.assignment_return),
                  StatTile('اللي عليك', money(s.balance),
                      color: s.balance > 0 ? kDanger : kSuccess,
                      icon: Icons.account_balance_wallet),
                ],
              ),
            ),
            if (s.overdueCount > 0)
              Card(
                color: const Color(0xFFFDECEA),
                child: ListTile(
                  leading: const Icon(Icons.warning_amber, color: kDanger),
                  title: Text('عليك ${money(s.overdue)} متأخرة',
                      style: const TextStyle(color: kDanger, fontWeight: FontWeight.bold)),
                  subtitle: Text('في ${s.overdueCount} فاتورة عدّى ميعاد تحصيلها'),
                ),
              ),
            SectionTitle('فواتيري (${docs.length})'),
            if (docs.isEmpty) const EmptyView('مفيش فواتير لسه'),
            ...docs.map((d) => InvoiceTile(d.id, d.data())),
          ]);
        },
      ),
      if (me['lat'] != null) ...[
        const SectionTitle('موقع المحل'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: ShopMap(lat: toD(me['lat']), lng: toD(me['lng']), height: 150),
        ),
      ],
      const SizedBox(height: 16),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(foregroundColor: kDanger),
          onPressed: () async {
            if (await confirm(context, 'تسجيل خروج', 'عاوز تخرج من حسابك؟')) {
              Cart.I.clear();
              await auth.signOut();
            }
          },
          icon: const Icon(Icons.logout),
          label: const Text('تسجيل خروج'),
        ),
      ),
    ]);
  }
}
