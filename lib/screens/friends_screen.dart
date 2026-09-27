import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/glass.dart';

/// Friends: add by nickname, incoming/outgoing requests, chat with friends
/// (text + photo + emoji via system keyboard, realtime), duels, notices.
class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  List<FriendEntry> _friends = [];
  List<FriendRequest> _incoming = [];
  List<FriendRequest> _outgoing = [];
  List<DuelInfo> _duels = [];
  bool _loading = true;
  final _addNick = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _reload();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _addNick.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final st = context.read<AppState>();
    setState(() => _loading = true);
    try {
      _friends = await st.backend.friends();
      _incoming = await st.backend.incomingRequests();
      _outgoing = await st.backend.outgoingRequests();
      _duels = await st.backend.myDuels();
      await st.refreshAll();
    } catch (e) {
      if (mounted) showError(context, e.toString().split('\n').first);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sendRequest() async {
    final st = context.read<AppState>();
    final ok = await st.run(() async {
      await st.backend.sendFriendRequest(_addNick.text);
      _addNick.clear();
      _outgoing = await st.backend.outgoingRequests();
    });
    if (!mounted) return;
    if (ok) {
      showOk(context, 'Заявка отправлена');
      setState(() {});
    } else {
      showError(context, st.lastError);
    }
  }

  Future<void> _respondReq(FriendRequest r, bool accept) async {
    final st = context.read<AppState>();
    final ok = await st.run(() async {
      await st.backend.respondFriendRequest(r.id, accept);
      _friends = await st.backend.friends();
      _incoming = await st.backend.incomingRequests();
    });
    if (!mounted) return;
    if (ok) {
      showOk(context, accept ? 'Заявка принята' : 'Заявка отклонена');
      setState(() {});
    } else {
      showError(context, st.lastError);
    }
  }

  Future<void> _removeFriend(FriendEntry f) async {
    final st = context.read<AppState>();
    final ok = await st.run(() async {
      await st.backend.removeFriend(f.userId);
      _friends = await st.backend.friends();
    });
    if (!mounted) return;
    if (ok) {
      showOk(context, '${f.nickname} удалён из друзей');
      setState(() {});
    } else {
      showError(context, st.lastError);
    }
  }

  Future<void> _challenge(FriendEntry f) async {
    final game = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Игра для дуэли'),
        children: [
          for (final g in GameDefs.all)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, g.id),
              child: Text('${g.emoji} ${g.title}'),
            ),
        ],
      ),
    );
    if (game == null || !mounted) return;
    final betC = TextEditingController();
    final bet = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Одинаковая ставка для обоих'),
        content: TextField(
            controller: betC,
            keyboardType: TextInputType.number,
            decoration:
                const InputDecoration(labelText: 'Ставка NC')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Отмена')),
          ElevatedButton(
              onPressed: () => Navigator.pop(
                  ctx, int.tryParse(betC.text.trim()) ?? 0),
              child: const Text('Вызвать')),
        ],
      ),
    );
    if (bet == null || bet <= 0 || !mounted) return;
    final st = context.read<AppState>();
    final ok = await st.run(() async {
      await st.backend.challengeDuel(f.userId, game, bet);
      _duels = await st.backend.myDuels();
      await st.refreshAll();
    });
    if (!mounted) return;
    if (ok) {
      showOk(context, 'Дуэль отправлена!');
      setState(() {});
    } else {
      showError(context, st.lastError);
    }
  }

  Future<void> _respondDuel(DuelInfo d, bool accept) async {
    final st = context.read<AppState>();
    final ok = await st.run(() async {
      await st.backend.respondDuel(d.id, accept);
      _duels = await st.backend.myDuels();
      await st.refreshAll();
    });
    if (!mounted) return;
    if (ok) {
      showOk(context,
          accept ? 'Дуэль сыграна!' : 'Дуэль отклонена');
      setState(() {});
    } else {
      showError(context, st.lastError);
    }
  }

  void _openChat(FriendEntry f) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ChatPage(friend: f)),
    ).then((_) => _reload());
  }

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    return Column(
      children: [
        TabBar(
          controller: _tabs,
          isScrollable: true,
          indicatorColor: NeverWinTheme.skyBlue,
          labelColor: Colors.white,
          unselectedLabelColor:
              Colors.white.withValues(alpha: 0.55),
          tabs: [
            const Tab(text: 'Друзья'),
            Tab(text: 'Заявки${_incoming.isNotEmpty ? ' (${_incoming.length})' : ''}'),
            const Tab(text: 'Дуэли'),
            Tab(
                text:
                    'Уведомления${st.unreadNotices > 0 ? ' (${st.unreadNotices})' : ''}'),
          ],
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : TabBarView(
                  controller: _tabs,
                  children: [
                    _buildFriends(),
                    _buildRequests(),
                    _buildDuels(),
                    _buildNotices(st),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildFriends() {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        GlassCard(
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _addNick,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Никнейм друга',
                    prefixIcon: Icon(Icons.person_add_rounded),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              GradientButton(
                  label: 'Добавить', onPressed: _sendRequest),
            ],
          ),
        ),
        const SectionTitle('Мои друзья'),
        if (_friends.isEmpty)
          const GlassCard(
              child: Text('Друзей пока нет.',
                  style: TextStyle(color: Colors.white70))),
        for (final f in _friends)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: GlassCard(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  const CircleAvatar(
                      child: Icon(Icons.person_rounded)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(f.nickname,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.sports_esports_rounded,
                        color: NeverWinTheme.goldGradient.colors.first),
                    tooltip: 'Вызвать на дуэль',
                    onPressed: () => _challenge(f),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chat_rounded,
                        color: NeverWinTheme.iceCyan),
                    onPressed: () => _openChat(f),
                  ),
                  IconButton(
                    icon: const Icon(Icons.person_remove_rounded,
                        color: Colors.redAccent),
                    onPressed: () => _removeFriend(f),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildRequests() {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        const SectionTitle('Входящие'),
        if (_incoming.isEmpty)
          const GlassCard(
              child: Text('Входящих заявок нет.',
                  style: TextStyle(color: Colors.white70))),
        for (final r in _incoming)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: GlassCard(
              child: Row(
                children: [
                  Expanded(
                    child: Text(r.fromNickname,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700)),
                  ),
                  GradientButton(
                      small: true,
                      label: 'Принять',
                      onPressed: () => _respondReq(r, true)),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => _respondReq(r, false),
                    child: const Text('Отклонить',
                        style:
                            TextStyle(color: Colors.redAccent)),
                  ),
                ],
              ),
            ),
          ),
        const SectionTitle('Исходящие'),
        if (_outgoing.isEmpty)
          const GlassCard(
              child: Text('Исходящих заявок нет.',
                  style: TextStyle(color: Colors.white70))),
        for (final r in _outgoing)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: GlassCard(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 12),
              child: Text('→ ${r.toNickname ?? r.toUserId}',
                  style: const TextStyle(color: Colors.white70)),
            ),
          ),
      ],
    );
  }

  Widget _buildDuels() {
    final me = context.read<AppState>().profile?.id;
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        const SectionTitle('Мои дуэли'),
        if (_duels.isEmpty)
          const GlassCard(
              child: Text(
                  'Дуэлей пока нет. Вызови друга из вкладки «Друзья».',
                  style: TextStyle(color: Colors.white70))),
        for (final d in _duels)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${d.challengerNickname} ⚔️ ${d.opponentNickname}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${GameDefs.byId(d.gameId).title} · ставка ${d.bet} NC · ${d.status}',
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 12.5),
                  ),
                  if (d.status == 'finished' &&
                      d.winnerNickname != null)
                    Text('🏆 Победитель: ${d.winnerNickname}',
                        style: const TextStyle(
                            color: NeverWinTheme.iceCyan,
                            fontWeight: FontWeight.w700)),
                  if (d.status == 'pending' &&
                      d.opponentId == me) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        GradientButton(
                            small: true,
                            label: 'Принять дуэль',
                            onPressed: () =>
                                _respondDuel(d, true)),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: () =>
                              _respondDuel(d, false),
                          child: const Text('Отклонить',
                              style: TextStyle(
                                  color: Colors.redAccent)),
                        ),
                      ],
                    ),
                  ],
                  if (d.status == 'pending' &&
                      d.challengerId == me)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text('Ждём ответа соперника...',
                          style: TextStyle(
                              color: Colors.white54,
                              fontSize: 12)),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildNotices(AppState st) {
    final list = st.notices;
    if (list.isEmpty) {
      return const Center(
          child: Text('Уведомлений нет.',
              style: TextStyle(color: Colors.white70)));
    }
    return RefreshIndicator(
      onRefresh: () async {
        await st.run(() async {
          await st.backend.markNoticesRead();
          await st.refreshAll();
        });
        setState(() {});
      },
      child: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          for (final n in list)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: GlassCard(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    Icon(
                      n.kind == 'transfer'
                          ? Icons.swap_horiz_rounded
                          : n.kind == 'duel'
                              ? Icons.sports_esports_rounded
                              : n.kind == 'friend'
                                  ? Icons.group_rounded
                                  : Icons.info_rounded,
                      color: n.read
                          ? Colors.white38
                          : NeverWinTheme.iceCyan,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(n.text,
                          style: TextStyle(
                              color: n.read
                                  ? Colors.white54
                                  : Colors.white,
                              fontSize: 13)),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 1-to-1 chat with a friend: text + photo, realtime updates.
class ChatPage extends StatefulWidget {
  final FriendEntry friend;
  const ChatPage({super.key, required this.friend});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  List<ChatMessage> _msgs = [];
  final _text = TextEditingController();
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _load();
    context
        .read<AppState>()
        .backend
        .watchMessages(widget.friend.userId)
        .listen((list) {
      if (!mounted) return;
      setState(() => _msgs = list);
      _jump();
    });
  }

  @override
  void dispose() {
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final st = context.read<AppState>();
    try {
      _msgs =
          await st.backend.messages(widget.friend.userId);
      if (mounted) {
        setState(() {});
        _jump();
      }
    } catch (e) {
      if (mounted) showError(context, e.toString().split('\n').first);
    }
  }

  void _jump() {
    Future<void>.delayed(const Duration(milliseconds: 120), () {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  Future<void> _send({String? imagePath}) async {
    final st = context.read<AppState>();
    final text = _text.text;
    if (text.trim().isEmpty && imagePath == null) return;
    final ok = await st.run(() async {
      await st.backend.sendMessage(widget.friend.userId, text,
          imagePath: imagePath);
      _msgs = await st.backend.messages(widget.friend.userId);
      await st.refreshAll();
    });
    if (!mounted) return;
    if (ok) {
      _text.clear();
      setState(() {});
      _jump();
    } else {
      showError(context, st.lastError);
    }
  }

  Future<void> _pickPhoto() async {
    try {
      final img = await ImagePicker()
          .pickImage(source: ImageSource.gallery, imageQuality: 70);
      if (img != null && mounted) {
        await _send(imagePath: img.path);
      }
    } catch (e) {
      if (mounted) {
        showError(context, 'Не удалось выбрать фото');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = context.read<AppState>().profile?.id;
    return Scaffold(
      appBar: AppBar(title: Text(widget.friend.nickname)),
      body: Column(
        children: [
          Expanded(
            child: _msgs.isEmpty
                ? const Center(
                    child: Text('Сообщений пока нет. Напиши первым!',
                        style:
                            TextStyle(color: Colors.white70)))
                : ListView(
                    controller: _scroll,
                    padding: const EdgeInsets.all(14),
                    children: [
                      for (final m in _msgs)
                        Align(
                          alignment: m.fromUserId == me
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            constraints: BoxConstraints(
                                maxWidth:
                                    MediaQuery.of(context)
                                            .size
                                            .width *
                                        0.75),
                            decoration: BoxDecoration(
                              gradient: m.fromUserId == me
                                  ? NeverWinTheme.primaryGradient
                                  : null,
                              color: m.fromUserId == me
                                  ? null
                                  : Colors.white
                                      .withValues(alpha: 0.1),
                              borderRadius:
                                  BorderRadius.circular(16),
                            ),
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                if (m.imagePath != null)
                                  Padding(
                                    padding:
                                        const EdgeInsets.only(
                                            bottom: 6),
                                    child: ClipRRect(
                                      borderRadius:
                                          BorderRadius.circular(
                                              10),
                                      child: m.imagePath!
                                              .startsWith('http')
                                          ? Image.network(
                                              m.imagePath!,
                                              errorBuilder: (_,
                                                      __,
                                                      ___) =>
                                                  const Icon(Icons
                                                      .broken_image_rounded))
                                          : Image.file(
                                              File(m.imagePath!),
                                              errorBuilder: (_,
                                                      __,
                                                      ___) =>
                                                  const Icon(Icons
                                                      .broken_image_rounded)),
                                    ),
                                  ),
                                if (m.text.isNotEmpty)
                                  Text(m.text,
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 14)),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.photo_rounded,
                        color: NeverWinTheme.iceCyan),
                    onPressed: _pickPhoto,
                  ),
                  Expanded(
                    child: TextField(
                      controller: _text,
                      style:
                          const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        hintText:
                            'Сообщение... (эмодзи: 😀🎮🏆)',
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GradientButton(
                      label: '➤', onPressed: () => _send()),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
