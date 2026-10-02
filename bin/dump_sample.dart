import 'dart:io';

import 'package:spike_prime_studio/src/codegen/python_gen.dart';
import 'package:spike_prime_studio/src/model/project.dart';

void main() {
  final project = sampleGettingStarted();
  Directory('examples').createSync();
  File('examples/getting_started.spstudio.json').writeAsStringSync('${ProjectFile.encodePretty(project)}\n');
  File('examples/getting_started.py').writeAsStringSync(generatePython(project));
  stdout.writeln('Wrote examples/getting_started.spstudio.json and examples/getting_started.py');
}
