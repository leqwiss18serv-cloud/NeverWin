import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/glass.dart';

/// Leaderboard: TOP-10 by main balance + all bank accounts.
class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  List<LeaderRow> _rows = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final st = context.read<AppState>();
    setState(() => _loading = true);
    try {
      _rows = await st.backend.leaderboard();
    } catch (e) {
      if (mounted) showError(context, e.toString().split('\n').first);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = context.watch<AppState>().profile?.nickname;
    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        children: [
          const SectionTitle('ТОП-10 самых богатых'),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_rows.isEmpty)
            const GlassCard(
                child: Text('Пока пусто.',
                    style: TextStyle(color: Colors.white70)))
          else
            for (var i = 0; i < _rows.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: GlassCard(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          gradient: i < 3
                              ? NeverWinTheme.goldGradient
                              : NeverWinTheme.primaryGradient,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '${i + 1}',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: i < 3
                                ? const Color(0xFF4A2C00)
                                : Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _rows[i].nickname +
                              (_rows[i].nickname == me ? ' (ты)' : ''),
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 15),
                        ),
                      ),
                      Text(
                        '${_rows[i].totalNc} NC',
                        style: const TextStyle(
                            color: NeverWinTheme.iceCyan,
                            fontWeight: FontWeight.w800),
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
