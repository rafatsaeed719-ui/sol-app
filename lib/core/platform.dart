import 'package:cloud_firestore/cloud_firestore.dart';

import 'app.dart';

/// باقة اشتراك في البرنامج (المدير العام بيحدد أسعارها)
class Plan {
  final String name;
  final int months;
  final double price;
  final String note;
  const Plan({required this.name, required this.months, required this.price, this.note = ''});

  factory Plan.fromMap(Map m) => Plan(
        name: (m['name'] ?? '').toString(),
        months: toI(m['months']),
        price: toD(m['price']),
        note: (m['note'] ?? '').toString(),
      );

  Map<String, dynamic> toMap() => {'name': name, 'months': months, 'price': price, 'note': note};

  String get period => months == 12
      ? 'سنة'
      : months == 0
          ? 'مفتوح'
          : months == 1
              ? 'شهر'
              : '$months شهور';
}

const List<Plan> kDefaultPlans = [
  Plan(name: 'شهري', months: 1, price: 300),
  Plan(name: '3 شهور', months: 3, price: 800),
  Plan(name: 'سنوي', months: 12, price: 2500, note: 'الأوفر'),
];

class PlatformConfig {
  final List<Plan> plans;
  final String paymentInfo; // طريقة الدفع (فودافون كاش / إنستاباي ...)
  final bool signupOpen;
  const PlatformConfig({required this.plans, this.paymentInfo = '', this.signupOpen = true});

  factory PlatformConfig.fromMap(Map<String, dynamic>? m) {
    if (m == null) return const PlatformConfig(plans: kDefaultPlans);
    final list = (m['plans'] as List? ?? []).map((e) => Plan.fromMap(e as Map)).toList();
    return PlatformConfig(
      plans: list.isEmpty ? kDefaultPlans : list,
      paymentInfo: (m['paymentInfo'] ?? '').toString(),
      signupOpen: m['signupOpen'] != false,
    );
  }

  Map<String, dynamic> toMap() => {
        'plans': plans.map((e) => e.toMap()).toList(),
        'paymentInfo': paymentInfo,
        'signupOpen': signupOpen,
      };
}

DocumentReference<Map<String, dynamic>> get platformRef =>
    db.collection('platform').doc('config');

Stream<PlatformConfig> platformStream() =>
    platformRef.snapshots().map((s) => PlatformConfig.fromMap(s.data()));

DateTime addMonths(DateTime d, int months) => DateTime(d.year, d.month + months, d.day);

/// تفعيل أو تجديد اشتراك محل بباقة — وبيتسجل في سجل الاشتراكات
Future<DateTime> activateStore(String storeId, Map<String, dynamic> store, Plan plan,
    {double? paid}) async {
  final cur = tsToDate(store['subscriptionEnd']);
  final base = (cur != null && cur.isAfter(DateTime.now()) && store['status'] != 'pending')
      ? cur
      : DateTime.now();
  final end = addMonths(base, plan.months);
  await db.collection('stores').doc(storeId).update({
    'active': true,
    'status': 'active',
    'plan': plan.toMap(),
    'subscriptionEnd': Timestamp.fromDate(end),
  });
  await db.collection('subscriptions').add({
    'storeId': storeId,
    'storeName': store['name'] ?? storeId,
    'plan': plan.name,
    'months': plan.months,
    'price': paid ?? plan.price,
    'from': Timestamp.fromDate(base),
    'to': Timestamp.fromDate(end),
    'createdAt': FieldValue.serverTimestamp(),
  });
  return end;
}
