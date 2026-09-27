import '../models.dart';

/// Abstract backend contract. Two implementations exist:
/// - [LocalBackend]: offline demo driven by SharedPreferences, enforces the
///   same rules (min bets, odds, atomic balance moves).
/// - [SupabaseBackend]: server-authoritative via PostgREST / RPC / Realtime.
///
/// Game parameters (min bets, multipliers, odds, global x2) are read from
/// config, which the Supabase implementation loads from the `game_config`
/// table so admins can tune everything via SQL without rebuilding the APK.
abstract class GameBackend {
  String get name;

  Future<PlayerProfile> register(String nickname, String password);
  Future<PlayerProfile> login(String nickname, String password);
  Future<void> logout();
  Future<PlayerProfile?> currentSession();

  /// Server-authoritative game round. Validates min bet + balance, rolls the
  /// outcome on the "server" side, applies payout (incl. global x2) atomically
  /// and returns the result. `choice` values:
  /// higher_lower: 'higher' | 'lower'; black_white: 'black' | 'white';
  /// dice_even_odd: 'even' | 'odd'; coin_flip: 'heads' | 'tails'.
  Future<GameResult> playGame(String gameId, String choice, int bet);

  Future<Map<String, dynamic>> getConfig();

  // ---- Bank ----
  Future<BankAccount> createBankAccount(String name, String pin);
  Future<List<BankAccount>> listBankAccounts();
  Future<BankAccount> bankDeposit(String accountId, int amount);
  Future<BankAccount> bankWithdraw(String accountId, int amount);
  Future<void> bankTransfer({
    required String fromAccountId,
    required String targetNumber,
    required int amount,
  });

  // ---- Promo ----
  Future<int> redeemPromo(String code);

  // ---- Leaderboard ----
  Future<List<LeaderRow>> leaderboard();

  // ---- Friends / messenger ----
  Future<void> sendFriendRequest(String nickname);
  Future<List<FriendRequest>> incomingRequests();
  Future<List<FriendRequest>> outgoingRequests();
  Future<void> respondFriendRequest(String requestId, bool accept);
  Future<List<FriendEntry>> friends();
  Future<void> removeFriend(String friendUserId);
  Future<void> sendMessage(String friendUserId, String text, {String? imagePath});
  Future<List<ChatMessage>> messages(String friendUserId);
  Stream<List<ChatMessage>> watchMessages(String friendUserId);

  // ---- Duels ----
  Future<DuelInfo> challengeDuel(String friendUserId, String gameId, int bet);
  Future<List<DuelInfo>> myDuels();
  Future<DuelInfo> respondDuel(String duelId, bool accept);

  // ---- Notifications / global ----
  Future<List<AppNotice>> notices();
  Future<void> markNoticesRead();
  Stream<GlobalMessage> watchGlobal();
  Future<GlobalMessage?> latestGlobal();

  // ---- Admin ----
  Future<void> blockUser(String nickname, {DateTime? until});
  Future<void> unblockUser(String nickname);
  Future<void> grantNc(String nickname, int amount);
  Future<void> takeNc(String nickname, int amount);
  Future<void> sendGlobal(String text);
  Future<void> setGlobalX2(bool enabled);
  Future<Map<String, dynamic>> adminParams();
  Future<void> setAdminParam(String key, dynamic value);
}
