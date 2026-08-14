import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

enum ChatMode { auto, ward, er, exam }

extension ChatModeX on ChatMode {
  String get apiValue => name;

  String get label => switch (this) {
    ChatMode.auto => 'Auto',
    ChatMode.ward => 'Ward',
    ChatMode.er => 'ER',
    ChatMode.exam => 'Exam Prep',
  };

  IconData get icon => switch (this) {
    ChatMode.auto => Icons.auto_awesome_rounded,
    ChatMode.ward => Icons.local_hospital_rounded,
    ChatMode.er => Icons.warning_amber_rounded,
    ChatMode.exam => Icons.school_rounded,
  };

  Color get accentColor => switch (this) {
    ChatMode.auto => AppColors.primary,
    ChatMode.ward => AppColors.wardIcon,
    ChatMode.er => AppColors.danger,
    ChatMode.exam => AppColors.examPlannerIcon,
  };
}

class ChatMessage {
  const ChatMessage({required this.role, required this.content});

  final String role; // 'user' | 'assistant'
  final String content;

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    role: json['role'] as String,
    content: json['content'] as String,
  );
}

class ConversationSummary {
  const ConversationSummary({
    required this.id,
    required this.mode,
    required this.title,
    required this.isSaved,
    required this.updatedAt,
  });

  final String id;
  final ChatMode mode;
  final String title;
  final bool isSaved;
  final DateTime updatedAt;

  factory ConversationSummary.fromJson(Map<String, dynamic> json) =>
      ConversationSummary(
        id: json['id'] as String,
        mode: ChatMode.values.byName(json['mode'] as String),
        title: json['title'] as String,
        isSaved: json['is_saved'] as bool,
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );
}

class ConversationDetail extends ConversationSummary {
  const ConversationDetail({
    required super.id,
    required super.mode,
    required super.title,
    required super.isSaved,
    required super.updatedAt,
    required this.messages,
  });

  final List<ChatMessage> messages;

  factory ConversationDetail.fromJson(Map<String, dynamic> json) =>
      ConversationDetail(
        id: json['id'] as String,
        mode: ChatMode.values.byName(json['mode'] as String),
        title: json['title'] as String,
        isSaved: json['is_saved'] as bool,
        updatedAt: DateTime.parse(json['updated_at'] as String),
        messages: (json['messages'] as List<dynamic>)
            .map((m) => ChatMessage.fromJson(m as Map<String, dynamic>))
            .toList(),
      );
}

/// Events emitted while a chat stream is in flight. The backend's first line
/// carries the conversation id (needed on the very first turn, before it was
/// known client-side) — see backend/app/api/v1/ai.py `event_stream()`.
sealed class ChatStreamEvent {}

class ChatStreamStarted extends ChatStreamEvent {
  ChatStreamStarted(this.conversationId);
  final String conversationId;
}

class ChatStreamDelta extends ChatStreamEvent {
  ChatStreamDelta(this.text);
  final String text;
}
