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

DocumentReference<Map<String, dynamic>> get settingsRef =>
    db.collection('settings').doc('app');

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

Future<void> notify(String to, String title, String body,
    {String type = 'general', String? refId}) {
  return db.collection('notifications').add({
    'to': to, // uid للعميل، 'admin' للمدير، 'all' للكل
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
  final counterRef = db.collection('settings').doc('counter');
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
  for (final l in lines) {
    used[l.productId] = (used[l.productId] ?? 0) - l.qty;
  }
  await adjustStock(used);
  if (paidNow > 0) {
    await addPayment(invRef.id, paidNow, note: 'دفعة عند الاستلام');
  }
  await notify(customerId, 'فاتورة جديدة رقم $number',
      'إجمالي ${money(total)} — كسبت $earned نقطة 🎉',
      type: 'invoice', refId: invRef.id);
  return (invRef.id, number);
}

/// يزوّد أو يقلل المخزن (بالسالب للخصم). الأصناف اللي مخزنها مش متتبع بتتساب.
Future<void> adjustStock(Map<String, int> changes) async {
  final merged = <String, int>{};
  changes.forEach((k, v) {
    if (k.isNotEmpty && v != 0) merged[k] = (merged[k] ?? 0) + v;
  });
  for (final e in merged.entries) {
    try {
      final ref = db.collection('products').doc(e.key);
      final s = await ref.get();
      if (!s.exists || s.data()?['stock'] == null) continue;
      await ref.update({'stock': FieldValue.increment(e.value)});
    } catch (_) {}
  }
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
  await db.runTransaction((tx) async {
    back.clear();
    final s = await tx.get(invRef);
    final d = s.data();
    if (d == null) throw 'الفاتورة مش موجودة';
    customerId = d['customerId'];
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
  await adjustStock(back);
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
      {isAdmin ? 'unreadAdmin' : 'unreadCustomer': 0}, SetOptions(merge: true));
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
