import 'package:flutter/material.dart';

import '../models/monitor_status.dart';
import '../services/monitor_controller.dart';
import '../widgets/monitor_item_card.dart';
import 'detail_screen.dart';

class MonitorScreen extends StatefulWidget {
  final MonitorController controller;

  const MonitorScreen({super.key, required this.controller});

  @override
  State<MonitorScreen> createState() => _MonitorScreenState();
}

class _MonitorScreenState extends State<MonitorScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.controller.refresh();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final c = widget.controller;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Monitor'),
            bottom: TabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: 'URLs', icon: Icon(Icons.link)),
                Tab(text: 'DNS', icon: Icon(Icons.dns)),
                Tab(text: 'CRLs', icon: Icon(Icons.security)),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: c.isRefreshing ? null : c.refresh,
                tooltip: 'Refresh',
              ),
            ],
          ),
          body: TabBarView(
            controller: _tabController,
            children: [
              _MonitorTab(
                items: c.urlItems,
                emptyMessage: 'No URLs configured',
                onRefresh: c.refresh,
              ),
              _MonitorTab(
                items: c.dnsItems,
                emptyMessage: 'No DNS hosts configured',
                onRefresh: c.refresh,
              ),
              _MonitorTab(
                items: c.crlItems,
                emptyMessage: 'No CRL URLs configured',
                onRefresh: c.refresh,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MonitorTab extends StatelessWidget {
  final List<MonitorItem> items;
  final String emptyMessage;
  final Future<void> Function() onRefresh;

  const _MonitorTab({
    required this.items,
    required this.emptyMessage,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return _EmptyState(message: emptyMessage);
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.builder(
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          return MonitorItemCard(
            key: ValueKey(item.id),
            item: item,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => DetailScreen(item: item)),
            ),
          );
        },
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String message;

  const _EmptyState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.info_outline,
              size: 64, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 16),
          Text(message),
          const SizedBox(height: 8),
          const Text(
            'Configure items in Settings',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }
}
