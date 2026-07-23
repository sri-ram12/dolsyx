import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'screens/login_screen.dart';
import 'package:provider/provider.dart';
import 'providers/auth_provider.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
      ],
      child: const DolsyxApp(),
    ),
  );
}

class DolsyxApp extends StatelessWidget {
  const DolsyxApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DOLSYX Mobile',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const LoginScreen(),
    );
  }
}
