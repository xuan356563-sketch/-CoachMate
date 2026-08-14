enum AiChatMessageRole { user, assistant, local, system }

enum AiChatMessageStatus { draft, sending, sent, failed }

enum AiChatIntent { trainingQuestion, explainPlan, openPlanGenerator }

extension AiChatMessageRoleJson on AiChatMessageRole {
  String get jsonValue => switch (this) {
        AiChatMessageRole.user => 'user',
        AiChatMessageRole.assistant => 'assistant',
        AiChatMessageRole.local => 'local',
        AiChatMessageRole.system => 'system',
      };
}

extension AiChatMessageStatusJson on AiChatMessageStatus {
  String get jsonValue => switch (this) {
        AiChatMessageStatus.draft => 'draft',
        AiChatMessageStatus.sending => 'sending',
        AiChatMessageStatus.sent => 'sent',
        AiChatMessageStatus.failed => 'failed',
      };
}

AiChatMessageRole _roleFromJson(String? value) => switch (value) {
      'assistant' => AiChatMessageRole.assistant,
      'local' => AiChatMessageRole.local,
      'system' => AiChatMessageRole.system,
      _ => AiChatMessageRole.user,
    };

AiChatMessageStatus _statusFromJson(String? value) => switch (value) {
      'draft' => AiChatMessageStatus.draft,
      'sending' => AiChatMessageStatus.sending,
      'failed' => AiChatMessageStatus.failed,
      _ => AiChatMessageStatus.sent,
    };

class AiChatMessage {
  const AiChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.createdAt,
    required this.status,
    required this.cloudEligible,
  });

  final String id;
  final AiChatMessageRole role;
  final String content;
  final DateTime createdAt;
  final AiChatMessageStatus status;
  final bool cloudEligible;

  AiChatMessage copyWith({
    AiChatMessageStatus? status,
    bool? cloudEligible,
  }) =>
      AiChatMessage(
        id: id,
        role: role,
        content: content,
        createdAt: createdAt,
        status: status ?? this.status,
        cloudEligible: cloudEligible ?? this.cloudEligible,
      );

  factory AiChatMessage.fromJson(Map<String, dynamic> json) => AiChatMessage(
        id: json['id'] as String? ?? '',
        role: _roleFromJson(json['role'] as String?),
        content: json['content'] as String? ?? '',
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        status: _statusFromJson(json['status'] as String?),
        cloudEligible: json['cloudEligible'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'role': role.jsonValue,
        'content': content,
        'createdAt': createdAt.toIso8601String(),
        'status': status.jsonValue,
        'cloudEligible': cloudEligible,
      };
}

class AiChatSession {
  const AiChatSession({
    required this.id,
    required this.accountId,
    required this.createdAt,
    required this.updatedAt,
    required this.messages,
  });

  final String id;
  final String accountId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<AiChatMessage> messages;

  AiChatSession copyWith({
    DateTime? updatedAt,
    List<AiChatMessage>? messages,
  }) =>
      AiChatSession(
        id: id,
        accountId: accountId,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        messages: messages ?? this.messages,
      );

  factory AiChatSession.fromJson(Map<String, dynamic> json) => AiChatSession(
        id: json['id'] as String? ?? '',
        accountId: json['accountId'] as String? ?? '',
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        messages: (json['messages'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map>()
            .map(
              (Map<dynamic, dynamic> item) =>
                  AiChatMessage.fromJson(Map<String, dynamic>.from(item)),
            )
            .toList(growable: false),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'accountId': accountId,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'messages': messages
            .map((AiChatMessage item) => item.toJson())
            .toList(growable: false),
      };
}

class AiChatContext {
  const AiChatContext({
    required this.goal,
    required this.sports,
    required this.availableMinutes,
    this.scheduledMinutes,
    this.scheduledPeriod,
  });

  final String goal;
  final List<String> sports;
  final int availableMinutes;
  final int? scheduledMinutes;
  final String? scheduledPeriod;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'goal': goal,
        'sports': sports,
        'available_minutes': availableMinutes,
        if (scheduledMinutes != null) 'scheduled_minutes': scheduledMinutes,
        if (scheduledPeriod != null) 'scheduled_period': scheduledPeriod,
      };
}

class AiChatResponse {
  const AiChatResponse({
    required this.reply,
    required this.intent,
    required this.suggestedActions,
    required this.warnings,
    required this.provider,
    required this.model,
  });

  final String reply;
  final AiChatIntent intent;
  final List<String> suggestedActions;
  final List<String> warnings;
  final String provider;
  final String model;

  factory AiChatResponse.fromJson(Map<String, dynamic> json) => AiChatResponse(
        reply: json['reply'] as String? ?? '',
        intent: switch (json['intent']) {
          'explain_plan' => AiChatIntent.explainPlan,
          'open_plan_generator' => AiChatIntent.openPlanGenerator,
          _ => AiChatIntent.trainingQuestion,
        },
        suggestedActions:
            (json['suggested_actions'] as List<dynamic>? ?? const <dynamic>[])
                .whereType<String>()
                .toList(growable: false),
        warnings: (json['warnings'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<String>()
            .toList(growable: false),
        provider: json['provider'] as String? ?? '',
        model: json['model'] as String? ?? '',
      );
}
