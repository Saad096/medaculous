class Shift {
  const Shift({
    required this.id,
    required this.hospital,
    required this.ward,
    required this.specialty,
    required this.shiftType,
    required this.active,
    required this.startedAt,
  });

  final String id;
  final String hospital;
  final String ward;
  final String specialty;
  final String shiftType;
  final bool active;
  final DateTime startedAt;

  factory Shift.fromJson(Map<String, dynamic> json) => Shift(
        id: json['id'] as String,
        hospital: json['hospital'] as String,
        ward: json['ward'] as String,
        specialty: json['specialty'] as String,
        shiftType: json['shift_type'] as String,
        active: json['active'] as bool,
        startedAt: DateTime.parse(json['started_at'] as String),
      );
}

class Patient {
  const Patient({
    required this.id,
    required this.initials,
    required this.age,
    required this.dob,
    required this.sex,
    required this.roomNumber,
    required this.bedNumber,
    required this.diagnosis,
    required this.coMorbids,
    required this.dnar,
    required this.reviewed,
    required this.sortOrder,
    required this.notes,
  });

  final String id;
  final String initials;
  final String age;
  final String dob;
  final String sex;
  final String roomNumber;
  final String bedNumber;
  final String diagnosis;
  final String coMorbids;
  final bool dnar;
  final bool reviewed;
  final int sortOrder;
  final String notes;

  factory Patient.fromJson(Map<String, dynamic> json) => Patient(
        id: json['id'] as String,
        initials: json['initials'] as String,
        age: json['age'] as String,
        dob: json['dob'] as String,
        sex: json['sex'] as String,
        roomNumber: json['room_number'] as String,
        bedNumber: json['bed_number'] as String,
        diagnosis: json['diagnosis'] as String,
        coMorbids: json['co_morbids'] as String,
        dnar: json['dnar'] as bool,
        reviewed: json['reviewed'] as bool,
        sortOrder: json['sort_order'] as int,
        notes: json['notes'] as String,
      );
}

class WardTask {
  const WardTask({
    required this.id,
    required this.patientId,
    required this.title,
    required this.completed,
    required this.priority,
    required this.note,
  });

  final String id;
  final String patientId;
  final String title;
  final bool completed;
  final String priority;
  final String note;

  factory WardTask.fromJson(Map<String, dynamic> json) => WardTask(
        id: json['id'] as String,
        patientId: json['patient_id'] as String,
        title: json['title'] as String,
        completed: json['completed'] as bool,
        priority: json['priority'] as String,
        note: json['note'] as String,
      );
}
