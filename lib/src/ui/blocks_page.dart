import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../model/catalog.dart';
import '../model/project.dart';
import '../state/studio_controller.dart';
import 'theme.dart';

class BlocksPage extends StatelessWidget {
  const BlocksPage({super.key, required this.controller});

  final StudioController controller;

  @override
  Widget build(BuildContext context) {
    final project = controller.project;
    if (project == null) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 1100;
        final palette = _Palette(controller: controller);
        final canvas = _Canvas(controller: controller, project: project);
        final help = _Help(controller: controller);
        if (!wide) {
          return Column(
            children: [
              SizedBox(height: 108, child: palette),
              if (controller.insertIntoId != null)
                Material(
                  color: studioPanel2,
                  child: ListTile(
                    dense: true,
                    title: const Text('Next block goes inside the selection'),
                    trailing: TextButton(
                      onPressed: controller.toggleInsertInside,
                      child: const Text('Cancel'),
                    ),
                  ),
                ),
              Expanded(child: canvas),
              if (controller.selectedId != null) SizedBox(height: 150, child: help),
            ],
          );
        }
        return Row(
          children: [
            SizedBox(width: 250, child: palette),
            const VerticalDivider(width: 1),
            Expanded(child: canvas),
            const VerticalDivider(width: 1),
            SizedBox(width: 300, child: help),
          ],
        );
      },
    );
  }
}

class _Palette extends StatelessWidget {
  const _Palette({required this.controller});
  final StudioController controller;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        for (final category in categories) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
            child: Text(
              categoryLabels[category] ?? category,
              style: TextStyle(color: categoryColor(category), fontWeight: FontWeight.w700, fontSize: 12),
            ),
          ),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final spec in blockSpecs.where((item) => item.category == category))
                ActionChip(
                  label: Text(spec.title),
                  backgroundColor: categoryColor(category).withValues(alpha: 0.15),
                  side: BorderSide(color: categoryColor(category).withValues(alpha: 0.5)),
                  onPressed: () => controller.addBlock(spec.op),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _Canvas extends StatelessWidget {
  const _Canvas({required this.controller, required this.project});
  final StudioController controller;
  final StudioProject project;

  @override
  Widget build(BuildContext context) {
    if (project.blocks.isEmpty) {
      return const Center(child: Text('The stack is empty. Add a block from the palette.'));
    }
    return ReorderableListView(
      padding: const EdgeInsets.all(12),
      buildDefaultDragHandles: false,
      onReorderItem: controller.reorderTop,
      children: [
        for (var i = 0; i < project.blocks.length; i++)
          _BlockTile(
            key: ValueKey(project.blocks[i].id),
            controller: controller,
            node: project.blocks[i],
            index: i,
            topLevel: true,
          ),
      ],
    );
  }
}

class _BlockTile extends StatelessWidget {
  const _BlockTile({
    super.key,
    required this.controller,
    required this.node,
    required this.index,
    required this.topLevel,
  });

  final StudioController controller;
  final BlockNode node;
  final int index;
  final bool topLevel;

  @override
  Widget build(BuildContext context) {
    final spec = blockSpec(node.op);
    final color = categoryColor(spec.category);
    final selected = controller.selectedId == node.id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: color.withValues(alpha: selected ? 0.22 : 0.12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: selected ? studioAccent : color.withValues(alpha: 0.55), width: selected ? 1.6 : 1),
        ),
        child: InkWell(
          onTap: () => controller.selectBlock(node.id),
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (topLevel) ReorderableDragStartListener(index: index, child: const Icon(Icons.drag_indicator, size: 18)),
                    Expanded(child: _Phrase(controller: controller, node: node, spec: spec)),
                    if (spec.cShape)
                      IconButton(
                        tooltip: 'Insert the next palette block inside',
                        onPressed: () {
                          controller.selectBlock(node.id);
                          if (controller.insertIntoId != node.id) controller.toggleInsertInside();
                        },
                        icon: Icon(
                          Icons.subdirectory_arrow_right,
                          size: 18,
                          color: controller.insertIntoId == node.id ? studioAccent : studioMuted,
                        ),
                      ),
                    IconButton(
                      tooltip: 'Move up',
                      onPressed: () {
                        controller.selectBlock(node.id);
                        controller.moveSelected(-1);
                      },
                      icon: const Icon(Icons.arrow_upward, size: 16),
                    ),
                  ],
                ),
                if (spec.cShape) _Nest(controller: controller, title: 'do', nodes: node.body),
                if (spec.hasElse) _Nest(controller: controller, title: 'else', nodes: node.alt),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Nest extends StatelessWidget {
  const _Nest({required this.controller, required this.title, required this.nodes});
  final StudioController controller;
  final String title;
  final List<BlockNode> nodes;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: studioMuted, fontSize: 11)),
          if (nodes.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text('Empty', style: TextStyle(color: studioMuted, fontSize: 12)),
            ),
          for (var i = 0; i < nodes.length; i++)
            _BlockTile(controller: controller, node: nodes[i], index: i, topLevel: false),
        ],
      ),
    );
  }
}

class _Phrase extends StatelessWidget {
  const _Phrase({required this.controller, required this.node, required this.spec});
  final StudioController controller;
  final BlockNode node;
  final BlockSpec spec;

  @override
  Widget build(BuildContext context) {
    final pattern = RegExp(r'\{(\w+)\}');
    final children = <Widget>[];
    var cursor = 0;
    for (final match in pattern.allMatches(spec.phrase)) {
      if (match.start > cursor) {
        children.add(Text(spec.phrase.substring(cursor, match.start)));
      }
      final key = match.group(1)!;
      FieldSpec? field;
      for (final item in spec.fields) {
        if (item.key == key) field = item;
      }
      if (field != null && showField(node, field)) {
        children.add(_Field(controller: controller, node: node, field: field));
      }
      cursor = match.end;
    }
    if (cursor < spec.phrase.length) {
      children.add(Text(spec.phrase.substring(cursor)));
    }
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 4,
      runSpacing: 4,
      children: children,
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.controller, required this.node, required this.field});
  final StudioController controller;
  final BlockNode node;
  final FieldSpec field;

  @override
  Widget build(BuildContext context) {
    final value = node.args[field.key] ?? field.defaultValue;
    if (field.kind == FieldKind.port || field.kind == FieldKind.choice) {
      final choices = field.kind == FieldKind.port ? ports : field.choices;
      final labels = field.kind == FieldKind.port ? ports : field.choiceLabels;
      return DropdownButton<String>(
        value: choices.contains(value) ? value : choices.first,
        isDense: true,
        dropdownColor: studioPanel2,
        items: [
          for (var i = 0; i < choices.length; i++)
            DropdownMenuItem(value: choices[i], child: Text(i < labels.length ? labels[i] : choices[i])),
        ],
        onChanged: (next) {
          if (next != null) controller.setArg(node.id, field.key, next);
        },
      );
    }
    return _MiniText(
      value: value,
      width: field.width,
      digits: field.kind == FieldKind.integer,
      onChanged: (next) => controller.setArg(node.id, field.key, next),
    );
  }
}

class _MiniText extends StatefulWidget {
  const _MiniText({
    required this.value,
    required this.width,
    required this.digits,
    required this.onChanged,
  });

  final String value;
  final double width;
  final bool digits;
  final ValueChanged<String> onChanged;

  @override
  State<_MiniText> createState() => _MiniTextState();
}

class _MiniTextState extends State<_MiniText> {
  late final TextEditingController _text;
  late final FocusNode _focus;

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: widget.value);
    _focus = FocusNode();
  }

  @override
  void didUpdateWidget(covariant _MiniText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != _text.text && !_focus.hasFocus) {
      _text.text = widget.value;
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      child: TextField(
        controller: _text,
        focusNode: _focus,
        style: const TextStyle(fontSize: 13),
        keyboardType: widget.digits ? const TextInputType.numberWithOptions(signed: true) : TextInputType.text,
        inputFormatters: widget.digits ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9-]'))] : null,
        onChanged: widget.onChanged,
        decoration: const InputDecoration(isDense: true),
      ),
    );
  }
}

class _Help extends StatelessWidget {
  const _Help({required this.controller});
  final StudioController controller;

  @override
  Widget build(BuildContext context) {
    final project = controller.project;
    final id = controller.selectedId;
    BlockNode? node;
    if (project != null && id != null) {
      node = _locate(project.blocks, id);
    }
    final spec = node == null ? null : blockSpec(node.op);
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text(spec?.title ?? 'Block help', style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text(spec?.blurb ?? 'Select a block to edit it. Drag the handle to reorder the top of the stack.'),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton(onPressed: controller.duplicateSelected, child: const Text('Duplicate')),
            OutlinedButton(onPressed: controller.deleteSelected, child: const Text('Delete')),
            OutlinedButton(onPressed: () => controller.moveSelected(-1), child: const Text('Up')),
            OutlinedButton(onPressed: () => controller.moveSelected(1), child: const Text('Down')),
          ],
        ),
        if (node?.op == 'drive') ...[
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => controller.expandDrive(node!.id),
            child: const Text('Expand into two motor moves'),
          ),
        ],
        const SizedBox(height: 16),
        const Text(
          'Desktop shortcuts: Ctrl/Cmd+Z undo, Shift+Ctrl/Cmd+Z redo, Ctrl/Cmd+Enter download, Ctrl/Cmd+D duplicate, Delete removes the selection.',
          style: TextStyle(color: studioMuted, fontSize: 12),
        ),
      ],
    );
  }
}

BlockNode? _locate(List<BlockNode> nodes, String id) {
  for (final node in nodes) {
    if (node.id == id) return node;
    final body = _locate(node.body, id);
    if (body != null) return body;
    final alt = _locate(node.alt, id);
    if (alt != null) return alt;
  }
  return null;
}
