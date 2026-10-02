import 'project.dart';

class FieldSpec {
  const FieldSpec({
    required this.key,
    required this.label,
    required this.kind,
    required this.defaultValue,
    this.choices = const [],
    this.choiceLabels = const [],
    this.width = 72,
  });

  final String key;
  final String label;
  final FieldKind kind;
  final String defaultValue;
  final List<String> choices;
  final List<String> choiceLabels;
  final double width;
}

enum FieldKind { port, integer, text, choice }

class BlockSpec {
  const BlockSpec({
    required this.op,
    required this.category,
    required this.title,
    required this.blurb,
    required this.phrase,
    this.hat = false,
    this.cShape = false,
    this.hasElse = false,
    this.fields = const [],
  });

  final String op;
  final String category;
  final String title;
  final String blurb;
  final String phrase;
  final bool hat;
  final bool cShape;
  final bool hasElse;
  final List<FieldSpec> fields;
}

const ports = ['A', 'B', 'C', 'D', 'E', 'F'];

const _port = FieldSpec(
  key: 'port',
  label: 'port',
  kind: FieldKind.port,
  defaultValue: 'A',
  width: 64,
);

const _stop = FieldSpec(
  key: 'stop',
  label: 'stop',
  kind: FieldKind.choice,
  defaultValue: 'BRAKE',
  choices: ['BRAKE', 'HOLD', 'COAST', 'CONTINUE', 'SMART_BRAKE', 'SMART_COAST'],
  choiceLabels: ['brake', 'hold', 'coast', 'continue', 'smart brake', 'smart coast'],
  width: 120,
);

const _velocity = FieldSpec(
  key: 'velocity',
  label: '°/s',
  kind: FieldKind.integer,
  defaultValue: '500',
  width: 72,
);

const blockSpecs = <BlockSpec>[
  BlockSpec(
    op: 'onStart',
    category: 'events',
    title: 'when program starts',
    blurb: 'Hat block. Another one starts a stack that runs beside the first.',
    phrase: 'when program starts',
    hat: true,
  ),
  BlockSpec(
    op: 'comment',
    category: 'extra',
    title: 'note',
    blurb: 'Kept in the project and written as a Python comment.',
    phrase: 'note {text}',
    fields: [
      FieldSpec(
        key: 'text',
        label: 'note',
        kind: FieldKind.text,
        defaultValue: 'Note',
        width: 220,
      ),
    ],
  ),
  BlockSpec(
    op: 'motorDegrees',
    category: 'motors',
    title: 'run for degrees',
    blurb: 'motor.run_for_degrees. Positive degrees are clockwise looking at the shaft.',
    phrase: 'run motor {port} for {degrees} ° at {velocity} °/s then {stop}',
    fields: [
      _port,
      FieldSpec(key: 'degrees', label: 'degrees', kind: FieldKind.integer, defaultValue: '360'),
      _velocity,
      _stop,
    ],
  ),
  BlockSpec(
    op: 'motorTime',
    category: 'motors',
    title: 'run for time',
    blurb: 'motor.run_for_time. Duration is milliseconds.',
    phrase: 'run motor {port} for {ms} ms at {velocity} °/s then {stop}',
    fields: [
      _port,
      FieldSpec(key: 'ms', label: 'ms', kind: FieldKind.integer, defaultValue: '1000'),
      _velocity,
      _stop,
    ],
  ),
  BlockSpec(
    op: 'motorAbsolute',
    category: 'motors',
    title: 'go to absolute position',
    blurb: 'motor.run_to_absolute_position. The hub absolute angle is about -180 to 179.',
    phrase: 'move motor {port} to absolute {position} ° at {velocity} °/s via {direction}',
    fields: [
      _port,
      FieldSpec(key: 'position', label: 'position', kind: FieldKind.integer, defaultValue: '0'),
      _velocity,
      FieldSpec(
        key: 'direction',
        label: 'direction',
        kind: FieldKind.choice,
        defaultValue: 'SHORTEST_PATH',
        choices: ['SHORTEST_PATH', 'CLOCKWISE', 'COUNTERCLOCKWISE', 'LONGEST_PATH'],
        choiceLabels: ['shortest', 'clockwise', 'counterclockwise', 'longest'],
        width: 150,
      ),
    ],
  ),
  BlockSpec(
    op: 'motorStart',
    category: 'motors',
    title: 'start motor',
    blurb: 'motor.run until another motor command. Negative velocity reverses it.',
    phrase: 'start motor {port} at {velocity} °/s',
    fields: [_port, _velocity],
  ),
  BlockSpec(
    op: 'motorStop',
    category: 'motors',
    title: 'stop motor',
    blurb: 'motor.stop.',
    phrase: 'stop motor {port} with {stop}',
    fields: [_port, _stop],
  ),
  BlockSpec(
    op: 'drive',
    category: 'motors',
    title: 'drive pair',
    blurb:
        'Macro for motor_pair.pair plus move_for_degrees, so the two motors start and stop together. Steering is -100 to 100.',
    phrase: 'drive {left}+{right} for {degrees} ° steering {steering} at {velocity} °/s',
    fields: [
      FieldSpec(key: 'left', label: 'left', kind: FieldKind.port, defaultValue: 'A', width: 64),
      FieldSpec(key: 'right', label: 'right', kind: FieldKind.port, defaultValue: 'B', width: 64),
      FieldSpec(key: 'degrees', label: 'degrees', kind: FieldKind.integer, defaultValue: '360'),
      FieldSpec(key: 'steering', label: 'steering', kind: FieldKind.integer, defaultValue: '0'),
      _velocity,
    ],
  ),
  BlockSpec(
    op: 'wait',
    category: 'control',
    title: 'wait',
    blurb: 'await runloop.sleep_ms.',
    phrase: 'wait {ms} ms',
    fields: [
      FieldSpec(key: 'ms', label: 'ms', kind: FieldKind.integer, defaultValue: '500'),
    ],
  ),
  BlockSpec(
    op: 'waitUntil',
    category: 'sensors',
    title: 'wait until',
    blurb:
        'await runloop.until. Timeout 0 waits without a limit. Distance -1 means nothing is seen. Yaw is in decidegrees.',
    phrase: 'wait until {sensor} {port} {op} {value} within {timeout} ms',
    fields: [
      _sensor,
      _port,
      _op,
      _value,
      FieldSpec(key: 'subject', label: 'variable', kind: FieldKind.text, defaultValue: 'x', width: 88),
      FieldSpec(key: 'timeout', label: 'timeout ms', kind: FieldKind.integer, defaultValue: '0'),
    ],
  ),
  BlockSpec(
    op: 'repeat',
    category: 'control',
    title: 'repeat',
    blurb: 'for loop.',
    phrase: 'repeat {times} times',
    cShape: true,
    fields: [
      FieldSpec(key: 'times', label: 'times', kind: FieldKind.integer, defaultValue: '4', width: 64),
    ],
  ),
  BlockSpec(
    op: 'forever',
    category: 'control',
    title: 'forever',
    blurb: 'while True. A short sleep is added if the body never waits, so the hub can breathe.',
    phrase: 'forever',
    cShape: true,
  ),
  BlockSpec(
    op: 'if',
    category: 'control',
    title: 'if',
    blurb: 'if / else on a sensor or variable.',
    phrase: 'if {sensor} {port} {op} {value}',
    cShape: true,
    hasElse: true,
    fields: [_sensor, _port, _op, _value, FieldSpec(key: 'subject', label: 'variable', kind: FieldKind.text, defaultValue: 'x', width: 88)],
  ),
  BlockSpec(
    op: 'setVar',
    category: 'variables',
    title: 'set variable',
    blurb: 'Assignment. Source can be a number, another variable, a sensor, or math.',
    phrase: 'set {name} to {source} {port} {value} {math} {right}',
    fields: [
      FieldSpec(key: 'name', label: 'name', kind: FieldKind.text, defaultValue: 'speed', width: 90),
      FieldSpec(
        key: 'source',
        label: 'source',
        kind: FieldKind.choice,
        defaultValue: 'number',
        choices: ['number', 'variable', 'reflection', 'distance', 'force', 'color', 'yaw', 'math'],
        choiceLabels: ['number', 'variable', 'reflection', 'distance', 'force', 'color', 'yaw', 'math'],
        width: 120,
      ),
      FieldSpec(key: 'value', label: 'value', kind: FieldKind.text, defaultValue: '50', width: 80),
      _port,
      FieldSpec(
        key: 'math',
        label: 'math',
        kind: FieldKind.choice,
        defaultValue: 'add',
        choices: ['add', 'sub', 'mul', 'div'],
        choiceLabels: ['+', '-', '*', '//'],
        width: 70,
      ),
      FieldSpec(key: 'right', label: 'right', kind: FieldKind.text, defaultValue: '1', width: 72),
    ],
  ),
  BlockSpec(
    op: 'changeVar',
    category: 'variables',
    title: 'change variable',
    blurb: 'Adds a number to a variable.',
    phrase: 'change {name} by {delta}',
    fields: [
      FieldSpec(key: 'name', label: 'name', kind: FieldKind.text, defaultValue: 'speed', width: 90),
      FieldSpec(key: 'delta', label: 'delta', kind: FieldKind.integer, defaultValue: '1'),
    ],
  ),
  BlockSpec(
    op: 'defBlock',
    category: 'myblocks',
    title: 'define my block',
    blurb: 'Defines an async function you can call. The body is hoisted out of the stack.',
    phrase: 'define {name}',
    cShape: true,
    fields: [
      FieldSpec(key: 'name', label: 'name', kind: FieldKind.text, defaultValue: 'setup', width: 120),
    ],
  ),
  BlockSpec(
    op: 'callBlock',
    category: 'myblocks',
    title: 'call my block',
    blurb: 'await your block.',
    phrase: 'call {name}',
    fields: [
      FieldSpec(key: 'name', label: 'name', kind: FieldKind.text, defaultValue: 'setup', width: 120),
    ],
  ),
  BlockSpec(
    op: 'matrixText',
    category: 'hub',
    title: 'show text',
    blurb: 'light_matrix.write.',
    phrase: 'show text {text}',
    fields: [
      FieldSpec(key: 'text', label: 'text', kind: FieldKind.text, defaultValue: 'Hi', width: 140),
    ],
  ),
  BlockSpec(
    op: 'matrixImage',
    category: 'hub',
    title: 'show image',
    blurb: 'light_matrix.show_image.',
    phrase: 'show image {image}',
    fields: [
      FieldSpec(
        key: 'image',
        label: 'image',
        kind: FieldKind.choice,
        defaultValue: 'IMAGE_HAPPY',
        choices: [
          'IMAGE_HAPPY',
          'IMAGE_SMILE',
          'IMAGE_SAD',
          'IMAGE_HEART',
          'IMAGE_YES',
          'IMAGE_NO',
          'IMAGE_ARROW_N',
        ],
        choiceLabels: ['happy', 'smile', 'sad', 'heart', 'yes', 'no', 'arrow north'],
        width: 140,
      ),
    ],
  ),
  BlockSpec(
    op: 'statusLight',
    category: 'hub',
    title: 'hub light',
    blurb: 'light.color on the center button.',
    phrase: 'set hub light to {color}',
    fields: [_color],
  ),
  BlockSpec(
    op: 'beep',
    category: 'hub',
    title: 'beep',
    blurb: 'sound.beep.',
    phrase: 'beep {freq} Hz for {ms} ms at volume {volume}',
    fields: [
      FieldSpec(key: 'freq', label: 'Hz', kind: FieldKind.integer, defaultValue: '440'),
      FieldSpec(key: 'ms', label: 'ms', kind: FieldKind.integer, defaultValue: '200'),
      FieldSpec(key: 'volume', label: 'volume', kind: FieldKind.integer, defaultValue: '80', width: 64),
    ],
  ),
  BlockSpec(
    op: 'stopAll',
    category: 'control',
    title: 'stop stack',
    blurb: 'return from the current stack. Other stacks keep running.',
    phrase: 'stop this stack',
  ),
  BlockSpec(
    op: 'together',
    category: 'extra',
    title: 'together',
    blurb:
        'Starts simple motor, wait, and beep calls together, then waits for all of them. Nested groups inside fall back to one-after-another and are marked in the Python.',
    phrase: 'together',
    cShape: true,
  ),
];

const _sensor = FieldSpec(
  key: 'sensor',
  label: 'sensor',
  kind: FieldKind.choice,
  defaultValue: 'distance',
  choices: ['color', 'reflection', 'distance', 'force', 'pressed', 'button', 'yaw', 'variable'],
  choiceLabels: ['color', 'reflection', 'distance', 'force', 'pressed', 'button', 'yaw', 'variable'],
  width: 120,
);

const _op = FieldSpec(
  key: 'op',
  label: 'op',
  kind: FieldKind.choice,
  defaultValue: 'lt',
  choices: ['eq', 'neq', 'lt', 'gt', 'le', 'ge'],
  choiceLabels: ['=', '≠', '<', '>', '≤', '≥'],
  width: 64,
);

const _value = FieldSpec(
  key: 'value',
  label: 'value',
  kind: FieldKind.text,
  defaultValue: '100',
  width: 88,
);

const _color = FieldSpec(
  key: 'color',
  label: 'color',
  kind: FieldKind.choice,
  defaultValue: 'BLUE',
  choices: [
    'RED',
    'GREEN',
    'BLUE',
    'YELLOW',
    'ORANGE',
    'AZURE',
    'MAGENTA',
    'PURPLE',
    'TURQUOISE',
    'WHITE',
    'BLACK',
  ],
  choiceLabels: [
    'red',
    'green',
    'blue',
    'yellow',
    'orange',
    'azure',
    'magenta',
    'purple',
    'turquoise',
    'white',
    'black',
  ],
  width: 120,
);

const categories = [
  'events',
  'motors',
  'sensors',
  'control',
  'variables',
  'myblocks',
  'hub',
  'extra',
];

const categoryLabels = {
  'events': 'Events',
  'motors': 'Motors',
  'sensors': 'Sensors',
  'control': 'Control',
  'variables': 'Variables',
  'myblocks': 'My blocks',
  'hub': 'Hub',
  'extra': 'Extras',
};

BlockSpec blockSpec(String op) {
  return blockSpecs.firstWhere(
    (spec) => spec.op == op,
    orElse: () => const BlockSpec(
      op: 'comment',
      category: 'extra',
      title: 'unknown',
      blurb: 'This block is not in the catalog.',
      phrase: 'unknown block',
    ),
  );
}

BlockNode freshBlock(String op) {
  final spec = blockSpec(op);
  return BlockNode(
    id: newId(),
    op: op,
    args: {for (final field in spec.fields) field.key: field.defaultValue},
  );
}

bool showField(BlockNode node, FieldSpec field) {
  final sensor = node.args['sensor'];
  final source = node.args['source'];
  if (node.op == 'waitUntil' || node.op == 'if') {
    if (field.key == 'port' && (sensor == 'button' || sensor == 'yaw' || sensor == 'variable')) {
      return false;
    }
    if (field.key == 'op' && sensor == 'pressed') return false;
    if (field.key == 'value' && sensor == 'pressed') return false;
    if (field.key == 'subject' && sensor != 'variable') return false;
  }
  if (node.op == 'setVar') {
    if (field.key == 'port' && !{'reflection', 'distance', 'force', 'color'}.contains(source)) {
      return false;
    }
    if (field.key == 'value' && (source == 'yaw' || source == 'math')) return false;
    if ((field.key == 'math' || field.key == 'right') && source != 'math') return false;
  }
  return true;
}

int asInt(String? raw, int fallback) => int.tryParse((raw ?? '').trim()) ?? fallback;

String portOf(String? raw, {String fallback = 'A'}) {
  final value = (raw ?? fallback).trim().toUpperCase();
  return ports.contains(value) ? value : fallback;
}
