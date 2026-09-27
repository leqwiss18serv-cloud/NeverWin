import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../widgets/glass.dart';

/// Admin panel: visible in the dock only for admins.
/// Block / temp-block, grant / take NC, global broadcast (10s cooldown),
/// global x2 toggle, tunable game parameters.
class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  Map<String, dynamic> _params = {};
  bool _loading = true;

  final _nickBlock = TextEditingController();
  final _hoursBlock = TextEditingController(text: '24');
  final _nickGrant = TextEditingController();
  final _amountGrant = TextEditingController();
  final _nickTake = TextEditingController();
  final _amountTake = TextEditingController();
  final _global = TextEditingController();

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _nickBlock.dispose();
    _hoursBlock.dispose();
    _nickGrant.dispose();
    _amountGrant.dispose();
    _nickTake.dispose();
    _amountTake.dispose();
    _global.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final st = context.read<AppState>();
    setState(() => _loading = true);
    try {
      _params = await st.backend.adminParams();
    } catch (e) {
      if (mounted) showError(context, e.toString().split('\n').first);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _act(Future<void> Function() fn, String okMsg) async {
    final st = context.read<AppState>();
    final ok = await st.run(() async {
      await fn();
      _params = await st.backend.adminParams();
      await st.refreshAll();
    });
    if (!mounted) return;
    if (ok) {
      showOk(context, okMsg);
      setState(() {});
    } else {
      showError(context, st.lastError);
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final gx = (_params['global_x2'] ?? st.globalX2) == true;
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      children: [
        const SectionTitle('Админ-панель'),
        if (_loading)
          const Center(child: CircularProgressIndicator())
        else ...[
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Блокировки',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                TextField(
                    controller: _nickBlock,
                    style:
                        const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                        labelText: 'Никнейм игрока')),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _hoursBlock,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter
                              .digitsOnly
                        ],
                        style: const TextStyle(
                            color: Colors.white),
                        decoration: const InputDecoration(
                            labelText: 'Часов (бан)'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GradientButton(
                      small: true,
                      label: 'Бан',
                      onPressed: () => _act(
                        () => st.backend.blockUser(
                          _nickBlock.text.trim(),
                          until: DateTime.now().add(Duration(
                              hours: int.tryParse(
                                      _hoursBlock.text) ??
                                  24)),
                        ),
                        'Игрок заблокирован',
                      ),
                    ),
                    const SizedBox(width: 8),
                    GradientButton(
                      small: true,
                      label: 'Пермамент',
                      onPressed: () => _act(
                        () => st.backend.blockUser(
                            _nickBlock.text.trim()),
                        'Игрок заблокирован навсегда',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                GradientButton(
                  small: true,
                  label: 'Разблокировать',
                  onPressed: () => _act(
                    () => st.backend
                        .unblockUser(_nickBlock.text.trim()),
                    'Игрок разблокирован',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Балансы (NC)',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                          controller: _nickGrant,
                          style: const TextStyle(
                              color: Colors.white),
                          decoration: const InputDecoration(
                              labelText: 'Никнейм')),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _amountGrant,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter
                              .digitsOnly
                        ],
                        style: const TextStyle(
                            color: Colors.white),
                        decoration: const InputDecoration(
                            labelText: 'Сумма'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                GradientButton(
                  small: true,
                  label: 'Выдать NC',
                  icon: Icons.add_rounded,
                  onPressed: () => _act(
                    () => st.backend.grantNc(
                        _nickGrant.text.trim(),
                        int.tryParse(
                                _amountGrant.text) ??
                            0),
                    'NC выданы',
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                          controller: _nickTake,
                          style: const TextStyle(
                              color: Colors.white),
                          decoration: const InputDecoration(
                              labelText: 'Никнейм')),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _amountTake,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter
                              .digitsOnly
                        ],
                        style: const TextStyle(
                            color: Colors.white),
                        decoration: const InputDecoration(
                            labelText: 'Сумма'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                GradientButton(
                  small: true,
                  label: 'Списать NC',
                  icon: Icons.remove_rounded,
                  onPressed: () => _act(
                    () => st.backend.takeNc(
                        _nickTake.text.trim(),
                        int.tryParse(
                                _amountTake.text) ??
                            0),
                    'NC списаны',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Глобальное сообщение (cooldown 10 c.)',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                TextField(
                    controller: _global,
                    maxLength: 200,
                    style:
                        const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                        labelText: 'ADMIN: ник / сообщение',
                        counterText: '')),
                const SizedBox(height: 8),
                GradientButton(
                  label: 'Отправить всем',
                  icon: Icons.campaign_rounded,
                  onPressed: () => _act(
                    () =>
                        st.backend.sendGlobal(_global.text),
                    'Глобальное сообщение отправлено',
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Глобальный x2: ${gx ? 'ВКЛ' : 'ВЫКЛ'}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                    Switch(
                      value: gx,
                      onChanged: (v) => _act(
                        () => st.backend.setGlobalX2(v),
                        v ? 'Global x2 включён' : 'Global x2 выключен',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const SectionTitle('Игровые параметры (SQL-конфиг)'),
          GlassCard(
            child: Column(
              children: [
                for (final e in _params.entries)
                  _ParamRow(
                    name: e.key,
                    value: e.value,
                    onSave: (v) => _act(
                      () =>
                          st.backend.setAdminParam(e.key, v),
                      'Параметр ${e.key} обновлён',
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _ParamRow extends StatefulWidget {
  final String name;
  final dynamic value;
  final Future<void> Function(dynamic) onSave;
  const _ParamRow(
      {required this.name,
      required this.value,
      required this.onSave});

  @override
  State<_ParamRow> createState() => _ParamRowState();
}

class _ParamRowState extends State<_ParamRow> {
  late final TextEditingController _c;

  @override
  void initState() {
    super.initState();
    _c = TextEditingController(text: widget.value.toString());
  }

  @override
  void didUpdateWidget(covariant _ParamRow old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) {
      _c.text = widget.value.toString();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(widget.name,
                style: const TextStyle(
                    color: Colors.white70, fontSize: 12)),
          ),
          Expanded(
            flex: 2,
            child: TextField(
              controller: _c,
              style: const TextStyle(
                  color: Colors.white, fontSize: 13),
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                    horizontal: 10, vertical: 8),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.save_rounded,
                color: Colors.white70, size: 20),
            onPressed: () {
              final raw = _c.text.trim();
              dynamic v = raw;
              if (raw == 'true') {
                v = true;
              } else if (raw == 'false') {
                v = false;
              } else if (int.tryParse(raw) != null) {
                v = int.parse(raw);
              }
              widget.onSave(v);
            },
          ),
        ],
      ),
    );
  }
}
