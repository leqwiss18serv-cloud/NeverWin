import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../backend/game_backend.dart';
import '../backend/local_backend.dart';
import '../backend/supabase_backend.dart';
import '../backend/supabase_config.dart';
import '../models.dart';

/// Global app state: session, backend selection, config, notices, banners.
class AppState extends ChangeNotifier {
  GameBackend _backend = LocalBackend();
  GameBackend get backend => _backend;
  bool get isSupabase => _backend is SupabaseBackend;
  String get backendLabel => isSupabase ? 'Supabase · online' : 'Локальный режим';

  PlayerProfile? profile;
  Map<String, dynamic> config = {};
  List<AppNotice> notices = [];
  GlobalMessage? banner; // currently displayed top banner
  bool busy = false;
  String? lastError;

  int section = 0; // dock index
  bool darkTheme = true;
  bool notifEnabled = true;

  StreamSubscription<GlobalMessage>? _globalSub;
  Timer? _poll;

  static const _kSbUrl = 'nw_sb_url';
  static const _kSbKey = 'nw_sb_key';
  static const _kDark = 'nw_dark';

  Future<void> boot() async {
    final p = await SharedPreferences.getInstance();
    darkTheme = p.getBool(_kDark) ?? true;
    final url = p.getString(_kSbUrl);
    final key = p.getString(_kSbKey);
    if (url != null && key != null && url.isNotEmpty && key.isNotEmpty) {
      try {
        await SupabaseBackend.init(url, key);
        _backend = SupabaseBackend.instance;
      } catch (_) {
        _backend = LocalBackend();
      }
    } else {
      // Compiled-in project defaults (publishable key — client-safe).
      // If the schema isn't applied yet or there's no network, stay local.
      try {
        await SupabaseBackend.init(
            SupabaseDefaults.url, SupabaseDefaults.publishableKey);
        await SupabaseBackend.instance.getConfig();
        _backend = SupabaseBackend.instance;
      } catch (_) {
        _backend = LocalBackend();
      }
    }
    profile = await _safe(() => _backend.currentSession());
    if (profile != null) {
      await refreshAll();
      _startFeeds();
    }
    notifyListeners();
  }

  Future<T?> _safe<T>(Future<T> Function() fn) async {
    try {
      return await fn();
    } catch (_) {
      return null;
    }
  }

  void _startFeeds() {
    _globalSub?.cancel();
    _poll?.cancel();
    _globalSub = _backend.watchGlobal().listen((g) {
      if (!notifEnabled) return;
      banner = g;
      notifyListeners();
      Future<void>.delayed(const Duration(seconds: 10), () {
        if (banner?.id == g.id) {
          banner = null;
          notifyListeners();
        }
      });
    });
    _poll = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (profile == null) return;
      final g = await _safe(() => _backend.latestGlobal());
      if (g != null && banner?.id != g.id && notifEnabled) {
        banner = g;
        notifyListeners();
        Future<void>.delayed(const Duration(seconds: 10), () {
          if (banner?.id == g.id) {
            banner = null;
            notifyListeners();
          }
        });
      }
      final n = await _safe(() => _backend.notices());
      if (n != null) {
        notices = n;
        notifyListeners();
      }
    });
    // initial global check
    _safe(() => _backend.latestGlobal()).then((g) {
      if (g != null && notifEnabled) {
        banner = g;
        notifyListeners();
      }
    });
  }

  void showLocalBanner(String text) {
    banner = GlobalMessage(
      id: 'local_${DateTime.now().millisecondsSinceEpoch}',
      adminNickname: 'NeverWin',
      text: text,
      createdAt: DateTime.now(),
    );
    notifyListeners();
    Future<void>.delayed(const Duration(seconds: 4), () {
      banner = null;
      notifyListeners();
    });
  }

  void dismissBanner() {
    banner = null;
    notifyListeners();
  }

  Future<bool> run(Future<void> Function() fn) async {
    busy = true;
    lastError = null;
    notifyListeners();
    try {
      await fn();
      busy = false;
      notifyListeners();
      return true;
    } on NeverWinException catch (e) {
      lastError = e.message;
      busy = false;
      notifyListeners();
      return false;
    } catch (e) {
      lastError = e.toString().split('\n').first;
      busy = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> refreshAll() async {
    profile = await _safe(() => _backend.currentSession());
    final c = await _safe(() => _backend.getConfig());
    if (c != null) config = c;
    final n = await _safe(() => _backend.notices());
    if (n != null) notices = n;
    notifyListeners();
  }

  Future<bool> doRegister(String nick, String pass) => run(() async {
        profile = await _backend.register(nick, pass);
        await refreshAll();
        _startFeeds();
      });

  Future<bool> doLogin(String nick, String pass) => run(() async {
        profile = await _backend.login(nick, pass);
        await refreshAll();
        _startFeeds();
      });

  Future<void> doLogout() async {
    await _backend.logout();
    profile = null;
    notices = [];
    banner = null;
    section = 0;
    _globalSub?.cancel();
    _poll?.cancel();
    notifyListeners();
  }

  void goSection(int i) {
    section = i;
    notifyListeners();
  }

  Future<void> toggleTheme() async {
    darkTheme = !darkTheme;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kDark, darkTheme);
    notifyListeners();
  }

  Future<bool> connectSupabase(String url, String key) => run(() async {
        await SupabaseBackend.init(url.trim(), key.trim());
        final p = await SharedPreferences.getInstance();
        await p.setString(_kSbUrl, url.trim());
        await p.setString(_kSbKey, key.trim());
        _backend = SupabaseBackend.instance;
        profile = null;
        notifyListeners();
      });

  Future<void> useLocalBackend() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kSbUrl);
    await p.remove(_kSbKey);
    await doLogout();
    _backend = LocalBackend();
    notifyListeners();
  }

  int minBet(String gameId) =>
      (config['min_bet_$gameId'] ?? GameDefs.byId(gameId).minBet) as int;

  /// Public re-notify helper for simple field toggles in Settings.
  void poke() => notifyListeners();

  bool get globalX2 => (config['global_x2'] ?? false) == true;

  int get unreadNotices => notices.where((n) => !n.read).length;
}
