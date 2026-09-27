import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models.dart';
import 'game_backend.dart';

/// Server-authoritative backend over Supabase (PostgREST + RPC + Realtime).
/// All money / outcome logic runs in SQL functions (see supabase/schema.sql);
/// the client only passes intents and renders results.
class SupabaseBackend implements GameBackend {
  SupabaseBackend._();
  static final SupabaseBackend instance = SupabaseBackend._();

  static bool _ready = false;
  static String? url;
  static String? publishableKey;

  static bool get isReady => _ready;

  static Future<void> init(String supabaseUrl, String supabaseKey) async {
    url = supabaseUrl;
    publishableKey = supabaseKey;
    await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseKey);
    _ready = true;
  }

  @override
  String get name => 'supabase';

  SupabaseClient get _db => Supabase.instance.client;
  String _email(String nickname) => '${nickname.trim().toLowerCase()}@neverwin.local';

  /// PostgREST returns `SETOF` RPC results as a JSON array; scalar RPCs as
  /// a bare value. Normalize both shapes to a single row map.
  Map<String, dynamic> _firstRow(dynamic res) {
    if (res is List) {
      if (res.isEmpty) throw const NeverWinException('Пустой ответ сервера');
      return Map<String, dynamic>.from(res.first as Map);
    }
    return Map<String, dynamic>.from(res as Map);
  }

  PlayerProfile _profile(Map<String, dynamic> r) => PlayerProfile(
        id: r['id'] as String,
        nickname: r['nickname'] as String,
        balance: (r['main_balance'] ?? 0) as int,
        isAdmin: (r['is_admin'] ?? false) as bool,
        blockedUntil: r['blocked_until'] != null
            ? DateTime.parse(r['blocked_until'] as String)
            : null,
        createdAt: DateTime.parse(r['created_at'] as String),
      );

  NeverWinException _err(Object e) {
    final m = e.toString();
    const map = {
      'over_email_send_rate_limit': 'Лимит отправки писем (429). Подожди минуту. Администратору: выключи Confirm email (Dashboard → Authentication → Providers → Email).',
      'email rate limit': 'Лимит отправки писем (429). Подожди минуту. Администратору: выключи Confirm email (Dashboard → Authentication → Providers → Email).',
      'already registered': 'Этот ник уже зарегистрирован. Войди в аккаунт.',
      'already been registered': 'Этот ник уже зарегистрирован. Войди в аккаунт.',
      'nickname_taken': 'Никнейм уже занят',
      'user_not_found': 'Игрок не найден',
      'no_profile': 'Профиль не найден',
      'not_authenticated': 'Нет сессии. Войди заново.',
      'blocked': 'Аккаунт заблокирован',
      'insufficient': 'Недостаточно NC',
      'bad_bet': 'Некорректная ставка',
      'bad_amount': 'Некорректная сумма',
      'bad_choice': 'Неверный выбор',
      'bad_name': 'Некорректное название счёта',
      'bad_pin': 'Пароль счёта — ровно 4 цифры',
      'bad_target': 'ID счёта — 6 цифр',
      'bad_text': 'Сообщение: 1–200 символов',
      'unknown_game': 'Неизвестная игра',
      'unknown_param': 'Неизвестный параметр',
      'no_account': 'Счёт не найден',
      'target_not_found': 'Счёт получателя не найден',
      'same_account': 'Нельзя перевести на тот же счёт',
      'account_limit': 'Достигнут лимит счетов',
      'transfer_limit': 'Превышен лимит перевода',
      'self_request': 'Нельзя добавить себя',
      'already_exists': 'Уже в друзьях или заявка отправлена',
      'request_not_found': 'Заявка не найдена',
      'not_friends': 'Дуэли — только с друзьями',
      'not_your_duel': 'Не твоя дуэль',
      'duel_not_found': 'Дуэль не найдена',
      'promo_not_found': 'Промокод не найден',
      'promo_inactive': 'Промокод неактивен',
      'promo_expired': 'Срок действия промокода истёк',
      'promo_exhausted': 'Лимит активаций промокода исчерпан',
      'promo_used': 'Ты уже использовал этот промокод',
      'promo_min_balance': 'Недостаточный баланс для этого промокода',
      'not_admin': 'Нет прав администратора',
    };
    for (final entry in map.entries) {
      if (m.contains(entry.key)) {
        return NeverWinException(entry.value);
      }
    }
    final minBet = RegExp(r'min_bet_(\d+)').firstMatch(m);
    if (minBet != null) {
      return NeverWinException(
          'Минимальная ставка: ${minBet.group(1)} NC');
    }
    if (m.contains('429') ||
        m.contains('rate limit') ||
        m.contains('Rate limit') ||
        m.contains('over_request_rate_limit')) {
      return const NeverWinException(
          'Слишком много попыток (лимит 429). Подожди ~1 минуту и попробуй снова.');
    }
    if (m.contains('cooldown')) {
      return const NeverWinException('Cooldown: подожди 10 c.');
    }
    return NeverWinException('Ошибка сервера: ${m.split('\n').first}');
  }

  @override
  Future<PlayerProfile> register(String nickname, String password) async {
    nickname = nickname.trim();
    try {
      final res = await _db.auth.signUp(
        email: _email(nickname),
        password: password,
        data: {'nickname': nickname},
      );
      final user = res.user ?? _db.auth.currentUser;
      if (user == null) throw const NeverWinException('Регистрация не удалась');
      final row = await _db.rpc('nw_ensure_profile',
          params: {'p_nickname': nickname}) as List;
      if (row.isEmpty) throw const NeverWinException('Профиль не создан');
      return _profile(Map<String, dynamic>.from(row.first as Map));
    } catch (e) {
      if (e is NeverWinException) rethrow;
      throw _err(e);
    }
  }

  @override
  Future<PlayerProfile> login(String nickname, String password) async {
    try {
      await _db.auth.signInWithPassword(
          email: _email(nickname), password: password);
      var me = await currentSession();
      if (me == null) {
        // Self-heal: auth-запись есть, а строки профиля нет
        // (прерванная регистрация) — создаём профиль и перечитываем.
        try {
          final fallbackNick =
              _db.auth.currentUser?.email?.split('@').first ?? nickname;
          final row = await _db.rpc('nw_ensure_profile',
              params: {'p_nickname': fallbackNick}) as List;
          if (row.isNotEmpty) {
            me = _profile(Map<String, dynamic>.from(row.first as Map));
          }
        } catch (_) {}
      }
      if (me == null) throw const NeverWinException('Вход не удался');
      if (me.isBlocked) {
        await _db.auth.signOut();
        throw NeverWinException(
            'Аккаунт заблокирован до ${me.blockedUntil}');
      }
      return me;
    } catch (e) {
      if (e is NeverWinException) rethrow;
      if (e.toString().contains('Invalid login')) {
        throw const NeverWinException('Неверный никнейм или пароль');
      }
      throw _err(e);
    }
  }

  @override
  Future<void> logout() => _db.auth.signOut();

  @override
  Future<PlayerProfile?> currentSession() async {
    final u = _db.auth.currentUser;
    if (u == null) return null;
    try {
      final row = await _db
          .from('profiles')
          .select()
          .eq('id', u.id)
          .maybeSingle();
      if (row == null) return null;
      return _profile(Map<String, dynamic>.from(row));
    } catch (_) {
      return null;
    }
  }

  @override
  Future<Map<String, dynamic>> getConfig() async {
    final rows =
        await _db.from('game_config').select('key,value') as List;
    return {for (final r in rows) (r['key'] as String): (r['value'])};
  }

  @override
  Future<GameResult> playGame(String gameId, String choice, int bet) async {
    try {
      final res = await _db.rpc('nw_play', params: {
        'p_game': gameId,
        'p_choice': choice,
        'p_bet': bet,
      }) as Map<String, dynamic>;
      final m = Map<String, dynamic>.from(res);
      return GameResult(
        gameId: gameId,
        bet: bet,
        payout: (m['payout'] ?? 0) as int,
        win: (m['win'] ?? false) as bool,
        draw: (m['draw'] ?? false) as bool,
        detail: (m['detail'] ?? '') as String,
        data: Map<String, dynamic>.from(m['data'] ?? {}),
        globalX2Applied: (m['global_x2'] ?? false) as bool,
      );
    } catch (e) {
      if (e is NeverWinException) rethrow;
      throw _err(e);
    }
  }

  BankAccount _account(Map<String, dynamic> r) => BankAccount(
        id: r['id'] as String,
        number: r['number'] as String,
        name: r['name'] as String,
        balance: (r['balance'] ?? 0) as int,
        ownerId: r['owner_id'] as String,
        createdAt: DateTime.parse(r['created_at'] as String),
      );

  @override
  Future<BankAccount> createBankAccount(String name, String pin) async {
    try {
      final row = await _db.rpc('nw_bank_create',
          params: {'p_name': name.trim(), 'p_pin': pin});
      return _account(_firstRow(row));
    } catch (e) {
      if (e is NeverWinException) rethrow;
      throw _err(e);
    }
  }

  @override
  Future<List<BankAccount>> listBankAccounts() async {
    final rows = await _db
        .from('bank_accounts')
        .select()
        .order('created_at') as List;
    return rows
        .map((r) => _account(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  @override
  Future<BankAccount> bankDeposit(String accountId, int amount) async {
    final row = await _db.rpc('nw_bank_deposit',
        params: {'p_account': accountId, 'p_amount': amount});
    return _account(_firstRow(row));
  }

  @override
  Future<BankAccount> bankWithdraw(String accountId, int amount) async {
    final row = await _db.rpc('nw_bank_withdraw',
        params: {'p_account': accountId, 'p_amount': amount});
    return _account(_firstRow(row));
  }

  @override
  Future<void> bankTransfer(
      {required String fromAccountId,
      required String targetNumber,
      required int amount}) async {
    try {
      await _db.rpc('nw_bank_transfer', params: {
        'p_from': fromAccountId,
        'p_target_number': targetNumber,
        'p_amount': amount,
      });
    } catch (e) {
      throw _err(e);
    }
  }

  @override
  Future<int> redeemPromo(String code) async {
    try {
      final res = await _db.rpc('nw_redeem_promo',
          params: {'p_code': code.trim().toUpperCase()});
      return (res as num).toInt();
    } catch (e) {
      throw _err(e);
    }
  }

  @override
  Future<List<LeaderRow>> leaderboard() async {
    // Честные итоги (main + Σ счетов) считает definer-RPC: view под RLS
    // скрыл бы чужие счета и занизил бы итоги.
    final rows = await _db.rpc('nw_leaderboard') as List;
    return rows
        .map((r) => LeaderRow((r['nickname'] ?? '') as String,
            (r['total_nc'] as num? ?? 0).toInt()))
        .toList();
  }

  FriendRequest _freq(Map<String, dynamic> r, String me) => FriendRequest(
        id: r['id'] as String,
        fromUserId: r['requester_id'] as String,
        fromNickname: (r['requester_nick'] ?? '') as String,
        toUserId: r['addressee_id'] as String,
        status: r['status'] as String,
      );

  @override
  Future<void> sendFriendRequest(String nickname) async {
    try {
      await _db.rpc('nw_friend_request', params: {'p_nickname': nickname.trim()});
    } catch (e) {
      throw _err(e);
    }
  }

  @override
  Future<List<FriendRequest>> incomingRequests() async {
    final me = _db.auth.currentUser!.id;
    final rows = await _db
        .from('friendships')
        .select()
        .eq('addressee_id', me)
        .eq('status', 'pending')
        .order('created_at') as List;
    return rows
        .map((r) => _freq(Map<String, dynamic>.from(r as Map), me))
        .toList();
  }

  @override
  Future<List<FriendRequest>> outgoingRequests() async {
    final me = _db.auth.currentUser!.id;
    final rows = await _db
        .from('friendships')
        .select()
        .eq('requester_id', me)
        .eq('status', 'pending')
        .order('created_at') as List;
    return rows
        .map((r) => _freq(Map<String, dynamic>.from(r as Map), me))
        .toList();
  }

  @override
  Future<void> respondFriendRequest(String requestId, bool accept) async {
    await _db.rpc('nw_friend_respond',
        params: {'p_id': requestId, 'p_accept': accept});
  }

  @override
  Future<List<FriendEntry>> friends() async {
    final rows = await _db.rpc('nw_friends') as List;
    return rows
        .map((r) => FriendEntry(
            (r['user_id'] ?? '') as String, (r['nickname'] ?? '') as String))
        .toList();
  }

  @override
  Future<void> removeFriend(String friendUserId) async {
    await _db.rpc('nw_friend_remove', params: {'p_friend': friendUserId});
  }

  @override
  Future<void> sendMessage(String friendUserId, String text,
      {String? imagePath}) async {
    // Фото грузим в Storage-бакет chat-images и шлём публичный URL, чтобы
    // картинку видел и второй клиент. При ошибке — fallback как есть.
    String? remoteUrl;
    if (imagePath != null && !imagePath.startsWith('http')) {
      try {
        final name =
            '${_db.auth.currentUser!.id}/${DateTime.now().millisecondsSinceEpoch}.jpg';
        await _db.storage.from('chat-images').upload(name, File(imagePath));
        remoteUrl = _db.storage.from('chat-images').getPublicUrl(name);
      } catch (_) {
        remoteUrl = null;
      }
    } else {
      remoteUrl = imagePath;
    }
    await _db.from('messages').insert({
      'to_user': friendUserId,
      'text': text.trim(),
      'image_url': remoteUrl ?? imagePath,
    });
  }

  @override
  Future<List<ChatMessage>> messages(String friendUserId) async {
    final me = _db.auth.currentUser!.id;
    final rows = await _db
        .from('messages')
        .select()
        .or('and(from_user.eq.$me,to_user.eq.$friendUserId),'
            'and(from_user.eq.$friendUserId,to_user.eq.$me)')
        .order('created_at') as List;
    return rows
        .map((r) => ChatMessage(
              id: r['id'] as String,
              fromUserId: r['from_user'] as String,
              toUserId: r['to_user'] as String,
              text: (r['text'] ?? '') as String,
              imagePath: r['image_url'] as String?,
              createdAt: DateTime.parse(r['created_at'] as String),
            ))
        .toList();
  }

  @override
  Stream<List<ChatMessage>> watchMessages(String friendUserId) {
    final ctl = StreamController<List<ChatMessage>>();
    var alive = true;
    Future<void> poll() async {
      var last = '';
      while (alive) {
        await Future<void>.delayed(const Duration(seconds: 2));
        if (!alive) break;
        try {
          final list = await messages(friendUserId);
          final sig = '${list.length}:${list.isEmpty ? '' : list.last.id}';
          if (sig != last) {
            last = sig;
            if (!ctl.isClosed) ctl.add(list);
          }
        } catch (_) {}
      }
    }

    final ch = _db.channel('nw-chat-$friendUserId')
      ..onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'messages',
        callback: (_) async {
          try {
            final list = await messages(friendUserId);
            if (!ctl.isClosed) ctl.add(list);
          } catch (_) {}
        },
      )
      ..subscribe();
    poll();
    ctl.onCancel = () {
      alive = false;
      _db.removeChannel(ch);
      ctl.close();
    };
    return ctl.stream;
  }

  DuelInfo _duel(Map<String, dynamic> r) => DuelInfo(
        id: r['id'] as String,
        challengerId: r['challenger_id'] as String,
        challengerNickname: (r['challenger_nick'] ?? '') as String,
        opponentId: r['opponent_id'] as String,
        opponentNickname: (r['opponent_nick'] ?? '') as String,
        gameId: r['game_id'] as String,
        bet: (r['bet'] ?? 0) as int,
        status: r['status'] as String,
        winnerId: r['winner_id'] as String?,
        winnerNickname: r['winner_nick'] as String?,
      );

  @override
  Future<DuelInfo> challengeDuel(
      String friendUserId, String gameId, int bet) async {
    final row = await _db.rpc('nw_duel_create', params: {
      'p_opponent': friendUserId,
      'p_game': gameId,
      'p_bet': bet,
    });
    return _duel(_firstRow(row));
  }

  @override
  Future<List<DuelInfo>> myDuels() async {
    final rows = await _db
        .from('duels')
        .select()
        .order('created_at', ascending: false)
        .limit(30) as List;
    return rows
        .map((r) => _duel(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  @override
  Future<DuelInfo> respondDuel(String duelId, bool accept) async {
    final row = await _db.rpc('nw_duel_respond',
        params: {'p_id': duelId, 'p_accept': accept});
    return _duel(_firstRow(row));
  }

  @override
  Future<List<AppNotice>> notices() async {
    final me = _db.auth.currentUser!.id;
    final rows = await _db
        .from('notices')
        .select()
        .eq('to_user', me)
        .order('created_at', ascending: false)
        .limit(50) as List;
    return rows
        .map((r) => AppNotice(
              id: r['id'] as String,
              kind: (r['kind'] ?? 'system') as String,
              text: (r['text'] ?? '') as String,
              createdAt: DateTime.parse(r['created_at'] as String),
              read: (r['read'] ?? false) as bool,
            ))
        .toList();
  }

  @override
  Future<void> markNoticesRead() async {
    final me = _db.auth.currentUser!.id;
    await _db.from('notices').update({'read': true}).eq('to_user', me);
  }

  @override
  Future<GlobalMessage?> latestGlobal() async {
    final rows = await _db
        .from('global_messages')
        .select()
        .order('created_at', ascending: false)
        .limit(1) as List;
    if (rows.isEmpty) return null;
    final r = Map<String, dynamic>.from(rows.first as Map);
    final at = DateTime.parse(r['created_at'] as String);
    if (DateTime.now().difference(at).inSeconds > 10) return null;
    return GlobalMessage(
        id: r['id'] as String,
        adminNickname: (r['admin_nick'] ?? 'ADMIN') as String,
        text: (r['text'] ?? '') as String,
        createdAt: at);
  }

  @override
  Stream<GlobalMessage> watchGlobal() {
    final ctl = StreamController<GlobalMessage>();
    final ch = _db.channel('nw-global')
      ..onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'global_messages',
        callback: (payload) {
          final r = payload.newRecord;
          ctl.add(GlobalMessage(
            id: (r['id'] ?? '') as String,
            adminNickname: (r['admin_nick'] ?? 'ADMIN') as String,
            text: (r['text'] ?? '') as String,
            createdAt: DateTime.tryParse((r['created_at'] ?? '') as String) ??
                DateTime.now(),
          ));
        },
      )
      ..subscribe();
    ctl.onCancel = () {
      _db.removeChannel(ch);
      ctl.close();
    };
    return ctl.stream;
  }

  @override
  Future<void> blockUser(String nickname, {DateTime? until}) async {
    await _db.rpc('nw_admin_block', params: {
      'p_nickname': nickname,
      'p_until': (until ?? DateTime.now().add(const Duration(days: 36500)))
          .toIso8601String(),
    });
  }

  @override
  Future<void> unblockUser(String nickname) async {
    await _db.rpc('nw_admin_unblock', params: {'p_nickname': nickname});
  }

  @override
  Future<void> grantNc(String nickname, int amount) async {
    await _db.rpc('nw_admin_grant',
        params: {'p_nickname': nickname, 'p_amount': amount});
  }

  @override
  Future<void> takeNc(String nickname, int amount) async {
    await _db.rpc('nw_admin_take',
        params: {'p_nickname': nickname, 'p_amount': amount});
  }

  @override
  Future<void> sendGlobal(String text) async {
    try {
      await _db.rpc('nw_admin_global', params: {'p_text': text.trim()});
    } catch (e) {
      throw _err(e);
    }
  }

  @override
  Future<void> setGlobalX2(bool enabled) async {
    await _db.rpc('nw_admin_set_param',
        params: {'p_key': 'global_x2', 'p_value': enabled});
  }

  @override
  Future<Map<String, dynamic>> adminParams() => getConfig();

  @override
  Future<void> setAdminParam(String key, dynamic value) async {
    await _db.rpc('nw_admin_set_param',
        params: {'p_key': key, 'p_value': value});
  }
}
