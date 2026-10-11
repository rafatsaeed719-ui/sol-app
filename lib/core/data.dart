import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'app.dart';

// ======================== الإعدادات ========================

class AppSettings {
  final int collectionDays; // أيام التحصيل الافتراضية
  final double amountPerPoint; // كل كام جنيه = نقطة
  final int pointsForReward; // كل كام نقطة
  final double rewardValue; // = كام جنيه خصم
  const AppSettings({
    this.collectionDays = 15,
    this.amountPerPoint = 10,
    this.pointsForReward = 100,
    this.rewardValue = 50,
  });

  factory AppSettings.fromMap(Map<String, dynamic>? m) {
    if (m == null) return const AppSettings();
    return AppSettings(
      collectionDays: toI(m['collectionDays'] ?? 15),
      amountPerPoint: toD(m['amountPerPoint'] ?? 10),
      pointsForReward: toI(m['pointsForReward'] ?? 100),
      rewardValue: toD(m['rewardValue'] ?? 50),
    );
  }

  Map<String, dynamic> toMap() => {
        'collectionDays': collectionDays,
        'amountPerPoint': amountPerPoint,
        'pointsForReward': pointsForReward,
        'rewardValue': rewardValue,
      };

  int pointsFor(double amount) =>
      amountPerPoint <= 0 ? 0 : (amount / amountPerPoint).floor();

  /// قيمة عدد من النقاط بالجنيه (بالمضاعفات الكاملة فقط)
  double valueOf(int points) {
    if (pointsForReward <= 0) return 0;
    return (points ~/ pointsForReward) * rewardValue;
  }

  String get rulesText =>
      'كل ${amountPerPoint.toStringAsFixed(0)} جنيه = نقطة، وكل $pointsForReward نقطة = ${rewardValue.toStringAsFixed(0)} جنيه خصم';
}

DocumentReference<Map<String, dynamic>> get settingsRef => storeMeta('settings');

Stream<AppSettings> settingsStream() =>
    settingsRef.snapshots().map((s) => AppSettings.fromMap(s.data()));

Future<AppSettings> getSettings() async =>
    AppSettings.fromMap((await settingsRef.get()).data());

// ======================== السلة ========================

class CartLine {
  final String key;
  final String productId;
  final String name;
  final String? image;
  final double sellPrice;
  final double wholesalePrice;
  final double discount;
  final String? offerId;
  int qty;
  CartLine({
    required this.key,
    required this.productId,
    required this.name,
    this.image,
    required this.sellPrice,
    required this.wholesalePrice,
    required this.discount,
    this.offerId,
    this.qty = 1,
  });
  double get unitNet => netUnit(sellPrice, discount, wholesalePrice);
  double get lineTotal => round2(unitNet * qty);

  Map<String, dynamic> toItem() => {
        'productId': productId,
        'name': name,
        'qty': qty,
        'sellPrice': sellPrice,
        'wholesalePrice': unitNet,
        'discount': discount,
        'unitNet': unitNet,
        if (offerId != null) 'offerId': offerId,
      };
}

class Cart extends ChangeNotifier {
  static final Cart I = Cart._();
  Cart._();
  final Map<String, CartLine> lines = {};

  int get count => lines.values.fold(0, (a, b) => a + b.qty);
  double get total => round2(lines.values.fold(0.0, (a, b) => a + b.lineTotal));

  void addProduct(String id, Map<String, dynamic> p, {int qty = 1}) {
    final l = lines[id];
    if (l != null) {
      l.qty += qty;
    } else {
      lines[id] = CartLine(
        key: id,
        productId: id,
        name: p['name'] ?? '',
        image: p['image'],
        sellPrice: toD(p['sellPrice']),
        wholesalePrice: toD(p['wholesalePrice']),
        discount: toD(p['discount']),
        qty: qty,
      );
    }
    notifyListeners();
  }

  void addOffer(String offerId, Map<String, dynamic> o, Map<String, dynamic> p) {
    final key = 'offer_$offerId';
    final minQ = toI(o['minQty']) < 1 ? 1 : toI(o['minQty']);
    final l = lines[key];
    if (l != null) {
      l.qty += minQ;
    } else {
      lines[key] = CartLine(
        key: key,
        productId: o['productId'],
        name: '${p['name'] ?? o['productName'] ?? ''} (عرض)',
        image: o['image'] ?? p['image'],
        sellPrice: toD(p['sellPrice']),
        wholesalePrice: toD(p['wholesalePrice']),
        discount: toD(o['discount']),
        offerId: offerId,
        qty: minQ,
      );
    }
    notifyListeners();
  }

  void setQty(String key, int q) {
    if (q <= 0) {
      lines.remove(key);
    } else {
      lines[key]?.qty = q;
    }
    notifyListeners();
  }

  void clear() {
    lines.clear();
    notifyListeners();
  }
}

// ======================== الإشعارات ========================

/// to: uid للعميل، 'admin' لمدير المحل، 'all' لكل عملاء المحل
Future<void> notify(String to, String title, String body,
    {String type = 'general', String? refId}) {
  final target = (to == 'admin' || to == 'all') ? '${to}_$sid' : to;
  return db.collection('notifications').add({
    'to': target,
    'storeId': sid,
    'title': title,
    'body': body,
    'type': type,
    'refId': refId,
    'createdAt': FieldValue.serverTimestamp(),
  });
}

// ======================== الطلبات ========================

Future<String> placeOrder(Map<String, dynamic> me, {String note = ''}) async {
  final c = Cart.I;
  if (c.lines.isEmpty) throw 'السلة فاضية';
  final ref = await db.collection('orders').add({
    'storeId': sid,
    'customerId': uid,
    'customerName': me['ownerName'] ?? '',
    'shopName': me['shopName'] ?? '',
    'items': c.lines.values.map((e) => e.toItem()).toList(),
    'total': c.total,
    'note': note,
    'status': 'new',
    'createdAt': FieldValue.serverTimestamp(),
  });
  await notify('admin', 'طلب جديد 🛒',
      '${me['shopName'] ?? ''} طلب أوردر بقيمة ${money(c.total)}',
      type: 'order', refId: ref.id);
  c.clear();
  return ref.id;
}

// ======================== الفواتير ========================

class InvLine {
  String productId;
  String name;
  int qty;
  double sellPrice;
  double wholesalePrice;
  double discount;
  InvLine({
    required this.productId,
    required this.name,
    required this.qty,
    required this.sellPrice,
    required this.wholesalePrice,
    required this.discount,
  });
  double get unitNet => netUnit(sellPrice, discount, wholesalePrice);
  double get lineTotal => round2(unitNet * qty);
  Map<String, dynamic> toMap() => {
        'productId': productId,
        'name': name,
        'qty': qty,
        'returnedQty': 0,
        'sellPrice': sellPrice,
        'wholesalePrice': unitNet,
        'discount': discount,
        'unitNet': unitNet,
      };
}

/// إنشاء فاتورة (من طلب أو يدوي). بيضيف نقاط للعميل ويخصم النقاط المستبدلة
/// وبيخصم الكميات من المخزن. بيرجع (id الفاتورة، رقمها).
Future<(String, int)> createInvoice({
  required String customerId,
  required String customerName,
  required List<InvLine> lines,
  required DateTime dueDate,
  required AppSettings settings,
  int collectionDays = 0,
  String? orderId,
  int redeemPoints = 0,
  double paidNow = 0,
  String note = '',
}) async {
  if (lines.isEmpty) throw 'الفاتورة من غير أصناف';
  final sellTotal = round2(lines.fold(0.0, (a, l) => a + l.sellPrice * l.qty));
  final gross = round2(lines.fold(0.0, (a, l) => a + l.lineTotal));
  final wholesaleTotal = gross;
  final redeemValue = settings.valueOf(redeemPoints);
  final usedPoints = settings.pointsForReward <= 0
      ? 0
      : (redeemPoints ~/ settings.pointsForReward) * settings.pointsForReward;
  final total = round2((gross - redeemValue).clamp(0, double.infinity).toDouble());
  final earned = settings.pointsFor(total);
  final counterRef = storeMeta('counter');
  final userRef = db.collection('users').doc(customerId);
  final invRef = db.collection('invoices').doc();

  final number = await db.runTransaction<int>((tx) async {
    final cs = await tx.get(counterRef);
    final us = await tx.get(userRef);
    final n = toI(cs.data()?['invoice']) + 1;
    final curPoints = toI(us.data()?['points']);
    if (usedPoints > curPoints) throw 'العميل معهوش نقاط كفاية';
    tx.set(counterRef, {'invoice': n}, SetOptions(merge: true));
    tx.set(invRef, {
      'storeId': sid,
      'number': n,
      'customerId': customerId,
      'customerName': customerName,
      'orderId': orderId,
      'items': lines.map((e) => e.toMap()).toList(),
      'sellTotal': sellTotal,
      'wholesaleTotal': wholesaleTotal,
      'discountTotal': round2(sellTotal - gross),
      'gross': gross,
      'pointsRedeemed': usedPoints,
      'redeemValue': redeemValue,
      'total': total,
      'paid': 0,
      'returned': 0,
      'balance': total,
      'pointsEarned': earned,
      'note': note,
      'dueDate': Timestamp.fromDate(dueDate),
      'collectionDays': collectionDays,
      'createdAt': FieldValue.serverTimestamp(),
    });
    tx.set(
        userRef,
        {'points': curPoints - usedPoints + earned},
        SetOptions(merge: true));
    if (orderId != null) {
      tx.update(db.collection('orders').doc(orderId),
          {'status': 'invoiced', 'invoiceId': invRef.id, 'invoiceNumber': n});
    }
    return n;
  });

  final used = <String, int>{};
  final names = <String, String>{};
  for (final l in lines) {
    used[l.productId] = (used[l.productId] ?? 0) - l.qty;
    names[l.productId] = l.name;
  }
  await adjustStock(used,
      type: 'sale', party: customerName, refId: invRef.id, refNumber: number, names: names);
  if (paidNow > 0) {
    await addPayment(invRef.id, paidNow, note: 'دفعة عند الاستلام');
  }
  await notify(customerId, 'فاتورة جديدة رقم $number',
      'إجمالي ${money(total)} — كسبت $earned نقطة 🎉',
      type: 'invoice', refId: invRef.id);
  return (invRef.id, number);
}

/// أنواع حركة المخزن
const Map<String, String> kMoveTypes = {
  'sale': 'بيع',
  'return': 'مرتجع',
  'in': 'وارد (بضاعة جديدة)',
  'adjust': 'تسوية / جرد',
  'invoice_delete': 'إلغاء فاتورة',
  'invoice_edit': 'تعديل فاتورة',
  'open': 'رصيد أول المدة',
};

/// يزوّد أو يقلل المخزن (بالسالب للخصم) ويسجّل الحركة.
/// الأصناف اللي مخزنها مش متتبع بتتسجل حركتها بس من غير ما يتغير رصيد.
Future<void> adjustStock(Map<String, int> changes,
    {required String type,
    String party = '',
    String? refId,
    int? refNumber,
    String note = '',
    Map<String, String> names = const {}}) async {
  final merged = <String, int>{};
  changes.forEach((k, v) {
    if (k.isNotEmpty && v != 0) merged[k] = (merged[k] ?? 0) + v;
  });
  for (final e in merged.entries) {
    try {
      final ref = db.collection('products').doc(e.key);
      final s = await ref.get();
      final p = s.data();
      int? after;
      if (p != null && p['stock'] != null) {
        await ref.update({'stock': FieldValue.increment(e.value)});
        after = toI(p['stock']) + e.value;
      }
      await db.collection('stockMoves').add({
        'storeId': sid,
        'productId': e.key,
        'productName': (p?['name'] ?? names[e.key] ?? '').toString(),
        'qty': e.value,
        'type': type,
        'party': party,
        'refId': refId,
        'refNumber': refNumber,
        'note': note,
        'after': after,
        'createdAt': FieldValue.serverTimestamp(),
      });
      // تنبيه إن الصنف قرب يخلص
      if (after != null && e.value < 0) {
        final low = p?['lowStock'] == null ? 5 : toI(p!['lowStock']);
        if (after <= low) {
          await notify(
              'admin',
              after <= 0 ? '⛔ الصنف خلص: ${p?['name']}' : '⚠️ الصنف قرب يخلص: ${p?['name']}',
              after <= 0 ? 'المخزن فاضي من الصنف ده' : 'باقي $after بس في المخزن',
              type: 'stock',
              refId: e.key);
        }
      }
    } catch (_) {}
  }
}

/// حذف فاتورة نهائياً: يرجّع البضاعة للمخزن، ويظبط النقاط، ويمسح الدفعات والمرتجعات بتاعتها
Future<void> deleteInvoice(String invoiceId, AppSettings settings) async {
  final invRef = db.collection('invoices').doc(invoiceId);
  final d = (await invRef.get()).data();
  if (d == null) throw 'الفاتورة مش موجودة';
  final customerId = (d['customerId'] ?? '').toString();
  final number = toI(d['number']);
  final items = List<Map<String, dynamic>>.from(
      (d['items'] as List? ?? []).map((e) => Map<String, dynamic>.from(e)));

  // النقاط: نشيل اللي كسبها ونرجّع اللي استبدلها
  final returnedPts = settings.pointsFor(toD(d['returned']));
  final delta = -toI(d['pointsEarned']) + returnedPts + toI(d['pointsRedeemed']);
  final userRef = db.collection('users').doc(customerId);
  await db.runTransaction((tx) async {
    final us = await tx.get(userRef);
    final cur = toI(us.data()?['points']);
    final np = cur + delta;
    if (us.exists) tx.update(userRef, {'points': np < 0 ? 0 : np});
    tx.delete(invRef);
    final orderId = d['orderId'];
    if (orderId != null && orderId.toString().isNotEmpty) {
      tx.set(db.collection('orders').doc(orderId), {
        'status': 'accepted',
        'invoiceId': FieldValue.delete(),
        'invoiceNumber': FieldValue.delete(),
      }, SetOptions(merge: true));
    }
  });

  for (final col in ['payments', 'returns']) {
    final q = await scoped(col).where('invoiceId', isEqualTo: invoiceId).get();
    for (final doc in q.docs) {
      await doc.reference.delete();
    }
  }

  final back = <String, int>{};
  final names = <String, String>{};
  for (final it in items) {
    final pid = (it['productId'] ?? '').toString();
    back[pid] = (back[pid] ?? 0) + toI(it['qty']) - toI(it['returnedQty']);
    names[pid] = (it['name'] ?? '').toString();
  }
  await adjustStock(back,
      type: 'invoice_delete',
      party: (d['customerName'] ?? '').toString(),
      refNumber: number,
      names: names);
  await notify(customerId, 'اتلغت فاتورة رقم $number', 'الفاتورة دي اتشالت من حسابك',
      type: 'invoice');
}

/// تعديل أصناف فاتورة موجودة (لو مفيهاش مرتجعات)
Future<void> updateInvoice({
  required String invoiceId,
  required List<InvLine> lines,
  required DateTime dueDate,
  required int collectionDays,
  required AppSettings settings,
  String note = '',
}) async {
  if (lines.isEmpty) throw 'الفاتورة من غير أصناف';
  final invRef = db.collection('invoices').doc(invoiceId);
  final d = (await invRef.get()).data();
  if (d == null) throw 'الفاتورة مش موجودة';
  if (toD(d['returned']) > 0) throw 'الفاتورة دي عليها مرتجع — مينفعش تتعدل أصنافها';
  final customerId = (d['customerId'] ?? '').toString();

  final sellTotal = round2(lines.fold(0.0, (a, l) => a + l.sellPrice * l.qty));
  final gross = round2(lines.fold(0.0, (a, l) => a + l.lineTotal));
  final redeemValue = toD(d['redeemValue']);
  final total = round2((gross - redeemValue).clamp(0, double.infinity).toDouble());
  final earned = settings.pointsFor(total);
  final paid = toD(d['paid']);

  // فرق المخزن: القديم يرجع والجديد يتخصم
  final diff = <String, int>{};
  final names = <String, String>{};
  for (final it in (d['items'] as List? ?? [])) {
    final pid = (it['productId'] ?? '').toString();
    diff[pid] = (diff[pid] ?? 0) + toI(it['qty']);
    names[pid] = (it['name'] ?? '').toString();
  }
  for (final l in lines) {
    diff[l.productId] = (diff[l.productId] ?? 0) - l.qty;
    names[l.productId] = l.name;
  }

  final userRef = db.collection('users').doc(customerId);
  await db.runTransaction((tx) async {
    final us = await tx.get(userRef);
    tx.update(invRef, {
      'items': lines.map((e) => e.toMap()).toList(),
      'sellTotal': sellTotal,
      'wholesaleTotal': gross,
      'discountTotal': round2(sellTotal - gross),
      'gross': gross,
      'total': total,
      'balance': round2(total - paid),
      'pointsEarned': earned,
      'note': note,
      'dueDate': Timestamp.fromDate(dueDate),
      'collectionDays': collectionDays,
      'editedAt': FieldValue.serverTimestamp(),
    });
    if (us.exists) {
      final np = toI(us.data()?['points']) - toI(d['pointsEarned']) + earned;
      tx.update(userRef, {'points': np < 0 ? 0 : np});
    }
  });
  await adjustStock(diff,
      type: 'invoice_edit',
      party: (d['customerName'] ?? '').toString(),
      refId: invoiceId,
      refNumber: toI(d['number']),
      names: names);
  await notify(customerId, 'اتعدلت فاتورة رقم ${d['number']}',
      'الإجمالي الجديد ${money(total)}',
      type: 'invoice', refId: invoiceId);
}

Future<void> addPayment(String invoiceId, double amount, {String note = ''}) async {
  if (amount <= 0) throw 'المبلغ لازم يكون أكبر من صفر';
  final invRef = db.collection('invoices').doc(invoiceId);
  final payRef = db.collection('payments').doc();
  String customerId = '';
  int number = 0;
  await db.runTransaction((tx) async {
    final s = await tx.get(invRef);
    final d = s.data();
    if (d == null) throw 'الفاتورة مش موجودة';
    customerId = d['customerId'];
    number = toI(d['number']);
    final paid = round2(toD(d['paid']) + amount);
    final balance = round2(toD(d['total']) - paid - toD(d['returned']));
    tx.update(invRef, {'paid': paid, 'balance': balance});
    tx.set(payRef, {
      'storeId': sid,
      'invoiceId': invoiceId,
      'invoiceNumber': number,
      'customerId': customerId,
      'customerName': d['customerName'],
      'amount': amount,
      'note': note,
      'createdAt': FieldValue.serverTimestamp(),
    });
  });
  await notify(customerId, 'تم تسجيل دفعة',
      'استلمنا ${money(amount)} على فاتورة رقم $number. شكراً ليك',
      type: 'payment', refId: invoiceId);
}

/// مرتجع: qtys = {index في items: الكمية المرتجعة}
Future<double> addReturn(String invoiceId, Map<int, int> qtys,
    AppSettings settings, {String note = ''}) async {
  final invRef = db.collection('invoices').doc(invoiceId);
  final retRef = db.collection('returns').doc();
  double amount = 0;
  String customerId = '';
  int number = 0;
  final back = <String, int>{};
  final names = <String, String>{};
  String customerName = '';
  await db.runTransaction((tx) async {
    back.clear();
    final s = await tx.get(invRef);
    final d = s.data();
    if (d == null) throw 'الفاتورة مش موجودة';
    customerId = d['customerId'];
    customerName = (d['customerName'] ?? '').toString();
    number = toI(d['number']);
    final userRef = db.collection('users').doc(customerId);
    final us = await tx.get(userRef);
    final items = List<Map<String, dynamic>>.from(
        (d['items'] as List).map((e) => Map<String, dynamic>.from(e)));
    final retItems = <Map<String, dynamic>>[];
    amount = 0;
    qtys.forEach((i, q) {
      if (q <= 0 || i < 0 || i >= items.length) return;
      final it = items[i];
      final avail = toI(it['qty']) - toI(it['returnedQty']);
      if (q > avail) throw 'الكمية المرتجعة من ${it['name']} أكبر من المتاح ($avail)';
      it['returnedQty'] = toI(it['returnedQty']) + q;
      final a = round2(toD(it['unitNet']) * q);
      amount += a;
      final pid = (it['productId'] ?? '').toString();
      back[pid] = (back[pid] ?? 0) + q;
      names[pid] = (it['name'] ?? '').toString();
      retItems.add({
        'productId': it['productId'],
        'name': it['name'],
        'qty': q,
        'unitNet': it['unitNet'],
        'amount': a,
      });
    });
    if (retItems.isEmpty) throw 'اختار كمية للمرتجع';
    amount = round2(amount);
    final returned = round2(toD(d['returned']) + amount);
    final balance = round2(toD(d['total']) - toD(d['paid']) - returned);
    tx.update(invRef, {'items': items, 'returned': returned, 'balance': balance});
    tx.set(retRef, {
      'storeId': sid,
      'invoiceId': invoiceId,
      'invoiceNumber': number,
      'customerId': customerId,
      'customerName': d['customerName'],
      'items': retItems,
      'amount': amount,
      'note': note,
      'createdAt': FieldValue.serverTimestamp(),
    });
    final lost = settings.pointsFor(amount);
    final cur = toI(us.data()?['points']);
    tx.set(userRef, {'points': (cur - lost) < 0 ? 0 : cur - lost},
        SetOptions(merge: true));
  });
  await adjustStock(back,
      type: 'return',
      party: customerName,
      refId: invoiceId,
      refNumber: number,
      note: note,
      names: names);
  await notify(customerId, 'مرتجع على فاتورة $number',
      'تم تسجيل مرتجع بقيمة ${money(amount)}',
      type: 'return', refId: invoiceId);
  return amount;
}

// ======================== ملخص حساب العميل ========================

class AccountSummary {
  double total = 0, paid = 0, returned = 0, balance = 0, overdue = 0;
  int invoices = 0, overdueCount = 0;
}

AccountSummary summarize(Iterable<Map<String, dynamic>> invoices) {
  final s = AccountSummary();
  final now = DateTime.now();
  for (final d in invoices) {
    s.invoices++;
    s.total += toD(d['total']);
    s.paid += toD(d['paid']);
    s.returned += toD(d['returned']);
    final b = toD(d['balance']);
    s.balance += b;
    final due = tsToDate(d['dueDate']);
    if (b > 0.009 && due != null && due.isBefore(now)) {
      s.overdue += b;
      s.overdueCount++;
    }
  }
  s.total = round2(s.total);
  s.paid = round2(s.paid);
  s.returned = round2(s.returned);
  s.balance = round2(s.balance);
  s.overdue = round2(s.overdue);
  return s;
}

bool isOverdue(Map<String, dynamic> inv) {
  final due = tsToDate(inv['dueDate']);
  return toD(inv['balance']) > 0.009 && due != null && due.isBefore(DateTime.now());
}

int daysLate(Map<String, dynamic> inv) {
  final due = tsToDate(inv['dueDate']);
  if (due == null) return 0;
  return DateTime.now().difference(due).inDays;
}

// ======================== الشات ========================

Future<void> sendMessage(String customerId, String text,
    {String customerName = ''}) async {
  final t = text.trim();
  if (t.isEmpty) return;
  final chatRef = db.collection('chats').doc(customerId);
  final fromAdmin = isAdmin;
  await chatRef.collection('messages').add({
    'from': fromAdmin ? 'admin' : customerId,
    'text': t,
    'createdAt': FieldValue.serverTimestamp(),
  });
  await chatRef.set({
    'storeId': sid,
    'customerId': customerId,
    if (customerName.isNotEmpty) 'customerName': customerName,
    'lastMessage': t,
    'lastAt': FieldValue.serverTimestamp(),
    if (fromAdmin) 'unreadCustomer': FieldValue.increment(1),
    if (!fromAdmin) 'unreadAdmin': FieldValue.increment(1),
  }, SetOptions(merge: true));
}

Future<void> markChatRead(String customerId) {
  return db.collection('chats').doc(customerId).set(
      {isAdmin ? 'unreadAdmin' : 'unreadCustomer': 0, 'storeId': sid},
      SetOptions(merge: true)).catchError((_) {});
}

List<QueryDocumentSnapshot<Map<String, dynamic>>> sortByDate(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    {String field = 'createdAt',
    bool desc = true}) {
  final l = [...docs];
  l.sort((a, b) {
    final da = tsToDate(a.data()[field]) ?? DateTime(2100);
    final dbb = tsToDate(b.data()[field]) ?? DateTime(2100);
    return desc ? dbb.compareTo(da) : da.compareTo(dbb);
  });
  return l;
}
