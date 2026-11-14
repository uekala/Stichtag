import 'package:flutter/material.dart';

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
        const Divider(),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Erinnerungen stellst du in Stichtag in Home Assistant unter Daten ein.\n\n'
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
