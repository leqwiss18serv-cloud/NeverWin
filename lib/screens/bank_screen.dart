import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/glass.dart';

/// Bank section: accounts (6-digit ID, 4-digit PIN), deposit / withdraw /
/// transfer by account number, account management + promocodes.
class BankScreen extends StatefulWidget {
  const BankScreen({super.key});

  @override
  State<BankScreen> createState() => _BankScreenState();
}

class _BankScreenState extends State<BankScreen> {
  List<BankAccount> _accounts = [];
  bool _loading = true;
  final _promo = TextEditingController();

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _promo.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final st = context.read<AppState>();
    setState(() => _loading = true);
    try {
      _accounts = await st.backend.listBankAccounts();
    } catch (e) {
      if (mounted) showError(context, e.toString().split('\n').first);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createAccount() async {
    final name = TextEditingController();
    final pin = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Новый счёт'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: name,
                decoration: const InputDecoration(
                    labelText: 'Название счёта')),
            const SizedBox(height: 10),
            TextField(
              controller: pin,
              keyboardType: TextInputType.number,
              maxLength: 4,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly
              ],
              decoration: const InputDecoration(
                  labelText: 'Пароль: 4 цифры', counterText: ''),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Создать')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final st = context.read<AppState>();
    final success = await st.run(() async {
      await st.backend.createBankAccount(name.text, pin.text);
      _accounts = await st.backend.listBankAccounts();
    });
    if (success && mounted) {
      showOk(context, 'Счёт создан');
      setState(() {});
    } else if (mounted) {
      showError(context, st.lastError);
    }
  }

  Future<void> _amountDialog({
    required String title,
    required Future<void> Function(int) action,
  }) async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration:
              const InputDecoration(labelText: 'Сумма NC'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('OK')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final amount = int.tryParse(c.text.trim());
    if (amount == null || amount <= 0) {
      showError(context, 'Некорректная сумма');
      return;
    }
    final st = context.read<AppState>();
    final success = await st.run(() async {
      await action(amount);
      _accounts = await st.backend.listBankAccounts();
      await st.refreshAll();
    });
    if (!mounted) return;
    if (success) {
      showOk(context, 'Готово');
      setState(() {});
    } else {
      showError(context, st.lastError);
    }
  }

  Future<void> _transferDialog(BankAccount from) async {
    final target = TextEditingController();
    final amount = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Перевод со счёта «${from.name}»'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: target,
              keyboardType: TextInputType.number,
              maxLength: 6,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly
              ],
              decoration: const InputDecoration(
                  labelText: 'ID счёта получателя (6 цифр)',
                  counterText: ''),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: amount,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly
              ],
              decoration:
                  const InputDecoration(labelText: 'Сумма NC'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Подтвердить перевод')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final st = context.read<AppState>();
    final success = await st.run(() async {
      await st.backend.bankTransfer(
        fromAccountId: from.id,
        targetNumber: target.text.trim(),
        amount: int.tryParse(amount.text.trim()) ?? 0,
      );
      _accounts = await st.backend.listBankAccounts();
      await st.refreshAll();
    });
    if (!mounted) return;
    if (success) {
      showOk(context, 'Перевод выполнен');
      setState(() {});
    } else {
      showError(context, st.lastError);
    }
  }

  void _manage(BankAccount a) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(18),
        decoration: const BoxDecoration(
          color: NeverWinTheme.panelDark,
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(26)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('«${a.name}» · ID ${a.number}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 16)),
              Text('Баланс: ${a.balance} NC',
                  style: const TextStyle(
                      color: NeverWinTheme.iceCyan,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 14),
              Wrap(spacing: 8, runSpacing: 8, children: [
                GradientButton(
                    small: true,
                    label: 'Пополнить счёт',
                    icon: Icons.arrow_downward_rounded,
                    onPressed: () {
                      Navigator.pop(ctx);
                      _amountDialog(
                        title: 'Пополнить «${a.name}»',
                        action: (v) =>
                            st(context).backend.bankDeposit(a.id, v),
                      );
                    }),
                GradientButton(
                    small: true,
                    label: 'Вывести на баланс',
                    icon: Icons.arrow_upward_rounded,
                    onPressed: () {
                      Navigator.pop(ctx);
                      _amountDialog(
                        title: 'Вывести с «${a.name}»',
                        action: (v) =>
                            st(context).backend.bankWithdraw(a.id, v),
                      );
                    }),
                GradientButton(
                    small: true,
                    label: 'Перевести на другой счёт',
                    icon: Icons.swap_horiz_rounded,
                    onPressed: () {
                      Navigator.pop(ctx);
                      _transferDialog(a);
                    }),
                GradientButton(
                    small: true,
                    label: 'Скопировать ID',
                    icon: Icons.copy_rounded,
                    onPressed: () {
                      Clipboard.setData(
                          ClipboardData(text: a.number));
                      Navigator.pop(ctx);
                      showOk(context, 'ID ${a.number} скопирован');
                    }),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  AppState st(BuildContext ctx) => ctx.read<AppState>();

  Future<void> _redeem() async {
    final st = context.read<AppState>();
    final success = await st.run(() async {
      final reward = await st.backend.redeemPromo(_promo.text);
      await st.refreshAll();
      _promo.clear();
      if (mounted) showOk(context, 'Промокод: +$reward NC!');
    });
    if (!success && mounted) showError(context, st.lastError);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      children: [
        Row(
          children: [
            const SectionTitle('Мои счета'),
            const Spacer(),
            GradientButton(
              small: true,
              label: '+ Новый счёт',
              icon: Icons.add_rounded,
              onPressed: _createAccount,
            ),
          ],
        ),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_accounts.isEmpty)
          const GlassCard(
              child: Text('Счетов пока нет. Создай первый!',
                  style: TextStyle(color: Colors.white70)))
        else
          for (final a in _accounts) ...[
            GlassCard(
              onTap: () => _manage(a),
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient:
                          NeverWinTheme.primaryGradient,
                      borderRadius:
                          BorderRadius.circular(14),
                    ),
                    child: const Icon(
                        Icons.account_balance_wallet_rounded,
                        color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Text(a.name,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 15)),
                        Text('ID ${a.number}',
                            style: TextStyle(
                                color: Colors.white
                                    .withValues(alpha: 0.6),
                                fontSize: 12,
                                fontFamily: 'monospace')),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.end,
                    children: [
                      Text('${a.balance} NC',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800)),
                      const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Управление',
                              style: TextStyle(
                                  color:
                                      NeverWinTheme.iceCyan,
                                  fontSize: 11,
                                  fontWeight:
                                      FontWeight.w700)),
                          Icon(Icons.chevron_right_rounded,
                              color:
                                  NeverWinTheme.iceCyan,
                              size: 16),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
        const SectionTitle('Промокод'),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Введи промокод, чтобы получить бонусные NC.',
                style:
                    TextStyle(color: Colors.white70, fontSize: 12.5),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _promo,
                      textCapitalization:
                          TextCapitalization.characters,
                      style:
                          const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Промокод',
                        prefixIcon:
                            Icon(Icons.card_giftcard_rounded),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  GradientButton(
                      label: 'OK', onPressed: _redeem),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
