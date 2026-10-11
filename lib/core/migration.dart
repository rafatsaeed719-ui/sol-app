import 'package:cloud_firestore/cloud_firestore.dart';

import 'app.dart';

/// بينقل بيانات SOL القديمة (قبل نظام المحلات) لمحل SOL — بيشتغل مرة واحدة للمدير العام.
Future<void> migrateToStores() async {
  final storeRef = db.collection('stores').doc(kMainStore);
  final st = await storeRef.get();
  if (st.exists && st.data()?['migrated'] == true) return;

  if (!st.exists) {
    await storeRef.set({
      'name': 'SOL Perfume',
      'slogan': 'عطرك، بصمتك',
      'logo': '',
      'active': true,
      'ownerUid': uid,
      'ownerEmail': kAdminEmail,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> fix(String col, Map<String, dynamic> Function(Map<String, dynamic>) extra) async {
    final snap = await db.collection(col).get();
    var batch = db.batch();
    var n = 0;
    for (final d in snap.docs) {
      final m = d.data();
      if (m['storeId'] != null) continue;
      batch.update(d.reference, {'storeId': kMainStore, ...extra(m)});
      n++;
      if (n % 400 == 0) {
        await batch.commit();
        batch = db.batch();
      }
    }
    if (n % 400 != 0) await batch.commit();
  }

  for (final c in ['products', 'offers', 'orders', 'invoices', 'payments', 'returns', 'chats']) {
    await fix(c, (_) => {});
  }
  await fix('notifications', (m) {
    final to = (m['to'] ?? '').toString();
    if (to == 'admin' || to == 'all') return {'to': '${to}_$kMainStore'};
    return {};
  });
  await fix('users', (m) => {'role': m['role'] ?? 'customer'});

  // الإعدادات وعدّاد الفواتير
  for (final pair in [
    ['app', 'settings'],
    ['counter', 'counter'],
  ]) {
    try {
      final old = await db.collection('settings').doc(pair[0]).get();
      final target = storeRef.collection('meta').doc(pair[1]);
      if (old.exists && !(await target.get()).exists) {
        await target.set(old.data()!);
      }
    } catch (_) {}
  }

  await storeRef.set({'migrated': true}, SetOptions(merge: true));
}
