import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../core/app_lock.dart';
import '../core/app_store.dart';
import '../core/logic.dart';
import 'vials_page.dart';
import 'widgets.dart';

const appVersion = String.fromEnvironment(
  'STICHTAG_VERSION',
  defaultValue: 'Entwicklung',
);

class MorePage extends StatelessWidget {
  const MorePage({super.key, required this.store, required this.appLock});

  final AppStore store;
  final AppLock appLock;

  /// Bearbeitet eine Liste mit einem Eintrag pro Zeile.
  Future<void> _editList(
    BuildContext context, {
    required String title,
    required String key,
    required List<String> current,
    required String hint,
  }) async {
    final controller = TextEditingController(text: current.join('\n'));
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          minLines: 5,
          maxLines: 10,
          decoration: InputDecoration(helperText: hint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Speichern'),
          ),
        ],
      ),
    );
    final lines = controller.text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toSet()
        .toList();
    if (saved == true) {
      store.change((state) => state[key] = lines);
    }
  }

  void _say(BuildContext context, String text) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  /// Übergibt die Sicherung als Datei an das Teilen-Menü des Handys.
  Future<void> _export(BuildContext context) async {
    final name = 'stichtag-${todayYmd()}.json';
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              utf8.encode(store.exportJson()),
              mimeType: 'application/json',
              name: name,
            ),
          ],
          fileNameOverrides: [name],
        ),
      );
    } on Object {
      if (context.mounted) _say(context, 'Der Export hat nicht geklappt.');
    }
  }

  Future<void> _import(BuildContext context) async {
    final String text;
    try {
      final file = await openFile();
      if (file == null) return;
      text = await file.readAsString();
    } on Object {
      if (context.mounted) _say(context, 'Die Datei ließ sich nicht lesen.');
      return;
    }
    if (!context.mounted) return;
    final ok = await confirm(
      context,
      'Sicherung einspielen? Sie ersetzt alle Einträge, Protokolle, Vials und Körperwerte.',
      action: 'Ersetzen',
    );
    if (!ok) return;
    try {
      store.importJson(text);
      if (context.mounted) _say(context, 'Sicherung eingespielt.');
    } on FormatException catch (e) {
      if (context.mounted) _say(context, e.message.toString());
    }
  }

  Future<void> _leaveLocal(BuildContext context) async {
    final ok = await confirm(
      context,
      'Zum Koppeln mit einem Server wechseln? Die Daten bleiben auf diesem Handy liegen. Exportiere sie vorher, wenn du sie auf den Server übernehmen willst, und spiele sie nach dem Koppeln ein.',
      action: 'Wechseln',
    );
    if (ok) await store.leaveLocal();
  }

  Future<void> _erase(BuildContext context) async {
    final ok = await confirm(
      context,
      'Alle Daten auf diesem Handy löschen? Ohne Sicherung lässt sich das nicht rückgängig machen.',
    );
    if (ok) await store.eraseLocal();
  }

  Future<void> _unpair(BuildContext context) async {
    final ok = await confirm(
      context,
      'Kopplung aufheben? Die Daten bleiben auf dem Server, dieses Handy braucht danach einen neuen Kopplungscode.',
      action: 'Entkoppeln',
    );
    if (ok) await store.unpair();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = store.session;
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        ListTile(
          leading: const Icon(Icons.science_outlined),
          title: const Text('Vials & Misch-Rechner'),
          trailing: const Icon(Icons.chevron_right),
          enabled: store.loadedOnce,
          onTap: () => Navigator.of(context).push<void>(
            MaterialPageRoute<void>(builder: (_) => VialsPage(store: store)),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.pin_drop_outlined),
          title: const Text('Injektionsstellen'),
          subtitle: Text('${sitesOf(store.state).length} Stellen in Rotation'),
          enabled: store.loadedOnce,
          onTap: () => _editList(
            context,
            title: 'Injektionsstellen',
            key: 'sites',
            current: sitesOf(store.state),
            hint: 'Eine Stelle pro Zeile',
          ),
        ),
        ListTile(
          leading: const Icon(Icons.sick_outlined),
          title: const Text('Nebenwirkungen'),
          subtitle: Text('${tagsOf(store.state).length} zum Ankreuzen'),
          enabled: store.loadedOnce,
          onTap: () => _editList(
            context,
            title: 'Nebenwirkungen',
            key: 'tags',
            current: tagsOf(store.state),
            hint: 'Eine pro Zeile',
          ),
        ),
        const Divider(),
        _LockTile(lock: appLock),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.upload_file_outlined),
          title: const Text('Daten exportieren'),
          subtitle: const Text('Sicherung als Datei speichern oder teilen'),
          enabled: store.loadedOnce,
          onTap: () => _export(context),
        ),
        ListTile(
          leading: const Icon(Icons.download_outlined),
          title: const Text('Daten importieren'),
          subtitle: const Text('Eine Sicherung einspielen'),
          enabled: store.loadedOnce,
          onTap: () => _import(context),
        ),
        const Divider(),
        if (store.isLocal) ...[
          const ListTile(
            leading: Icon(Icons.phone_android),
            title: Text('Speicherort'),
            subtitle: Text('Nur auf diesem Handy, ohne Server'),
          ),
          ListTile(
            leading: const Icon(Icons.dns_outlined),
            title: const Text('Mit einem Stichtag-Server koppeln'),
            onTap: () => _leaveLocal(context),
          ),
          ListTile(
            leading: Icon(Icons.delete_forever, color: theme.colorScheme.error),
            title: const Text('Alle Daten auf diesem Handy löschen'),
            onTap: () => _erase(context),
          ),
        ] else ...[
          ListTile(
            leading: const Icon(Icons.dns_outlined),
            title: const Text('Server'),
            subtitle: Text(session?.serverUrl ?? ''),
          ),
          ListTile(
            leading: const Icon(Icons.smartphone),
            title: const Text('Dieses Handy'),
            subtitle: Text(session?.deviceName ?? ''),
          ),
          ListTile(
            leading: Icon(Icons.link_off, color: theme.colorScheme.error),
            title: const Text('Kopplung aufheben'),
            onTap: () => _unpair(context),
          ),
        ],
        const Divider(),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            '${store.isLocal ? 'Ohne Server gibt es noch keine Erinnerungen.' : 'Erinnerungen stellst du in Stichtag in Home Assistant unter Daten ein.'}\n\n'
            'Stichtag ist ein Protokoll und ein Rechenhilfsmittel. Die App empfiehlt keine Substanzen, Dosen oder Zyklen und ersetzt keine ärztliche Beratung.\n\n'
            'Version $appVersion',
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

/// Schalter für die App-Sperre. Einschalten verlangt einmal das Entsperren,
/// damit sich niemand mit einer nicht funktionierenden Sperre aussperrt.
class _LockTile extends StatefulWidget {
  const _LockTile({required this.lock});

  final AppLock lock;

  @override
  State<_LockTile> createState() => _LockTileState();
}

class _LockTileState extends State<_LockTile> {
  bool? _enabled;
  bool _supported = false;
  String? _hint;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final enabled = await widget.lock.enabled;
    final supported = await widget.lock.supported;
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _supported = supported;
    });
  }

  Future<void> _toggle(bool value) async {
    if (value) {
      final ok = await widget.lock.unlock('App-Sperre einschalten');
      if (!ok) {
        if (mounted) {
          setState(() => _hint = 'Die Sperre wurde nicht eingeschaltet.');
        }
        return;
      }
    }
    try {
      await widget.lock.setEnabled(value);
    } on Object {
      if (mounted) {
        setState(() => _hint = 'Die Einstellung ließ sich nicht speichern.');
      }
      return;
    }
    if (mounted) {
      setState(() {
        _enabled = value;
        _hint = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _enabled;
    final subtitle =
        _hint ??
        (enabled == null
            ? ''
            : _supported
            ? 'Fingerabdruck, Gesicht oder Geräte-PIN beim Öffnen'
            : 'Dafür braucht das Handy eine Bildschirmsperre');
    return SwitchListTile(
      secondary: const Icon(Icons.lock_outline),
      title: const Text('App-Sperre'),
      subtitle: Text(subtitle),
      value: enabled ?? false,
      onChanged: enabled == null || !_supported ? null : _toggle,
    );
  }
}
