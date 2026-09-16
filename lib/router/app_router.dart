import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:theme/theme.dart';
import '../screens/screens.dart';

final _shellKey = GlobalKey<NavigatorState>();

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    ShellRoute(
      navigatorKey: _shellKey,
      builder: (context, state, child) => AppShell(child: child),
      routes: [
        GoRoute(path: '/', builder: (c, s) => const DashboardScreen()),
        GoRoute(path: '/rules', builder: (c, s) => const RulesScreen()),
        GoRoute(path: '/settings', builder: (c, s) => const SettingsScreen()),
      ],
    ),
    GoRoute(path: '/blocklists', builder: (c, s) => const BlocklistsScreen()),
    GoRoute(path: '/allowlist', builder: (c, s) => const AllowlistScreen()),
    GoRoute(path: '/custom-rules', builder: (c, s) => const CustomRulesScreen()),
    GoRoute(path: '/apps', builder: (c, s) => const AppsScreen()),
    GoRoute(path: '/dns-servers', builder: (c, s) => const DnsServersScreen()),
    GoRoute(path: '/statistics', builder: (c, s) => const StatisticsScreen()),
    GoRoute(path: '/test', builder: (c, s) => const TestModeScreen()),
    GoRoute(path: '/dev', builder: (c, s) => const DevDiagnosticsScreen()),
    GoRoute(path: '/about', builder: (c, s) => const AboutScreen()),
  ],
);

class AppShell extends StatelessWidget {
  final Widget child;
  const AppShell({super.key, required this.child});

  static const _destinations = [
    BottomNavigationBarItem(icon: Icon(Icons.home_outlined), activeIcon: Icon(Icons.home), label: 'Home'),
    BottomNavigationBarItem(icon: Icon(Icons.shield_outlined), activeIcon: Icon(Icons.shield), label: 'Rules'),
    BottomNavigationBarItem(icon: Icon(Icons.settings_outlined), activeIcon: Icon(Icons.settings), label: 'Settings'),
  ];

  int _index(BuildContext context) {
    final loc = GoRouterState.of(context).uri.toString();
    if (loc.startsWith('/rules')) return 1;
    if (loc.startsWith('/settings')) return 2;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final idx = _index(context);
    return Scaffold(
      appBar: ThemeAppBar(
        title: 'NetShield',
        actions: [
          IconButton(
            icon: const Icon(Icons.science_outlined),
            tooltip: 'Test mode',
            onPressed: () => context.push('/test'),
          ),
        ],
      ),
      body: child,
      bottomNavigationBar: ThemeBottomNavigationBar(
        items: _destinations,
        currentIndex: idx,
        onTap: (i) {
          switch (i) {
            case 0: context.go('/');
            case 1: context.go('/rules');
            case 2: context.go('/settings');
          }
        },
      ),
    );
  }
}