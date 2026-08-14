import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/providers/auth_providers.dart';
import '../../data/notes_api.dart';

final notesApiProvider = Provider<NotesApi>(
  (ref) => NotesApi(ref.read(apiClientProvider).dio),
);
