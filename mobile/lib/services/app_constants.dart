class AppConstants {
  // Geographical location where classification was performed (e.g., town, province).
  static const String locationKey = 'classification_location';
  // Backward-compatibility key for previously saved values.
  static const String legacyAddressKey = 'server_address';
  static const List<String> labels = <String>['AX', 'BX', 'CX', 'DX', 'K3'];

  /// Minimum softmax probability required to accept a grade (no analytics below this).
  static const double minClassificationConfidence = 0.80;
}

class LabelLegend {
  final String description;
  final String ntaGrade;

  const LabelLegend({required this.description, required this.ntaGrade});
}

const Map<String, LabelLegend> labelLegend = <String, LabelLegend>{
  'AX': LabelLegend(description: 'Fine quality', ntaGrade: 'NTA Grade A'),
  'BX': LabelLegend(description: 'Good quality', ntaGrade: 'NTA Grade B'),
  'CX': LabelLegend(description: 'Good quality', ntaGrade: 'NTA Grade C'),
  'DX': LabelLegend(description: 'Fair quality', ntaGrade: 'NTA Grade D'),
  'K3': LabelLegend(description: 'Good quality', ntaGrade: 'NTA Grade C'),
  'R': LabelLegend(description: 'Reject', ntaGrade: 'Reject'),
};
