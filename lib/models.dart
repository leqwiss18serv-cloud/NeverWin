/// Shared data models for NeverWin. Backend-agnostic: both the local
/// demo backend and the Supabase backend map to these classes.

class PlayerProfile {
  final String id;
  final String nickname;
  final int balance;
  final bool isAdmin;
  final DateTime? blockedUntil;
  final DateTime createdAt;

  const PlayerProfile({
    required this.id,
    required this.nickname,
    required this.balance,
    this.isAdmin = false,
    this.blockedUntil,
    required this.createdAt,
  });

  bool get isBlocked =>
      blockedUntil != null && blockedUntil!.isAfter(DateTime.now());

  PlayerProfile copyWith({int? balance, bool? isAdmin, DateTime? blockedUntil}) =>
      PlayerProfile(
        id: id,
        nickname: nickname,
        balance: balance ?? this.balance,
        isAdmin: isAdmin ?? this.isAdmin,
        blockedUntil: blockedUntil ?? this.blockedUntil,
        createdAt: createdAt,
      );
}

class BankAccount {
  final String id; // internal uuid
  final String number; // 6-digit public ID
  final String name;
  final int balance;
  final String ownerId;
  final DateTime createdAt;

  const BankAccount({
    required this.id,
    required this.number,
    required this.name,
    required this.balance,
    required this.ownerId,
    required this.createdAt,
  });
}

class GameDef {
  final String id;
  final String title;
  final String rules;
  final int minBet;
  final String emoji;

  const GameDef({
    required this.id,
    required this.title,
    required this.rules,
    required this.minBet,
    required this.emoji,
  });
}

class GameDefs {
  static const List<GameDef> all = [
    GameDef(
      id: 'higher_lower',
      title: 'Больше — Меньше',
      rules:
          'Ставка от 1000 NC. Выпадает число 1–200. Угадай, будет ли следующее больше или меньше. Выигрыш x2, ничья — возврат ставки.',
      minBet: 1000,
      emoji: '🎲',
    ),
    GameDef(
      id: 'black_white',
      title: 'Чёрное или Белое',
      rules:
          'Ставка от 1500 NC. В барабане 25 чёрных, 25 белых и 2 зелёных. Угаданный цвет — x2, зелёный — x5 (<8%).',
      minBet: 1500,
      emoji: '⚫',
    ),
    GameDef(
      id: 'dice_even_odd',
      title: 'Кости: Чёт / Нечет',
      rules:
          'Ставка от 500 NC. Бросаются 2 кубика. Угадай чётность суммы. Выигрыш x2.',
      minBet: 500,
      emoji: '🎯',
    ),
    GameDef(
      id: 'coin_flip',
      title: 'Орёл или Решка',
      rules:
          'Ставка от 500 NC. Выбери сторону монеты. Угадал — x2. Также доступно в дуэлях.',
      minBet: 500,
      emoji: '🪙',
    ),
  ];

  static GameDef byId(String id) =>
      all.firstWhere((g) => g.id == id, orElse: () => all.first);
}

class GameResult {
  final String gameId;
  final int bet;
  final int payout; // credited amount (0 on loss, bet on draw)
  final bool win;
  final bool draw;
  final String detail; // human-readable outcome description
  final Map<String, dynamic> data; // raw outcome (numbers, colors...)
  final bool globalX2Applied;

  const GameResult({
    required this.gameId,
    required this.bet,
    required this.payout,
    required this.win,
    required this.draw,
    required this.detail,
    required this.data,
    this.globalX2Applied = false,
  });
}

class LeaderRow {
  final String nickname;
  final int totalNc;
  const LeaderRow(this.nickname, this.totalNc);
}

class FriendEntry {
  final String userId;
  final String nickname;
  const FriendEntry(this.userId, this.nickname);
}

class FriendRequest {
  final String id;
  final String fromUserId;
  final String fromNickname;
  final String toUserId;
  final String? toNickname;
  final String status; // pending | accepted | declined
  const FriendRequest({
    required this.id,
    required this.fromUserId,
    required this.fromNickname,
    required this.toUserId,
    this.toNickname,
    required this.status,
  });
}

class ChatMessage {
  final String id;
  final String fromUserId;
  final String toUserId;
  final String text;
  final String? imagePath; // local path or remote url
  final DateTime createdAt;
  const ChatMessage({
    required this.id,
    required this.fromUserId,
    required this.toUserId,
    required this.text,
    this.imagePath,
    required this.createdAt,
  });
}

class DuelInfo {
  final String id;
  final String challengerId;
  final String challengerNickname;
  final String opponentId;
  final String opponentNickname;
  final String gameId;
  final int bet;
  final String status; // pending | active | finished | declined
  final String? winnerId;
  final String? winnerNickname;
  const DuelInfo({
    required this.id,
    required this.challengerId,
    required this.challengerNickname,
    required this.opponentId,
    required this.opponentNickname,
    required this.gameId,
    required this.bet,
    required this.status,
    this.winnerId,
    this.winnerNickname,
  });
}

/// In-app notification item (transfers, friends, duels).
class AppNotice {
  final String id;
  final String kind; // transfer | friend | duel | system | promo
  final String text;
  final DateTime createdAt;
  bool read;
  AppNotice({
    required this.id,
    required this.kind,
    required this.text,
    required this.createdAt,
    this.read = false,
  });
}

/// Global admin broadcast shown as a top banner for 10 seconds.
class GlobalMessage {
  final String id;
  final String adminNickname;
  final String text;
  final DateTime createdAt;
  const GlobalMessage({
    required this.id,
    required this.adminNickname,
    required this.text,
    required this.createdAt,
  });

  String get formatted => 'ADMIN: $adminNickname / $text';
}

class NeverWinException implements Exception {
  final String message;
  const NeverWinException(this.message);
  @override
  String toString() => message;
}
