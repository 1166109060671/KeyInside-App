import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'admin_chat_room_page.dart';

class AdminChatListPage extends StatelessWidget {
  const AdminChatListPage({super.key});

  // ===== Firestore stream =====
  Stream<QuerySnapshot<Map<String, dynamic>>> _streamRooms() {
    return FirebaseFirestore.instance
        .collection('chats')
        .where('participants', arrayContains: 'admin')
        .orderBy('updatedAt', descending: true)
        .snapshots();
  }

  // ===== Cache =====
  static final Map<String, _UserMeta> _cache = {};

  Future<_UserMeta> _getUserMeta(String uid) async {
    if (uid.isEmpty || uid == 'admin') {
      return const _UserMeta(displayName: 'ลูกค้า', imageProvider: null);
    }

    if (_cache.containsKey(uid)) return _cache[uid]!;

    final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final data = doc.data() ?? {};

    final name = (data['displayName'] ?? data['email'] ?? 'ลูกค้า').toString();

    ImageProvider? image;
    final photoUrl = data['photoURL'] ?? data['photoUrl'];
    final photoB64 = data['photoB64'];
    if (photoUrl != null && photoUrl.toString().isNotEmpty) {
      image = NetworkImage(photoUrl.toString());
    } else if (photoB64 != null && photoB64.toString().startsWith('data:image')) {
      final base64Str = photoB64.toString().split(',').last;
      final bytes = base64Decode(base64Str);
      image = MemoryImage(Uint8List.fromList(bytes));
    }

    final meta = _UserMeta(displayName: name, imageProvider: image);
    _cache[uid] = meta;
    return meta;
  }

  String _formatWhen(dynamic ts) {
    if (ts is! Timestamp) return '-';
    final dt = ts.toDate();
    final now = DateTime.now();
    final sameDay = dt.year == now.year && dt.month == now.month && dt.day == now.day;
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    if (sameDay) return '$hh:$mm';
    final dd = dt.day.toString().padLeft(2, '0');
    final mo = dt.month.toString().padLeft(2, '0');
    return '$dd/$mo $hh:$mm';
  }

  String _initial(String name) {
    if (name.isEmpty) return '?';
    final parts = name.trim().split(' ');
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts[0].characters.first + parts[1].characters.first).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _streamRooms(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(child: Text('เกิดข้อผิดพลาด: ${snap.error}'));
        }

        final docs = snap.data?.docs ?? const [];
        if (docs.isEmpty) {
          return Center(child: Text('ยังไม่มีห้องแชท', style: TextStyle(color: cs.onSurfaceVariant)));
        }

        return ListView.separated(
          padding: const EdgeInsets.all(12),
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemCount: docs.length,
          itemBuilder: (_, i) {
            final d = docs[i];
            final data = d.data();
            final roomId = d.id;
            final last = (data['lastMessage'] ?? '').toString();
            final when = _formatWhen(data['lastAt'] ?? data['updatedAt'] ?? data['createdAt']);
            final parts = (data['participants'] as List? ?? const []).map((e) => e.toString()).toList();
            final otherUid = parts.firstWhere((x) => x != 'admin', orElse: () => '');

            return FutureBuilder<_UserMeta>(
              future: _getUserMeta(otherUid),
              builder: (context, metaSnap) {
                final meta = metaSnap.data ?? const _UserMeta(displayName: 'ลูกค้า', imageProvider: null);
                return ListTile(
                  tileColor: cs.surfaceContainerHighest.withOpacity(.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  leading: CircleAvatar(
                    radius: 22,
                    backgroundColor: cs.primaryContainer,
                    foregroundColor: cs.onPrimaryContainer,
                    backgroundImage: meta.imageProvider,
                    child: meta.imageProvider == null
                        ? Text(_initial(meta.displayName), style: const TextStyle(fontWeight: FontWeight.bold))
                        : null,
                  ),
                  title: Text(meta.displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    last.isEmpty ? '(ยังไม่มีข้อความ)' : last,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Text(when, style: Theme.of(context).textTheme.bodySmall),
                  onTap: () {
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => AdminChatRoomPage(roomId: roomId, otherUid: '',),
                    ));
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}

class _UserMeta {
  final String displayName;
  final ImageProvider? imageProvider;
  const _UserMeta({required this.displayName, this.imageProvider});
}
