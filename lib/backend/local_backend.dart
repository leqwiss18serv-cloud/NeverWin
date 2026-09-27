import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';
import 'game_backend.dart';

/// Offline backend: enforces the same rules the SQL RPCs enforce
/// (min bets, odds, atomic balance moves) using a sequential gate so
/// concurrent calls cannot double-spend. Used until Supabase is configured.
class LocalBackend implements GameBackend {
  @override
  String get name => 'local';

  final _rnd = Random.secure();
  Future<void> _gate = Future.value();

  Future<T> _locked<T>(Future<T> Function() fn) {
    final c = Completer<T>();
    _gate = _gate.then((_) async {
      try {
        c.complete(await fn());
      } catch (e, s) {
        c.completeError(e, s);
      }
    });
    return c.future;
  }

  // ---------- storage helpers ----------
  static const _kUsers = 'nw_users';
  static const _kSession = 'nw_session';
  static const _kBank = 'nw_bank';
  static const _kPromos = 'nw_promos';
  static const _kPromoUsed = 'nw_promo_used';
  static const _kFriends = 'nw_friends';
  static const _kMessages = 'nw_messages';
  static const _kDuels = 'nw_duels';
  static const _kNotices = 'nw_notices';
  static const _kGlobal = 'nw_global';
  static const _kGlobalCd = 'nw_global_cd';
  static const _kConfig = 'nw_config';

  Future<SharedPreferences> get _prefs async =>
      SharedPreferences.getInstance();

  Map<String, dynamic> _decodeMap(String? raw) =>
      raw == null || raw.isEmpty ? {} : Map<String, dynamic>.from(jsonDecode(raw));
  List<Map<String, dynamic>> _decodeList(String? raw) => raw == null || raw.isEmpty
      ? []
      : (jsonDecode(raw) as List).map((e) => Map<String, dynamic>.from(e)).toList();

  String _id(String p) =>
      '${p}_${DateTime.now().microsecondsSinceEpoch}_${_rnd.nextInt(1 << 32)}';

  String _hash(String salt, String password) =>
      sha256.convert(utf8.encode('$salt::$password')).toString();

  Map<String, dynamic> _defaultConfig() => {
        'start_balance': 5000,
        'min_bet_higher_lower': 1000,
        'min_bet_black_white': 1500,
        'min_bet_dice_even_odd': 500,
        'min_bet_coin_flip': 500,
        'mult_higher_lower': 2,
        'mult_black_white': 2,
        'mult_black_white_green': 5,
        'mult_dice_even_odd': 2,
        'mult_coin_flip': 2,
        'global_x2_mult': 2,
        'global_x2': false,
        'hl_loss_pct': 50,
        'hl_win_pct': 45,
        'hl_draw_pct': 5,
        'bw_black': 25,
        'bw_white': 25,
        'bw_green': 2,
        'transfer_limit': 1000000,
        'max_bank_accounts': 10,
        'global_cooldown_sec': 10,
        'global_ttl_sec': 10,
      };

  Future<Map<String, dynamic>> _config(SharedPreferences p) async {
    final cfg = Map<String, dynamic>.from(_defaultConfig())
      ..addAll(_decodeMap(p.getString(_kConfig)));
    return cfg;
  }

  Future<String?> _sessionNick(SharedPreferences p) async =>
      p.getString(_kSession);

  Future<Map<String, dynamic>> _requireUser(SharedPreferences p) async {
    final nick = await _sessionNick(p);
    if (nick == null) throw const NeverWinException('Нет активной сессии');
    final users = _decodeMap(p.getString(_kUsers));
    final u = users[nick];
    if (u == null) throw const NeverWinException('Сессия недействительна');
    final map = Map<String, dynamic>.from(u);
    final until = map['blockedUntil'];
    if (until != null && DateTime.parse(until).isAfter(DateTime.now())) {
      throw NeverWinException('Аккаунт заблокирован до $until');
    }
    return map;
  }

  PlayerProfile _toProfile(Map<String, dynamic> u) => PlayerProfile(
        id: u['id'],
        nickname: u['nickname'],
        balance: u['balance'],
        isAdmin: u['isAdmin'] ?? false,
        blockedUntil: u['blockedUntil'] != null
            ? DateTime.parse(u['blockedUntil'])
            : null,
        createdAt: DateTime.parse(u['createdAt']),
      );

  void _saveUsers(SharedPreferences p, Map<String, dynamic> users) =>
      p.setString(_kUsers, jsonEncode(users));

  // ---------- auth ----------
  @override
  Future<PlayerProfile> register(String nickname, String password) =>
      _locked(() async {
        final p = await _prefs;
        nickname = nickname.trim();
        if (nickname.length < 3 || nickname.length > 20) {
          throw const NeverWinException('Никнейм: 3–20 символов');
        }
        if (!RegExp(r'^[A-Za-z0-9_]+$').hasMatch(nickname)) {
          throw const NeverWinException(
              'Никнейм: только латиница, цифры и _');
        }
        if (password.length < 4) {
          throw const NeverWinException('Пароль: минимум 4 символа');
        }
        final users = _decodeMap(p.getString(_kUsers));
        if (users.containsKey(nickname)) {
          throw const NeverWinException('Никнейм уже занят');
        }
        final cfg = await _config(p);
        final salt = _rnd.nextInt(1 << 32).toRadixString(16);
        final u = {
          'id': _id('u'),
          'nickname': nickname,
          'salt': salt,
          'passHash': _hash(salt, password),
          'balance': cfg['start_balance'],
          'isAdmin': false,
          'blockedUntil': null,
          'createdAt': DateTime.now().toIso8601String(),
        };
        users[nickname] = u;
        _saveUsers(p, users);
        await p.setString(_kSession, nickname);
        return _toProfile(u);
      });

  @override
  Future<PlayerProfile> login(String nickname, String password) =>
      _locked(() async {
        final p = await _prefs;
        final users = _decodeMap(p.getString(_kUsers));
        final u = users[nickname.trim()];
        if (u == null) {
          throw const NeverWinException('Неверный никнейм или пароль');
        }
        final map = Map<String, dynamic>.from(u);
        if (_hash(map['salt'], password) != map['passHash']) {
          throw const NeverWinException('Неверный никнейм или пароль');
        }
        final until = map['blockedUntil'];
        if (until != null && DateTime.parse(until).isAfter(DateTime.now())) {
          throw NeverWinException('Аккаунт заблокирован до $until');
        }
        await p.setString(_kSession, map['nickname']);
        return _toProfile(map);
      });

  @override
  Future<void> logout() => _locked(() async {
        final p = await _prefs;
        await p.remove(_kSession);
      });

  @override
  Future<PlayerProfile?> currentSession() => _locked(() async {
        final p = await _prefs;
        final nick = await _sessionNick(p);
        if (nick == null) return null;
        final users = _decodeMap(p.getString(_kUsers));
        final u = users[nick];
        return u == null ? null : _toProfile(Map<String, dynamic>.from(u));
      });

  @override
  Future<Map<String, dynamic>> getConfig() => _locked(() async {
        final p = await _prefs;
        return _config(p);
      });

  // ---------- games (server-authoritative mirror of SQL RPC play_game) ----------
  int _minBet(Map<String, dynamic> cfg, String gameId) =>
      (cfg['min_bet_$gameId'] ?? 500) as int;
  int _mult(Map<String, dynamic> cfg, String gameId, {bool green = false}) {
    if (gameId == 'black_white' && green) {
      return (cfg['mult_black_white_green'] ?? 5) as int;
    }
    return (cfg['mult_$gameId'] ?? 2) as int;
  }

  @override
  Future<GameResult> playGame(String gameId, String choice, int bet) =>
      _locked(() async {
        final p = await _prefs;
        final cfg = await _config(p);
        final me = await _requireUser(p);
        final users = _decodeMap(p.getString(_kUsers));

        final minBet = _minBet(cfg, gameId);
        if (bet < minBet) {
          throw NeverWinException('Минимальная ставка: $minBet NC');
        }
        if (bet <= 0) throw const NeverWinException('Ставка должна быть > 0');
        if (me.balance < bet) {
          throw const NeverWinException('Недостаточно NC на балансе');
        }

        final gx = (cfg['global_x2'] ?? false) as bool;
        final gxMult = (cfg['global_x2_mult'] ?? 2) as int;

        late GameResult r;
        switch (gameId) {
          case 'higher_lower':
            r = _rollHigherLower(choice, bet, cfg, gx, gxMult);
            break;
          case 'black_white':
            r = _rollBlackWhite(choice, bet, cfg, gx, gxMult);
            break;
          case 'dice_even_odd':
            r = _rollDice(choice, bet, cfg, gx, gxMult);
            break;
          case 'coin_flip':
            r = _rollCoin(choice, bet, cfg, gx, gxMult);
            break;
          default:
            throw const NeverWinException('Неизвестная игра');
        }

        final u = Map<String, dynamic>.from(users[me.nickname]);
        u['balance'] = (u['balance'] as int) - bet + r.payout;
        users[me.nickname] = u;
        _saveUsers(p, users);
        return r;
      });

  GameResult _rollHigherLower(
      String choice, int bet, Map cfg, bool gx, int gxMult) {
    if (choice != 'higher' && choice != 'lower') {
      throw const NeverWinException('Выбери «Больше» или «Меньше»');
    }
    final first = 1 + _rnd.nextInt(200);
    final lossPct = (cfg['hl_loss_pct'] ?? 50) as int;
    final winPct = (cfg['hl_win_pct'] ?? 45) as int;
    final roll = _rnd.nextInt(100);
    final isLoss = roll < lossPct;
    final isWin = !isLoss && roll < lossPct + winPct;
    int second;
    bool win, draw;
    if (!isLoss && !isWin) {
      second = first;
      win = false;
      draw = true;
    } else {
      final wantGreater = (choice == 'higher') == isWin;
      if (wantGreater) {
        if (first >= 200) {
          second = first;
          win = false;
          draw = true;
        } else {
          second = first + 1 + _rnd.nextInt(200 - first);
          win = isWin;
          draw = false;
        }
      } else {
        if (first <= 1) {
          second = first;
          win = false;
          draw = true;
        } else {
          second = 1 + _rnd.nextInt(first - 1);
          win = isWin;
          draw = false;
        }
      }
    }
    final mult = (cfg['mult_higher_lower'] ?? 2) as int;
    final payout = draw ? bet : (win ? bet * mult * (gx ? gxMult : 1) : 0);
    return GameResult(
      gameId: 'higher_lower',
      bet: bet,
      payout: payout,
      win: win,
      draw: draw,
      detail: draw
          ? 'Ничья: выпало то же число $first. Ставка возвращена.'
          : (win ? 'Победа! $first → $second' : 'Поражение. $first → $second'),
      data: {'first': first, 'second': second},
      globalX2Applied: gx && win,
    );
  }

  GameResult _rollBlackWhite(
      String choice, int bet, Map cfg, bool gx, int gxMult) {
    if (choice != 'black' && choice != 'white') {
      throw const NeverWinException('Выбери «Чёрное» или «Белое»');
    }
    final blacks = (cfg['bw_black'] ?? 25) as int;
    final whites = (cfg['bw_white'] ?? 25) as int;
    final greens = (cfg['bw_green'] ?? 2) as int;
    final total = blacks + whites + greens;
    final pick = _rnd.nextInt(total);
    final isGreen = pick < greens;
    final isBlack = !isGreen && pick < greens + blacks;
    final color = isGreen ? 'green' : (isBlack ? 'black' : 'white');
    final colorRu =
        isGreen ? 'ЗЕЛЁНЫЙ' : (isBlack ? 'ЧЁРНОЕ' : 'БЕЛОЕ');
    final win = isGreen ||
        (choice == 'black' && isBlack) ||
        (choice == 'white' && !isBlack);
    final mult = _mult(cfg, 'black_white', green: isGreen);
    final payout = win ? bet * mult * (gx ? gxMult : 1) : 0;
    return GameResult(
      gameId: 'black_white',
      bet: bet,
      payout: payout,
      win: win,
      draw: false,
      detail: isGreen
          ? 'ЗЕЛЁНЫЙ! Выигрыш x$mult.'
          : (win ? 'Выпало: $colorRu — победа!' : 'Выпало: $colorRu — проигрыш.'),
      data: {'color': color},
      globalX2Applied: gx && win,
    );
  }

  GameResult _rollDice(String choice, int bet, Map cfg, bool gx, int gxMult) {
    if (choice != 'even' && choice != 'odd') {
      throw const NeverWinException('Выбери «Чёт» или «Нечет»');
    }
    final d1 = 1 + _rnd.nextInt(6), d2 = 1 + _rnd.nextInt(6);
    final even = (d1 + d2) % 2 == 0;
    final win = (choice == 'even') == even;
    final mult = (cfg['mult_dice_even_odd'] ?? 2) as int;
    return GameResult(
      gameId: 'dice_even_odd',
      bet: bet,
      payout: win ? bet * mult * (gx ? gxMult : 1) : 0,
      win: win,
      draw: false,
      detail: 'Кубики: $d1 + $d2 = ${d1 + d2} (${even ? 'чёт' : 'нечет'}) — '
          '${win ? 'победа!' : 'проигрыш.'}',
      data: {'d1': d1, 'd2': d2, 'sum': d1 + d2},
      globalX2Applied: gx && win,
    );
  }

  GameResult _rollCoin(String choice, int bet, Map cfg, bool gx, int gxMult) {
    if (choice != 'heads' && choice != 'tails') {
      throw const NeverWinException('Выбери «Орёл» или «Решка»');
    }
    final heads = _rnd.nextBool();
    final win = (choice == 'heads') == heads;
    final mult = (cfg['mult_coin_flip'] ?? 2) as int;
    return GameResult(
      gameId: 'coin_flip',
      bet: bet,
      payout: win ? bet * mult * (gx ? gxMult : 1) : 0,
      win: win,
      draw: false,
      detail: 'Выпало: ${heads ? 'ОРЁЛ' : 'РЕШКА'} — ${win ? 'победа!' : 'проигрыш.'}',
      data: {'side': heads ? 'heads' : 'tails'},
      globalX2Applied: gx && win,
    );
  }

  // ---------- bank ----------
  Future<List<Map<String, dynamic>>> _bank(SharedPreferences p) async =>
      _decodeList(p.getString(_kBank));

  Future<void> _saveBank(SharedPreferences p, List<Map<String, dynamic>> b) =>
      p.setString(_kBank, jsonEncode(b));

  String _newAccountNumber(List<Map<String, dynamic>> bank) {
    String n;
    do {
      n = (100000 + _rnd.nextInt(900000)).toString();
    } while (bank.any((a) => a['number'] == n));
    return n;
  }

  BankAccount _toAccount(Map<String, dynamic> a) => BankAccount(
        id: a['id'],
        number: a['number'],
        name: a['name'],
        balance: a['balance'],
        ownerId: a['ownerId'],
        createdAt: DateTime.parse(a['createdAt']),
      );

  @override
  Future<BankAccount> createBankAccount(String name, String pin) =>
      _locked(() async {
        final p = await _prefs;
        final me = await _requireUser(p);
        name = name.trim();
        if (name.isEmpty || name.length > 30) {
          throw const NeverWinException('Название счёта: 1–30 символов');
        }
        if (!RegExp(r'^\d{4}$').hasMatch(pin)) {
          throw const NeverWinException('Пароль счёта — ровно 4 цифры');
        }
        final cfg = await _config(p);
        final bank = await _bank(p);
        final mine = bank.where((a) => a['ownerId'] == me.id).length;
        if (mine >= ((cfg['max_bank_accounts'] ?? 10) as int)) {
          throw const NeverWinException('Достигнут лимит счетов');
        }
        final a = {
          'id': _id('b'),
          'number': _newAccountNumber(bank),
          'name': name,
          'pinHash': sha256.convert(utf8.encode('pin::$pin')).toString(),
          'balance': 0,
          'ownerId': me.id,
          'createdAt': DateTime.now().toIso8601String(),
        };
        bank.add(a);
        await _saveBank(p, bank);
        return _toAccount(a);
      });

  @override
  Future<List<BankAccount>> listBankAccounts() => _locked(() async {
        final p = await _prefs;
        final me = await _requireUser(p);
        final bank = await _bank(p);
        return bank
            .where((a) => a['ownerId'] == me.id)
            .map(_toAccount)
            .toList();
      });

  @override
  Future<BankAccount> bankDeposit(String accountId, int amount) =>
      _locked(() async {
        final p = await _prefs;
        final me = await _requireUser(p);
        if (amount <= 0) throw const NeverWinException('Сумма должна быть > 0');
        final users = _decodeMap(p.getString(_kUsers));
        final bank = await _bank(p);
        final i = bank.indexWhere(
            (a) => a['id'] == accountId && a['ownerId'] == me.id);
        if (i < 0) throw const NeverWinException('Счёт не найден');
        final u = Map<String, dynamic>.from(users[me.nickname]);
        if ((u['balance'] as int) < amount) {
          throw const NeverWinException('Недостаточно NC на балансе');
        }
        u['balance'] = (u['balance'] as int) - amount;
        users[me.nickname] = u;
        bank[i] = Map<String, dynamic>.from(bank[i])
          ..['balance'] = (bank[i]['balance'] as int) + amount;
        _saveUsers(p, users);
        await _saveBank(p, bank);
        return _toAccount(bank[i]);
      });

  @override
  Future<BankAccount> bankWithdraw(String accountId, int amount) =>
      _locked(() async {
        final p = await _prefs;
        final me = await _requireUser(p);
        if (amount <= 0) throw const NeverWinException('Сумма должна быть > 0');
        final users = _decodeMap(p.getString(_kUsers));
        final bank = await _bank(p);
        final i = bank.indexWhere(
            (a) => a['id'] == accountId && a['ownerId'] == me.id);
        if (i < 0) throw const NeverWinException('Счёт не найден');
        if ((bank[i]['balance'] as int) < amount) {
          throw const NeverWinException('Недостаточно NC на счёте');
        }
        bank[i] = Map<String, dynamic>.from(bank[i])
          ..['balance'] = (bank[i]['balance'] as int) - amount;
        final u = Map<String, dynamic>.from(users[me.nickname]);
        u['balance'] = (u['balance'] as int) + amount;
        users[me.nickname] = u;
        _saveUsers(p, users);
        await _saveBank(p, bank);
        return _toAccount(bank[i]);
      });

  @override
  Future<void> bankTransfer({
    required String fromAccountId,
    required String targetNumber,
    required int amount,
  }) =>
      _locked(() async {
        final p = await _prefs;
        final me = await _requireUser(p);
        if (amount <= 0) throw const NeverWinException('Сумма должна быть > 0');
        if (!RegExp(r'^\d{6}$').hasMatch(targetNumber)) {
          throw const NeverWinException('ID счёта — 6 цифр');
        }
        final cfg = await _config(p);
        if (amount > ((cfg['transfer_limit'] ?? 1000000) as int)) {
          throw const NeverWinException('Превышен лимит перевода');
        }
        final bank = await _bank(p);
        final from = bank.indexWhere(
            (a) => a['id'] == fromAccountId && a['ownerId'] == me.id);
        if (from < 0) throw const NeverWinException('Счёт не найден');
        final to = bank.indexWhere((a) => a['number'] == targetNumber);
        if (to < 0) {
          throw const NeverWinException('Счёт получателя не найден');
        }
        if (to == from) {
          throw const NeverWinException('Нельзя перевести на тот же счёт');
        }
        if ((bank[from]['balance'] as int) < amount) {
          throw const NeverWinException('Недостаточно NC на счёте');
        }
        bank[from] = Map<String, dynamic>.from(bank[from])
          ..['balance'] = (bank[from]['balance'] as int) - amount;
        bank[to] = Map<String, dynamic>.from(bank[to])
          ..['balance'] = (bank[to]['balance'] as int) + amount;
        await _saveBank(p, bank);

        final users = _decodeMap(p.getString(_kUsers));
        String? recipientNick;
        for (final e in users.entries) {
          if ((e.value['id'] as String) == bank[to]['ownerId']) {
            recipientNick = e.key;
            break;
          }
        }
        if (recipientNick != null) {
          await _pushNotice(
            p,
            recipientNick,
            'transfer',
            'Игрок ${me.nickname} перевёл на ваш счёт '
                '«${bank[to]['name']}» $amount NC.',
          );
        }
      });

  // ---------- promo ----------
  Future<List<Map<String, dynamic>>> _promos(SharedPreferences p) async {
    var list = _decodeList(p.getString(_kPromos));
    if (list.isEmpty) {
      list = [
        {
          'code': 'WELCOME500',
          'reward': 500,
          'maxGlobal': 1000,
          'usedGlobal': 0,
          'maxPerUser': 1,
          'active': true,
          'validUntil': null,
        },
        {
          'code': 'NEVERWIN2026',
          'reward': 1000,
          'maxGlobal': 500,
          'usedGlobal': 0,
          'maxPerUser': 1,
          'active': true,
          'validUntil': null,
        },
      ];
      await p.setString(_kPromos, jsonEncode(list));
    }
    return list;
  }

  @override
  Future<int> redeemPromo(String code) => _locked(() async {
        final p = await _prefs;
        final me = await _requireUser(p);
        code = code.trim().toUpperCase();
        if (code.isEmpty) throw const NeverWinException('Введи промокод');
        final promos = await _promos(p);
        final i = promos.indexWhere((x) => (x['code'] as String) == code);
        if (i < 0) throw const NeverWinException('Промокод не найден');
        final promo = Map<String, dynamic>.from(promos[i]);
        if (!(promo['active'] ?? true)) {
          throw const NeverWinException('Промокод неактивен');
        }
        final vu = promo['validUntil'];
        if (vu != null && DateTime.parse(vu).isBefore(DateTime.now())) {
          throw const NeverWinException('Срок действия истёк');
        }
        if ((promo['usedGlobal'] as int) >= (promo['maxGlobal'] as int)) {
          throw const NeverWinException('Лимит активаций исчерпан');
        }
        final used = _decodeList(p.getString(_kPromoUsed));
        final mine =
            used.where((e) => e['code'] == code && e['nick'] == me.nickname).length;
        if (mine >= (promo['maxPerUser'] as int)) {
          throw const NeverWinException('Ты уже использовал этот промокод');
        }
        final reward = promo['reward'] as int;
        final users = _decodeMap(p.getString(_kUsers));
        final u = Map<String, dynamic>.from(users[me.nickname]);
        u['balance'] = (u['balance'] as int) + reward;
        users[me.nickname] = u;
        _saveUsers(p, users);
        promo['usedGlobal'] = (promo['usedGlobal'] as int) + 1;
        promos[i] = promo;
        await p.setString(_kPromos, jsonEncode(promos));
        used.add({'code': code, 'nick': me.nickname});
        await p.setString(_kPromoUsed, jsonEncode(used));
        return reward;
      });

  // ---------- leaderboard ----------
  @override
  Future<List<LeaderRow>> leaderboard() => _locked(() async {
        final p = await _prefs;
        final users = _decodeMap(p.getString(_kUsers));
        final bank = await _bank(p);
        final rows = <LeaderRow>[];
        for (final e in users.entries) {
          final u = Map<String, dynamic>.from(e.value);
          var total = u['balance'] as int;
          for (final a in bank) {
            if (a['ownerId'] == u['id']) total += a['balance'] as int;
          }
          rows.add(LeaderRow(u['nickname'], total));
        }
        rows.sort((a, b) => b.totalNc.compareTo(a.totalNc));
        return rows.take(10).toList();
      });

  // ---------- friends ----------
  Future<List<Map<String, dynamic>>> _friendRows(SharedPreferences p) async =>
      _decodeList(p.getString(_kFriends));

  Future<void> _saveFriendRows(
          SharedPreferences p, List<Map<String, dynamic>> l) =>
      p.setString(_kFriends, jsonEncode(l));

  bool _areFriends(List<Map<String, dynamic>> rows, String a, String b) =>
      rows.any((r) =>
          r['status'] == 'accepted' &&
          ((r['requesterId'] == a && r['addresseeId'] == b) ||
              (r['requesterId'] == b && r['addresseeId'] == a)));

  String? _nickById(Map<String, dynamic> users, String id) {
    for (final e in users.entries) {
      if ((e.value['id'] as String) == id) return e.key;
    }
    return null;
  }

  @override
  Future<void> sendFriendRequest(String nickname) => _locked(() async {
        final p = await _prefs;
        final me = await _requireUser(p);
        nickname = nickname.trim();
        final users = _decodeMap(p.getString(_kUsers));
        final target = users[nickname];
        if (target == null) {
          throw const NeverWinException('Игрок не найден');
        }
        if (nickname == me.nickname) {
          throw const NeverWinException('Нельзя добавить себя');
        }
        final rows = await _friendRows(p);
        final tid = (target['id'] as String);
        if (_areFriends(rows, me.id, tid)) {
          throw const NeverWinException('Уже в друзьях');
        }
        if (rows.any((r) =>
            r['status'] == 'pending' &&
            ((r['requesterId'] == me.id && r['addresseeId'] == tid) ||
                (r['requesterId'] == tid && r['addresseeId'] == me.id)))) {
          throw const NeverWinException('Заявка уже отправлена');
        }
        rows.add({
          'id': _id('f'),
          'requesterId': me.id,
          'requesterNick': me.nickname,
          'addresseeId': tid,
          'status': 'pending',
          'createdAt': DateTime.now().toIso8601String(),
        });
        await _saveFriendRows(p, rows);
        await _pushNotice(p, nickname, 'friend',
            'Новая заявка в друзья от ${me.nickname}.');
      });

  @override
  Future<List<FriendRequest>> incomingRequests() => _locked(() async {
        final p = await _prefs;
        final me = await _requireUser(p);
        final rows = await _friendRows(p);
        return rows
            .where((r) =>
                r['addresseeId'] == me.id && r['status'] == 'pending')
            .map((r) => FriendRequest(
                  id: r['id'],
                  fromUserId: r['requesterId'],
                  fromNickname: r['requesterNick'],
                  toUserId: me.id,
                  status: r['status'],
                ))
            .toList();
      });

  @override
  Future<List<FriendRequest>> outgoingRequests() => _locked(() async {
        final p = await _prefs;
        final me = await _requireUser(p);
        final users = _decodeMap(p.getString(_kUsers));
        final rows = await _friendRows(p);
        return rows
            .where((r) =>
                r['requesterId'] == me.id && r['status'] == 'pending')
            .map((r) => FriendRequest(
                  id: r['id'],
                  fromUserId: me.id,
                  fromNickname: me.nickname,
                  toUserId: r['addresseeId'],
                  toNickname:
                      _nickById(users, r['addresseeId'] as String),
                  status: r['status'],
                ))
            .toList();
      });

  @override
  Future<void> respondFriendRequest(String requestId, bool accept) =>
      _locked(() async {
        final p = await _prefs;
        final me = await _requireUser(p);
        final rows = await _friendRows(p);
        final i = rows.indexWhere(
            (r) => r['id'] == requestId && r['addresseeId'] == me.id);
        if (i < 0) throw const NeverWinException('Заявка не найдена');
        rows[i] = Map<String, dynamic>.from(rows[i])
          ..['status'] = accept ? 'accepted' : 'declined';
        await _saveFriendRows(p, rows);
        final users = _decodeMap(p.getString(_kUsers));
        final fromNick = _nickById(users, rows[i]['requesterId']);
        if (fromNick != null) {
          await _pushNotice(
            p,
            fromNick,
            'friend',
            accept
                ? '${me.nickname} принял вашу заявку в друзья.'
                : '${me.nickname} отклонил вашу заявку в друзья.',
          );
        }
      });

  @override
  Future<List<FriendEntry>> friends() => _locked(() async {
        final p = await _prefs;
        final me = await _requireUser(p);
        final users = _decodeMap(p.getString(_kUsers));
        final rows = await _friendRows(p);
        final out = <FriendEntry>[];
        for (final r in rows) {
          if (r['status'] != 'accepted') continue;
          String? other;
          if (r['requesterId'] == me.id) {
            other = r['addresseeId'];
          } else if (r['addresseeId'] == me.id) {
            other = r['requesterId'];
          }
          if (other != null) {
            final nick = _nickById(users, other);
            if (nick != null) out.add(FriendEntry(other, nick));
          }
        }
        return out;
      });

  @override
  Future<void> removeFriend(String friendUserId) => _locked(() async {
        final p = await _prefs;
        final me = await _requireUser(p);
        final rows = await _friendRows(p);
        rows.removeWhere((r) =>
            r['status'] == 'accepted' &&
            ((r['requesterId'] == me.id &&
                    r['addresseeId'] == friendUserId) ||
                (r['requesterId'] == friendUserId &&
                    r['addresseeId'] == me.id)));
        await _saveFriendRows(p, rows);
      });

  Future<bool> _isFriend(SharedPreferences p, String a, String b) async =>
      _areFriends(await _friendRows(p), a, b);

  // ---------- messenger ----------
  @override
  Future<void> sendMessage(String friendUserId, String text,
          {String? imagePath}) =>
      _locked(() async {
        final p = await _prefs;
        final me = await _requireUser(p);
        if (!(await _isFriend(p, me.id, friendUserId))) {
          throw const NeverWinException(
              'Писать можно только друзьям');
        }
        if (text.trim().isEmpty && imagePath == null) {
          throw const NeverWinException('Пустое сообщение');
        }
        final msgs = _decodeList(p.getString(_kMessages));
        msgs.add({
          'id': _id('m'),
          'from': me.id,
          'to': friendUserId,
          'text': text.trim(),
          'image': imagePath,
          'createdAt': DateTime.now().toIso8601String(),
        });
        await p.setString(_kMessages, jsonEncode(msgs));
        final users = _decodeMap(p.getString(_kUsers));
        final nick = _nickById(users, friendUserId);
        if (nick != null) {
          await _pushNotice(
              p, nick, 'system', 'Новое сообщение от ${me.nickname}.');
        }
      });

  List<ChatMessage> _filterMsgs(
      List<Map<String, dynamic>> msgs, String a, String b) {
    final out = msgs
        .where((m) =>
            (m['from'] == a && m['to'] == b) ||
            (m['from'] == b && m['to'] == a))
        .map((m) => ChatMessage(
              id: m['id'],
              fromUserId: m['from'],
              toUserId: m['to'],
              text: m['text'] ?? '',
              imagePath: m['image'],
              createdAt: DateTime.parse(m['createdAt']),
            ))
        .toList();
    out.sort((x, y) => x.createdAt.compareTo(y.createdAt));
    return out;
  }

  @override
  Future<List<ChatMessage>> messages(String friendUserId) =>
      _locked(() async {
        final p = await _prefs;
        final me = await _requireUser(p);
        return _filterMsgs(
            _decodeList(p.getString(_kMessages)), me.id, friendUserId);
      });

  @override
  Stream<List<ChatMessage>> watchMessages(String friendUserId) async* {
    var last = '';
    while (true) {
      await Future<void>.delayed(const Duration(seconds: 2));
      try {
        final p = await _prefs;
        final me = await _requireUser(p);
        final list = _filterMsgs(
            _decodeList(p.getString(_kMessages)), me.id, friendUserId);
        final sig = list.length.toString() +
            (list.isEmpty ? '' : list.last.id);
        if (sig != last) {
          last = sig;
          yield list;
        }
      } catch (_) {
        return;
      }
    }
  }

  // ---------- duels (head-to-head, atomic) ----------
  Future<List<Map<String, dynamic>>> _duels(SharedPreferences p) async =>
      _decodeList(p.getString(_kDuels));

  DuelInfo _toDuel(Map<String, dynamic> d) => DuelInfo(
        id: d['id'],
        challengerId: d['challengerId'],
        challengerNickname: d['challengerNick'],
        opponentId: d['opponentId'],
        opponentNickname: d['opponentNick'],
        gameId: d['gameId'],
        bet: d['bet'],
        status: d['status'],
        winnerId: d['winnerId'],
        winnerNickname: d['winnerNick'],
      );

  @override
  Future<DuelInfo> challengeDuel(
          String friendUserId, String gameId, int bet) =>
      _locked(() async {
        final p = await _prefs;
        final me = await _requireUser(p);
        if (!(await _isFriend(p, me.id, friendUserId))) {
          throw const NeverWinException('Дуэли — только с друзьями');
        }
        final cfg = await _config(p);
        if (bet < _minBet(cfg, gameId)) {
          throw NeverWinException(
              'Минимальная ставка: ${_minBet(cfg, gameId)} NC');
        }
        final users = _decodeMap(p.getString(_kUsers));
        final oppNick = _nickById(users, friendUserId);
        if (oppNick == null) {
          throw const NeverWinException('Игрок не найден');
        }
        final duels = await _duels(p);
        final d = {
          'id': _id('d'),
          'challengerId': me.id,
          'challengerNick': me.nickname,
          'opponentId': friendUserId,
          'opponentNick': oppNick,
          'gameId': gameId,
          'bet': bet,
          'status': 'pending',
          'winnerId': null,
          'winnerNick': null,
          'createdAt': DateTime.now().toIso8601String(),
        };
        duels.add(d);
        await p.setString(_kDuels, jsonEncode(duels));
        await _pushNotice(p, oppNick, 'duel',
            '${me.nickname} вызывает тебя на дуэль: ${GameDefs.byId(gameId).title}, ставка $bet NC.');
        return _toDuel(d);
      });

  /// Shared head-to-head resolution: both stakes are deducted atomically,
  /// the winner takes the pot (x2 of one bet, x2 again under global x2).
  Map<String, dynamic> _resolveDuel(String gameId, int bet) {
    switch (gameId) {
      case 'coin_flip':
        final heads = _rnd.nextBool();
        return {'challengerWin': heads, 'detail': heads ? 'ОРЁЛ' : 'РЕШКА'};
      case 'dice_even_odd': {
        final d1 = 1 + _rnd.nextInt(6), d2 = 1 + _rnd.nextInt(6);
        final even = (d1 + d2) % 2 == 0;
        return {
          'challengerWin': even, // challenger = чёт, opponent = нечет
          'detail': '$d1+$d2=${d1 + d2} (${even ? 'чёт' : 'нечет'})',
          'draw': false,
        };
      }
      case 'black_white': {
        final pick = _rnd.nextInt(52);
        if (pick < 2) {
          return {'draw': true, 'detail': 'ЗЕЛЁНЫЙ — ничья, возврат ставок'};
        }
        final black = pick < 27; // challenger = чёрное, opponent = белое
        return {
          'challengerWin': black,
          'detail': black ? 'ЧЁРНОЕ' : 'БЕЛОЕ'
        };
      }
      case 'higher_lower':
      default: {
        final first = 1 + _rnd.nextInt(200);
        final higher = _rnd.nextBool(); // challenger = больше, opponent = меньше
        int second;
        if (higher) {
          second = first >= 200 ? first : first + 1 + _rnd.nextInt(200 - first);
        } else {
          second = first <= 1 ? first : 1 + _rnd.nextInt(first - 1);
        }
        if (second == first) {
          return {'draw': true, 'detail': 'Ничья $first — возврат ставок'};
        }
        return {'challengerWin': higher, 'detail': '$first → $second'};
      }
    }
  }

  @override
  Future<DuelInfo> respondDuel(String duelId, bool accept) =>
      _locked(() async {
        final p = await _prefs;
        final me = await _requireUser(p);
        final duels = await _duels(p);
        final i =
            duels.indexWhere((d) => d['id'] == duelId && d['status'] == 'pending');
        if (i < 0) throw const NeverWinException('Дуэль не найдена');
        final d = Map<String, dynamic>.from(duels[i]);
        if (d['opponentId'] != me.id) {
          throw const NeverWinException('Не твоя дуэль');
        }
        final users = _decodeMap(p.getString(_kUsers));
        if (!accept) {
          d['status'] = 'declined';
          duels[i] = d;
          await p.setString(_kDuels, jsonEncode(duels));
          final chNick = _nickById(users, d['challengerId']);
          if (chNick != null) {
            await _pushNotice(p, chNick, 'duel',
                '${me.nickname} отклонил дуэль.');
          }
          return _toDuel(d);
        }
        final bet = d['bet'] as int;
        final ch = Map<String, dynamic>.from(users[d['challengerNick']]);
        final op = Map<String, dynamic>.from(users[me.nickname]);
        if ((ch['balance'] as int) < bet || (op['balance'] as int) < bet) {
          throw const NeverWinException(
              'Недостаточно NC у одного из дуэлянтов');
        }
        final res = _resolveDuel(d['gameId'], bet);
        final cfg = await _config(p);
        final gx = (cfg['global_x2'] ?? false) as bool;
        final gxMult = (cfg['global_x2_mult'] ?? 2) as int;
        ch['balance'] = (ch['balance'] as int) - bet;
        op['balance'] = (op['balance'] as int) - bet;
        if (res['draw'] == true) {
          ch['balance'] = (ch['balance'] as int) + bet;
          op['balance'] = (op['balance'] as int) + bet;
          d['status'] = 'finished';
        } else {
          final pot = bet * 2 * (gx ? gxMult : 1);
          final chWin = res['challengerWin'] as bool;
          if (chWin) {
            ch['balance'] = (ch['balance'] as int) + pot;
            d['winnerId'] = d['challengerId'];
            d['winnerNick'] = d['challengerNick'];
          } else {
            op['balance'] = (op['balance'] as int) + pot;
            d['winnerId'] = d['opponentId'];
            d['winnerNick'] = d['opponentNick'];
          }
          d['status'] = 'finished';
          d['detail'] = res['detail'];
        }
        users[d['challengerNick']] = ch;
        users[me.nickname] = op;
        _saveUsers(p, users);
        duels[i] = d;
        await p.setString(_kDuels, jsonEncode(duels));
        final chNick = _nickById(users, d['challengerId']);
        if (chNick != null) {
          await _pushNotice(
            p,
            chNick,
            'duel',
            res['draw'] == true
                ? 'Дуэль с ${me.nickname}: ничья. Ставки возвращены.'
                : 'Дуэль с ${me.nickname} завершена. Победитель: ${d['winnerNick']}.',
          );
        }
        return _toDuel(d);
      });

  @override
  Future<List<DuelInfo>> myDuels() => _locked(() async {
        final p = await _prefs;
        final me = await _requireUser(p);
        final duels = await _duels(p);
        final mine = duels
            .where((d) =>
                d['challengerId'] == me.id || d['opponentId'] == me.id)
            .map(_toDuel)
            .toList();
        mine.sort((a, b) => b.id.compareTo(a.id));
        return mine;
      });

  // ---------- notices / global ----------
  Future<void> _pushNotice(
      SharedPreferences p, String toNick, String kind, String text) async {
    final list = _decodeList(p.getString(_kNotices));
    list.add({
      'id': _id('n'),
      'to': toNick,
      'kind': kind,
      'text': text,
      'createdAt': DateTime.now().toIso8601String(),
      'read': false,
    });
    await p.setString(_kNotices, jsonEncode(list));
  }

  @override
  Future<List<AppNotice>> notices() => _locked(() async {
        final p = await _prefs;
        final me = await _requireUser(p);
        final list = _decodeList(p.getString(_kNotices))
            .where((n) => n['to'] == me.nickname)
            .map((n) => AppNotice(
                  id: n['id'],
                  kind: n['kind'],
                  text: n['text'],
                  createdAt: DateTime.parse(n['createdAt']),
                  read: n['read'] ?? false,
                ))
            .toList();
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return list.take(50).toList();
      });

  @override
  Future<void> markNoticesRead() => _locked(() async {
        final p = await _prefs;
        final me = await _requireUser(p);
        final list = _decodeList(p.getString(_kNotices));
        for (final n in list) {
          if (n['to'] == me.nickname) n['read'] = true;
        }
        await p.setString(_kNotices, jsonEncode(list));
      });

  @override
  Future<GlobalMessage?> latestGlobal() => _locked(() async {
        final p = await _prefs;
        final raw = p.getString(_kGlobal);
        if (raw == null) return null;
        final g = Map<String, dynamic>.from(jsonDecode(raw));
        final at = DateTime.parse(g['createdAt']);
        final cfg = await _config(p);
        final ttl = (cfg['global_ttl_sec'] ?? 10) as int;
        if (DateTime.now().difference(at).inSeconds > ttl) return null;
        return GlobalMessage(
            id: g['id'], adminNickname: g['admin'], text: g['text'], createdAt: at);
      });

  @override
  Stream<GlobalMessage> watchGlobal() async* {
    String? last;
    while (true) {
      await Future<void>.delayed(const Duration(seconds: 2));
      try {
        final g = await latestGlobal();
        if (g != null && g.id != last) {
          last = g.id;
          yield g;
        }
      } catch (_) {
        return;
      }
    }
  }

  // ---------- admin ----------
  Future<void> _requireAdmin(SharedPreferences p) async {
    final me = await _requireUser(p);
    final users = _decodeMap(p.getString(_kUsers));
    final u = Map<String, dynamic>.from(users[me.nickname]);
    if (!(u['isAdmin'] ?? false)) {
      throw const NeverWinException('Нет прав администратора');
    }
  }

  @override
  Future<void> blockUser(String nickname, {DateTime? until}) =>
      _locked(() async {
        final p = await _prefs;
        await _requireAdmin(p);
        final users = _decodeMap(p.getString(_kUsers));
        final u = users[nickname];
        if (u == null) throw const NeverWinException('Игрок не найден');
        final m = Map<String, dynamic>.from(u);
        m['blockedUntil'] =
            (until ?? DateTime.now().add(const Duration(days: 365 * 100)))
                .toIso8601String();
        users[nickname] = m;
        _saveUsers(p, users);
      });

  @override
  Future<void> unblockUser(String nickname) => _locked(() async {
        final p = await _prefs;
        await _requireAdmin(p);
        final users = _decodeMap(p.getString(_kUsers));
        final u = users[nickname];
        if (u == null) throw const NeverWinException('Игрок не найден');
        final m = Map<String, dynamic>.from(u)..['blockedUntil'] = null;
        users[nickname] = m;
        _saveUsers(p, users);
      });

  @override
  Future<void> grantNc(String nickname, int amount) => _locked(() async {
        final p = await _prefs;
        await _requireAdmin(p);
        if (amount <= 0) throw const NeverWinException('Сумма должна быть > 0');
        final users = _decodeMap(p.getString(_kUsers));
        final u = users[nickname];
        if (u == null) throw const NeverWinException('Игрок не найден');
        final m = Map<String, dynamic>.from(u);
        m['balance'] = (m['balance'] as int) + amount;
        users[nickname] = m;
        _saveUsers(p, users);
      });

  @override
  Future<void> takeNc(String nickname, int amount) => _locked(() async {
        final p = await _prefs;
        await _requireAdmin(p);
        if (amount <= 0) throw const NeverWinException('Сумма должна быть > 0');
        final users = _decodeMap(p.getString(_kUsers));
        final u = users[nickname];
        if (u == null) throw const NeverWinException('Игрок не найден');
        final m = Map<String, dynamic>.from(u);
        m['balance'] = ((m['balance'] as int) - amount).clamp(0, 1 << 60);
        users[nickname] = m;
        _saveUsers(p, users);
      });

  @override
  Future<void> sendGlobal(String text) => _locked(() async {
        final p = await _prefs;
        final me = await _requireUser(p);
        await _requireAdmin(p);
        text = text.trim();
        if (text.isEmpty || text.length > 200) {
          throw const NeverWinException('Сообщение: 1–200 символов');
        }
        final cfg = await _config(p);
        final cd = (cfg['global_cooldown_sec'] ?? 10) as int;
        final last = p.getInt(_kGlobalCd) ?? 0;
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        if (nowMs - last < cd * 1000) {
          final wait = ((cd * 1000 - (nowMs - last)) / 1000).ceil();
          throw NeverWinException('Cooldown: подожди $wait c.');
        }
        await p.setInt(_kGlobalCd, nowMs);
        await p.setString(
            _kGlobal,
            jsonEncode({
              'id': _id('g'),
              'admin': me.nickname,
              'text': text,
              'createdAt': DateTime.now().toIso8601String(),
            }));
      });

  @override
  Future<void> setGlobalX2(bool enabled) => _locked(() async {
        final p = await _prefs;
        await _requireAdmin(p);
        final cfg = await _config(p)..['global_x2'] = enabled;
        await p.setString(_kConfig, jsonEncode(cfg));
      });

  @override
  Future<Map<String, dynamic>> adminParams() => _locked(() async {
        final p = await _prefs;
        await _requireAdmin(p);
        return _config(p);
      });

  @override
  Future<void> setAdminParam(String key, dynamic value) =>
      _locked(() async {
        final p = await _prefs;
        await _requireAdmin(p);
        final cfg = await _config(p);
        if (!cfg.containsKey(key)) {
          throw const NeverWinException('Неизвестный параметр');
        }
        if (value is int && value < 0) {
          throw const NeverWinException('Значение должно быть >= 0');
        }
        cfg[key] = value;
        await p.setString(_kConfig, jsonEncode(cfg));
      });

  /// Demo-only helper: grant admin to a nickname on the local backend.
  Future<void> grantLocalAdmin(String nickname) => _locked(() async {
        final p = await _prefs;
        final users = _decodeMap(p.getString(_kUsers));
        final u = users[nickname.trim()];
        if (u == null) throw const NeverWinException('Игрок не найден');
        final m = Map<String, dynamic>.from(u)..['isAdmin'] = true;
        users[nickname.trim()] = m;
        _saveUsers(p, users);
      });
}
