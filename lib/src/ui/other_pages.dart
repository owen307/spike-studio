import 'package:flutter/material.dart';

import '../hub/mock_hub.dart';
import '../protocol/spike_codec.dart';
import '../state/studio_controller.dart';
import '../teach/teach.dart';
import 'theme.dart';

class TeachPage extends StatelessWidget {
  const TeachPage({super.key, required this.controller});

  final StudioController controller;

  @override
  Widget build(BuildContext context) {
    final options = controller.teachOptions;
    final mock = controller.hub is MockHubLink ? controller.hub as MockHubLink : null;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Move the robot by hand while recording. Studio samples motor positions and turns the trace into blocks you can edit. '
          'Relative mode makes run-for-degrees segments plus waits. Absolute mode makes go-to-position keyframes. '
          'Neither one is a continuous curve: short wiggles under the noise setting are dropped, and absolute mode cannot see extra full turns.',
        ),
        const SizedBox(height: 8),
        const Text(
          'Teach is for authoring. In a match the robot has to run the downloaded program by itself.',
          style: TextStyle(color: studioAmber),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: controller.toggleRecord,
              icon: Icon(controller.recording ? Icons.stop : Icons.fiber_manual_record),
              label: Text(controller.recording ? 'Stop recording' : 'Record'),
            ),
            OutlinedButton(onPressed: controller.clearTake, child: const Text('Clear take')),
            FilledButton(
              onPressed: () => controller.applyTeach(replace: false),
              child: const Text('Append blocks'),
            ),
            OutlinedButton(
              onPressed: () => controller.applyTeach(replace: true),
              child: const Text('Replace stack'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text('${controller.take.length} samples', style: const TextStyle(color: studioMuted)),
        const SizedBox(height: 8),
        SizedBox(height: 160, child: _Timeline(samples: controller.take)),
        const SizedBox(height: 12),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('Relative moves')),
            ButtonSegment(value: true, label: Text('Absolute keyframes')),
          ],
          selected: {options.absolute},
          onSelectionChanged: (value) {
            controller.setTeachOptions(options.copyWith(absolute: value.first));
          },
        ),
        const SizedBox(height: 12),
        _SliderRow(
          label: 'Sample step ${options.gridMs} ms',
          value: options.gridMs.toDouble(),
          min: 50,
          max: 400,
          onChanged: (value) => controller.setTeachOptions(options.copyWith(gridMs: value.round())),
        ),
        _SliderRow(
          label: 'Ignore moves under ${options.noiseDeg}°',
          value: options.noiseDeg.toDouble(),
          min: 1,
          max: 45,
          onChanged: (value) => controller.setTeachOptions(options.copyWith(noiseDeg: value.round())),
        ),
        _SliderRow(
          label: 'Keep pauses of at least ${options.minHoldMs} ms',
          value: options.minHoldMs.toDouble(),
          min: 0,
          max: 1000,
          onChanged: (value) => controller.setTeachOptions(options.copyWith(minHoldMs: value.round())),
        ),
        if (mock != null) ...[
          const SizedBox(height: 8),
          const Text('Hand motion on the mock hub', style: TextStyle(fontWeight: FontWeight.w700)),
          const Text(
            'Drag these while recording. A real hub uses the positions it streams instead.',
            style: TextStyle(color: studioMuted),
          ),
          _SliderRow(
            label: 'Motor A ${mock.current.port('A').position ?? 0}°',
            value: (mock.current.port('A').position ?? 0).toDouble(),
            min: -720,
            max: 720,
            onChanged: (value) => mock.setMotor('A', value.round()),
          ),
          _SliderRow(
            label: 'Motor B ${mock.current.port('B').position ?? 0}°',
            value: (mock.current.port('B').position ?? 0).toDouble(),
            min: -720,
            max: 720,
            onChanged: (value) => mock.setMotor('B', value.round()),
          ),
          _SliderRow(
            label: 'Distance C ${mock.current.port('C').distanceMm ?? 0} mm',
            value: (mock.current.port('C').distanceMm ?? 0).toDouble(),
            min: 40,
            max: 2000,
            onChanged: (value) => mock.setDistance(value.round()),
          ),
        ],
      ],
    );
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline({required this.samples});
  final List<TeachSample> samples;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: studioPanel,
        border: Border.all(color: studioLine),
        borderRadius: BorderRadius.circular(8),
      ),
      child: CustomPaint(
        painter: _TimelinePainter(samples),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _TimelinePainter extends CustomPainter {
  _TimelinePainter(this.samples);
  final List<TeachSample> samples;

  @override
  void paint(Canvas canvas, Size size) {
    final axis = Paint()..color = studioLine;
    canvas.drawLine(Offset(8, size.height - 16), Offset(size.width - 8, size.height - 16), axis);
    if (samples.length < 2) return;
    final t0 = samples.first.tMs.toDouble();
    final t1 = samples.last.tMs.toDouble().clamp(t0 + 1, double.infinity);
    final ports = <String>{};
    for (final sample in samples) {
      ports.addAll(sample.motorPos.keys);
    }
    final colors = [studioAccent, studioAmber, const Color(0xFF7AA2FF), const Color(0xFFE58AB8)];
    var index = 0;
    for (final port in ports) {
      final paint = Paint()
        ..color = colors[index % colors.length]
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      final path = Path();
      var started = false;
      var min = 0.0;
      var max = 1.0;
      for (final sample in samples) {
        final value = (sample.motorPos[port] ?? 0).toDouble();
        if (value < min) min = value;
        if (value > max) max = value;
      }
      final span = (max - min).abs() < 1 ? 1.0 : (max - min);
      for (final sample in samples) {
        final x = 8 + (sample.tMs - t0) / (t1 - t0) * (size.width - 16);
        final y = 12 + (1 - ((sample.motorPos[port] ?? 0) - min) / span) * (size.height - 36);
        if (!started) {
          path.moveTo(x, y);
          started = true;
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, paint);
      index += 1;
    }
  }

  @override
  bool shouldRepaint(covariant _TimelinePainter oldDelegate) => oldDelegate.samples != samples;
}

class HubPage extends StatelessWidget {
  const HubPage({super.key, required this.controller});

  final StudioController controller;

  @override
  Widget build(BuildContext context) {
    final live = controller.live;
    final mock = controller.hub.isMock;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: true, label: Text('Mock hub')),
            ButtonSegment(value: false, label: Text('Bluetooth')),
          ],
          selected: {mock},
          onSelectionChanged: (value) {
            if (value.first) {
              controller.useMock();
            } else {
              controller.useRadio();
            }
          },
        ),
        const SizedBox(height: 12),
        Text(live.status),
        if (live.firmware != null) Text('Firmware ${live.firmware}', style: const TextStyle(color: studioMuted)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            FilledButton(onPressed: controller.scan, child: const Text('Scan')),
            OutlinedButton(onPressed: controller.disconnectHub, child: const Text('Disconnect')),
            OutlinedButton(onPressed: controller.openOnboarding, child: const Text('Pairing notes')),
          ],
        ),
        const SizedBox(height: 12),
        if (!mock)
          const Text(
            'Look for a device that advertises service 0000fd02. Hubs flashed with Pybricks, or hubs that only speak the older LWP3 service, will not complete this handshake.',
            style: TextStyle(color: studioMuted),
          ),
        for (final item in controller.found)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(item.name),
            subtitle: Text(
              '${item.confirmed ? 'SPIKE App 3 service' : 'Name looks like a hub'}'
              '${item.rssi == null ? '' : ' · ${item.rssi} dBm'}',
            ),
            trailing: FilledButton(
              onPressed: () => controller.connectHub(item),
              child: const Text('Connect'),
            ),
          ),
        const SizedBox(height: 8),
        Text('Battery ${live.battery ?? '-'}%    Face ${live.face ?? '-'}'),
        Text('Yaw ${live.yaw ?? '-'}   Pitch ${live.pitch ?? '-'}   Roll ${live.roll ?? '-'}'),
        const SizedBox(height: 8),
        _IntervalSlider(onSelected: controller.setNotify),
        Text('Program slot ${controller.project?.slot ?? 0}'),
        Slider(
          value: (controller.project?.slot ?? 0).toDouble(),
          min: 0,
          max: 19,
          divisions: 19,
          label: '${controller.project?.slot ?? 0}',
          onChanged: (value) => controller.setSlot(value.round()),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final port in live.ports) _PortCard(port: port),
          ],
        ),
        if (live.matrix.length == 25) ...[
          const SizedBox(height: 12),
          const Text('Light matrix'),
          const SizedBox(height: 6),
          _Matrix(pixels: live.matrix),
        ],
      ],
    );
  }
}

class _PortCard extends StatelessWidget {
  const _PortCard({required this.port});
  final PortReading port;

  @override
  Widget build(BuildContext context) {
    final detail = switch (port.kind) {
      'motor' =>
        '${motorTypeName(port.deviceType ?? 0)}\nposition ${port.position ?? '-'}°\nabsolute ${port.absPosition ?? '-'}°\nspeed ${port.speed ?? '-'}',
      'force' => 'force ${port.force ?? '-'}  ${port.pressed == true ? 'pressed' : 'released'}',
      'color' =>
        '${colorNames[port.color] ?? port.color ?? '-'}\nrgb ${port.red ?? '-'} ${port.green ?? '-'} ${port.blue ?? '-'}',
      'distance' => port.distanceMm == null
          ? 'no reading'
          : (port.distanceMm! < 0 ? 'nothing seen' : '${port.distanceMm} mm'),
      'empty' => 'empty',
      _ => port.kind,
    };
    return Container(
      width: 180,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: studioPanel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: studioLine),
      ),
      child: Text('Port ${port.letter}\n$detail'),
    );
  }
}

class _Matrix extends StatelessWidget {
  const _Matrix({required this.pixels});
  final List<int> pixels;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 140,
      height: 140,
      child: GridView.count(
        crossAxisCount: 5,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          for (final pixel in pixels)
            Container(
              margin: const EdgeInsets.all(2),
              color: studioAccent.withValues(alpha: (pixel.clamp(0, 9)) / 9),
            ),
        ],
      ),
    );
  }
}

class PythonPage extends StatelessWidget {
  const PythonPage({super.key, required this.controller});

  final StudioController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            spacing: 8,
            children: [
              FilledButton(onPressed: controller.copyPython, child: const Text('Copy Python')),
              OutlinedButton(onPressed: () => controller.export(kind: 'py'), child: const Text('Save .py')),
              OutlinedButton(
                onPressed: controller.live.connected ? controller.runOnHub : null,
                child: const Text('Download & run'),
              ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'This is the program.py the hub would receive. It uses the SPIKE App 3 modules: motor, motor_pair, runloop, and the hub package.',
            style: TextStyle(color: studioMuted),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            padding: const EdgeInsets.all(12),
            color: const Color(0xFF0E1116),
            child: SingleChildScrollView(
              child: SelectableText(
                controller.python,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13, height: 1.4),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _IntervalSlider extends StatefulWidget {
  const _IntervalSlider({required this.onSelected});
  final Future<void> Function(int ms) onSelected;

  @override
  State<_IntervalSlider> createState() => _IntervalSliderState();
}

class _IntervalSliderState extends State<_IntervalSlider> {
  double _ms = 200;

  @override
  Widget build(BuildContext context) {
    return _SliderRow(
      label: 'Reading interval ${_ms.round()} ms',
      value: _ms,
      min: 50,
      max: 1000,
      onChanged: (value) => setState(() => _ms = value),
      onChangeEnd: (value) => widget.onSelected(value.round()),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.onChangeEnd,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final clamped = value.clamp(min, max);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label),
        Slider(value: clamped, min: min, max: max, onChanged: onChanged, onChangeEnd: onChangeEnd),
      ],
    );
  }
}
