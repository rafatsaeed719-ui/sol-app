import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app.dart';
import '../core/data.dart';

Query<Map<String, dynamic>> myNotificationsQuery() {
  final c = db.collection('notifications');
  if (isAdmin) return c.where('to', isEqualTo: 'admin');
  return c.where('to', whereIn: [uid, 'all']);
}

class NotifCenter extends ChangeNotifier {
  static final NotifCenter I = NotifCenter._();
  NotifCenter._();

  StreamSubscription? _sub;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> docs = [];
  DateTime lastSeen = DateTime.fromMillisecondsSinceEpoch(0);
  final DateTime _startedAt = DateTime.now();
  final _incoming = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get incoming => _incoming.stream;

  String get _key => 'lastSeen_$uid';

  Future<void> start() async {
    await _sub?.cancel();
    final prefs = await SharedPreferences.getInstance();
    lastSeen = DateTime.fromMillisecondsSinceEpoch(prefs.getInt(_key) ?? 0);
    _sub = myNotificationsQuery().snapshots().listen((s) {
      docs = sortByDate(s.docs);
      for (final ch in s.docChanges) {
        if (ch.type != DocumentChangeType.added) continue;
        final d = ch.doc.data();
        final t = tsToDate(d?['createdAt']);
        if (d != null && t != null && t.isAfter(_startedAt)) _incoming.add(d);
      }
      notifyListeners();
    }, onError: (_) {});
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
    docs = [];
  }

  int get unread => docs.where((d) {
        final t = tsToDate(d.data()['createdAt']);
        return t != null && t.isAfter(lastSeen);
      }).length;

  Future<void> markAllSeen() async {
    lastSeen = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key, lastSeen.millisecondsSinceEpoch);
    notifyListeners();
  }
}

/// زرار الجرس مع عدد الإشعارات الجديدة
class NotifBell extends StatelessWidget {
  const NotifBell({super.key});
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: NotifCenter.I,
      builder: (context, _) {
        final n = NotifCenter.I.unread;
        return IconButton(
          tooltip: 'الإشعارات',
          onPressed: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const NotificationsScreen())),
          icon: Badge(
            isLabelVisible: n > 0,
            label: Text('$n'),
            child: const Icon(Icons.notifications_outlined),
          ),
        );
      },
    );
  }
}

/// بيعرض بانر فوق الشاشة لما ييجي إشعار جديد والتطبيق مفتوح
class NotifListener extends StatefulWidget {
  final Widget child;
  const NotifListener({super.key, required this.child});
  @override
  State<NotifListener> createState() => _NotifListenerState();
}

class _NotifListenerState extends State<NotifListener> {
  StreamSubscription? sub;
  @override
  void initState() {
    super.initState();
    NotifCenter.I.start();
    sub = NotifCenter.I.incoming.listen((d) {
      if (!mounted) return;
      final m = ScaffoldMessenger.of(context);
      m.hideCurrentMaterialBanner();
      m.showMaterialBanner(MaterialBanner(
        backgroundColor: const Color(0xFFFFF4E0),
        leading: const Icon(Icons.notifications_active, color: kAccent),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(d['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
            Text(d['body'] ?? ''),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => m.hideCurrentMaterialBanner(), child: const Text('تمام')),
        ],
      ));
      Future.delayed(const Duration(seconds: 6), () {
        if (mounted) m.hideCurrentMaterialBanner();
      });
    });
  }

  @override
  void dispose() {
    sub?.cancel();
    NotifCenter.I.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late final DateTime seenBefore;
  @override
  void initState() {
    super.initState();
    seenBefore = NotifCenter.I.lastSeen;
    NotifCenter.I.markAllSeen();
  }

  IconData _icon(String? t) {
    switch (t) {
      case 'order':
        return Icons.shopping_cart;
      case 'offer':
        return Icons.local_offer;
      case 'invoice':
        return Icons.receipt_long;
      case 'payment':
        return Icons.payments;
      case 'return':
        return Icons.assignment_return;
      case 'overdue':
        return Icons.warning_amber;
      case 'customer':
        return Icons.storefront;
      case 'chat':
        return Icons.chat;
    }
    return Icons.notifications;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الإشعارات')),
      body: ListenableBuilder(
        listenable: NotifCenter.I,
        builder: (context, _) {
          final docs = NotifCenter.I.docs;
          if (docs.isEmpty) {
            return const EmptyView('مفيش إشعارات لسه', icon: Icons.notifications_none);
          }
          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (c, i) {
              final d = docs[i].data();
              final t = tsToDate(d['createdAt']);
              final isNew = t != null && t.isAfter(seenBefore);
              return Card(
                color: isNew ? const Color(0xFFFFF8EC) : null,
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: kPrimary.withValues(alpha: 0.1),
                    child: Icon(_icon(d['type']), color: kPrimary),
                  ),
                  title: Text(d['title'] ?? '',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('${d['body'] ?? ''}\n${fmtDate(d['createdAt'], time: true)}'),
                  isThreeLine: true,
                ),
              );
            },
          );
        },
      ),
    );
  }
}
