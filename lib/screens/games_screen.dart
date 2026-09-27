import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/glass.dart';

/// Games section: 4 mini-games with server-authoritative rounds.
class GamesScreen extends StatelessWidget {
  const GamesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      children: [
        for (final g in GameDefs.all) ...[
          _GameCard(def: g),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _GameCard extends StatefulWidget {
  final GameDef def;
  const _GameCard({required this.def});

  @override
  State<_GameCard> createState() => _GameCardState();
}

class _GameCardState extends State<_GameCard> {
  final _bet = TextEditingController();
  String? _choice;
  GameResult? _last;
  bool _playing = false;

  @override
  void dispose() {
    _bet.dispose();
    super.dispose();
  }

  List<Map<String, String>> _choices() {
    switch (widget.def.id) {
      case 'higher_lower':
        return const [
          {'v': 'higher', 't': 'Больше ⬆️'},
          {'v': 'lower', 't': 'Меньше ⬇️'},
        ];
      case 'black_white':
        return const [
          {'v': 'black', 't': '⚫ Чёрное'},
          {'v': 'white', 't': '⚪ Белое'},
        ];
      case 'dice_even_odd':
        return const [
          {'v': 'even', 't': 'Чёт'},
          {'v': 'odd', 't': 'Нечет'},
        ];
      default:
        return const [
          {'v': 'heads', 't': '🦅 Орёл'},
          {'v': 'tails', 't': '🪙 Решка'},
        ];
    }
  }

  Future<void> _play() async {
    final st = context.read<AppState>();
    final bet = int.tryParse(_bet.text.trim());
    if (bet == null || bet <= 0) {
      showError(context, 'Введи корректную ставку');
      return;
    }
    if (_choice == null) {
      showError(context, 'Сначала выбери вариант');
      return;
    }
    setState(() => _playing = true);
    HapticFeedback.lightImpact();
    try {
      final r =
          await st.backend.playGame(widget.def.id, _choice!, bet);
      await st.refreshAll();
      if (mounted) {
        setState(() => _last = r);
        HapticFeedback.mediumImpact();
      }
    } on NeverWinException catch (e) {
      if (mounted) showError(context, e.message);
    } catch (e) {
      if (mounted) showError(context, e.toString().split('\n').first);
    } finally {
      if (mounted) setState(() => _playing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final minBet = st.minBet(widget.def.id);
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: NeverWinTheme.primaryGradient,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(widget.def.emoji,
                    style: const TextStyle(fontSize: 24)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.def.title,
                        style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            color: Colors.white)),
                    Text('Мин. ставка: $minBet NC',
                        style: TextStyle(
                            color: NeverWinTheme.iceCyan,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              if (st.globalX2)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    gradient: NeverWinTheme.goldGradient,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text('x2',
                      style: TextStyle(
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF4A2C00))),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(widget.def.rules,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 12.5)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              for (final c in _choices())
                ChoiceChip(
                  label: Text(c['t']!),
                  selected: _choice == c['v'],
                  onSelected: (_) =>
                      setState(() => _choice = c['v']),
                  selectedColor: NeverWinTheme.skyBlue,
                  labelStyle: TextStyle(
                    color: _choice == c['v']
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.8),
                    fontWeight: FontWeight.w700,
                  ),
                  backgroundColor:
                      Colors.white.withValues(alpha: 0.08),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _bet,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly
                  ],
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Ставка (мин. $minBet)',
                    prefixIcon:
                        const Icon(Icons.monetization_on_rounded),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              GradientButton(
                label: _playing ? '...' : 'Старт',
                icon: Icons.play_arrow_rounded,
                onPressed: _playing ? null : _play,
              ),
            ],
          ),
          if (_last != null) ...[
            const SizedBox(height: 12),
            AnimatedContainer(
              duration: NeverWinMotion.normal,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _last!.draw
                    ? Colors.white.withValues(alpha: 0.08)
                    : (_last!.win
                        ? const Color(0xFF0E6E3E)
                            .withValues(alpha: 0.45)
                        : const Color(0xFF7A1F2B)
                            .withValues(alpha: 0.45)),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: Colors.white.withValues(alpha: 0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _last!.draw
                        ? '🤝 ${_last!.detail}'
                        : (_last!.win
                            ? '🎉 ${_last!.detail} (+${_last!.payout} NC${_last!.globalX2Applied ? ', GLOBAL x2!' : ''})'
                            : '😞 ${_last!.detail} (−${_last!.bet} NC)'),
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
