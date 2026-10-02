import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../storage/local_export_stub.dart' if (dart.library.io) '../storage/local_export_io.dart';

import '../codegen/python_gen.dart';
import '../hub/hub_factory.dart';
import '../hub/hub_models.dart';
import '../hub/mock_hub.dart';
import '../model/catalog.dart';
import '../model/project.dart';
import '../storage/project_store.dart';
import '../teach/teach.dart';

class StudioController extends ChangeNotifier {
  StudioController({HubLink? hub}) : hub = hub ?? MockHubLink();

  HubLink hub;
  List<StudioProject> projects = [];
  String? activeId;
  bool ready = false;
  bool showOnboarding = false;
  int page = 1;
  String? selectedId;
  String? insertIntoId;
  final console = <String>[];
  List<DiscoveredHub> found = [];
  var live = HubLive.idle();
  bool recording = false;
  List<TeachSample> take = [];
  TeachOptions teachOptions = const TeachOptions();
  String? lastExportPath;
  bool protocolDetail = true;

  final _undo = <String>[];
  int _undoAt = -1;
  bool _historyLock = false;
  StreamSubscription<HubLive>? _liveSub;
  StreamSubscription<String>? _consoleSub;
  StreamSubscription<List<DiscoveredHub>>? _deviceSub;
  int? _recordT0;

  StudioProject? get project {
    for (final item in projects) {
      if (item.id == activeId) return item;
    }
    return null;
  }

  bool get canUndo => _undoAt > 0;
  bool get canRedo => _undoAt >= 0 && _undoAt < _undo.length - 1;
  String get python => project == null ? '' : generatePython(project!);

  Future<void> init() async {
    try {
      projects = await ProjectStore.load();
      showOnboarding = !await ProjectStore.onboarded();
    } catch (error) {
      log('Could not open the project library: $error');
      projects = [];
    }
    if (projects.isEmpty) projects = [sampleGettingStarted()];
    activeId = projects.first.id;
    _resetHistory();
    _bind();
    ready = true;
    notifyListeners();
    if (hub is MockHubLink) {
      await hub.connect(MockHubLink.discovered);
    }
  }

  Future<void> dismissOnboarding() async {
    showOnboarding = false;
    await ProjectStore.setOnboarded();
    notifyListeners();
  }

  void openOnboarding() {
    showOnboarding = true;
    notifyListeners();
  }

  void go(int index) {
    page = index;
    notifyListeners();
  }

  Future<void> useMock() async {
    await _swap(MockHubLink());
    await hub.connect(MockHubLink.discovered);
    log('Mock hub is on. It is labeled and does not use the radio.');
  }

  Future<void> useRadio() async {
    await _swap(openRadioHub());
    log('Bluetooth mode. Turn the hub on and disconnect it from other apps.');
    try {
      await hub.scan();
    } catch (error) {
      log('$error');
    }
  }

  Future<void> scan() async {
    try {
      await hub.scan();
    } catch (error) {
      log('$error');
    }
  }

  Future<void> connectHub(DiscoveredHub item) async {
    try {
      await hub.connect(item);
    } catch (error) {
      log('$error');
    }
  }

  Future<void> disconnectHub() async {
    await hub.disconnect();
    log(hub.isMock ? 'Mock hub disconnected.' : 'Hub disconnected.');
  }

  Future<void> runOnHub() async {
    final current = project;
    if (current == null) return;
    try {
      await hub.uploadAndRun(generatePython(current), slot: current.slot);
    } catch (error) {
      log('Download failed: $error');
    }
  }

  Future<void> stopOnHub() async {
    final slot = project?.slot ?? 0;
    try {
      await hub.stopProgram(slot);
    } catch (error) {
      log('Stop failed: $error');
    }
  }

  Future<void> setNotify(int ms) async {
    try {
      await hub.setNotifyInterval(ms);
      log('Asked the hub for readings every $ms ms.');
    } catch (error) {
      log('$error');
    }
  }

  void selectProject(String id) {
    activeId = id;
    selectedId = null;
    insertIntoId = null;
    _resetHistory();
    notifyListeners();
  }

  void newProject() {
    final created = blankProject();
    projects = [...projects, created];
    activeId = created.id;
    _resetHistory();
    _save();
    log('Created ${created.name}.');
    notifyListeners();
  }

  void duplicateProject() {
    final current = project;
    if (current == null) return;
    final copy = current.clone(name: '${current.name} copy');
    projects = [...projects, copy];
    activeId = copy.id;
    _resetHistory();
    _save();
    notifyListeners();
  }

  void renameProject(String name) {
    final current = project;
    if (current == null) return;
    current.name = name.trim().isEmpty ? current.name : name.trim();
    current.updatedAt = _now();
    _save();
    notifyListeners();
  }

  void setNotes(String notes) {
    final current = project;
    if (current == null) return;
    current.notes = notes;
    current.updatedAt = _now();
    _save();
    notifyListeners();
  }

  void setSlot(int slot) {
    mutate((item) => item.slot = slot.clamp(0, 19));
  }

  void deleteProject() {
    final current = project;
    if (current == null) return;
    projects = projects.where((item) => item.id != current.id).toList();
    if (projects.isEmpty) projects = [blankProject()];
    activeId = projects.first.id;
    _resetHistory();
    _save();
    notifyListeners();
  }

  void selectBlock(String? id) {
    selectedId = id;
    notifyListeners();
  }

  void toggleInsertInside() {
    final current = project;
    if (current == null || selectedId == null) return;
    final spot = _find(current.blocks, selectedId!);
    if (spot == null || !blockSpec(spot.node.op).cShape) {
      insertIntoId = null;
    } else {
      insertIntoId = insertIntoId == selectedId ? null : selectedId;
    }
    notifyListeners();
  }

  void addBlock(String op) {
    final created = freshBlock(op);
    mutate((item) {
      if (insertIntoId != null) {
        final spot = _find(item.blocks, insertIntoId!);
        if (spot != null && blockSpec(spot.node.op).cShape) {
          spot.node.body.add(created);
          return;
        }
      }
      if (selectedId != null) {
        final spot = _find(item.blocks, selectedId!);
        if (spot != null) {
          spot.list.insert(spot.index + 1, created);
          return;
        }
      }
      item.blocks.add(created);
    });
    selectedId = created.id;
    notifyListeners();
  }

  void setArg(String id, String key, String value) {
    mutate((item) {
      final spot = _find(item.blocks, id);
      if (spot == null) return;
      spot.node.args[key] = value;
    });
  }

  void deleteSelected() {
    final id = selectedId;
    if (id == null) return;
    mutate((item) {
      final spot = _find(item.blocks, id);
      if (spot == null) return;
      spot.list.removeAt(spot.index);
    });
    selectedId = null;
    if (insertIntoId == id) insertIntoId = null;
    notifyListeners();
  }

  void duplicateSelected() {
    final current = project;
    final id = selectedId;
    if (current == null || id == null) return;
    final spot = _find(current.blocks, id);
    if (spot == null) return;
    final copy = spot.node.clone();
    mutate((item) {
      final liveSpot = _find(item.blocks, id);
      if (liveSpot == null) return;
      liveSpot.list.insert(liveSpot.index + 1, copy);
    });
    selectedId = copy.id;
    notifyListeners();
  }

  void moveSelected(int delta) {
    final id = selectedId;
    if (id == null) return;
    mutate((item) {
      final spot = _find(item.blocks, id);
      if (spot == null) return;
      final next = spot.index + delta;
      if (next < 0 || next >= spot.list.length) return;
      final node = spot.list.removeAt(spot.index);
      spot.list.insert(next, node);
    });
  }

  void reorderTop(int oldIndex, int newIndex) {
    mutate((item) {
      if (oldIndex < 0 || oldIndex >= item.blocks.length) return;
      final node = item.blocks.removeAt(oldIndex);
      final target = newIndex.clamp(0, item.blocks.length);
      item.blocks.insert(target, node);
    });
  }

  void expandDrive(String id) {
    mutate((item) {
      final spot = _find(item.blocks, id);
      if (spot == null || spot.node.op != 'drive') return;
      final node = spot.node;
      final degrees = asInt(node.args['degrees'], 360);
      final steering = asInt(node.args['steering'], 0).clamp(-100, 100);
      final velocity = node.args['velocity'] ?? '400';
      final scaleLeft = steering >= 0 ? 1.0 : (1 + steering / 100).clamp(0.0, 1.0);
      final scaleRight = steering <= 0 ? 1.0 : (1 - steering / 100).clamp(0.0, 1.0);
      final replacement = [
        BlockNode(
          id: newId(),
          op: 'comment',
          args: {
            'text':
                'Expanded drive. The two motors are no longer synchronized, and steering is only approximate.',
          },
        ),
        BlockNode(
          id: newId(),
          op: 'motorDegrees',
          args: {
            'port': portOf(node.args['left']),
            'degrees': '${(degrees * scaleLeft).round()}',
            'velocity': velocity,
            'stop': 'BRAKE',
          },
        ),
        BlockNode(
          id: newId(),
          op: 'motorDegrees',
          args: {
            'port': portOf(node.args['right'], fallback: 'B'),
            'degrees': '${(degrees * scaleRight).round()}',
            'velocity': velocity,
            'stop': 'BRAKE',
          },
        ),
      ];
      spot.list.replaceRange(spot.index, spot.index + 1, replacement);
    });
  }

  void undo() => _jump(-1);
  void redo() => _jump(1);

  void toggleRecord() {
    if (!live.connected) {
      log('Connect the mock hub or a real hub before recording.');
      return;
    }
    if (recording) {
      recording = false;
      log('Recording stopped. ${take.length} samples. Convert them when you are ready.');
      notifyListeners();
      return;
    }
    take = [];
    _recordT0 = DateTime.now().millisecondsSinceEpoch;
    recording = true;
    _capture(live, force: true);
    log('Recording. Move the robot by hand. The result is keyframes, not a continuous curve.');
    notifyListeners();
  }

  void clearTake() {
    recording = false;
    take = [];
    notifyListeners();
  }

  void setTeachOptions(TeachOptions options) {
    teachOptions = options;
    notifyListeners();
  }

  void applyTeach({required bool replace}) {
    if (take.length < 2) {
      log('Record a little longer before converting.');
      return;
    }
    final blocks = compileTeach(take, teachOptions);
    mutate((item) {
      if (replace) {
        item.blocks
          ..clear()
          ..add(BlockNode(id: newId(), op: 'onStart'))
          ..addAll(blocks);
      } else {
        item.blocks.addAll(blocks);
      }
    });
    page = 1;
    log('Teach blocks added. ${teachSummary(blocks)}');
    notifyListeners();
  }

  Future<void> copyPython() async {
    await Clipboard.setData(ClipboardData(text: python));
    log('Python copied.');
  }

  Future<void> copyProjectJson() async {
    final current = project;
    if (current == null) return;
    await Clipboard.setData(ClipboardData(text: ProjectFile.encodePretty(current)));
    log('Project JSON copied.');
  }

  Future<void> export({required String kind}) async {
    final current = project;
    if (current == null) return;
    final slug = current.name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-|-$'), '');
    final safe = slug.isEmpty ? 'project' : slug;
    final py = generatePython(current);
    late final String filename;
    late final Uint8List bytes;
    late final String mime;
    switch (kind) {
      case 'py':
        filename = '$safe.py';
        bytes = Uint8List.fromList(utf8.encode(py));
        mime = 'text/x-python';
      case 'zip':
        filename = '$safe.spstudio';
        bytes = ProjectFile.encodeZip(current, py);
        mime = 'application/zip';
      default:
        filename = '$safe.spstudio.json';
        bytes = Uint8List.fromList(utf8.encode(ProjectFile.encodePretty(current)));
        mime = 'application/json';
    }
    String? dialog;
    try {
      final uri = await FilePicker.saveFile(
        fileName: filename,
        bytes: bytes,
        mimeType: mime,
        dialogTitle: 'Export $filename',
      );
      if (uri != null) dialog = uri.toString();
    } catch (error) {
      dialog = 'dialog unavailable ($error)';
    }
    final local = await _writeLocal(filename, bytes);
    lastExportPath = local ?? dialog;
    log('Exported $filename${local == null ? '' : ' to $local'}${dialog == null ? '' : ' / $dialog'}');
    notifyListeners();
  }

  Future<void> importProject() async {
    try {
      final file = await FilePicker.pickFile(
        dialogTitle: 'Import a Spike Prime Studio project',
        type: FileType.custom,
        allowedExtensions: const ['json', 'spstudio', 'py'],
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      final imported = ProjectFile.decodeBytes(bytes, filename: file.name);
      imported.id = newId();
      imported.updatedAt = _now();
      projects = [...projects, imported];
      activeId = imported.id;
      _resetHistory();
      _save();
      log('Imported ${imported.name}.');
      notifyListeners();
    } catch (error) {
      log('Import failed: $error');
    }
  }

  void log(String line) {
    final stamp = DateTime.now().toIso8601String().substring(11, 19);
    console.add('$stamp  $line');
    if (console.length > 200) console.removeRange(0, console.length - 200);
    notifyListeners();
  }

  void mutate(void Function(StudioProject project) change) {
    final current = project;
    if (current == null) return;
    change(current);
    current.updatedAt = _now();
    _pushHistory();
    _save();
    notifyListeners();
  }

  @override
  void dispose() {
    _liveSub?.cancel();
    _consoleSub?.cancel();
    _deviceSub?.cancel();
    hub.dispose();
    super.dispose();
  }

  Future<void> _swap(HubLink next) async {
    await _liveSub?.cancel();
    await _consoleSub?.cancel();
    await _deviceSub?.cancel();
    await hub.dispose();
    hub = next;
    live = hub.current;
    found = [];
    recording = false;
    _bind();
    notifyListeners();
  }

  void _bind() {
    _liveSub = hub.live.listen((next) {
      live = next;
      _capture(next);
      notifyListeners();
    });
    _consoleSub = hub.console.listen(log);
    _deviceSub = hub.devices.listen((items) {
      found = items;
      notifyListeners();
    });
    live = hub.current;
  }

  void _capture(HubLive next, {bool force = false}) {
    if (!recording || !next.connected) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final t = now - (_recordT0 ?? now);
    final pos = <String, int>{};
    final absPos = <String, int>{};
    for (final port in next.ports) {
      if (port.kind != 'motor') continue;
      if (port.position != null) pos[port.letter] = port.position!;
      if (port.absPosition != null) absPos[port.letter] = port.absPosition!;
    }
    if (!force && take.isNotEmpty) {
      final last = take.last;
      var jumped = false;
      for (final entry in pos.entries) {
        final previous = last.motorPos[entry.key] ?? entry.value;
        if ((entry.value - previous).abs() >= 4) jumped = true;
      }
      if (t - last.tMs < 40 && !jumped) return;
    }
    take.add(TeachSample(tMs: t, motorPos: pos, motorAbs: absPos));
  }

  void _resetHistory() {
    _undo
      ..clear()
      ..add(jsonEncode(project?.toJson()));
    _undoAt = 0;
  }

  void _pushHistory() {
    if (_historyLock) return;
    final snap = jsonEncode(project?.toJson());
    if (_undoAt >= 0 && _undoAt == _undo.length - 1 && _undo.isNotEmpty && _undo.last == snap) {
      return;
    }
    if (_undoAt >= 0 && _undoAt < _undo.length - 1) {
      _undo.removeRange(_undoAt + 1, _undo.length);
    }
    _undo.add(snap);
    if (_undo.length > 80) {
      _undo.removeAt(0);
    }
    _undoAt = _undo.length - 1;
  }

  void _jump(int delta) {
    final next = _undoAt + delta;
    if (next < 0 || next >= _undo.length) return;
    _undoAt = next;
    final decoded = jsonDecode(_undo[next]);
    if (decoded is! Map) return;
    final restored = StudioProject.fromJson(Map<String, dynamic>.from(decoded));
    final index = projects.indexWhere((item) => item.id == activeId);
    _historyLock = true;
    if (index >= 0) {
      projects[index] = restored;
      activeId = restored.id;
    }
    _historyLock = false;
    _save();
    notifyListeners();
  }

  Future<void> _save() async {
    try {
      await ProjectStore.save(projects);
    } catch (error) {
      log('Could not save the library: $error');
    }
  }

  Future<String?> _writeLocal(String filename, List<int> bytes) async {
    if (kIsWeb) return null;
    try {
      return await writeExportFile(filename, bytes);
    } catch (error) {
      log('Could not write a local copy: $error');
      return null;
    }
  }

  String _now() => DateTime.now().toUtc().toIso8601String();
}

class _Spot {
  _Spot(this.list, this.index);
  final List<BlockNode> list;
  final int index;
  BlockNode get node => list[index];
}

_Spot? _find(List<BlockNode> list, String id) {
  for (var i = 0; i < list.length; i++) {
    if (list[i].id == id) return _Spot(list, i);
    final inBody = _find(list[i].body, id);
    if (inBody != null) return inBody;
    final inAlt = _find(list[i].alt, id);
    if (inAlt != null) return inAlt;
  }
  return null;
}
