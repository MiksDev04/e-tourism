// ignore_for_file: deprecated_member_use

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:app/ui/shared/pages/error_page.dart';
import '../../../core/constants/app_colors.dart';
import '../../../api/messages_api.dart';
import '../../../api/login_api.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/services/session_service.dart';
import '../widgets/message_view_dialog.dart';
import '../../shared/layouts/business_layout.dart';
import '../widgets/offline_state.dart';
import '../../shared/widgets/paginator.dart';

// ─── Filter Options ───────────────────────────────────────────────────────────

enum _Filter { all, compliance, announcement, general }

// ─── Letter Preview Helper ────────────────────────────────────────────────────

/// Extracts a meaningful preview from the frozen letter by skipping the
/// standard header block (letterhead, date, salutation lines) and returning
/// the first non-empty body line(s).
String _letterPreview(String content) {
  final lines = content.split('\n');

  bool pastHeader = false;
  final preview = StringBuffer();

  for (final raw in lines) {
    final line = raw.trim();

    if (!pastHeader) {
      if (line.startsWith('Dear ')) {
        pastHeader = true;
      }
      continue;
    }

    if (line.isEmpty && preview.isEmpty) continue;

    if (line.startsWith('This notice is duly issued') ||
        line.startsWith('Respectfully') ||
        line.startsWith('---')) {
      break;
    }

    if (preview.isNotEmpty) preview.write(' ');
    preview.write(line);

    if (preview.length > 180) break;
  }

  final result = preview.toString().trim();
  return result.isNotEmpty ? result : content;
}

// ─── Business Messages Page ───────────────────────────────────────────────────

class BusinessMessagesPage extends StatefulWidget {
  const BusinessMessagesPage({super.key});

  @override
  State<BusinessMessagesPage> createState() => _BusinessMessagesPageState();
}

class _BusinessMessagesPageState extends State<BusinessMessagesPage> {
  final _api = MessagesApi();

  // ── Connectivity ──────────────────────────────────────────────────────────
  bool _isOffline = false;
  StreamSubscription<bool>? _connectivitySub;

  // ── Filter / pagination ───────────────────────────────────────────────────
  _Filter _activeFilter = _Filter.all;
  int _currentPage = 0;
  int _pageSize = 10;
  int _totalPages = 0;
  int _totalItems = 0;

  List<InboxMessage> _messages = [];

  /// Optimistic local read tracking for this session.
  final Set<String> _locallyRead = {};

  bool    _isLoading  = true;
  String? _error;
  int? _errorCode;
  String? _businessId;

  static const List<int> _pageSizeOptions = [10, 20, 30];

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _subscribeConnectivity();
    _initSession();
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    super.dispose();
  }

  // ── Connectivity subscription ─────────────────────────────────────────────

  void _subscribeConnectivity() {
    _connectivitySub =
        ConnectivityService.instance.onlineStream.listen((isOnline) {
      if (!mounted || !isOnline || !_isOffline || _isLoading) return;
      // Was showing offline state, connection restored → auto-retry.
      setState(() => _isOffline = false);
      _loadData();
    });
  }

  // ── Session + Data Loading ────────────────────────────────────────────────

  Future<void> _initSession() async {
    _loadData();
  }

  Future<void> _loadData() async {
    var session = await SessionService.instance.loadAndCache();
    if (!mounted) return;

    setState(() => _businessId = session?.businessId);

    if (_businessId == null) {
      setState(() {
        _error     = 'No business account found for this user.';
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error     = null;
      _errorCode = null;
    });

    // ── Pre-check connectivity ─────────────────────────────────────────────
    final online = await ConnectivityService.instance.checkOnline;
    if (!mounted) return;
    if (!online) {
      setState(() {
        _isOffline = true;
        _isLoading = false;
      });
      return;
    }

    // Check if we need to auto-authenticate (offline to online transition)
    if (session != null && (session.token == null || session.isOfflineSession)) {
      if (session.username != null && session.password != null) {
        final success = await LoginApi().backgroundAuth(
          username: session.username!,
          password: session.password!,
        );
        if (success) {
          session = SessionService.instance.current;
        }
      }
    }

    setState(() => _businessId = session?.businessId);

    // ── Fetch ─────── ───────────────────────────────────────────────────────
    try {
      final type = switch (_activeFilter) {
        _Filter.all          => null,
        _Filter.compliance   => 'compliance',
        _Filter.announcement => 'announcement',
        _Filter.general      => 'general',
      };
       final result = await _api.fetchInbox(
         _businessId!,
         page: _currentPage + 1,
         pageSize: _pageSize,
         type: type,
       );
       final unreadCount = await _api.fetchUnreadCount(_businessId!);
       if (mounted) {
         setState(() {
           _messages   = result.data;
           _totalPages = result.pageCount;
           _totalItems = result.totalCount;
           _unreadCount = unreadCount;
           _isLoading  = false;
         });
       }
    } catch (e) {
      if (!mounted) return;
      final code = await classifyError(e);
      if (code == 503) {
        setState(() { _isOffline = true; _isLoading = false; });
      } else if (code == 500 || code == 408) {
        setState(() { _errorCode = code; _isLoading = false; });
      } else {
        setState(() {
          _error     = 'Failed to load messages. Please try again.';
          _isLoading = false;
        });
      }
    }
  }

  // ── Computed ──────────────────────────────────────────────────────────────

  bool _isRead(InboxMessage msg) =>
      msg.isRead || _locallyRead.contains(msg.recipientId);

  int _unreadCount = 0;

  // ── Actions ───────────────────────────────────────────────────────────────

   Future<void> _openMessage(InboxMessage msg) async {
     if (!_isRead(msg)) {
       setState(() {
         _locallyRead.add(msg.recipientId);
         if (_unreadCount > 0) _unreadCount--;
       });
       _api.markAsRead(msg.recipientId).catchError((_) {});
     }

    if (!mounted) return;
    showMessageViewDialog(context, msg);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return BusinessLayout(
      title:         'Messages',
      selectedIndex: 4,
      onNavSelected: (_) {},
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 600;
          return RefreshIndicator(
            color:           AppColors.primaryCyan,
            backgroundColor: AppColors.cardBackground,
            onRefresh:       _loadData,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.all(isNarrow ? 16 : 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _PageHeader(unreadCount: _unreadCount),
                  const SizedBox(height: 16),
                  _FilterTabBar(
                    activeFilter: _activeFilter,
                    onChanged: (f) {
                      setState(() {
                        _activeFilter = f;
                        _currentPage = 0;
                      });
                      _loadData();
                    },
                  ),
                  const SizedBox(height: 16),
                  _buildBody(isNarrow),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBody(bool isNarrow) {
    if (_isLoading)          return const _LoadingState();
    if (_errorCode != null)  return ErrorPage(statusCode: _errorCode!, onRetry: _loadData);
    if (_isOffline)          return OfflineState(onRetry: _loadData);
    if (_error != null)      return _ErrorState(message: _error!, onRetry: _loadData);
    if (_messages.isEmpty)   return const _EmptyState();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: _messages.map((msg) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _MessageCard(
                message:  msg,
                preview:  _letterPreview(msg.content),
                isRead:   _isRead(msg),
                isNarrow: isNarrow,
                onTap:    () => _openMessage(msg),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
        Paginator(
          currentPage: _currentPage,
          totalPages: _totalPages,
          totalItems: _totalItems,
          pageSize: _pageSize,
          pageSizeOptions: _pageSizeOptions,
          onPageSizeChanged: (size) {
            setState(() {
              _pageSize = size;
              _currentPage = 0;
            });
            _loadData();
          },
          onPageChanged: (page) {
            setState(() => _currentPage = page);
            _loadData();
          },
        ),
      ],
    );
  }
}

// ─── Page Header ──────────────────────────────────────────────────────────────

class _PageHeader extends StatelessWidget {
  const _PageHeader({required this.unreadCount});
  final int unreadCount;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Messages',
          style: TextStyle(
            color:      AppColors.textWhite,
            fontSize:   22,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          unreadCount > 0
              ? '$unreadCount unread message${unreadCount > 1 ? 's' : ''}'
              : 'No unread messages',
          style: TextStyle(
            color: unreadCount > 0
                ? AppColors.primaryCyan
                : AppColors.textSubtle,
            fontSize:   13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

// ─── Filter Tab Bar ───────────────────────────────────────────────────────────

class _FilterTabBar extends StatelessWidget {
  const _FilterTabBar({required this.activeFilter, required this.onChanged});

  final _Filter               activeFilter;
  final ValueChanged<_Filter> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 6),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _FilterChip(
            label:    'All',
            emoji:    null,
            isActive: activeFilter == _Filter.all,
            onTap:    () => onChanged(_Filter.all),
          ),
          _FilterChip(
            label:    'Compliance',
            emoji:    '⚠️',
            isActive: activeFilter == _Filter.compliance,
            onTap:    () => onChanged(_Filter.compliance),
          ),
          _FilterChip(
            label:    'Announcement',
            emoji:    '📣',
            isActive: activeFilter == _Filter.announcement,
            onTap:    () => onChanged(_Filter.announcement),
          ),
          _FilterChip(
            label:    'General',
            emoji:    '💬',
            isActive: activeFilter == _Filter.general,
            onTap:    () => onChanged(_Filter.general),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.emoji,
    required this.isActive,
    required this.onTap,
  });

  final String       label;
  final String?      emoji;
  final bool         isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding:  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          gradient: isActive
              ? const LinearGradient(
                  colors: [AppColors.gradientStart, AppColors.gradientEnd],
                )
              : null,
          color:        isActive ? null : AppColors.cardBackground,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive ? Colors.transparent : AppColors.cardBorder,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (emoji != null) ...[
              Text(emoji!, style: const TextStyle(fontSize: 12)),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: TextStyle(
                color:      isActive ? Colors.white : AppColors.textGray,
                fontSize:   13,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Message Card ─────────────────────────────────────────────────────────────

class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.message,
    required this.preview,
    required this.isRead,
    required this.isNarrow,
    required this.onTap,
  });

  final InboxMessage message;
  final String       preview;
  final bool         isRead;
  final bool         isNarrow;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isUnread = !isRead;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration:  const Duration(milliseconds: 200),
        padding:   const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isUnread ? AppColors.activeNavBg : AppColors.cardBackground,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isUnread
                ? AppColors.primaryCyan.withOpacity(0.25)
                : AppColors.cardBorder,
          ),
        ),
        child: isNarrow
            ? _NarrowLayout(message: message, preview: preview, isUnread: isUnread)
            : _WideLayout(message: message, preview: preview, isUnread: isUnread),
      ),
    );
  }
}

// ─── Wide Layout ──────────────────────────────────────────────────────────────

class _WideLayout extends StatelessWidget {
  const _WideLayout({
    required this.message,
    required this.preview,
    required this.isUnread,
  });
  final InboxMessage message;
  final String       preview;
  final bool         isUnread;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2, right: 14),
          child: Icon(
            isUnread ? Icons.email_rounded : Icons.drafts_rounded,
            color: isUnread ? AppColors.primaryCyan : AppColors.textSubtle,
            size:  20,
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      message.subject,
                      style: TextStyle(
                        color:      AppColors.textWhite,
                        fontSize:   14,
                        fontWeight:
                            isUnread ? FontWeight.w600 : FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isUnread) ...[
                    const SizedBox(width: 8),
                    Container(
                      width:  8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: AppColors.primaryCyan,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 5),
              Text(
                preview,
                style: const TextStyle(
                  color:    AppColors.textGray,
                  fontSize: 12.5,
                  height:   1.4,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _TypeBadge(type: message.messageType),
            const SizedBox(height: 4),
            if (message.isBroadcast) const _BroadcastTag(),
            const SizedBox(height: 4),
            Text(
              _formatDate(message.sentAt),
              style: const TextStyle(
                color:    AppColors.textSubtle,
                fontSize: 11.5,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ─── Narrow Layout ────────────────────────────────────────────────────────────

class _NarrowLayout extends StatelessWidget {
  const _NarrowLayout({
    required this.message,
    required this.preview,
    required this.isUnread,
  });
  final InboxMessage message;
  final String       preview;
  final bool         isUnread;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              isUnread ? Icons.email_rounded : Icons.drafts_rounded,
              color: isUnread ? AppColors.primaryCyan : AppColors.textSubtle,
              size:  18,
            ),
            const SizedBox(width: 8),
            _TypeBadge(type: message.messageType),
            if (message.isBroadcast) ...[
              const SizedBox(width: 6),
              const _BroadcastTag(),
            ],
            const Spacer(),
            Text(
              _formatDate(message.sentAt),
              style: const TextStyle(
                color:    AppColors.textSubtle,
                fontSize: 11.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: Text(
                message.subject,
                style: TextStyle(
                  color:      AppColors.textWhite,
                  fontSize:   13.5,
                  fontWeight: isUnread ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
            if (isUnread)
              Container(
                width:  8,
                height: 8,
                margin: const EdgeInsets.only(left: 8),
                decoration: const BoxDecoration(
                  color: AppColors.primaryCyan,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          preview,
          style: const TextStyle(
            color:    AppColors.textGray,
            fontSize: 12.5,
            height:   1.4,
          ),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

// ─── Type Badge ───────────────────────────────────────────────────────────────

class _TypeBadge extends StatelessWidget {
  const _TypeBadge({required this.type});
  final MessageType type;

  static ({String label, Color color, String emoji}) _styleFor(MessageType t) =>
      switch (t) {
        MessageType.general      => (label: 'General',      color: AppColors.primaryBlue,   emoji: '💬'),
        MessageType.compliance   => (label: 'Compliance',   color: AppColors.accentRed,     emoji: '⚠️'),
        MessageType.announcement => (label: 'Announcement', color: AppColors.accentPurple,  emoji: '📣'),
      };

  @override
  Widget build(BuildContext context) {
    final s = _styleFor(type);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color:        s.color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border:       Border.all(color: s.color.withOpacity(0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(s.emoji, style: const TextStyle(fontSize: 10)),
          const SizedBox(width: 4),
          Text(
            s.label,
            style: TextStyle(
              color:      s.color,
              fontSize:   11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Broadcast Tag ────────────────────────────────────────────────────────────

class _BroadcastTag extends StatelessWidget {
  const _BroadcastTag();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color:        const Color(0xFF22C55E).withOpacity(0.10),
        borderRadius: BorderRadius.circular(20),
        border:       Border.all(color: const Color(0xFF22C55E).withOpacity(0.3)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.campaign_rounded, size: 10, color: Color(0xFF22C55E)),
          SizedBox(width: 3),
          Text(
            'Broadcast',
            style: TextStyle(
              color:      Color(0xFF22C55E),
              fontSize:   10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Loading State ────────────────────────────────────────────────────────────

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 64),
      child: Center(
        child: CircularProgressIndicator(
          color:       AppColors.primaryCyan,
          strokeWidth: 2,
        ),
      ),
    );
  }
}

// ─── Error State ──────────────────────────────────────────────────────────────

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String       message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(
            Icons.error_outline_rounded,
            color: AppColors.accentRed.withOpacity(0.6),
            size:  44,
          ),
          const SizedBox(height: 12),
          Text(
            message,
            style: const TextStyle(color: AppColors.textSubtle, fontSize: 14),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: onRetry,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.gradientStart, AppColors.gradientEnd],
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'Retry',
                style: TextStyle(
                  color:      Colors.white,
                  fontSize:   13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Empty State ──────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:   const EdgeInsets.symmetric(vertical: 48),
      alignment: Alignment.center,
      child: Column(
        children: [
          Icon(
            Icons.inbox_rounded,
            color: AppColors.textSubtle.withOpacity(0.4),
            size:  48,
          ),
          const SizedBox(height: 12),
          const Text(
            'No messages found.',
            style: TextStyle(color: AppColors.textSubtle, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

// ─── Date Formatter ───────────────────────────────────────────────────────────

String _formatDate(DateTime dt) {
  final y = dt.year.toString();
  final m = dt.month.toString().padLeft(2, '0');
  final d = dt.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}