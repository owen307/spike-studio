import '../model/project.dart';

class TeachSample {
  TeachSample({
    required this.tMs,
    Map<String, int>? motorPos,
    Map<String, int>? motorAbs,
  }) : motorPos = motorPos ?? <String, int>{},
       motorAbs = motorAbs ?? <String, int>{};

  final int tMs;
  final Map<String, int> motorPos;
  final Map<String, int> motorAbs;
}

class TeachOptions {
  const TeachOptions({
    this.absolute = false,
    this.gridMs = 100,
    this.noiseDeg = 8,
    this.minHoldMs = 200,
  });

  final bool absolute;
  final int gridMs;
  final int noiseDeg;
  final int minHoldMs;

  TeachOptions copyWith({bool? absolute, int? gridMs, int? noiseDeg, int? minHoldMs}) {
    return TeachOptions(
      absolute: absolute ?? this.absolute,
      gridMs: gridMs ?? this.gridMs,
      noiseDeg: noiseDeg ?? this.noiseDeg,
      minHoldMs: minHoldMs ?? this.minHoldMs,
    );
  }
}

class _Seg {
  _Seg({
    required this.move,
    required this.startMs,
    required this.endMs,
    required this.startPos,
    required this.endPos,
    required this.startAbs,
    required this.endAbs,
  });

  bool move;
  final int startMs;
  int endMs;
  final Map<String, int> startPos;
  Map<String, int> endPos;
  final Map<String, int> startAbs;
  Map<String, int> endAbs;
}

/// Turns a hand-recorded trace into blocks.
///
/// This is a keyframe approximation. Relative mode emits `motor.run_for_degrees`
/// for each stretch of motion, plus waits where the motors stayed still.
/// Absolute mode emits `motor.run_to_absolute_position` for the pose at the
/// end of each stretch. Neither mode stores a continuous curve, and absolute
/// mode cannot tell extra full rotations apart because the hub absolute angle
/// wraps around.
List<BlockNode> compileTeach(List<TeachSample> raw, TeachOptions options) {
  final note = options.absolute
      ? 'Teach take: absolute keyframes. Each kept pose becomes motor.run_to_absolute_position. This is not a continuous recording, and turns past half a revolution can collapse.'
      : 'Teach take: relative segments. Motion becomes motor.run_for_degrees plus waits. This is not a continuous curve.';
  final blocks = <BlockNode>[
    BlockNode(id: newId(), op: 'comment', args: {'text': note}),
  ];
  if (raw.isEmpty) {
    blocks.add(
      BlockNode(
        id: newId(),
        op: 'comment',
        args: {'text': 'Recording was empty.'},
      ),
    );
    return blocks;
  }

  final sorted = [...raw]..sort((a, b) => a.tMs.compareTo(b.tMs));
  final t0 = sorted.first.tMs;
  final t1 = sorted.last.tMs;
  final grid = options.gridMs < 20 ? 20 : options.gridMs;
  if (t1 - t0 < grid) {
    blocks.add(
      BlockNode(
        id: newId(),
        op: 'comment',
        args: {'text': 'Recording was shorter than one sample step.'},
      ),
    );
    return blocks;
  }

  final frames = <TeachSample>[];
  var cursor = 0;
  var last = sorted.first;
  for (var t = t0; t <= t1; t += grid) {
    while (cursor < sorted.length && sorted[cursor].tMs <= t) {
      last = sorted[cursor];
      cursor += 1;
    }
    frames.add(
      TeachSample(
        tMs: t,
        motorPos: Map<String, int>.of(last.motorPos),
        motorAbs: Map<String, int>.of(last.motorAbs),
      ),
    );
  }

  final ports = <String>{};
  for (final frame in frames) {
    ports.addAll(frame.motorPos.keys);
    ports.addAll(frame.motorAbs.keys);
  }
  final portList = ports.toList()..sort();
  if (portList.isEmpty) {
    blocks.add(
      BlockNode(
        id: newId(),
        op: 'comment',
        args: {'text': 'No motor positions were in the recording.'},
      ),
    );
    return blocks;
  }

  final segs = <_Seg>[];
  for (var i = 1; i < frames.length; i++) {
    final a = frames[i - 1];
    final b = frames[i];
    var moving = false;
    for (final port in portList) {
      final delta = (b.motorPos[port] ?? a.motorPos[port] ?? 0) - (a.motorPos[port] ?? 0);
      if (delta.abs() >= 1) moving = true;
    }
    if (segs.isEmpty || segs.last.move != moving) {
      segs.add(
        _Seg(
          move: moving,
          startMs: a.tMs,
          endMs: b.tMs,
          startPos: Map<String, int>.of(a.motorPos),
          endPos: Map<String, int>.of(b.motorPos),
          startAbs: Map<String, int>.of(a.motorAbs),
          endAbs: Map<String, int>.of(b.motorAbs),
        ),
      );
    } else {
      segs.last.endMs = b.tMs;
      segs.last.endPos = Map<String, int>.of(b.motorPos);
      segs.last.endAbs = Map<String, int>.of(b.motorAbs);
    }
  }

  for (final seg in segs) {
    if (!seg.move) continue;
    var significant = false;
    for (final port in portList) {
      final delta = (seg.endPos[port] ?? 0) - (seg.startPos[port] ?? 0);
      if (delta.abs() >= options.noiseDeg) significant = true;
    }
    if (!significant) seg.move = false;
  }

  final merged = <_Seg>[];
  for (final seg in segs) {
    if (merged.isNotEmpty && !merged.last.move && !seg.move) {
      merged.last.endMs = seg.endMs;
      merged.last.endPos = seg.endPos;
      merged.last.endAbs = seg.endAbs;
    } else {
      merged.add(seg);
    }
  }

  for (final seg in merged) {
    final dur = seg.endMs - seg.startMs;
    if (!seg.move) {
      if (dur >= options.minHoldMs) blocks.add(_wait(dur));
      continue;
    }
    final moves = <BlockNode>[];
    for (final port in portList) {
      if (options.absolute) {
        final target = seg.endAbs[port];
        final start = seg.startAbs[port];
        if (target == null) continue;
        if (start != null && _shortest(start, target).abs() < options.noiseDeg) continue;
        final delta = start == null ? options.noiseDeg : _shortest(start, target).abs();
        final velocity = _velocity(delta, dur);
        moves.add(
          BlockNode(
            id: newId(),
            op: 'motorAbsolute',
            args: {
              'port': port,
              'position': '$target',
              'velocity': '$velocity',
              'direction': 'SHORTEST_PATH',
            },
          ),
        );
      } else {
        final delta = (seg.endPos[port] ?? 0) - (seg.startPos[port] ?? 0);
        if (delta.abs() < options.noiseDeg) continue;
        moves.add(
          BlockNode(
            id: newId(),
            op: 'motorDegrees',
            args: {
              'port': port,
              'degrees': '$delta',
              'velocity': '${_velocity(delta.abs(), dur)}',
              'stop': 'BRAKE',
            },
          ),
        );
      }
    }
    if (moves.isEmpty) {
      if (dur >= options.minHoldMs) blocks.add(_wait(dur));
      continue;
    }
    if (moves.length == 1) {
      blocks.add(moves.single);
    } else {
      blocks.add(BlockNode(id: newId(), op: 'together', body: moves));
    }
  }

  blocks.add(
    BlockNode(
      id: newId(),
      op: 'comment',
      args: {'text': 'End of teach take. Edit the blocks, then download them to the hub.'},
    ),
  );
  return blocks;
}

BlockNode _wait(int ms) {
  return BlockNode(id: newId(), op: 'wait', args: {'ms': '$ms'});
}

int _velocity(int degrees, int durMs) {
  final dur = durMs <= 0 ? 1 : durMs;
  final raw = (degrees * 1000 / dur).round();
  if (raw < 60) return 60;
  if (raw > 1000) return 1000;
  return raw;
}

int _shortest(int from, int to) {
  var delta = (to - from) % 360;
  if (delta > 180) delta -= 360;
  if (delta < -180) delta += 360;
  return delta;
}

String teachSummary(List<BlockNode> blocks) {
  final motors = blocks.where((b) => b.op == 'motorDegrees' || b.op == 'motorAbsolute').length;
  final groups = blocks.where((b) => b.op == 'together').length;
  final waits = blocks.where((b) => b.op == 'wait').length;
  final inside = blocks.where((b) => b.op == 'together').fold<int>(0, (sum, b) => sum + b.body.length);
  return '${motors + inside} motor moves, $groups simultaneous groups, $waits waits';
}
