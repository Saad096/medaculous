import 'package:dio/dio.dart';

import '../../../core/network/api_exception.dart';
import '../domain/exam_planner.dart';

// Matches the backend's YYYY-MM-DD date param format. Avoids adding the
// `intl` package for a single format call (see notes_list_screen.dart's
// _formatUpdatedAt for the same convention).
String _dateStr(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Thin wrapper over backend/app/api/v1/exam_planner.py.
class ExamPlannerApi {
  ExamPlannerApi(this._dio);

  final Dio _dio;

  Future<T> _call<T>(Future<Response> Function() request, T Function(dynamic) onOk) async {
    try {
      final response = await request();
      return onOk(response.data);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<List<ExamInfo>> listExams() {
    return _call(
      () => _dio.get('/exam-planner/exams'),
      (data) => (data as List<dynamic>).map((e) => ExamInfo.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }

  Future<ExamSetup?> getSetup() {
    return _call(
      () => _dio.get('/exam-planner/setup'),
      (data) => data == null ? null : ExamSetup.fromJson(data as Map<String, dynamic>),
    );
  }

  Future<ExamSetup> createSetup({
    required String examId,
    String customExamName = '',
    required DateTime targetExamDate,
    required DateTime startDate,
    required String prepLevel,
    required int dailyStudyMinutes,
    required List<int> availableDaysPerWeek,
    required String studyPreference,
    required String goal,
    required String studyMode,
  }) {
    return _call(
      () => _dio.post(
        '/exam-planner/setup',
        data: {
          'exam_id': examId,
          'custom_exam_name': customExamName,
          'target_exam_date': _dateStr(targetExamDate),
          'start_date': _dateStr(startDate),
          'prep_level': prepLevel,
          'daily_study_minutes': dailyStudyMinutes,
          'available_days_per_week': availableDaysPerWeek,
          'study_preference': studyPreference,
          'goal': goal,
          'study_mode': studyMode,
        },
        options: Options(receiveTimeout: const Duration(seconds: 30)),
      ),
      (data) => ExamSetup.fromJson(data as Map<String, dynamic>),
    );
  }

  Future<void> deleteSetup() {
    return _call(() => _dio.delete('/exam-planner/setup'), (_) {});
  }

  Future<List<ExamSession>> getSchedule({required DateTime start, required DateTime end}) {
    return _call(
      () => _dio.get('/exam-planner/schedule', queryParameters: {'start_date': _dateStr(start), 'end_date': _dateStr(end)}),
      (data) => (data as List<dynamic>).map((e) => ExamSession.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }

  Future<List<ExamSession>> getTodaySchedule() {
    return _call(
      () => _dio.get('/exam-planner/schedule/today'),
      (data) => (data as List<dynamic>).map((e) => ExamSession.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }

  Future<ExamSession> updateSession(String id, {String? status, int? actualMinutesSpent, int? confidenceRating}) {
    return _call(
      () => _dio.patch('/exam-planner/sessions/$id', data: {
        'status': ?status,
        'actual_minutes_spent': ?actualMinutesSpent,
        'confidence_rating': ?confidenceRating,
      }),
      (data) => ExamSession.fromJson(data as Map<String, dynamic>),
    );
  }

  Future<int> runCatchup() {
    return _call(
      () => _dio.post('/exam-planner/catchup'),
      (data) => (data as Map<String, dynamic>)['redistributed_count'] as int,
    );
  }

  Future<PlannerStreak?> getStreak() async {
    try {
      final response = await _dio.get('/exam-planner/streak');
      return PlannerStreak.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      throw ApiException.fromDioException(e);
    }
  }

  Future<PlannerStats?> getStats() async {
    try {
      final response = await _dio.get('/exam-planner/stats');
      return PlannerStats.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      throw ApiException.fromDioException(e);
    }
  }

  Future<List<Specialty>> getSpecialties() {
    return _call(
      () => _dio.get('/exam-planner/specialties'),
      (data) => (data as List<dynamic>).map((e) => Specialty.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }

  Future<Topic> updateTopicNotes(String topicId, String notes) {
    return _call(
      () => _dio.patch('/exam-planner/topics/$topicId/notes', data: {'notes': notes}),
      (data) => Topic.fromJson(data as Map<String, dynamic>),
    );
  }

  /// Partial update of a topic's personal notes, checklist items, and
  /// bookmark flag (backs the planner's Notes tab).
  Future<Topic> updateTopicMeta(
    String topicId, {
    String? notes,
    List<ChecklistItem>? checklists,
    bool? isBookmarked,
    String? difficulty,
  }) {
    return _call(
      () => _dio.patch('/exam-planner/topics/$topicId/meta', data: {
        'notes': ?notes,
        if (checklists != null) 'checklists': checklists.map((c) => c.toJson()).toList(),
        'is_bookmarked': ?isBookmarked,
        'difficulty': ?difficulty,
      }),
      (data) => Topic.fromJson(data as Map<String, dynamic>),
    );
  }

  Future<Specialty> createSpecialty(String title) {
    return _call(
      () => _dio.post('/exam-planner/specialties', data: {'title': title}),
      (data) => Specialty.fromJson(data as Map<String, dynamic>),
    );
  }

  Future<Topic> createTopic(String specialtyId, {required String title, int estimatedMinutes = 45}) {
    return _call(
      () => _dio.post(
        '/exam-planner/specialties/$specialtyId/topics',
        data: {'title': title, 'estimated_minutes': estimatedMinutes},
      ),
      (data) => Topic.fromJson(data as Map<String, dynamic>),
    );
  }

  Future<void> deleteTopic(String topicId) {
    return _call(() => _dio.delete('/exam-planner/topics/$topicId'), (_) {});
  }

  /// Rebuilds all pending sessions from today (used after syllabus edits).
  Future<int> regenerateSchedule() {
    return _call(
      () => _dio.post(
        '/exam-planner/schedule/regenerate',
        options: Options(receiveTimeout: const Duration(seconds: 30)),
      ),
      (data) => (data as Map<String, dynamic>)['created_sessions'] as int,
    );
  }
}
