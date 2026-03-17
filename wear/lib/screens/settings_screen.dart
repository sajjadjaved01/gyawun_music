import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../services/watch_sync_service.dart';

// ---------------------------------------------------------------------------
// SettingsScreen
// Shows storage usage, phone connection status, and manual sync trigger.
// ---------------------------------------------------------------------------
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  WatchSyncService get _sync => GetIt.I<WatchSyncService>();

  int _storageUsedBytes = 0;
  bool _isSyncing = false;

  static const String _appVersion = '1.0.0';

  @override
  void initState() {
    super.initState();
    _refreshStorage();
  }

  Future<void> _refreshStorage() async {
    final bytes = await _sync.computeStorageUsedBytes();
    if (mounted) setState(() => _storageUsedBytes = bytes);
  }

  Future<void> _syncNow() async {
    setState(() => _isSyncing = true);
    await _sync.requestLibrarySync();
    // Give the phone a moment to respond, then refresh storage.
    await Future<void>.delayed(const Duration(seconds: 2));
    await _refreshStorage();
    if (mounted) setState(() => _isSyncing = false);
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  @override
  Widget build(BuildContext context) {
    final isConnected = _sync.phoneConnected;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Section: Connection
          _SectionLabel(label: 'Phone'),
          _SettingsTile(
            icon: isConnected
                ? Icons.bluetooth_connected_rounded
                : Icons.bluetooth_disabled_rounded,
            iconColor: isConnected
                ? const Color(0xFF1DB954)
                : const Color(0xFF888888),
            title: 'Status',
            value: isConnected ? 'Connected' : 'Not connected',
          ),
          const SizedBox(height: 10),

          // Section: Storage
          _SectionLabel(label: 'Storage'),
          _SettingsTile(
            icon: Icons.storage_rounded,
            iconColor: const Color(0xFF5C6BC0),
            title: 'Used',
            value: _formatBytes(_storageUsedBytes),
          ),
          const SizedBox(height: 10),

          // Section: Sync
          _SectionLabel(label: 'Sync'),
          _SyncButton(isSyncing: _isSyncing, onTap: _isSyncing ? null : _syncNow),
          const SizedBox(height: 10),

          // Section: About
          _SectionLabel(label: 'About'),
          _SettingsTile(
            icon: Icons.info_outline_rounded,
            iconColor: const Color(0xFF888888),
            title: 'Version',
            value: _appVersion,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Supporting widgets
// ---------------------------------------------------------------------------
class _SectionLabel extends StatelessWidget {
  final String label;

  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 4),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          color: Color(0xFF555555),
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String value;

  const _SettingsTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
          Text(
            value,
            style: const TextStyle(color: Color(0xFF888888), fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _SyncButton extends StatelessWidget {
  final bool isSyncing;
  final VoidCallback? onTap;

  const _SyncButton({required this.isSyncing, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSyncing
              ? const Color(0xFF1E1E1E)
              : const Color(0xFF1DB954).withAlpha(30),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSyncing
                ? const Color(0xFF333333)
                : const Color(0xFF1DB954),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isSyncing) ...[
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: Color(0xFF1DB954),
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'Syncing...',
                style: TextStyle(color: Color(0xFF888888), fontSize: 12),
              ),
            ] else ...[
              const Icon(Icons.sync_rounded,
                  color: Color(0xFF1DB954), size: 16),
              const SizedBox(width: 8),
              const Text(
                'Sync now',
                style: TextStyle(
                  color: Color(0xFF1DB954),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
