import 'package:flutter/material.dart';

import '../core/logic.dart';

class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.label,
    required this.value,
    this.small = false,
    this.valueColor,
  });

  final String label;
  final String value;
  final bool small;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final style = (small ? text.titleMedium : text.headlineSmall)?.copyWith(
      color: valueColor,
    );
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: text.bodySmall),
            const SizedBox(height: 4),
            Text(value, style: style),
          ],
        ),
      ),
    );
  }
}

class InfoCard extends StatelessWidget {
  const InfoCard(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
    ),
  );
}

class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      border: Border.all(color: color),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      text,
      style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
    ),
  );
}

Future<bool> confirm(
  BuildContext context,
  String question, {
  String action = 'Löschen',
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      content: Text(question),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(action),
        ),
      ],
    ),
  );
  return result ?? false;
}

Future<void> openPage(BuildContext context, Widget page) =>
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => page, fullscreenDialog: true),
    );

Widget dropdown<T>({
  required String label,
  required T value,
  required Map<T, String> options,
  required ValueChanged<T> onChanged,
}) => DropdownButtonFormField<T>(
  initialValue: value,
  isExpanded: true,
  decoration: InputDecoration(labelText: label),
  items: [
    for (final option in options.entries)
      DropdownMenuItem<T>(
        value: option.key,
        child: Text(option.value, overflow: TextOverflow.ellipsis),
      ),
  ],
  onChanged: (selected) {
    if (selected != null) onChanged(selected);
  },
);

class NumField extends StatelessWidget {
  const NumField({
    super.key,
    required this.controller,
    required this.label,
    this.onChanged,
    this.errorText,
  });

  final TextEditingController controller;
  final String label;
  final ValueChanged<String>? onChanged;
  final String? errorText;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    onChanged: onChanged,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    decoration: InputDecoration(labelText: label, errorText: errorText),
  );
}

class DateField extends StatelessWidget {
  const DateField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;

  /// `JJJJ-MM-TT` oder leer
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () async {
      final current = tryParseYmd(value);
      final now = DateTime.now();
      final picked = await showDatePicker(
        context: context,
        initialDate: current == null
            ? DateTime(now.year, now.month, now.day)
            : DateTime(current.year, current.month, current.day),
        firstDate: DateTime(2015),
        lastDate: DateTime(2100),
      );
      if (picked != null) onChanged(ymd(picked));
    },
    child: InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: const Icon(Icons.calendar_today),
      ),
      child: Text(value.isEmpty ? 'Nicht gesetzt' : deDate(value)),
    ),
  );
}

class TimeField extends StatelessWidget {
  const TimeField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.clearable = false,
  });

  final String label;

  /// `HH:MM` oder leer
  final String value;
  final ValueChanged<String> onChanged;
  final bool clearable;

  @override
  Widget build(BuildContext context) {
    final parts = value.split(':');
    final initial = parts.length == 2
        ? TimeOfDay(hour: toInt(parts[0]) % 24, minute: toInt(parts[1]) % 60)
        : TimeOfDay.now();
    return InkWell(
      onTap: () async {
        final picked = await showTimePicker(
          context: context,
          initialTime: initial,
        );
        if (picked != null) {
          final hour = picked.hour.toString().padLeft(2, '0');
          final minute = picked.minute.toString().padLeft(2, '0');
          onChanged('$hour:$minute');
        }
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: clearable && value.isNotEmpty
              ? IconButton(
                  tooltip: 'Uhrzeit entfernen',
                  onPressed: () => onChanged(''),
                  icon: const Icon(Icons.clear),
                )
              : const Icon(Icons.schedule),
        ),
        child: Text(value.isEmpty ? 'Keine Uhrzeit' : '$value Uhr'),
      ),
    );
  }
}

class EditorScaffold extends StatelessWidget {
  const EditorScaffold({
    super.key,
    required this.title,
    required this.onSave,
    required this.children,
    this.error,
  });

  final String title;
  final VoidCallback onSave;
  final List<Widget> children;
  final String? error;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(title),
      actions: [
        TextButton(onPressed: onSave, child: const Text('Speichern')),
      ],
    ),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final child in children)
            Padding(padding: const EdgeInsets.only(bottom: 14), child: child),
          if (error != null)
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    ),
  );
}
