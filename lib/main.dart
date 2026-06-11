import 'package:flutter/material.dart';

import 'services/configuration_manager.dart';
import 'services/monitor_controller.dart';
import 'screens/monitor_screen.dart';
import 'screens/settings_screen.dart';
import 'theme/app_theme.dart';
import 'utils/logging.dart';

void main() {
  setupLogging();
  runApp(const MonitorApp());
}

class MonitorApp extends StatefulWidget {
  const MonitorApp({super.key});

  @override
  State<MonitorApp> createState() => _MonitorAppState();
}

class _MonitorAppState extends State<MonitorApp> {
  final MonitorController _controller = MonitorController();
  final ConfigurationManager _configManager = ConfigurationManager();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mobile Monitor',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: Scaffold(
        body: IndexedStack(
          index: _index,
          children: [
            MonitorScreen(controller: _controller),
            SettingsScreen(
              configManager: _configManager,
              onChanged: _controller.refresh,
            ),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.monitor), label: 'Monitor'),
            NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
          ],
        ),
      ),
    );
  }
}
