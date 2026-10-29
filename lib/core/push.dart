import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';

/// الإشعارات اللي بتوصل والتطبيق مقفول.
/// كل موبايل بيشترك في "مواضيع": عملاء المحل all_<محل>، العميل نفسه u_<uid>،
/// مدير المحل admin_<محل>، والمدير العام super.
/// وفيه برنامج صغير على GitHub بيبعت الإشعارات الجديدة للمواضيع دي كل كام دقيقة.
Future<void> setupPush(List<String> topics) async {
  if (kIsWeb) return;
  try {
    final m = FirebaseMessaging.instance;
    await m.requestPermission(alert: true, badge: true, sound: true);
    final prefs = await SharedPreferences.getInstance();
    final old = prefs.getStringList('push_topics') ?? [];
    for (final t in old) {
      if (!topics.contains(t)) await m.unsubscribeFromTopic(t);
    }
    for (final t in topics) {
      await m.subscribeToTopic(t);
    }
    await prefs.setStringList('push_topics', topics);
  } catch (_) {}
}

/// عند تسجيل الخروج: نوقف إشعارات الحساب ده على الموبايل ده
Future<void> clearPush() async {
  if (kIsWeb) return;
  try {
    final prefs = await SharedPreferences.getInstance();
    final old = prefs.getStringList('push_topics') ?? [];
    if (old.isEmpty) return;
    for (final t in old) {
      await FirebaseMessaging.instance.unsubscribeFromTopic(t);
    }
    await prefs.remove('push_topics');
  } catch (_) {}
}

String pushTopic(String to) {
  final t = to.replaceAll(RegExp(r'[^a-zA-Z0-9\-_.~%]'), '_');
  if (to == 'super' || to.startsWith('all_') || to.startsWith('admin_')) return t;
  return 'u_$t';
}
