import 'dart:async';
import 'package:flutter/foundation.dart';
import '../core/services/connectivity_service.dart';
import 'base_api.dart';

// ─── Enums ────────────────────────────────────────────────────────────────────

enum MessageType {
  compliance,
  announcement,
  general;

  /// Matches the enum value in the `messages` table.
  String get dbValue => name;

  String get label => switch (this) {
    MessageType.compliance => 'Compliance',
    MessageType.announcement => 'Announcement',
    MessageType.general => 'General',
  };

  String get icon => switch (this) {
    MessageType.compliance => '⚠️',
    MessageType.announcement => '📣',
    MessageType.general => '💬',
  };
}

/// Matches the `recipient_status` enum on `message_recipients`.
enum RecipientStatus {
  unread,
  read,
  archived;

  String get dbValue => name;
}

/// Builds the official tourism-office letter format used by compose message
/// and by automated accommodation decisions.
String buildOfficialMessageLetter({
  required String recipient,
  required String subject,
  required String messageContent,
  required String senderFullName,
  required String senderEmail,
  required String senderPhone,
  required MessageType messageType,
  DateTime? now,
}) {
  final current = now ?? DateTime.now();
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  final dateStr =
      '${months[current.month - 1]} ${current.day}, ${current.year}';
  final typeLabel = switch (messageType) {
    MessageType.compliance => 'COMPLIANCE NOTICE',
    MessageType.announcement => 'ANNOUNCEMENT',
    MessageType.general => 'GENERAL NOTICE',
  };
  final ref =
      'MSG-${DateTime.now().millisecondsSinceEpoch.toString().substring(4)}';

  return '''REPUBLIC OF THE PHILIPPINES
CITY OF SAN PABLO
OFFICE OF TOURISM

$dateStr

To: $recipient
Re: ${subject.isEmpty ? '(no subject)' : subject}

$typeLabel

Dear Establishment Representative,

${messageContent.isEmpty ? '(no content)' : messageContent}

This notice is duly issued by the San Pablo City Tourism Office and is valid even without a handwritten signature, being an official electronic communication of the office.

For questions and concerns, please contact us at $senderEmail or call us at $senderPhone, or visit our office at the San Pablo City Hall.

Respectfully,

$senderFullName
Tourism Officer
San Pablo City Tourism Office

---
This is an official communication from the San Pablo City Tourism Office.
Reference No.: $ref''';
}

/// Shared unread-count cache for business navigation badges.
class MessageBadgeController {
  MessageBadgeController._();

  static final MessageBadgeController instance = MessageBadgeController._();

  final ValueNotifier<int> unreadCount = ValueNotifier<int>(0);
  bool _isRefreshing = false;

  Future<void> refresh() async {
    if (_isRefreshing) return;
    _isRefreshing = true;
    try {
      final count = await MessagesApi().fetchUnreadCount('');
      unreadCount.value = count;
    } catch (_) {
      unreadCount.value = 0;
    } finally {
      _isRefreshing = false;
    }
  }
}

// ─── Models ───────────────────────────────────────────────────────────────────

/// Lightweight business representation used in the compose dropdown.
/// Only approved + warning businesses are eligible as message recipients.
class BusinessSummary {
  const BusinessSummary({
    required this.id,
    required this.name,
    required this.status,
  });

  final String id;
  final String name;
  final String status;

  bool get isEligible => status == 'approved' || status == 'warning';

  factory BusinessSummary.fromJson(Map<String, dynamic> json) =>
      BusinessSummary(
        id: json['id'] as String,
        name: json['business_name'] as String,
        status: json['status'] as String,
      );
}

/// Represents a row from `messages` joined with its sender profile.
/// Used on the admin outbox side.
class Message {
  const Message({
    required this.id,
    required this.senderId,
    required this.messageType,
    required this.subject,
    required this.content,
    required this.isBroadcast,
    required this.createdAt,
    this.senderName,
  });

  final String id;
  final String senderId;
  final MessageType messageType;
  final String subject;
  final String content;
  final bool isBroadcast;
  final DateTime createdAt;
  final String? senderName;

  factory Message.fromJson(Map<String, dynamic> json) => Message(
    id: json['id'] as String,
    senderId: json['sender_id'] as String,
    messageType: MessageType.values.firstWhere(
      (e) => e.dbValue == json['message_type'],
      orElse: () => MessageType.general,
    ),
    subject: json['subject'] as String,
    content: json['content'] as String,
    isBroadcast: json['is_broadcast'] == 1 || json['is_broadcast'] == true,
    createdAt: DateTime.parse(json['created_at'] as String),
    senderName:
        (json['sender'] as Map<String, dynamic>?)?['full_name'] as String?,
  );
}

/// Represents a row from `message_recipients` joined with its parent message.
/// Used on the business inbox side.
class InboxMessage {
  const InboxMessage({
    required this.recipientId,
    required this.messageId,
    required this.businessId,
    required this.status,
    required this.isRead,
    required this.createdAt,
    this.readAt,
    // joined from messages
    required this.messageType,
    required this.subject,
    required this.content,
    required this.isBroadcast,
    required this.sentAt,
    this.senderName,
  });

  final String recipientId;
  final String messageId;
  final String businessId;
  final RecipientStatus status;
  final bool isRead;
  final DateTime createdAt;
  final DateTime? readAt;

  final MessageType messageType;
  final String subject;
  final String content;
  final bool isBroadcast;
  final DateTime sentAt;
  final String? senderName;

  factory InboxMessage.fromJson(Map<String, dynamic> json) {
    final msg = json['message'] as Map<String, dynamic>;
    return InboxMessage(
      recipientId: json['id'] as String,
      messageId: json['message_id'] as String,
      businessId: json['business_id'] as String,
      status: RecipientStatus.values.firstWhere(
        (e) => e.dbValue == json['status'],
        orElse: () => RecipientStatus.unread,
      ),
      isRead: json['is_read'] == 1 || json['is_read'] == true,
      createdAt: DateTime.parse(json['created_at'] as String),
      readAt: json['read_at'] != null
          ? DateTime.parse(json['read_at'] as String)
          : null,
      messageType: MessageType.values.firstWhere(
        (e) => e.dbValue == msg['message_type'],
        orElse: () => MessageType.general,
      ),
      subject: msg['subject'] as String,
      content: msg['content'] as String,
      isBroadcast: msg['is_broadcast'] == 1 || msg['is_broadcast'] == true,
      sentAt: DateTime.parse(msg['created_at'] as String),
      senderName:
          (msg['sender'] as Map<String, dynamic>?)?['full_name'] as String?,
    );
  }
}

/// Per-business read state for a single message.
/// Used in the admin delivery report.
class DeliveryReceipt {
  const DeliveryReceipt({
    required this.recipientId,
    required this.businessId,
    required this.businessName,
    required this.businessStatus,
    required this.status,
    required this.isRead,
    this.readAt,
  });

  final String recipientId;
  final String businessId;
  final String businessName;
  final String businessStatus;
  final RecipientStatus status;
  final bool isRead;
  final DateTime? readAt;

  factory DeliveryReceipt.fromJson(Map<String, dynamic> json) {
    final biz = json['business'] as Map<String, dynamic>;
    return DeliveryReceipt(
      recipientId: json['id'] as String,
      businessId: json['business_id'] as String,
      businessName: biz['business_name'] as String,
      businessStatus: biz['status'] as String,
      status: RecipientStatus.values.firstWhere(
        (e) => e.dbValue == json['status'],
        orElse: () => RecipientStatus.unread,
      ),
      isRead: json['is_read'] == 1 || json['is_read'] == true,
      readAt: json['read_at'] != null
          ? DateTime.parse(json['read_at'] as String)
          : null,
    );
  }
}

// ─── API ──────────────────────────────────────────────────────────────────────

class MessagesApi extends BaseApi {
  MessagesApi();

  // ── Businesses ─────────────────────────────────────────────────────────────

  Future<String?> fetchReceiverName(String businessId) async {
    final response = await get('/api/messages/receiver-name/$businessId');
    return handleResponse(response) as String?;
  }

  Future<List<BusinessSummary>> fetchEligibleBusinesses() async {
    final response = await get('/api/messages/eligible-businesses');
    final data = handleResponse(response) as List<dynamic>;
    return data
        .map((b) => BusinessSummary.fromJson(b as Map<String, dynamic>))
        .toList();
  }

  // ── Send ───────────────────────────────────────────────────────────────────

  Future<String> sendToSelected({
    required String senderId,
    required List<String> businessIds,
    required MessageType messageType,
    required String subject,
    required String content,
  }) async {
    final response = await post('/api/messages/send-selected', {
      'businessIds': businessIds,
      'messageType': messageType.dbValue,
      'subject': subject,
      'content': content,
    });
    final data = handleResponse(response);
    return data['messageId'] as String;
  }

  Future<({String messageId, int recipientCount})> sendToAll({
    required String senderId,
    required MessageType messageType,
    required String subject,
    required String content,
  }) async {
    final response = await post('/api/messages/send-all', {
      'messageType': messageType.dbValue,
      'subject': subject,
      'content': content,
    });
    final data = handleResponse(response);
    return (
      messageId: data['messageId'] as String,
      recipientCount: data['recipientCount'] as int,
    );
  }

  // ── Admin: Outbox ──────────────────────────────────────────────────────────

  Future<List<Message>> fetchSentByAdmin(String adminId) async {
    final response = await get('/api/messages/admin/outbox');
    final data = handleResponse(response) as List<dynamic>;
    return data
        .map((m) => Message.fromJson(m as Map<String, dynamic>))
        .toList();
  }

  Future<List<DeliveryReceipt>> fetchDeliveryReport(String messageId) async {
    final response = await get('/api/messages/admin/report/$messageId');
    final data = handleResponse(response) as List<dynamic>;
    return data
        .map((r) => DeliveryReceipt.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  // ── Business: Inbox ────────────────────────────────────────────────────────

  Future<List<InboxMessage>> fetchInbox(
    String businessId, {
    bool includeArchived = false,
  }) async {
    final response = await get(
      '/api/messages/business/inbox?includeArchived=$includeArchived&businessId=$businessId',
    );
    final data = handleResponse(response) as List<dynamic>;
    return data
        .map((r) => InboxMessage.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<int> fetchUnreadCount(String businessId) async {
    final response = await get('/api/messages/business/unread-count');
    return handleResponse(response) as int;
  }

  // ── Business: Update State ─────────────────────────────────────────────────

  Future<void> markAsRead(String recipientId) async {
    final response = await put('/api/messages/recipient/$recipientId/read', {});
    handleResponse(response);
    unawaited(MessageBadgeController.instance.refresh());
  }

  Future<void> archive(String recipientId) async {
    final response = await put(
      '/api/messages/recipient/$recipientId/archive',
      {},
    );
    handleResponse(response);
    unawaited(MessageBadgeController.instance.refresh());
  }
}
