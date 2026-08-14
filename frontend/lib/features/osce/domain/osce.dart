class OsceStep {
  const OsceStep({
    required this.id,
    required this.slug,
    required this.text,
    required this.hint,
    required this.isKeyStep,
    required this.checked,
  });

  final String id;
  final String slug;
  final String text;
  final String? hint;
  final bool isKeyStep;
  final bool checked;

  OsceStep copyWith({bool? checked}) => OsceStep(
        id: id,
        slug: slug,
        text: text,
        hint: hint,
        isKeyStep: isKeyStep,
        checked: checked ?? this.checked,
      );

  factory OsceStep.fromJson(Map<String, dynamic> json) => OsceStep(
        id: json['id'] as String,
        slug: json['slug'] as String,
        text: json['text'] as String,
        hint: json['hint'] as String?,
        isKeyStep: json['is_key_step'] as bool,
        checked: json['checked'] as bool,
      );
}

class OsceSection {
  const OsceSection({required this.id, required this.title, required this.steps});

  final String id;
  final String title;
  final List<OsceStep> steps;

  OsceSection copyWith({List<OsceStep>? steps}) => OsceSection(id: id, title: title, steps: steps ?? this.steps);

  factory OsceSection.fromJson(Map<String, dynamic> json) => OsceSection(
        id: json['id'] as String,
        title: json['title'] as String,
        steps: (json['steps'] as List<dynamic>).map((e) => OsceStep.fromJson(e as Map<String, dynamic>)).toList(),
      );
}

class OsceStation {
  const OsceStation({
    required this.id,
    required this.slug,
    required this.title,
    required this.category,
    required this.system,
    required this.estimatedTime,
    required this.summary,
    required this.isFavorite,
    required this.completedSteps,
    required this.totalSteps,
    required this.sections,
  });

  final String id;
  final String slug;
  final String title;
  final String category;
  final String system;
  final String estimatedTime;
  final String summary;
  final bool isFavorite;
  final int completedSteps;
  final int totalSteps;
  final List<OsceSection> sections;

  int get progressPercent => totalSteps == 0 ? 0 : ((completedSteps / totalSteps) * 100).round();

  OsceStation copyWith({bool? isFavorite, int? completedSteps, List<OsceSection>? sections}) => OsceStation(
        id: id,
        slug: slug,
        title: title,
        category: category,
        system: system,
        estimatedTime: estimatedTime,
        summary: summary,
        isFavorite: isFavorite ?? this.isFavorite,
        completedSteps: completedSteps ?? this.completedSteps,
        totalSteps: totalSteps,
        sections: sections ?? this.sections,
      );

  factory OsceStation.fromJson(Map<String, dynamic> json) => OsceStation(
        id: json['id'] as String,
        slug: json['slug'] as String,
        title: json['title'] as String,
        category: json['category'] as String,
        system: json['system'] as String,
        estimatedTime: json['estimated_time'] as String,
        summary: json['summary'] as String,
        isFavorite: json['is_favorite'] as bool,
        completedSteps: json['completed_steps'] as int,
        totalSteps: json['total_steps'] as int,
        sections: (json['sections'] as List<dynamic>).map((e) => OsceSection.fromJson(e as Map<String, dynamic>)).toList(),
      );
}

const oscCategories = [
  'All',
  'Favourites',
  'General & Endocrine',
  'Cardiovascular & Respiratory',
  'Abdominal & Gastrointestinal',
  'Neurological & Mental Health',
  'Musculoskeletal & Orthopaedics',
  'ENT & Ophthalmology',
  'Specialities (Paediatrics & Obstetrics)',
];
