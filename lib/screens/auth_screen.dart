import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/glass.dart';

/// Registration / login gate. New accounts receive the start balance
/// (5000 NC by default, tunable via game_config / SQL).
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen>
    with SingleTickerProviderStateMixin {
  bool _isLogin = false;
  final _nick = TextEditingController();
  final _pass = TextEditingController();
  final _pass2 = TextEditingController();
  bool _obscure = true;
  DateTime? _coolUntil; // client-side 60s cooldown after a 429
  Timer? _coolTimer;

  int get _coolLeft {
    if (_coolUntil == null) return 0;
    return _coolUntil!
        .difference(DateTime.now())
        .inSeconds
        .clamp(0, 60);
  }

  @override
  void dispose() {
    _nick.dispose();
    _pass.dispose();
    _pass2.dispose();
    _coolTimer?.cancel();
    super.dispose();
  }

  void _startCooldown() {
    _coolUntil =
        DateTime.now().add(const Duration(seconds: 60));
    _coolTimer?.cancel();
    _coolTimer = Timer.periodic(
        const Duration(seconds: 1), (t) {
      if (!mounted || _coolLeft <= 0) {
        t.cancel();
        if (mounted) setState(() {});
      } else if (mounted) {
        setState(() {});
      }
    });
  }

  Future<void> _submit() async {
    final st = context.read<AppState>();
    if (_coolLeft > 0) {
      showError(context, 'Подожди $_coolLeft c. (лимит попыток)');
      return;
    }
    final nick = _nick.text.trim();
    final pass = _pass.text;
    if (nick.isEmpty || pass.isEmpty) {
      showError(context, 'Заполни никнейм и пароль');
      return;
    }
    if (!_isLogin && pass != _pass2.text) {
      showError(context, 'Пароли не совпадают');
      return;
    }
    final ok = _isLogin
        ? await st.doLogin(nick, pass)
        : await st.doRegister(nick, pass);
    if (!ok && mounted) {
      showError(context, st.lastError);
      if ((st.lastError ?? '').contains('429')) _startCooldown();
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
            gradient: NeverWinTheme.darkGradient),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(22),
              child: Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(30),
                    child: Image.asset(
                      'assets/logo/neverwin_logo.png',
                      width: 130,
                      height: 130,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const Icon(
                          Icons.videogame_asset_rounded,
                          size: 90,
                          color: NeverWinTheme.skyBlue),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'NeverWin',
                    style: TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 1.2),
                  ),
                  Text(
                    'Играй на виртуальные NC · старт 5000 NC',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 13),
                  ),
                  const SizedBox(height: 22),
                  GlassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _ModeTab(
                                label: 'Регистрация',
                                active: !_isLogin,
                                onTap: () =>
                                    setState(() => _isLogin = false),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _ModeTab(
                                label: 'Вход',
                                active: _isLogin,
                                onTap: () =>
                                    setState(() => _isLogin = true),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _nick,
                          style:
                              const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            labelText: 'Никнейм (уникальный)',
                            prefixIcon: Icon(Icons.person_rounded),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _pass,
                          obscureText: _obscure,
                          style:
                              const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: 'Пароль',
                            prefixIcon:
                                const Icon(Icons.lock_rounded),
                            suffixIcon: IconButton(
                              icon: Icon(_obscure
                                  ? Icons.visibility_rounded
                                  : Icons.visibility_off_rounded),
                              onPressed: () => setState(
                                  () => _obscure = !_obscure),
                            ),
                          ),
                        ),
                        if (!_isLogin) ...[
                          const SizedBox(height: 12),
                          TextField(
                            controller: _pass2,
                            obscureText: _obscure,
                            style: const TextStyle(
                                color: Colors.white),
                            decoration: const InputDecoration(
                              labelText: 'Подтверждение пароля',
                              prefixIcon:
                                  Icon(Icons.lock_outline_rounded),
                            ),
                          ),
                        ],
                        const SizedBox(height: 18),
                        GradientButton(
                          label: st.busy
                              ? 'Загрузка...'
                              : (_coolLeft > 0
                                  ? 'Подожди $_coolLeft c.'
                                  : (_isLogin
                                      ? 'Войти'
                                      : 'Зарегистрироваться')),
                          icon: _isLogin
                              ? Icons.login_rounded
                              : Icons.person_add_rounded,
                          onPressed: (st.busy || _coolLeft > 0)
                              ? null
                              : _submit,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          st.backendLabel,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Colors.white
                                  .withValues(alpha: 0.55),
                              fontSize: 11),
                        ),
                      ],
                    ),
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

class _ModeTab extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _ModeTab(
      {required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: NeverWinMotion.fast,
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          gradient: active ? NeverWinTheme.primaryGradient : null,
          color: active ? null : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withValues(alpha: active ? 1 : 0.6),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
