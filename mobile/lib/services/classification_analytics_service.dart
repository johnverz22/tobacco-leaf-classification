import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'app_constants.dart';

class ClassificationAnalyticsService {
  static const String _counterPrefix = 'class_count_';
  static const String _recordsKey = 'class_records';

  Future<void> recordClassification({
    required String label,
    required double confidence,
  }) async {
    if (!AppConstants.labels.contains(label)) return;
    final prefs = await SharedPreferences.getInstance();
    final location =
        prefs.getString(AppConstants.locationKey) ??
        prefs.getString(AppConstants.legacyAddressKey) ??
        '';

    final counterKey = '$_counterPrefix$label';
    final current = prefs.getInt(counterKey) ?? 0;
    await prefs.setInt(counterKey, current + 1);

    final records = prefs.getStringList(_recordsKey) ?? <String>[];
    final record = jsonEncode(<String, dynamic>{
      'timestamp': DateTime.now().toIso8601String(),
      'label': label,
      'confidence': confidence,
      'description': labelLegend[label]?.description ?? '',
      'nta_grade': labelLegend[label]?.ntaGrade ?? '',
      'location': location,
    });
    records.add(record);
    await prefs.setStringList(_recordsKey, records);
  }

  Future<Map<String, int>> getCounters() async {
    final prefs = await SharedPreferences.getInstance();
    final map = <String, int>{};
    for (final label in AppConstants.labels) {
      map[label] = prefs.getInt('$_counterPrefix$label') ?? 0;
    }
    return map;
  }

  Future<int> getTotalClassifications() async {
    final counters = await getCounters();
    return counters.values.fold<int>(0, (sum, v) => sum + v);
  }

  Future<String> buildExportJson() async {
    final prefs = await SharedPreferences.getInstance();
    final location =
        prefs.getString(AppConstants.locationKey) ??
        prefs.getString(AppConstants.legacyAddressKey) ??
        '';
    final counters = await getCounters();
    final recordStrings = prefs.getStringList(_recordsKey) ?? <String>[];
    final records = recordStrings
        .map((e) => jsonDecode(e) as Map<String, dynamic>)
        .toList();

    final payload = <String, dynamic>{
      'schema': 'tobacco_analytics_v1',
      'location': location,
      'labels': AppConstants.labels,
      'legend': <String, Map<String, String>>{
        for (final entry in labelLegend.entries)
          entry.key: <String, String>{
            'description': entry.value.description,
            'nta_grade': entry.value.ntaGrade,
          },
      },
      'counters': counters,
      'total_classifications': counters.values.fold<int>(
        0,
        (sum, v) => sum + v,
      ),
      'records': records,
      'generated_at': DateTime.now().toIso8601String(),
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  Future<void> resetAllAnalytics() async {
    final prefs = await SharedPreferences.getInstance();
    for (final label in AppConstants.labels) {
      await prefs.remove('$_counterPrefix$label');
    }
    await prefs.remove(_recordsKey);
  }
}
