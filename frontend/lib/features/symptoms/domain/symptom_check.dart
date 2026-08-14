class Diagnosis {
  const Diagnosis({
    required this.condition,
    required this.likelihood,
    required this.explanation,
    required this.redFlags,
    required this.commonCauses,
    required this.nextSteps,
  });

  final String condition;
  final String likelihood;
  final String explanation;
  final String redFlags;
  final String commonCauses;
  final String nextSteps;

  factory Diagnosis.fromJson(Map<String, dynamic> json) => Diagnosis(
    condition: json['condition'] as String,
    likelihood: json['likelihood'] as String,
    explanation: json['explanation'] as String,
    redFlags: json['red_flags'] as String,
    commonCauses: json['common_causes'] as String,
    nextSteps: json['next_steps'] as String,
  );
}

class SymptomCheckResult {
  const SymptomCheckResult({
    required this.clinicalSummary,
    required this.diagnoses,
  });

  final String clinicalSummary;
  final List<Diagnosis> diagnoses;

  factory SymptomCheckResult.fromJson(Map<String, dynamic> json) =>
      SymptomCheckResult(
        clinicalSummary: json['clinical_summary'] as String,
        diagnoses: (json['diagnoses'] as List<dynamic>)
            .map((e) => Diagnosis.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
