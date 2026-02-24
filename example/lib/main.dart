import 'dart:async';

import 'package:flutter/material.dart';
import 'package:screen_brightness_monitor/screen_brightness_monitor.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Screen Brightness Monitor',
      theme: ThemeData(
        colorSchemeSeed: Colors.amber,
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.amber,
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      home: const BrightnessPage(),
    );
  }
}

class BrightnessPage extends StatefulWidget {
  const BrightnessPage({super.key});

  @override
  State<BrightnessPage> createState() => _BrightnessPageState();
}

class _BrightnessPageState extends State<BrightnessPage> {
  BrightnessMonitor? _monitor;
  StreamSubscription<int>? _subscription;

  int _brightness = -1;
  bool _observing = false;
  final List<_BrightnessEntry> _history = [];

  @override
  void initState() {
    super.initState();
    _initMonitor();
  }

  void _initMonitor() {
    _monitor = BrightnessMonitor();
    _refreshBrightness();
  }

  void _refreshBrightness() {
    final value = _monitor?.brightness ?? -1;
    setState(() {
      _brightness = value;
    });
  }

  void _toggleObserving() {
    if (_observing) {
      _subscription?.cancel();
      _subscription = null;
      setState(() => _observing = false);
    } else {
      _subscription = _monitor?.onBrightnessChanged.listen((value) {
        setState(() {
          _brightness = value;
          _history.insert(0, _BrightnessEntry(value, DateTime.now()));
          // Keep last 50 entries
          if (_history.length > 50) _history.removeLast();
        });
      });
      setState(() => _observing = true);
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _monitor?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fraction = _brightness.clamp(0, 255) / 255.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Brightness Monitor'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Read current brightness',
            onPressed: _refreshBrightness,
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Brightness display card ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Icon(
                      _brightnessIcon(fraction),
                      size: 64,
                      color: Color.lerp(
                        theme.colorScheme.outline,
                        theme.colorScheme.primary,
                        fraction,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '$_brightness',
                      style: theme.textTheme.displayMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _brightness < 0
                          ? 'Unable to read brightness'
                          : '${(fraction * 100).round()}% brightness',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Progress indicator
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: fraction,
                        minHeight: 12,
                        backgroundColor:
                            theme.colorScheme.surfaceContainerHighest,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Observe toggle ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: FilledButton.icon(
              onPressed: _toggleObserving,
              icon: Icon(_observing ? Icons.stop : Icons.play_arrow),
              label: Text(_observing ? 'Stop observing' : 'Start observing'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                backgroundColor: _observing
                    ? theme.colorScheme.error
                    : theme.colorScheme.primary,
              ),
            ),
          ),

          const SizedBox(height: 8),

          // ── History list ──
          if (_history.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  Text(
                    'Change history',
                    style: theme.textTheme.titleSmall,
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => setState(() => _history.clear()),
                    child: const Text('Clear'),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _history.isEmpty
                ? Center(
                    child: Text(
                      _observing
                          ? 'Waiting for brightness changes…'
                          : 'Tap "Start observing" to track changes',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _history.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final entry = _history[index];
                      final entryFraction =
                          entry.brightness.clamp(0, 255) / 255.0;
                      return ListTile(
                        leading: Icon(
                          _brightnessIcon(entryFraction),
                          color: Color.lerp(
                            theme.colorScheme.outline,
                            theme.colorScheme.primary,
                            entryFraction,
                          ),
                        ),
                        title: Text(
                          '${entry.brightness}  (${(entryFraction * 100).round()}%)',
                        ),
                        subtitle: Text(_formatTime(entry.timestamp)),
                        dense: true,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  IconData _brightnessIcon(double fraction) {
    if (fraction < 0.15) return Icons.brightness_low;
    if (fraction < 0.6) return Icons.brightness_medium;
    return Icons.brightness_high;
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}:'
        '${dt.second.toString().padLeft(2, '0')}.'
        '${dt.millisecond.toString().padLeft(3, '0')}';
  }
}

class _BrightnessEntry {
  final int brightness;
  final DateTime timestamp;

  _BrightnessEntry(this.brightness, this.timestamp);
}
