import 'package:flutter/material.dart';

class FullScreenAlertPage extends StatelessWidget {
  const FullScreenAlertPage({
    super.key,
    this.title = 'Alert',
    this.body = '',
  });

  final String title;
  final String body;

  static const routeName = '/fullscreen-alert';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // ── Header ────────────────────────────────────────────────
              Column(
                children: [
                  const Icon(
                    Icons.notifications_active,
                    size: 72,
                    color: Colors.white,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (body.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      body,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 16,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),

              // ── OK button ─────────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.deepOrange,
                    shape: const StadiumBorder(),
                  ),
                  onPressed: () {
                    debugPrint('pressed ok from the fullscreen notification');
                    // Pop back to the main app (or replace if launched fresh).
                    if (Navigator.of(context).canPop()) {
                      Navigator.of(context).pop();
                    } else {
                      Navigator.of(context).pushReplacementNamed('/');
                    }
                  },
                  child: const Text(
                    'OK',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
