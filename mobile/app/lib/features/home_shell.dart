import 'package:flutter/material.dart';

import '../core/app_store.dart';
import 'body_page.dart';
import 'editors.dart';
import 'history_page.dart';
import 'more_page.dart';
import 'protocols_page.dart';
import 'today_page.dart';
import 'widgets.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.store});

  final AppStore store;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  static const _titles = ['Heute', 'Protokolle', 'Verlauf', 'Körper', 'Mehr'];

  int _index = 0;

  Widget? _fab(BuildContext context) {
    final store = widget.store;
    if (!store.loadedOnce) return null;
    switch (_index) {
      case 0:
        return FloatingActionButton.extended(
          onPressed: () => openPage(context, LogEditor(store: store)),
          icon: const Icon(Icons.add),
          label: const Text('Dosis'),
        );
      case 1:
        return FloatingActionButton.extended(
          onPressed: () => openPage(context, ProtocolEditor(store: store)),
          icon: const Icon(Icons.add),
          label: const Text('Protokoll'),
        );
      case 3:
        return FloatingActionButton.extended(
          onPressed: () => openPage(context, BodyEditor(store: store)),
          icon: const Icon(Icons.add),
          label: const Text('Messung'),
        );
      default:
        return null;
    }
  }

  Widget _page() {
    final store = widget.store;
    switch (_index) {
      case 0:
        return TodayPage(store: store);
      case 1:
        return ProtocolsPage(store: store);
      case 2:
        return HistoryPage(store: store);
      case 3:
        return BodyPage(store: store);
      default:
        return MorePage(store: store);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final colors = Theme.of(context).colorScheme;
    final error = store.error;
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_index]),
        actions: [
          IconButton(
            tooltip: 'Neu laden',
            onPressed: store.loading ? null : store.refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
        bottom: store.loading
            ? const PreferredSize(
                preferredSize: Size.fromHeight(3),
                child: LinearProgressIndicator(),
              )
            : null,
      ),
      body: Column(
        children: [
          if (error != null)
            Material(
              color: colors.errorContainer,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        error,
                        style: TextStyle(color: colors.onErrorContainer),
                      ),
                    ),
                    if (store.hasUnsaved)
                      TextButton(
                        onPressed: store.retry,
                        child: const Text('Erneut senden'),
                      ),
                    IconButton(
                      tooltip: 'Hinweis schließen',
                      onPressed: store.clearError,
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: store.loadedOnce || _index == 4
                ? _page()
                : Center(
                    child: store.loading
                        ? const CircularProgressIndicator()
                        : const Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              'Die Daten konnten noch nicht geladen werden. Tippe oben auf Neu laden.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                  ),
          ),
        ],
      ),
      floatingActionButton: _fab(context),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) => setState(() => _index = index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.today), label: 'Heute'),
          NavigationDestination(
            icon: Icon(Icons.event_repeat),
            label: 'Protokolle',
          ),
          NavigationDestination(icon: Icon(Icons.history), label: 'Verlauf'),
          NavigationDestination(
            icon: Icon(Icons.monitor_weight),
            label: 'Körper',
          ),
          NavigationDestination(icon: Icon(Icons.more_horiz), label: 'Mehr'),
        ],
      ),
    );
  }
}
