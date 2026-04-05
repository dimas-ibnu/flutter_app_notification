import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'firebase_options.dart';
import 'fullscreen_alert_page.dart';
import 'notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await NotificationService.instance.initialize();
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Firebase Notifications',
      navigatorKey: NotificationService.instance.navigatorKey,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepOrange),
        useMaterial3: true,
      ),
      routes: {
        FullScreenAlertPage.routeName: (_) => const FullScreenAlertPage(),
      },
      home: const NotificationHomePage(),
    );
  }
}

class NotificationHomePage extends StatefulWidget {
  const NotificationHomePage({super.key});

  @override
  State<NotificationHomePage> createState() => _NotificationHomePageState();
}

class _NotificationHomePageState extends State<NotificationHomePage>
    with WidgetsBindingObserver {
  final List<_NotificationItem> _messages = [];
  String? _fcmToken;
  bool _notificationPermissionGranted = false;
  bool _fullScreenPermissionGranted = false;
  bool _batteryOptimizationExempted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadToken();
    _refreshPermissions();

    // Listen for foreground messages
    NotificationService.instance.foregroundMessages.listen((message) {
      setState(() {
        _messages.insert(
          0,
          _NotificationItem(
            title: message.notification?.title ?? '(no title)',
            body: message.notification?.body ?? '(no body)',
            state: 'Foreground',
          ),
        );
      });
    });

    // Listen for taps (background / terminated)
    NotificationService.instance.notificationOpened.listen((message) {
      setState(() {
        _messages.insert(
          0,
          _NotificationItem(
            title: message.notification?.title ?? '(no title)',
            body: message.notification?.body ?? '(no body)',
            state: 'Opened from notification',
          ),
        );
      });
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Re-check permissions each time the app comes back to the foreground
  // (covers the case where the user grants permission in Settings and returns).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Small delay: Android may not have committed the permission change by
      // the time the resumed callback fires.
      Future.delayed(const Duration(milliseconds: 300), _refreshPermissions);
    }
  }

  Future<void> _loadToken() async {
    try {
      final token = await NotificationService.instance.getToken();
      setState(() => _fcmToken = token);
    } catch (e) {
      setState(() => _fcmToken = 'Unavailable — check internet / Play Services');
    }
  }

  Future<void> _refreshPermissions() async {
    // Re-query the native side so we always reflect the real system state.
    await NotificationService.instance.refreshFullScreenIntentPermission();
    await NotificationService.instance.refreshBatteryOptimization();
    if (!mounted) return;
    setState(() {
      _notificationPermissionGranted =
          NotificationService.instance.notificationPermissionGranted;
      _fullScreenPermissionGranted =
          NotificationService.instance.canUseFullScreenIntent;
      _batteryOptimizationExempted =
          NotificationService.instance.batteryOptimizationExempted;
    });
  }

  Future<void> _requestNotificationPermission() async {
    // If already granted, go straight to settings so the user can manage
    // channels. Otherwise trigger the system dialog (falls back to settings
    // if permanently denied).
    if (_notificationPermissionGranted) {
      await NotificationService.instance.openNotificationSettings();
    } else {
      await NotificationService.instance.requestNotificationPermission();
    }
    await _refreshPermissions();
  }

  Future<void> _requestFullScreenPermission() async {
    await NotificationService.instance.requestFullScreenIntentPermission();
    // Don't refresh here — the user is leaving to Settings now.
    // The refresh happens automatically when they return via didChangeAppLifecycleState.
  }

  Future<void> _requestBatteryOptimization() async {
    if (_batteryOptimizationExempted) return;
    await NotificationService.instance.requestIgnoreBatteryOptimizations();
    // Refresh happens on resume via didChangeAppLifecycleState.
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Firebase Notifications'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            tooltip: 'Test fullscreen notification',
            icon: const Icon(Icons.fullscreen),
            onPressed: () {
              NotificationService.instance.showFullScreenNotification(
                id: 1,
                title: 'Test Alert',
                body: 'This is a fullscreen intent notification',
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          _TokenCard(token: _fcmToken),
          _PermissionsCard(
            notificationGranted: _notificationPermissionGranted,
            fullScreenGranted: _fullScreenPermissionGranted,
            batteryOptimizationExempted: _batteryOptimizationExempted,
            onRequestNotification: _requestNotificationPermission,
            onRequestFullScreen: _requestFullScreenPermission,
            onRequestBatteryOptimization: _requestBatteryOptimization,
          ),
          const Divider(height: 1),
          Expanded(
            child: _messages.isEmpty
                ? const Center(
                    child: Text(
                      'No notifications yet.\nSend one from Firebase Console.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.separated(
                    itemCount: _messages.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = _messages[index];
                      return ListTile(
                        leading: const Icon(Icons.notifications),
                        title: Text(item.title),
                        subtitle: Text(item.body),
                        trailing: Chip(
                          label: Text(
                            item.state,
                            style: const TextStyle(fontSize: 10),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _PermissionsCard extends StatelessWidget {
  const _PermissionsCard({
    required this.notificationGranted,
    required this.fullScreenGranted,
    required this.batteryOptimizationExempted,
    required this.onRequestNotification,
    required this.onRequestFullScreen,
    required this.onRequestBatteryOptimization,
  });

  final bool notificationGranted;
  final bool fullScreenGranted;
  final bool batteryOptimizationExempted;
  final VoidCallback onRequestNotification;
  final VoidCallback onRequestFullScreen;
  final VoidCallback onRequestBatteryOptimization;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Permissions',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          _PermissionRow(
            icon: Icons.notifications,
            label: 'Notification Permission',
            granted: notificationGranted,
            onRequest: onRequestNotification,
          ),
          const SizedBox(height: 6),
          _PermissionRow(
            icon: Icons.fullscreen,
            label: 'Full-Screen Intent (Android 14+)',
            sublabel: 'Play Store auto-revokes for non-call/alarm apps',
            granted: fullScreenGranted,
            onRequest: onRequestFullScreen,
          ),
          const SizedBox(height: 6),
          _PermissionRow(
            icon: Icons.battery_saver,
            label: 'Battery Optimization (No restrictions)',
            granted: batteryOptimizationExempted,
            onRequest: onRequestBatteryOptimization,
          ),
        ],
      ),
    );
  }
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({
    required this.icon,
    required this.label,
    this.sublabel,
    required this.granted,
    required this.onRequest,
  });

  final IconData icon;
  final String label;
  final String? sublabel;
  final bool granted;
  final VoidCallback onRequest;

  @override
  Widget build(BuildContext context) {
    final color = granted ? Colors.green : Colors.orange;
    return Row(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 13)),
              if (sublabel != null)
                Text(
                  sublabel!,
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                ),
            ],
          ),
        ),
        granted
            ? const Chip(
                label: Text('Granted', style: TextStyle(fontSize: 11)),
                backgroundColor: Color(0xFFE8F5E9),
                side: BorderSide.none,
                padding: EdgeInsets.zero,
              )
            : FilledButton.tonal(
                onPressed: onRequest,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Grant', style: TextStyle(fontSize: 12)),
              ),
      ],
    );
  }
}

class _TokenCard extends StatelessWidget {
  const _TokenCard({required this.token});
  final String? token;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'FCM Device Token',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          SelectableText(
            token ?? 'Loading…',
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),

          TextButton.icon(
            onPressed: () {
              if (token != null) {
                Clipboard.setData(ClipboardData(text: token ?? ''));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Token copied to clipboard')),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Token not available yet')),
                );
              }
            },
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copy', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

class _NotificationItem {
  const _NotificationItem({
    required this.title,
    required this.body,
    required this.state,
  });
  final String title;
  final String body;
  final String state;
}
