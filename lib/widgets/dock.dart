import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme.dart';

class DockItem {
  final IconData icon;
  final String label;
  const DockItem(this.icon, this.label);
}

/// Bottom dock bar. The admin tab is only present for admins.
class NeverWinDock extends StatelessWidget {
  const NeverWinDock({super.key});

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final isAdmin = st.profile?.isAdmin ?? false;
    final items = <DockItem>[
      const DockItem(Icons.videogame_asset_rounded, 'Игры'),
      const DockItem(Icons.account_balance_rounded, 'Банк'),
      const DockItem(Icons.leaderboard_rounded, 'Топ'),
      const DockItem(Icons.group_rounded, 'Друзья'),
      const DockItem(Icons.settings_rounded, 'Настройки'),
      if (isAdmin) const DockItem(Icons.admin_panel_settings_rounded, 'Админ'),
    ];
    final index = st.section.clamp(0, items.length - 1);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF0B3C6E).withValues(alpha: 0.82),
                    const Color(0xFF0B1220).withValues(alpha: 0.88),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(
                    color: Colors.white.withValues(alpha: 0.18)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  for (var i = 0; i < items.length; i++)
                    _DockButton(
                      item: items[i],
                      selected: i == index,
                      badge: items[i].label == 'Друзья' &&
                          st.unreadNotices > 0,
                      onTap: () => st.goSection(i),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DockButton extends StatelessWidget {
  final DockItem item;
  final bool selected;
  final bool badge;
  final VoidCallback onTap;

  const _DockButton({
    required this.item,
    required this.selected,
    required this.badge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: NeverWinMotion.fast,
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          gradient: selected ? NeverWinTheme.primaryGradient : null,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(item.label == 'Админ' && selected
                    ? Icons.admin_panel_settings_rounded
                    : item.icon, color: Colors.white, size: 22),
                if (badge)
                  Positioned(
                    right: -6,
                    top: -4,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        color: Colors.redAccent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              item.label,
              style: TextStyle(
                color: Colors.white.withValues(
                    alpha: selected ? 1 : 0.65),
                fontSize: 10.5,
                fontWeight:
                    selected ? FontWeight.w800 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
