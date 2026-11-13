import 'package:flutter/material.dart';

import '../core/app_store.dart';
import '../core/logic.dart';
import 'editors.dart';
import 'widgets.dart';

class VialsPage extends StatelessWidget {
  const VialsPage({super.key, required this.store});

  final AppStore store;

  Future<void> _delete(BuildContext context, String id) async {
    final ok = await confirm(context, 'Dieses Vial löschen?');
    if (!ok) return;
    store.change(
      (state) => items(state, 'vials').removeWhere((v) => v['id'] == id),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Vials & Rechner')),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () => openPage(context, VialEditor(store: store)),
      icon: const Icon(Icons.add),
      label: const Text('Vial'),
    ),
    body: ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final theme = Theme.of(context);
        final colors = theme.colorScheme;
        final vials = items(store.state, 'vials');
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            if (vials.isEmpty) const InfoCard('Noch kein Vial angelegt.'),
            for (final vial in vials)
              _VialCard(
                vial: vial,
                level: vialLevel(store.state, vial),
                onEdit: () => openPage(
                  context,
                  VialEditor(store: store, existing: vial),
                ),
                onDelete: () => _delete(context, str(vial['id'])),
              ),
            const SizedBox(height: 4),
            Text(
              'Der Vorrat sinkt mit jedem Eintrag, dem du das Vial zuordnest (nur mcg und mg).',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            Text('Misch-Rechner', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            const MixCalculator(),
          ],
        );
      },
    ),
  );
}

class _VialCard extends StatelessWidget {
  const _VialCard({
    required this.vial,
    required this.level,
    required this.onEdit,
    required this.onDelete,
  });

  final Json vial;
  final VialLevel level;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final low = level.fraction < 0.2;
    final empty = level.leftMcg <= 0;
    final mg = toDouble(vial['mg']);
    final ml = toDouble(vial['ml']);
    final mixed = str(vial['mixed']);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    str(vial['name']),
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                Pill(
                  empty
                      ? 'Leer'
                      : low
                      ? 'Fast leer'
                      : 'Vorrat ok',
                  color: empty
                      ? colors.error
                      : low
                      ? colors.tertiary
                      : colors.primary,
                ),
              ],
            ),
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: level.fraction.clamp(0.0, 1.0).toDouble(),
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
              color: low ? colors.tertiary : colors.primary,
            ),
            const SizedBox(height: 8),
            Text(
              '${fmtNum(level.leftMcg / 1000, 3)} von ${fmtNum(mg, 3)} mg übrig',
            ),
            Text(
              [
                if (ml > 0)
                  '${fmtNum(ml)} ml Wasser · ${fmtNum(mg * 1000 / ml, 0)} mcg/ml'
                else
                  'nicht angemischt',
                if (mixed.isNotEmpty) 'angemischt ${deDate(mixed)}',
              ].join(' · '),
              style: theme.textTheme.bodySmall,
            ),
            Wrap(
              alignment: WrapAlignment.end,
              children: [
                TextButton(onPressed: onEdit, child: const Text('Bearbeiten')),
                TextButton(
                  onPressed: onDelete,
                  child: Text('Löschen', style: TextStyle(color: colors.error)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Rechnet nur mit den eingegebenen Werten und schlägt keine Dosis vor.
class MixCalculator extends StatefulWidget {
  const MixCalculator({super.key});

  @override
  State<MixCalculator> createState() => _MixCalculatorState();
}

class _MixCalculatorState extends State<MixCalculator> {
  final _mg = TextEditingController(text: '5');
  final _ml = TextEditingController(text: '2');
  final _dose = TextEditingController(text: '250');
  String _unit = 'mcg';

  @override
  void dispose() {
    _mg.dispose();
    _ml.dispose();
    _dose.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mg = toDouble(_mg.text);
    final dose = toDouble(_dose.text) * (_unit == 'mg' ? 1000 : 1);
    final result = calcMix(
      vialMg: mg,
      waterMl: toDouble(_ml.text),
      doseMcg: dose,
    );
    String hint = '';
    if (result == null) {
      hint = 'Bitte drei Werte größer als 0 eingeben.';
    } else if (dose > mg * 1000) {
      hint = 'Die Dosis ist größer als der Inhalt des Vials.';
    } else if (result.units > 100) {
      hint =
          'Das sind mehr als 100 Einheiten, also mehr als eine 1-ml-Spritze fasst.';
    } else if (result.units < 2) {
      hint =
          'Unter 2 Einheiten lässt sich kaum genau aufziehen. Mit mehr Wasser wird das Volumen größer.';
    }
    void update(String _) => setState(() {});
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: NumField(
                    controller: _mg,
                    label: 'Peptid im Vial (mg)',
                    onChanged: update,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: NumField(
                    controller: _ml,
                    label: 'Wasser (ml)',
                    onChanged: update,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: NumField(
                    controller: _dose,
                    label: 'Gewünschte Dosis',
                    onChanged: update,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: dropdown<String>(
                    label: 'Einheit',
                    value: _unit,
                    options: const <String, String>{'mcg': 'mcg', 'mg': 'mg'},
                    onChanged: (value) => setState(() => _unit = value),
                  ),
                ),
              ],
            ),
            if (result != null) ...[
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: StatCard(
                      label: 'Aufziehen',
                      value: '${fmtNum(result.units, 1)} E',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: StatCard(
                      label: 'Volumen',
                      value: '${fmtNum(result.volumeMl, 3)} ml',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'Konzentration ${fmtNum(result.concentration, 0)} mcg/ml · ${fmtNum(result.dosesPerVial, 1)} Dosen pro Vial',
              ),
            ],
            if (hint.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(hint, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 8),
            Text(
              'Einheiten gelten für eine U-100-Insulinspritze (100 Einheiten = 1 ml). Der Rechner rechnet nur mit deinen Werten und schlägt keine Dosis vor.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
