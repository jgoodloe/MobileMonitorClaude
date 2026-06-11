import 'package:flutter/material.dart';

import '../services/configuration_manager.dart';

class SettingsScreen extends StatefulWidget {
  final ConfigurationManager configManager;
  final VoidCallback onChanged;

  const SettingsScreen({
    super.key,
    required this.configManager,
    required this.onChanged,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  List<String> _urls = [];
  List<String> _dnsHosts = [];
  List<String> _crlUrls = [];
  bool _countRevoked = true;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final config = await widget.configManager.load();
    if (!mounted) return;
    setState(() {
      _urls = List.of(config.urls);
      _dnsHosts = List.of(config.dnsHosts);
      _crlUrls = List.of(config.crlUrls);
      _countRevoked = config.countRevokedCertificates;
      _loading = false;
    });
  }

  Future<void> _addItem(List<String> list, String label,
      Future<void> Function(List<String>) save) async {
    final value = await _promptForValue(label);
    if (value == null || value.trim().isEmpty) return;
    setState(() => list.add(value.trim()));
    await save(list);
    widget.onChanged();
  }

  Future<void> _removeItem(List<String> list, int index,
      Future<void> Function(List<String>) save) async {
    setState(() => list.removeAt(index));
    await save(list);
    widget.onChanged();
  }

  Future<String?> _promptForValue(String label) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Add $label'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: 'Enter $label'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'URLs'),
            Tab(text: 'DNS'),
            Tab(text: 'CRLs'),
            Tab(text: 'Options'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildList(_urls, 'URL', widget.configManager.setUrls),
          _buildList(_dnsHosts, 'DNS host', widget.configManager.setDnsHosts),
          _buildList(_crlUrls, 'CRL URL', widget.configManager.setCrlUrls),
          _buildOptions(),
        ],
      ),
    );
  }

  Widget _buildList(
    List<String> list,
    String label,
    Future<void> Function(List<String>) save,
  ) {
    return Scaffold(
      body: list.isEmpty
          ? Center(child: Text('No ${label}s configured'))
          : ListView.builder(
              itemCount: list.length,
              itemBuilder: (context, index) => ListTile(
                title: Text(list[index]),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _removeItem(list, index, save),
                ),
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addItem(list, label, save),
        icon: const Icon(Icons.add),
        label: Text('Add $label'),
      ),
    );
  }

  Widget _buildOptions() {
    return ListView(
      children: [
        SwitchListTile(
          title: const Text('Count revoked certificates'),
          subtitle: const Text(
              'Parse and count revoked entries in CRLs (slightly slower)'),
          value: _countRevoked,
          onChanged: (value) async {
            setState(() => _countRevoked = value);
            await widget.configManager.setCountRevokedCertificates(value);
            widget.onChanged();
          },
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.restore),
          title: const Text('Reset to defaults'),
          onTap: () async {
            await widget.configManager.resetToDefaults();
            await _load();
            widget.onChanged();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Reset to default targets')),
              );
            }
          },
        ),
      ],
    );
  }
}
