// بيبعت الإشعارات الجديدة من Firestore لموبايلات العملاء (Firebase Cloud Messaging)
// بيشتغل على GitHub كل 5 دقايق. محتاج سر FIREBASE_SERVICE_ACCOUNT في إعدادات الريبو.
const admin = require('firebase-admin');

function topicFor(to) {
  const t = String(to).replace(/[^a-zA-Z0-9\-_.~%]/g, '_');
  if (to === 'super' || to.startsWith('all_') || to.startsWith('admin_')) return t;
  return 'u_' + t;
}

(async () => {
  const sa = process.env.SERVICE_ACCOUNT;
  if (!sa || !sa.trim()) {
    console.log('FIREBASE_SERVICE_ACCOUNT secret is not set yet — skipping.');
    return;
  }
  admin.initializeApp({ credential: admin.credential.cert(JSON.parse(sa)) });
  const db = admin.firestore();
  const since = new Date(Date.now() - 6 * 60 * 60 * 1000);
  const snap = await db.collection('notifications').where('createdAt', '>=', since).get();
  let sent = 0, failed = 0;
  for (const doc of snap.docs) {
    const n = doc.data();
    if (n.pushed) continue;
    if (!n.to) continue;
    try {
      await admin.messaging().send({
        topic: topicFor(n.to),
        notification: { title: String(n.title || 'SOL'), body: String(n.body || '') },
        android: { priority: 'high', notification: { sound: 'default' } },
        data: { type: String(n.type || ''), refId: String(n.refId || '') },
      });
      await doc.ref.update({ pushed: true, pushedAt: admin.firestore.FieldValue.serverTimestamp() });
      sent++;
    } catch (e) {
      failed++;
      console.error('failed', doc.id, e.message);
      await doc.ref.update({ pushed: true, pushError: String(e.message).slice(0, 200) });
    }
  }
  console.log(`checked ${snap.size}, sent ${sent}, failed ${failed}`);
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
