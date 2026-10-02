import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

int _seq = 0;

String newId() {
  _seq += 1;
  final now = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  return '$now$_seq';
}

class BlockNode {
  BlockNode({
    required this.id,
    required this.op,
    Map<String, String>? args,
    List<BlockNode>? body,
    List<BlockNode>? alt,
  }) : args = args ?? <String, String>{},
       body = body ?? <BlockNode>[],
       alt = alt ?? <BlockNode>[];

  String id;
  String op;
  final Map<String, String> args;
  final List<BlockNode> body;
  final List<BlockNode> alt;

  BlockNode clone() {
    return BlockNode(
      id: newId(),
      op: op,
      args: Map<String, String>.of(args),
      body: body.map((b) => b.clone()).toList(),
      alt: alt.map((b) => b.clone()).toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'op': op,
    'args': args,
    'body': body.map((b) => b.toJson()).toList(),
    'alt': alt.map((b) => b.toJson()).toList(),
  };

  factory BlockNode.fromJson(Map<String, dynamic> json) {
    return BlockNode(
      id: (json['id'] as String?) ?? newId(),
      op: json['op'] as String,
      args: _stringMap(json['args']),
      body: _nodeList(json['body']),
      alt: _nodeList(json['alt']),
    );
  }
}

class StudioProject {
  StudioProject({
    required this.id,
    required this.name,
    this.notes = '',
    this.slot = 0,
    String? updatedAt,
    List<BlockNode>? blocks,
  }) : updatedAt = updatedAt ?? DateTime.now().toUtc().toIso8601String(),
       blocks = blocks ?? <BlockNode>[];

  String id;
  String name;
  String notes;
  int slot;
  String updatedAt;
  final List<BlockNode> blocks;

  StudioProject clone({String? name}) {
    return StudioProject(
      id: newId(),
      name: name ?? '$this.name copy',
      notes: notes,
      slot: slot,
      blocks: blocks.map((b) => b.clone()).toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'notes': notes,
    'slot': slot,
    'updatedAt': updatedAt,
    'blocks': blocks.map((b) => b.toJson()).toList(),
  };

  factory StudioProject.fromJson(Map<String, dynamic> json) {
    return StudioProject(
      id: (json['id'] as String?) ?? newId(),
      name: (json['name'] as String?) ?? 'Untitled',
      notes: (json['notes'] as String?) ?? '',
      slot: (json['slot'] as num?)?.toInt() ?? 0,
      updatedAt: json['updatedAt'] as String?,
      blocks: _nodeList(json['blocks']),
    );
  }
}

class ProjectFile {
  static const format = 'spstudio';
  static const formatVersion = 1;

  static Map<String, dynamic> encode(StudioProject project) => {
    'format': format,
    'formatVersion': formatVersion,
    'project': project.toJson(),
  };

  static String encodePretty(StudioProject project) {
    return const JsonEncoder.withIndent('  ').convert(encode(project));
  }

  static StudioProject decode(Object? json) {
    if (json is! Map) {
      throw const FormatException('Project file is not a JSON object.');
    }
    final map = Map<String, dynamic>.from(json);
    if (map['format'] != format) {
      throw const FormatException(
        'This file is not a Spike Prime Studio project.',
      );
    }
    final version = map['formatVersion'];
    if (version is! int || version != formatVersion) {
      throw FormatException('Unsupported project format version: $version');
    }
    final project = map['project'];
    if (project is! Map) {
      throw const FormatException('Project file is missing its project.');
    }
    return StudioProject.fromJson(Map<String, dynamic>.from(project));
  }

  static Uint8List encodeZip(StudioProject project, String python) {
    final archive = Archive();
    final jsonBytes = utf8.encode(encodePretty(project));
    final pyBytes = utf8.encode(python);
    archive.addFile(
      ArchiveFile('project.json', jsonBytes.length, jsonBytes),
    );
    archive.addFile(ArchiveFile('program.py', pyBytes.length, pyBytes));
    return ZipEncoder().encodeBytes(archive);
  }

  static StudioProject decodeBytes(List<int> bytes, {String? filename}) {
    if (_looksLikeZip(bytes, filename)) {
      final archive = ZipDecoder().decodeBytes(bytes);
      final entry = archive.files.cast<ArchiveFile?>().firstWhere(
        (file) => file!.name == 'project.json' || file.name.endsWith('/project.json'),
        orElse: () => null,
      );
      if (entry == null) {
        throw const FormatException('Zip has no project.json.');
      }
      return decode(jsonDecode(utf8.decode(entry.readBytes()!)));
    }
    return decode(jsonDecode(utf8.decode(bytes)));
  }
}

bool _looksLikeZip(List<int> bytes, String? filename) {
  final name = filename?.toLowerCase() ?? '';
  if (name.endsWith('.spstudio') || name.endsWith('.zip')) return true;
  return bytes.length > 3 && bytes[0] == 0x50 && bytes[1] == 0x4b;
}

Map<String, String> _stringMap(Object? raw) {
  if (raw is! Map) return {};
  return raw.map((key, value) => MapEntry('$key', '$value'));
}

List<BlockNode> _nodeList(Object? raw) {
  if (raw is! List) return [];
  return raw
      .whereType<Map>()
      .map((e) => BlockNode.fromJson(Map<String, dynamic>.from(e)))
      .toList();
}

StudioProject blankProject() {
  return StudioProject(
    id: newId(),
    name: 'Untitled',
    notes: 'New program.',
    blocks: [BlockNode(id: newId(), op: 'onStart')],
  );
}

StudioProject sampleGettingStarted() {
  return StudioProject(
    id: 'sample-drive-look',
    name: 'Drive and look',
    notes:
        'Sample project. Pair motors on A and B, drive forward, then wait until a distance sensor on C sees something close.',
    slot: 0,
    updatedAt: '2026-10-02T00:00:00.000Z',
    blocks: [
      BlockNode(id: 's-start', op: 'onStart'),
      BlockNode(
        id: 's-ready',
        op: 'defBlock',
        args: {'name': 'ready'},
        body: [
          BlockNode(
            id: 's-light',
            op: 'statusLight',
            args: {'color': 'BLUE'},
          ),
          BlockNode(
            id: 's-beep',
            op: 'beep',
            args: {'freq': '523', 'ms': '90', 'volume': '60'},
          ),
        ],
      ),
      BlockNode(id: 's-call', op: 'callBlock', args: {'name': 'ready'}),
      BlockNode(
        id: 's-note',
        op: 'comment',
        args: {
          'text':
              'Drive forward, then stop the drive if something is close. Edit the ports to match your build.',
        },
      ),
      BlockNode(
        id: 's-drive',
        op: 'drive',
        args: {
          'left': 'A',
          'right': 'B',
          'degrees': '720',
          'steering': '0',
          'velocity': '450',
        },
      ),
      BlockNode(
        id: 's-wait',
        op: 'waitUntil',
        args: {
          'sensor': 'distance',
          'port': 'C',
          'op': 'lt',
          'value': '150',
          'timeout': '4000',
          'subject': 'x',
        },
      ),
      BlockNode(
        id: 's-if',
        op: 'if',
        args: {
          'sensor': 'color',
          'port': 'D',
          'op': 'eq',
          'value': 'RED',
          'subject': 'x',
        },
        body: [
          BlockNode(
            id: 's-happy',
            op: 'matrixImage',
            args: {'image': 'IMAGE_HAPPY'},
          ),
        ],
        alt: [
          BlockNode(id: 's-pause', op: 'wait', args: {'ms': '200'}),
        ],
      ),
      BlockNode(
        id: 's-back',
        op: 'together',
        body: [
          BlockNode(
            id: 's-back-a',
            op: 'motorDegrees',
            args: {
              'port': 'A',
              'degrees': '-180',
              'velocity': '300',
              'stop': 'BRAKE',
            },
          ),
          BlockNode(
            id: 's-back-b',
            op: 'motorDegrees',
            args: {
              'port': 'B',
              'degrees': '-180',
              'velocity': '300',
              'stop': 'BRAKE',
            },
          ),
        ],
      ),
      BlockNode(id: 's-text', op: 'matrixText', args: {'text': 'Hi'}),
    ],
  );
}
