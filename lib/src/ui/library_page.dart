import 'package:flutter/material.dart';

import '../state/studio_controller.dart';
import 'theme.dart';

class LibraryPage extends StatelessWidget {
  const LibraryPage({super.key, required this.controller});

  final StudioController controller;

  @override
  Widget build(BuildContext context) {
    final project = controller.project;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Projects stay on this device. Export a .spstudio.json file or a .spstudio zip when you want to move one to another phone or computer.',
          style: TextStyle(color: studioMuted),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(onPressed: controller.newProject, icon: const Icon(Icons.add), label: const Text('New')),
            OutlinedButton.icon(
              onPressed: controller.importProject,
              icon: const Icon(Icons.file_open),
              label: const Text('Import'),
            ),
            OutlinedButton(onPressed: controller.duplicateProject, child: const Text('Duplicate')),
            OutlinedButton(onPressed: () => _rename(context), child: const Text('Rename')),
            OutlinedButton(onPressed: controller.deleteProject, child: const Text('Delete')),
            OutlinedButton(onPressed: () => controller.export(kind: 'json'), child: const Text('Export JSON')),
            OutlinedButton(onPressed: () => controller.export(kind: 'zip'), child: const Text('Export .spstudio')),
            OutlinedButton(onPressed: () => controller.export(kind: 'py'), child: const Text('Export Python')),
            OutlinedButton(onPressed: controller.copyProjectJson, child: const Text('Copy JSON')),
          ],
        ),
        if (controller.lastExportPath != null) ...[
          const SizedBox(height: 8),
          Text('Last copy: ${controller.lastExportPath}', style: const TextStyle(color: studioMuted, fontSize: 12)),
        ],
        const SizedBox(height: 16),
        for (final item in controller.projects)
          Card(
            color: item.id == controller.activeId ? studioPanel2 : studioPanel,
            child: ListTile(
              selected: item.id == controller.activeId,
              title: Text(item.name),
              subtitle: Text('Slot ${item.slot} · ${item.blocks.length} blocks'),
              onTap: () => controller.selectProject(item.id),
            ),
          ),
        const SizedBox(height: 12),
        _NotesField(
          projectId: project?.id ?? '',
          notes: project?.notes ?? '',
          onChanged: controller.setNotes,
        ),
      ],
    );
  }

  Future<void> _rename(BuildContext context) async {
    final project = controller.project;
    if (project == null) return;
    final text = TextEditingController(text: project.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename project'),
        content: TextField(controller: text, autofocus: true, decoration: const InputDecoration(labelText: 'Name')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, text.text), child: const Text('Save')),
        ],
      ),
    );
    if (name != null) controller.renameProject(name);
  }
}

class _NotesField extends StatefulWidget {
  const _NotesField({required this.projectId, required this.notes, required this.onChanged});

  final String projectId;
  final String notes;
  final ValueChanged<String> onChanged;

  @override
  State<_NotesField> createState() => _NotesFieldState();
}

class _NotesFieldState extends State<_NotesField> {
  late final TextEditingController _text = TextEditingController(text: widget.notes);

  @override
  void didUpdateWidget(covariant _NotesField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.projectId != oldWidget.projectId && _text.text != widget.notes) {
      _text.text = widget.notes;
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _text,
      maxLines: 4,
      decoration: const InputDecoration(labelText: 'Notes'),
      onChanged: widget.onChanged,
    );
  }
}
