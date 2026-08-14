/// Display order for disease-detail sections. Mirrors
/// backend/app/models/disease.py DISEASE_SECTION_ORDER — the backend already
/// orders and omits empty sections, so the client just renders in list order.
const kDiseaseSectionOrder = [
  'Definition',
  'Classification',
  'Signs/Symptoms',
  'Anatomy',
  'Pathophysiology',
  'Approach',
  'Investigations',
  'Diagnosis',
  'Differentials',
  'Patient Advice',
  'Management',
  'Prescribing Information',
  'Calculators',
  'Evidence',
  'Complications',
];

class MedicalSystem {
  const MedicalSystem({
    required this.id,
    required this.name,
    required this.icon,
  });

  final String id;
  final String name;
  final String icon;

  factory MedicalSystem.fromJson(Map<String, dynamic> json) => MedicalSystem(
    id: json['id'] as String,
    name: json['name'] as String,
    icon: json['icon'] as String,
  );
}

class DiseaseSummary {
  const DiseaseSummary({
    required this.id,
    required this.name,
    required this.category,
  });

  final String id;
  final String name;
  final String category;

  factory DiseaseSummary.fromJson(Map<String, dynamic> json) => DiseaseSummary(
    id: json['id'] as String,
    name: json['name'] as String,
    category: json['category'] as String,
  );
}

class DiseaseDetail extends DiseaseSummary {
  const DiseaseDetail({
    required super.id,
    required super.name,
    required super.category,
    required this.systemId,
    required this.sections,
  });

  final String systemId;
  final Map<String, String> sections;

  factory DiseaseDetail.fromJson(Map<String, dynamic> json) => DiseaseDetail(
    id: json['id'] as String,
    name: json['name'] as String,
    category: json['category'] as String,
    systemId: json['system_id'] as String,
    sections: Map<String, String>.from(json['sections'] as Map),
  );
}
