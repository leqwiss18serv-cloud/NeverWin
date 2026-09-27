import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../widgets/dock.dart';
import '../widgets/glass.dart';
import 'admin_screen.dart';
import 'bank_screen.dart';
import 'friends_screen.dart';
import 'games_screen.dart';
import 'leaderboard_screen.dart';
import 'settings_screen.dart';

/// Main shell: balance header + section body + dock bar + top banners.
class HomeShell extends StatelessWidget {
  const HomeShell({super.key});

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final isAdmin = st.profile?.isAdmin ?? false;
    final idx = st.section.clamp(0, isAdmin ? 5 : 4).toInt();

    Widget body;
    switch (idx) {
      case 0:
        body = const GamesScreen();
        break;
      case 1:
        body = const BankScreen();
        break;
      case 2:
        body = const LeaderboardScreen();
        break;
      case 3:
        body = const FriendsScreen();
        break;
      case 4:
        body = const SettingsScreen();
        break;
      default:
        body = const AdminScreen();
    }

    return Scaffold(
      body: Column(
        children: [
          BalanceHeader(
            nickname: st.profile?.nickname ?? '—',
            balance: st.profile?.balance ?? 0,
            backendLabel: st.backendLabel,
            globalX2: st.globalX2,
          ),
          if (st.banner != null)
            TopBanner(
              text: st.banner!.formatted,
              isAdmin: st.banner!.adminNickname != 'NeverWin' &&
                  st.banner!.formatted.startsWith('ADMIN:'),
              onClose: () => st.dismissBanner(),
            ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOutCubic,
              child: KeyedSubtree(key: ValueKey(idx), child: body),
            ),
          ),
          const NeverWinDock(),
        ],
      ),
    );
  }
}
