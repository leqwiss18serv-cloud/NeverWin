import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../backend/local_backend.dart';
import '../state/app_state.dart';
import '../widgets/glass.dart';

/// Settings: theme, notifications, backend connection (Supabase URL/key),
/// demo admin grant (local backend only), logout.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _url = TextEditingController();
  final _key = TextEditingController();
  final _demoAdmin = TextEditingController();

  @override
  void dispose() {
    _url.dispose();
    _key.dispose();
    _demoAdmin.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final st = context.read<AppState>();
    final ok =
        await st.connectSupabase(_url.text, _key.text);
    if (!mounted) return;
    if (ok) {
      showOk(context, 'Supabase подключён. Войди заново.');
    } else {
      showError(context, st.lastError);
    }
  }

  Future<void> _grantDemoAdmin() async {
    final st = context.read<AppState>();
    final backend = st.backend;
    if (backend is! LocalBackend) {
      showError(context, 'Только для локального режима');
      return;
    }
    final ok = await st.run(() async {
      final nick = _demoAdmin.text.trim().isEmpty
          ? (st.profile?.nickname ?? '')
          : _demoAdmin.text.trim();
      await backend.grantLocalAdmin(nick);
      await st.refreshAll();
    });
    if (!mounted) return;
    if (ok) {
      showOk(context, 'Demo-админ выдан');
    } else {
      showError(context, st.lastError);
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      children: [
        const SectionTitle('Оформление'),
        GlassCard(
          child: Column(
            children: [
              SwitchListTile(
                title: const Text('Тёмная тема',
                    style: TextStyle(color: Colors.white)),
                value: st.darkTheme,
                onChanged: (_) => st.toggleTheme(),
              ),
              SwitchListTile(
                title: const Text('Уведомления и баннеры',
                    style: TextStyle(color: Colors.white)),
                value: st.notifEnabled,
                onChanged: (_) {
                  st.notifEnabled = !st.notifEnabled;
                  st.poke();
                },
              ),
            ],
          ),
        ),
        const SectionTitle('Сервер (Supabase)'),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Текущий режим: ${st.backendLabel}',
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 12.5)),
              const SizedBox(height: 10),
              TextField(
                controller: _url,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                    labelText: 'Supabase URL (https://...)'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _key,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                    labelText: 'Supabase anon key'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: GradientButton(
                        label: 'Подключить',
                        onPressed: _connect),
                  ),
                  if (st.isSupabase) ...[
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () =>
                          st.useLocalBackend(),
                      child: const Text('Офлайн режим',
                          style: TextStyle(
                              color: Colors.redAccent)),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'Примени supabase/schema.sql в SQL Editor проекта, затем введи URL и anon key. Вся денежная логика — в RPC.',
                style:
                    TextStyle(color: Colors.white54, fontSize: 11.5),
              ),
            ],
          ),
        ),
        if (!st.isSupabase) ...[
          const SectionTitle('Демо (локальный режим)'),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Выдать себе demo-права администратора для проверки админ-панели. В Supabase-режиме права выдаются только через SQL.',
                  style: TextStyle(
                      color: Colors.white54, fontSize: 11.5),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _demoAdmin,
                        style: const TextStyle(
                            color: Colors.white),
                        decoration: const InputDecoration(
                            labelText:
                                'Никнейм (пусто = я)'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    GradientButton(
                        label: 'Админ',
                        onPressed: _grantDemoAdmin),
                  ],
                ),
              ],
            ),
          ),
        ],
        const SectionTitle('Аккаунт'),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                  'Никнейм: ${st.profile?.nickname ?? '—'} · Баланс: ${st.profile?.balance ?? 0} NC',
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 12),
              GradientButton(
                label: 'Выйти из аккаунта',
                icon: Icons.logout_rounded,
                onPressed: () => st.doLogout(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        const Center(
          child: Text('NeverWin 0.1.1 · NC — виртуальная валюта',
              style:
                  TextStyle(color: Colors.white38, fontSize: 11)),
        ),
      ],
    );
  }
}
