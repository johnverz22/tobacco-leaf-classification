import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/app_constants.dart' show AppConstants, labelLegend;
import '../services/classification_analytics_service.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final TextEditingController _controller = TextEditingController();
  final ClassificationAnalyticsService _analytics =
      ClassificationAnalyticsService();
  bool _loading = true;
  Map<String, int> _counters = <String, int>{};
  int _total = 0;

  @override
  void initState() {
    super.initState();
    _loadAddress();
  }

  Future<void> _loadAddress() async {
    final prefs = await SharedPreferences.getInstance();
    _controller.text =
        prefs.getString(AppConstants.locationKey) ??
        prefs.getString(AppConstants.legacyAddressKey) ??
        '';
    _counters = await _analytics.getCounters();
    _total = _counters.values.fold<int>(0, (sum, v) => sum + v);
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.locationKey, _controller.text.trim());
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  Future<void> _copyAnalyticsJson() async {
    final payload = await _analytics.buildExportJson();
    await Clipboard.setData(ClipboardData(text: payload));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Analytics JSON copied'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _shareAnalyticsJson() async {
    final payload = await _analytics.buildExportJson();
    await Share.share(payload, subject: 'Tobacco Classification Analytics');
  }

  Future<void> _resetAnalytics() async {
    await _analytics.resetAllAnalytics();
    await _loadAddress();
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  List<Widget> _legendRows(ColorScheme cs) {
    const order = <String>[...AppConstants.labels, 'R'];
    final rows = <Widget>[];
    for (final key in order) {
      final legend = labelLegend[key];
      if (legend == null) continue;
      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                alignment: Alignment.centerLeft,
                child: Text(
                  key,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: cs.primary,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  '${legend.description} (${legend.ntaGrade})',
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.35,
                    color: cs.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return rows;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Scaffold(
      backgroundColor: cs.surface,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomInset),
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                child: Container(
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: cs.outlineVariant),
                  ),
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Location (Town, Province)',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _controller,
                        style: TextStyle(color: cs.onSurface),
                        textInputAction: TextInputAction.done,
                        decoration: InputDecoration(
                          hintText: 'e.g. Candon City, Ilocos Sur',
                          hintStyle: TextStyle(color: cs.onSurfaceVariant),
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Grade legend',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Same labels and text as on classification results.',
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 10),
                      ..._legendRows(cs),
                      const SizedBox(height: 20),
                      Text(
                        'Classification counter: $_total',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: AppConstants.labels
                            .map(
                              (label) => Chip(
                                backgroundColor: cs.surface,
                                label: Text(
                                  '$label: ${_counters[label] ?? 0}',
                                  style: TextStyle(color: cs.onSurface),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: _copyAnalyticsJson,
                          child: const Text('Copy analytics JSON'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: _shareAnalyticsJson,
                          child: const Text('Share analytics JSON'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: _resetAnalytics,
                          child: const Text('Reset analytics'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _save,
                          child: const Text('Save'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
