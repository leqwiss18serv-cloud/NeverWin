import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'state/app_state.dart';
import 'screens/auth_screen.dart';
import 'screens/home_shell.dart';
import 'theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = AppState();
  await state.boot();
  runApp(NeverWinApp(state: state));
}

class NeverWinApp extends StatelessWidget {
  final AppState state;
  const NeverWinApp({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: state,
      child: Consumer<AppState>(
        builder: (ctx, st, _) => MaterialApp(
          title: 'NeverWin',
          debugShowCheckedModeBanner: false,
          theme: NeverWinTheme.build(dark: false),
          darkTheme: NeverWinTheme.build(dark: true),
          themeMode: st.darkTheme ? ThemeMode.dark : ThemeMode.light,
          home: st.profile == null
              ? const AuthScreen()
              : const HomeShell(),
        ),
      ),
    );
  }
}
