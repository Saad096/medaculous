import 'package:dio/dio.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/offline_cache.dart';
import '../domain/ward.dart';

/// Thin wrapper over backend/app/api/v1/ward.py.
class WardApi {
  WardApi(this._dio);

  final Dio _dio;

  Future<T> _call<T>(Future<Response> Function() request, T Function(dynamic) onOk) async {
    try {
      final response = await request();
      return onOk(response.data);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  // Available offline via the last-loaded copy (owner feedback, 2026-09-14)
  // — creating/editing a patient or task still requires being online. See
  // core/network/offline_cache.dart.
  Future<Shift?> getShift() {
    return cachedApiGet(_dio, '/ward/shift', 'ward_shift', (data) => data == null ? null : Shift.fromJson(data as Map<String, dynamic>));
  }

  Future<Shift> startShift({
    required String hospital,
    required String ward,
    required String specialty,
    required String shiftType,
  }) {
    return _call(
      () => _dio.post('/ward/shift', data: {'hospital': hospital, 'ward': ward, 'specialty': specialty, 'shift_type': shiftType}),
      (data) => Shift.fromJson(data as Map<String, dynamic>),
    );
  }

  Future<Shift> completeShift(String shiftId) {
    return _call(
      () => _dio.patch('/ward/shift/$shiftId/complete'),
      (data) => Shift.fromJson(data as Map<String, dynamic>),
    );
  }

  Future<void> wipeShiftData() {
    return _call(() => _dio.delete('/ward/wipe'), (_) {});
  }

  Future<List<Patient>> listPatients() {
    return cachedApiGet(
      _dio,
      '/ward/patients',
      'ward_patients',
      (data) => (data as List<dynamic>).map((e) => Patient.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }

  Future<Patient> createPatient({
    required String initials,
    String age = '',
    String sex = 'Male',
    String roomNumber = '',
    String bedNumber = '',
    String diagnosis = '',
    String coMorbids = '',
    bool dnar = false,
    String notes = '',
  }) {
    return _call(
      () => _dio.post('/ward/patients', data: {
        'initials': initials,
        'age': age,
        'sex': sex,
        'room_number': roomNumber,
        'bed_number': bedNumber,
        'diagnosis': diagnosis,
        'co_morbids': coMorbids,
        'dnar': dnar,
        'notes': notes,
      }),
      (data) => Patient.fromJson(data as Map<String, dynamic>),
    );
  }

  Future<Patient> updatePatient(String id, Map<String, dynamic> updates) {
    return _call(
      () => _dio.patch('/ward/patients/$id', data: updates),
      (data) => Patient.fromJson(data as Map<String, dynamic>),
    );
  }

  Future<void> deletePatient(String id) {
    return _call(() => _dio.delete('/ward/patients/$id'), (_) {});
  }

  Future<List<WardTask>> listTasks() {
    return cachedApiGet(
      _dio,
      '/ward/tasks',
      'ward_tasks',
      (data) => (data as List<dynamic>).map((e) => WardTask.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }

  Future<WardTask> createTask({required String patientId, required String title, String priority = 'Medium', String note = ''}) {
    return _call(
      () => _dio.post('/ward/tasks', data: {'patient_id': patientId, 'title': title, 'priority': priority, 'note': note}),
      (data) => WardTask.fromJson(data as Map<String, dynamic>),
    );
  }

  Future<WardTask> updateTask(String id, Map<String, dynamic> updates) {
    return _call(
      () => _dio.patch('/ward/tasks/$id', data: updates),
      (data) => WardTask.fromJson(data as Map<String, dynamic>),
    );
  }

  Future<void> deleteTask(String id) {
    return _call(() => _dio.delete('/ward/tasks/$id'), (_) {});
  }
}
