import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:theme/theme.dart';
import 'providers/providers.dart';
import 'services/storage_service.dart';
import 'services/blocklist_update_service.dart';
import 'router/app_router.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final storage = StorageService();
  await storage.init();
  // Check for remote blocklist updates in the background (non-blocking).
  BlocklistUpdateService(storage).checkAndUpdate().catchError((_) => false);
  runApp(ProviderScope(
    overrides: [storageProvider.overrideWithValue(storage)],
    child: const DnsFirewallApp(),
  ));
}

class DnsFirewallApp extends ConsumerWidget {
  const DnsFirewallApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final darkMode = ref.watch(darkModeProvider);
    return MaterialApp.router(
      title: 'NetShield',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme(),
      darkTheme: AppTheme.darkTheme(),
      themeMode: darkMode ? ThemeMode.dark : ThemeMode.light,
      routerConfig: appRouter,
    );
  }
}
