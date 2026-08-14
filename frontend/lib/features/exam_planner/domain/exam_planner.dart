class ExamInfo {
  const ExamInfo({required this.id, required this.name, required this.fullName, required this.region, required this.description, required this.defaultPrepWeeks});

  final String id;
  final String name;
  final String fullName;
  final String region;
  final String description;
  final int defaultPrepWeeks;

  factory ExamInfo.fromJson(Map<String, dynamic> json) => ExamInfo(
        id: json['id'] as String,
        name: json['name'] as String,
        fullName: json['full_name'] as String,
        region: json['region'] as String,
        description: json['description'] as String,
        defaultPrepWeeks: json['default_prep_weeks'] as int,
      );
}

class ExamSetup {
  const ExamSetup({
    required this.id,
    required this.examId,
    required this.customExamName,
    required this.targetExamDate,
    required this.startDate,
    required this.prepLevel,
    required this.dailyStudyMinutes,
    required this.availableDaysPerWeek,
    required this.studyPreference,
    required this.goal,
    required this.studyMode,
  });

  final String id;
  final String examId;
  final String customExamName;
  final DateTime targetExamDate;
  final DateTime startDate;
  final String prepLevel;
  final int dailyStudyMinutes;
  final List<int> availableDaysPerWeek;
  final String studyPreference;
  final String goal;
  final String studyMode;

  factory ExamSetup.fromJson(Map<String, dynamic> json) => ExamSetup(
        id: json['id'] as String,
        examId: json['exam_id'] as String,
        customExamName: json['custom_exam_name'] as String,
        targetExamDate: DateTime.parse(json['target_exam_date'] as String),
        startDate: DateTime.parse(json['start_date'] as String),
        prepLevel: json['prep_level'] as String,
        dailyStudyMinutes: json['daily_study_minutes'] as int,
        availableDaysPerWeek: List<int>.from(json['available_days_per_week'] as List),
        studyPreference: json['study_preference'] as String,
        goal: json['goal'] as String,
        studyMode: json['study_mode'] as String,
      );
}

class ExamSession {
  const ExamSession({
    required this.id,
    required this.topicId,
    required this.topicTitle,
    required this.specialtyTitle,
    required this.date,
    required this.type,
    required this.revisionIteration,
    required this.estimatedMinutes,
    required this.status,
    required this.confidenceRating,
  });

  final String id;
  final String topicId;
  final String topicTitle;
  final String specialtyTitle;
  final DateTime date;
  final String type;
  final int? revisionIteration;
  final int estimatedMinutes;
  final String status;
  final int? confidenceRating;

  factory ExamSession.fromJson(Map<String, dynamic> json) => ExamSession(
        id: json['id'] as String,
        topicId: json['topic_id'] as String,
        topicTitle: json['topic_title'] as String,
        specialtyTitle: json['specialty_title'] as String,
        date: DateTime.parse(json['date'] as String),
        type: json['type'] as String,
        revisionIteration: json['revision_iteration'] as int?,
        estimatedMinutes: json['estimated_minutes'] as int,
        status: json['status'] as String,
        confidenceRating: json['confidence_rating'] as int?,
      );
}

/// One tick-able item in a topic's personal checklist (stored as JSONB on
/// the backend's ExamTopicMeta.checklists).
class ChecklistItem {
  const ChecklistItem({required this.id, required this.text, required this.done});

  final String id;
  final String text;
  final bool done;

  ChecklistItem copyWith({String? text, bool? done}) =>
      ChecklistItem(id: id, text: text ?? this.text, done: done ?? this.done);

  factory ChecklistItem.fromJson(Map<String, dynamic> json) => ChecklistItem(
        id: json['id'] as String? ?? '',
        text: json['text'] as String? ?? '',
        done: json['done'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {'id': id, 'text': text, 'done': done};
}

class Topic {
  const Topic({
    required this.id,
    required this.key,
    required this.title,
    required this.estimatedMinutes,
    required this.difficulty,
    required this.highYield,
    required this.learningObjectives,
    required this.suggestedResources,
    required this.notes,
    required this.checklists,
    required this.isBookmarked,
    required this.status,
    required this.confidenceRating,
  });

  final String id;
  final String key;
  final String title;
  final int estimatedMinutes;
  final String difficulty;
  final bool highYield;
  final List<String> learningObjectives;
  final List<String> suggestedResources;
  final String notes;
  final List<ChecklistItem> checklists;
  final bool isBookmarked;
  final String status;
  final int confidenceRating;

  bool get isCompleted => status == 'completed';

  factory Topic.fromJson(Map<String, dynamic> json) => Topic(
        id: json['id'] as String,
        key: json['key'] as String,
        title: json['title'] as String,
        estimatedMinutes: json['estimated_minutes'] as int,
        difficulty: json['difficulty'] as String,
        highYield: json['high_yield'] as bool,
        learningObjectives: List<String>.from(json['learning_objectives'] as List),
        suggestedResources: List<String>.from(json['suggested_resources'] as List),
        notes: json['notes'] as String? ?? '',
        checklists: [
          for (final item in json['checklists'] as List? ?? const [])
            if (item is Map<String, dynamic>) ChecklistItem.fromJson(item),
        ],
        isBookmarked: json['is_bookmarked'] as bool? ?? false,
        status: json['status'] as String? ?? 'pending',
        confidenceRating: json['confidence_rating'] as int? ?? 3,
      );
}

class Specialty {
  const Specialty({
    required this.id,
    required this.key,
    required this.title,
    required this.description,
    required this.icon,
    required this.topics,
  });

  final String id;
  final String key;
  final String title;
  final String description;
  final String icon;
  final List<Topic> topics;

  factory Specialty.fromJson(Map<String, dynamic> json) => Specialty(
        id: json['id'] as String,
        key: json['key'] as String,
        title: json['title'] as String,
        description: json['description'] as String,
        icon: json['icon'] as String,
        topics: (json['topics'] as List<dynamic>).map((e) => Topic.fromJson(e as Map<String, dynamic>)).toList(),
      );
}

class PlannerStreak {
  const PlannerStreak({required this.currentStreak, required this.longestStreak, required this.totalStudyDays});

  final int currentStreak;
  final int longestStreak;
  final int totalStudyDays;

  factory PlannerStreak.fromJson(Map<String, dynamic> json) => PlannerStreak(
        currentStreak: json['current_streak'] as int,
        longestStreak: json['longest_streak'] as int,
        totalStudyDays: json['total_study_days'] as int,
      );
}

class PlannerStats {
  const PlannerStats({
    required this.totalTopics,
    required this.completedTopicsCount,
    required this.syllabusProgressPct,
    required this.scheduleProgressPct,
    required this.totalSessions,
    required this.completedSessions,
    required this.readinessScore,
    required this.avgConfidence,
  });

  final int totalTopics;
  final int completedTopicsCount;
  final int syllabusProgressPct;
  final int scheduleProgressPct;
  final int totalSessions;
  final int completedSessions;
  final int readinessScore;
  final double avgConfidence;

  factory PlannerStats.fromJson(Map<String, dynamic> json) => PlannerStats(
        totalTopics: json['total_topics'] as int,
        completedTopicsCount: json['completed_topics_count'] as int,
        syllabusProgressPct: json['syllabus_progress_pct'] as int,
        scheduleProgressPct: json['schedule_progress_pct'] as int,
        totalSessions: json['total_sessions'] as int,
        completedSessions: json['completed_sessions'] as int,
        readinessScore: json['readiness_score'] as int,
        avgConfidence: (json['avg_confidence'] as num).toDouble(),
      );
}
