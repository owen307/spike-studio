import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'src/state/studio_controller.dart';
import 'src/ui/blocks_page.dart';
import 'src/ui/library_page.dart';
import 'src/ui/other_pages.dart';
import 'src/ui/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SpikeStudioApp());
}

class SpikeStudioApp extends StatefulWidget {
  const SpikeStudioApp({super.key});

  @override
  State<SpikeStudioApp> createState() => _SpikeStudioAppState();
}

class _SpikeStudioAppState extends State<SpikeStudioApp> {
  late final StudioController controller;

  @override
  void initState() {
    super.initState();
    controller = StudioController();
    controller.addListener(_onChange);
    controller.init();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    controller.removeListener(_onChange);
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Spike Prime Studio',
      debugShowCheckedModeBanner: false,
      theme: studioTheme(),
      home: StudioShell(controller: controller),
    );
  }
}

class StudioShell extends StatelessWidget {
  const StudioShell({super.key, required this.controller});

  final StudioController controller;

  @override
  Widget build(BuildContext context) {
    if (!controller.ready) {
      return const Scaffold(
        body: Center(child: Text('Opening studio...')),
      );
    }
    return CallbackShortcuts(
      bindings: _bindings(controller),
      child: Focus(
        autofocus: true,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 900;
            final page = _page(controller);
            return Scaffold(
              body: Stack(
                children: [
                  Column(
                    children: [
                      _Header(controller: controller, compact: !wide),
                      Expanded(
                        child: Row(
                          children: [
                            if (wide) _Rail(controller: controller),
                            Expanded(child: page),
                          ],
                        ),
                      ),
                      _Console(controller: controller),
                    ],
                  ),
                  if (controller.showOnboarding) _Onboarding(controller: controller),
                ],
              ),
              bottomNavigationBar: wide ? null : _BottomNav(controller: controller),
            );
          },
        ),
      ),
    );
  }
}

Map<ShortcutActivator, VoidCallback> _bindings(StudioController controller) {
  void undo() => controller.undo();
  void redo() => controller.redo();
  void run() => controller.runOnHub();
  void remove() {
    if (_typing()) return;
    controller.deleteSelected();
  }

  return {
    const SingleActivator(LogicalKeyboardKey.keyZ, control: true, shift: true): redo,
    const SingleActivator(LogicalKeyboardKey.keyZ, meta: true, shift: true): redo,
    const SingleActivator(LogicalKeyboardKey.keyZ, control: true): undo,
    const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): undo,
    const SingleActivator(LogicalKeyboardKey.enter, control: true): run,
    const SingleActivator(LogicalKeyboardKey.enter, meta: true): run,
    const SingleActivator(LogicalKeyboardKey.delete): remove,
    const SingleActivator(LogicalKeyboardKey.keyD, control: true): controller.duplicateSelected,
    const SingleActivator(LogicalKeyboardKey.keyD, meta: true): controller.duplicateSelected,
  };
}

bool _typing() {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return false;
  return context.widget is EditableText || context.findAncestorWidgetOfExactType<EditableText>() != null;
}

Widget _page(StudioController controller) {
  return switch (controller.page) {
    0 => LibraryPage(controller: controller),
    2 => TeachPage(controller: controller),
    3 => HubPage(controller: controller),
    4 => PythonPage(controller: controller),
    _ => BlocksPage(controller: controller),
  };
}

class _Header extends StatelessWidget {
  const _Header({required this.controller, required this.compact});

  final StudioController controller;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final project = controller.project;
    final live = controller.live;
    final link = live.connected
        ? (live.mock ? 'Mock' : (live.hubName ?? 'Hub'))
        : 'Offline';
    return Material(
      color: studioPanel,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.asset(
                'assets/brand/sp-mark.png',
                width: 28,
                height: 28,
                filterQuality: FilterQuality.medium,
                semanticLabel: 'Spike Prime Studio',
              ),
            ),
            const Text(
              'Spike Prime Studio',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            if (!compact)
              const Text(
                'SPIKE Prime compatible',
                style: TextStyle(color: studioMuted, fontSize: 12),
              ),
            Text(project?.name ?? '', style: const TextStyle(color: studioAmber)),
            _Chip(label: link, color: live.mock ? studioAmber : studioAccent),
            if (live.battery != null) _Chip(label: '${live.battery}%', color: studioMuted),
            IconButton(
              tooltip: 'Undo',
              onPressed: controller.canUndo ? controller.undo : null,
              icon: const Icon(Icons.undo),
            ),
            IconButton(
              tooltip: 'Redo',
              onPressed: controller.canRedo ? controller.redo : null,
              icon: const Icon(Icons.redo),
            ),
            FilledButton.icon(
              onPressed: live.connected ? controller.runOnHub : null,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Download & run'),
            ),
            OutlinedButton(
              onPressed: live.connected ? controller.stopOnHub : null,
              child: const Text('Stop'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: color.withValues(alpha: 0.7)),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 12)),
    );
  }
}

class _Rail extends StatelessWidget {
  const _Rail({required this.controller});
  final StudioController controller;

  @override
  Widget build(BuildContext context) {
    return NavigationRail(
      selectedIndex: controller.page,
      onDestinationSelected: controller.go,
      labelType: NavigationRailLabelType.all,
      destinations: const [
        NavigationRailDestination(icon: Icon(Icons.folder_outlined), label: Text('Library')),
        NavigationRailDestination(icon: Icon(Icons.view_agenda_outlined), label: Text('Blocks')),
        NavigationRailDestination(icon: Icon(Icons.pan_tool_alt_outlined), label: Text('Teach')),
        NavigationRailDestination(icon: Icon(Icons.bluetooth), label: Text('Hub')),
        NavigationRailDestination(icon: Icon(Icons.code), label: Text('Python')),
      ],
    );
  }
}

class _BottomNav extends StatelessWidget {
  const _BottomNav({required this.controller});
  final StudioController controller;

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: controller.page,
      onDestinationSelected: controller.go,
      destinations: const [
        NavigationDestination(icon: Icon(Icons.folder_outlined), label: 'Library'),
        NavigationDestination(icon: Icon(Icons.view_agenda_outlined), label: 'Blocks'),
        NavigationDestination(icon: Icon(Icons.pan_tool_alt_outlined), label: 'Teach'),
        NavigationDestination(icon: Icon(Icons.bluetooth), label: 'Hub'),
        NavigationDestination(icon: Icon(Icons.code), label: 'Python'),
      ],
    );
  }
}

class _Console extends StatelessWidget {
  const _Console({required this.controller});
  final StudioController controller;

  @override
  Widget build(BuildContext context) {
    final text = controller.console.isEmpty ? 'Console is quiet.' : controller.console.join('\n');
    return Container(
      height: 112,
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: const BoxDecoration(
        color: Color(0xFF0E1116),
        border: Border(top: BorderSide(color: studioLine)),
      ),
      child: SingleChildScrollView(
        reverse: true,
        child: SelectableText(
          text,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: studioMuted, height: 1.35),
        ),
      ),
    );
  }
}

class _Onboarding extends StatelessWidget {
  const _Onboarding({required this.controller});
  final StudioController controller;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xCC000000),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.asset(
                        'assets/brand/sp-mark.png',
                        width: 72,
                        height: 72,
                        filterQuality: FilterQuality.medium,
                        semanticLabel: 'Spike Prime Studio',
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text('Before you connect', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 12),
                    const Text(
                      'Spike Prime Studio writes MicroPython for a hub running the SPIKE App 3 firmware and talks to it over Bluetooth Low Energy.',
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Turn the hub on. If the official app or another phone is already connected, disconnect it first or this scan will not see the hub.',
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'On Android, allow Nearby devices. On Android 11 and older the system also asks for Location before it will return Bluetooth scan results. This app does not track where you are.',
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Teach mode records the robot while you move it by hand, then builds editable blocks. It is for authoring. In a match the robot has to run the downloaded program by itself. Do not drive it from this app during a match.',
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'No hub nearby? Stay on the mock hub. It is labeled and never uses the radio.',
                    ),
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton(
                        onPressed: controller.dismissOnboarding,
                        child: const Text('Continue'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
