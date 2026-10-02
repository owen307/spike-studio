import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../model/project.dart';

class ProjectStore {
  static const projectsKey = 'spstudio.projects.v1';
  static const onboardKey = 'spstudio.onboarded';

  static Future<List<StudioProject>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(projectsKey);
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return [];
    return decoded
        .whereType<Map>()
        .map((item) => StudioProject.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  static Future<void> save(List<StudioProject> projects) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(projects.map((project) => project.toJson()).toList());
    await prefs.setString(projectsKey, raw);
  }

  static Future<bool> onboarded() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(onboardKey) ?? false;
  }

  static Future<void> setOnboarded() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(onboardKey, true);
  }
}
