import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../core/api.dart';
import '../core/app_store.dart';
import '../core/pairing_payload.dart';
import 'app_logo.dart';

/// Erster Bildschirm: das Handy mit dem eigenen Stichtag-Server koppeln.
class PairingPage extends StatefulWidget {
  const PairingPage({super.key, required this.store});

  final AppStore store;

  @override
  State<PairingPage> createState() => _PairingPageState();
}

class _PairingPageState extends State<PairingPage> {
  final _deviceName = TextEditingController(text: 'Mein Handy');
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _deviceName.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    final raw = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(builder: (_) => const PairingScannerPage()),
    );
    if (raw != null) await _pair(raw);
  }

  Future<void> _pair(String raw) async {
    final PairingPayload payload;
    try {
      payload = PairingPayload.fromRawValue(raw);
    } on FormatException catch (e) {
      setState(() => _error = e.message.toString());
      return;
    }
    final name = _deviceName.text.trim();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.store.pair(payload, name.isEmpty ? 'Handy' : name);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 24),
            const Align(
              alignment: Alignment.centerLeft,
              child: AppLogo(size: 64),
            ),
            const SizedBox(height: 16),
            Text('Stichtag', style: theme.textTheme.headlineMedium),
            const SizedBox(height: 8),
            Text(
              'Öffne Stichtag in Home Assistant, gehe auf Daten und wähle dort „Handy koppeln“. Scanne dann den angezeigten QR-Code.',
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _deviceName,
              decoration: const InputDecoration(
                labelText: 'Name dieses Handys',
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy ? null : _scan,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('QR-Code scannen'),
            ),
            const SizedBox(height: 32),
            Text('Ohne Kamera', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            TextField(
              controller: _code,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: 'Kopplungscode einfügen',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _busy ? null : () => _pair(_code.text),
              child: const Text('Mit Code koppeln'),
            ),
            if (_busy) ...[
              const SizedBox(height: 24),
              const Center(child: CircularProgressIndicator()),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
          ],
        ),
      ),
    );
  }
}

class PairingScannerPage extends StatefulWidget {
  const PairingScannerPage({super.key});

  @override
  State<PairingScannerPage> createState() => _PairingScannerPageState();
}

class _PairingScannerPageState extends State<PairingScannerPage> {
  late final MobileScannerController _controller;
  bool _handled = false;
  String? _scanError;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      formats: const [BarcodeFormat.qrCode],
    );
  }

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null || raw.isEmpty) continue;
      try {
        PairingPayload.fromRawValue(raw);
        _handled = true;
        Navigator.of(context).pop(raw);
      } on FormatException catch (e) {
        if (mounted && _scanError != e.message) {
          setState(() => _scanError = e.message.toString());
        }
      }
      return;
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('QR-Code scannen')),
    backgroundColor: Colors.black,
    body: Stack(
      fit: StackFit.expand,
      children: [
        MobileScanner(
          controller: _controller,
          onDetect: _onDetect,
          errorBuilder: (context, error) => const ColoredBox(
            color: Colors.black,
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Die Kamera konnte nicht gestartet werden. Erlaube den Kamerazugriff in den App-Einstellungen oder füge den Kopplungscode als Text ein.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 20,
          right: 20,
          bottom: 28,
          child: SafeArea(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                _scanError ??
                    'Richte die Kamera auf den QR-Code unter Daten → Handy-App.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
