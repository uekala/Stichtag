import 'package:flutter/material.dart';

import '../core/app_store.dart';
import '../core/logic.dart';
import 'vials_page.dart';
import 'widgets.dart';

const appVersion = String.fromEnvironment(
  'STICHTAG_VERSION',
  defaultValue: 'Entwicklung',
);

class MorePage extends StatelessWidget {
  const MorePage({super.key, required this.store});

  final AppStore store;

  Future<void> _editSites(BuildContext context) async {
    final controller = TextEditingController(
      text: sitesOf(store.state).join('\n'),
    );
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Injektionsstellen'),
        content: TextField(
          controller: controller,
          minLines: 5,
          maxLines: 10,
          decoration: const InputDecoration(
            helperText: 'Eine Stelle pro Zeile',
          ),
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
      store.change((state) => state['sites'] = lines);
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
          onTap: () => _editSites(context),
        ),
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
