class ClinicalReference {
  const ClinicalReference({required this.guideline, required this.details, required this.year, required this.evidenceLevel});

  final String guideline;
  final String details;
  final String year;
  final String evidenceLevel;

  factory ClinicalReference.fromJson(Map<String, dynamic> json) => ClinicalReference(
        guideline: json['guideline'] as String,
        details: json['details'] as String,
        year: json['year'] as String,
        evidenceLevel: json['evidence_level'] as String,
      );
}

class Medication {
  const Medication({
    required this.genericName,
    required this.drugClass,
    required this.brandNames,
    required this.adultDose,
    required this.pediatricDose,
    required this.route,
    required this.frequency,
    required this.maxDailyDose,
    required this.typicalDuration,
    required this.mechanismOfAction,
    required this.sideEffects,
    required this.contraindications,
    required this.interactions,
    required this.pregnancySafety,
    required this.breastfeedingSafety,
    required this.renalAdjustment,
    required this.hepaticAdjustment,
    required this.monitoringRequirements,
    required this.tier,
    required this.rankingRationale,
    required this.clinicalReferences,
  });

  final String genericName;
  final String drugClass;
  final List<String> brandNames;
  final String adultDose;
  final String pediatricDose;
  final String route;
  final String frequency;
  final String maxDailyDose;
  final String typicalDuration;
  final String mechanismOfAction;
  final List<String> sideEffects;
  final List<String> contraindications;
  final List<String> interactions;
  final String pregnancySafety;
  final String breastfeedingSafety;
  final String renalAdjustment;
  final String hepaticAdjustment;
  final String monitoringRequirements;
  final String tier;
  final String rankingRationale;
  final List<ClinicalReference> clinicalReferences;

  factory Medication.fromJson(Map<String, dynamic> json) => Medication(
        genericName: json['generic_name'] as String,
        drugClass: json['drug_class'] as String,
        brandNames: List<String>.from(json['brand_names'] as List),
        adultDose: json['adult_dose'] as String,
        pediatricDose: json['pediatric_dose'] as String,
        route: json['route'] as String,
        frequency: json['frequency'] as String,
        maxDailyDose: json['max_daily_dose'] as String,
        typicalDuration: json['typical_duration'] as String,
        mechanismOfAction: json['mechanism_of_action'] as String,
        sideEffects: List<String>.from(json['side_effects'] as List),
        contraindications: List<String>.from(json['contraindications'] as List),
        interactions: List<String>.from(json['interactions'] as List),
        pregnancySafety: json['pregnancy_safety'] as String,
        breastfeedingSafety: json['breastfeeding_safety'] as String,
        renalAdjustment: json['renal_adjustment'] as String,
        hepaticAdjustment: json['hepatic_adjustment'] as String,
        monitoringRequirements: json['monitoring_requirements'] as String,
        tier: json['tier'] as String,
        rankingRationale: json['ranking_rationale'] as String,
        clinicalReferences: (json['clinical_references'] as List<dynamic>)
            .map((e) => ClinicalReference.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'generic_name': genericName,
        'drug_class': drugClass,
        'brand_names': brandNames,
        'adult_dose': adultDose,
        'pediatric_dose': pediatricDose,
        'route': route,
        'frequency': frequency,
        'max_daily_dose': maxDailyDose,
        'typical_duration': typicalDuration,
        'mechanism_of_action': mechanismOfAction,
        'side_effects': sideEffects,
        'contraindications': contraindications,
        'interactions': interactions,
        'pregnancy_safety': pregnancySafety,
        'breastfeeding_safety': breastfeedingSafety,
        'renal_adjustment': renalAdjustment,
        'hepatic_adjustment': hepaticAdjustment,
        'monitoring_requirements': monitoringRequirements,
        'tier': tier,
        'ranking_rationale': rankingRationale,
        'clinical_references': clinicalReferences
            .map((r) => {
                  'guideline': r.guideline,
                  'details': r.details,
                  'year': r.year,
                  'evidence_level': r.evidenceLevel,
                })
            .toList(),
      };
}

class RecommendationResult {
  const RecommendationResult({
    required this.warningBanner,
    required this.urgentAssessmentRequired,
    required this.urgentAssessmentRationale,
    required this.recommendations,
  });

  final String warningBanner;
  final bool urgentAssessmentRequired;
  final String urgentAssessmentRationale;
  final List<Medication> recommendations;

  factory RecommendationResult.fromJson(Map<String, dynamic> json) => RecommendationResult(
        warningBanner: json['warning_banner'] as String? ?? '',
        urgentAssessmentRequired: json['urgent_assessment_required'] as bool? ?? false,
        urgentAssessmentRationale: json['urgent_assessment_rationale'] as String? ?? '',
        recommendations: (json['recommendations'] as List<dynamic>)
            .map((e) => Medication.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class InteractionResult {
  const InteractionResult({required this.severity, required this.mechanism, required this.management, required this.clinicalTip});

  final String severity;
  final String mechanism;
  final String management;
  final String clinicalTip;

  factory InteractionResult.fromJson(Map<String, dynamic> json) => InteractionResult(
        severity: json['severity'] as String,
        mechanism: json['mechanism'] as String,
        management: json['management'] as String,
        clinicalTip: json['clinical_tip'] as String,
      );
}

class Substitute {
  const Substitute({
    required this.genericName,
    required this.drugClass,
    required this.clinicalIndication,
    required this.therapeuticAdvantage,
    required this.costTier,
  });

  final String genericName;
  final String drugClass;
  final String clinicalIndication;
  final String therapeuticAdvantage;
  final String costTier;

  factory Substitute.fromJson(Map<String, dynamic> json) => Substitute(
        genericName: json['generic_name'] as String,
        drugClass: json['drug_class'] as String,
        clinicalIndication: json['clinical_indication'] as String,
        therapeuticAdvantage: json['therapeutic_advantage'] as String,
        costTier: json['cost_tier'] as String,
      );
}

class FavoriteDrug {
  const FavoriteDrug({required this.id, required this.medication});

  final String id;
  final Medication medication;

  factory FavoriteDrug.fromJson(Map<String, dynamic> json) => FavoriteDrug(
        id: json['id'] as String,
        medication: Medication.fromJson(json['data'] as Map<String, dynamic>),
      );
}
