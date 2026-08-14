class DrugSummary {
  const DrugSummary({
    required this.id,
    required this.genericName,
    required this.drugClass,
    required this.therapeuticArea,
    required this.brandNames,
  });

  final String id;
  final String genericName;
  final String drugClass;
  final String therapeuticArea;
  final String brandNames;

  factory DrugSummary.fromJson(Map<String, dynamic> json) => DrugSummary(
    id: json['id'] as String,
    genericName: json['generic_name'] as String,
    drugClass: json['drug_class'] as String,
    therapeuticArea: json['therapeutic_area'] as String,
    brandNames: json['brand_names'] as String,
  );
}

/// System -> Class -> drugs, as returned by GET /formulary/tree.
typedef FormularyTree = Map<String, Map<String, List<DrugSummary>>>;

FormularyTree parseFormularyTree(Map<String, dynamic> json) {
  return json.map((system, classes) {
    final classMap = (classes as Map<String, dynamic>).map((className, drugs) {
      final list = (drugs as List<dynamic>)
          .map((e) => DrugSummary.fromJson(e as Map<String, dynamic>))
          .toList();
      return MapEntry(className, list);
    });
    return MapEntry(system, classMap);
  });
}

class DrugProfile {
  const DrugProfile({
    required this.id,
    required this.genericName,
    required this.drugClass,
    required this.therapeuticArea,
    required this.brandNames,
    required this.mechanismOfAction,
    required this.indications,
    required this.dosage,
    required this.contraindications,
    required this.adverseEffects,
    required this.drugInteractions,
    required this.pregnancyLactation,
    required this.monitoringParameters,
    required this.pharmacokinetics,
    required this.clinicalNotes,
    required this.isAiGenerated,
  });

  final String id;
  final String genericName;
  final String drugClass;
  final String therapeuticArea;
  final String brandNames;
  final String mechanismOfAction;
  final String indications;
  final String dosage;
  final String contraindications;
  final String adverseEffects;
  final String drugInteractions;
  final String pregnancyLactation;
  final String monitoringParameters;
  final String pharmacokinetics;
  final String clinicalNotes;
  final bool isAiGenerated;

  factory DrugProfile.fromJson(Map<String, dynamic> json) => DrugProfile(
    id: json['id'] as String,
    genericName: json['generic_name'] as String,
    drugClass: json['drug_class'] as String,
    therapeuticArea: json['therapeutic_area'] as String,
    brandNames: json['brand_names'] as String,
    mechanismOfAction: json['mechanism_of_action'] as String,
    indications: json['indications'] as String,
    dosage: json['dosage'] as String,
    contraindications: json['contraindications'] as String,
    adverseEffects: json['adverse_effects'] as String,
    drugInteractions: json['drug_interactions'] as String,
    pregnancyLactation: json['pregnancy_lactation'] as String,
    monitoringParameters: json['monitoring_parameters'] as String,
    pharmacokinetics: json['pharmacokinetics'] as String,
    clinicalNotes: json['clinical_notes'] as String,
    isAiGenerated: json['is_ai_generated'] as bool,
  );
}

class SearchOrCreateResult {
  const SearchOrCreateResult({
    required this.isValidDrug,
    required this.profile,
    required this.message,
  });

  final bool isValidDrug;
  final DrugProfile? profile;
  final String message;

  factory SearchOrCreateResult.fromJson(Map<String, dynamic> json) =>
      SearchOrCreateResult(
        isValidDrug: json['is_valid_drug'] as bool,
        profile: json['profile'] != null
            ? DrugProfile.fromJson(json['profile'] as Map<String, dynamic>)
            : null,
        message: json['message'] as String? ?? '',
      );
}
