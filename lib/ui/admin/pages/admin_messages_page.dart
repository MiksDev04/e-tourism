// ignore_for_file: deprecated_member_use

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:app/core/services/connectivity_service.dart';
import 'package:app/ui/shared/pages/error_page.dart';
import 'package:app/ui/shared/pages/loading_page.dart';
import '../../../core/constants/app_colors.dart';
import '../../../api/messages_api.dart';
import '../../../core/services/session_service.dart';
import '../../shared/layouts/admin_layout.dart';
import '../../shared/widgets/action_icon_button.dart';
import '../../shared/widgets/paginator.dart';
import '../widgets/compose_message_modal.dart';
import '../widgets/message_view_dialog.dart';

// ─── Admin Messages Page ──────────────────────────────────────────────────────

class AdminMessagesPage extends StatefulWidget {
  const AdminMessagesPage({super.key});

  @override
  State<AdminMessagesPage> createState() => _AdminMessagesPageState();
}

class _AdminMessagesPageState extends State<AdminMessagesPage> {
  // ── Session + API (resolved once in initState) ─────────────────────────────
  final _api = MessagesApi();
  String? _senderId;

  // ── Filter state ───────────────────────────────────────────────────────────
  String _searchQuery = '';
  String _selectedType = 'All Types';
  String _selectedScope = 'All'; // 'All' | 'Broadcast' | 'Targeted'
  int _currentPage = 0;
  int _pageSize = 10;

  final _searchCtrl = TextEditingController();

  // ── Data state ─────────────────────────────────────────────────────────────
  List<Message> _messages = [];
  bool _loading = true;
  String? _fetchError;
  int? _errorCode;
  int _totalPages = 0;
  int _totalItems = 0;

  static const _typeOptions = [
    'All Types',
    'Compliance',
    'Announcement',
    'General',
  ];

  static const _scopeOptions = ['All', 'Broadcast', 'Targeted'];
  static const List<int> _pageSizeOptions = [10, 20, 30];

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _initSession();
  }

  Future<void> _initSession() async {
    final session =
        SessionService.instance.current ??
        await SessionService.instance.loadAndCache();
    if (!mounted) return;
    setState(() => _senderId = session?.userId);
    _loadMessages();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Data ───────────────────────────────────────────────────────────────────

  Future<void> _loadMessages() async {
    if (_senderId == null) return;
    setState(() {
      _loading = true;
      _fetchError = null;
      _errorCode = null;
    });
    try {
      final result = await _api.fetchSentByAdmin(
        _senderId!,
        page: _currentPage + 1,
        pageSize: _pageSize,
        searchQuery: _searchQuery.isNotEmpty ? _searchQuery : null,
        type: _selectedType != 'All Types' ? _selectedType : null,
        scope: _selectedScope != 'All' ? _selectedScope : null,
      );
      if (mounted) {
        setState(() {
          _messages = result.data;
          _totalPages = result.pageCount;
          _totalItems = result.totalCount;
        });
      }
    } catch (e) {
      final code = await classifyError(e);
      if (mounted)
        setState(() {
          _fetchError = e.toString();
          _errorCode = code;
        });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Compose ────────────────────────────────────────────────────────────────

  Future<void> _openCompose() async {
    final sent = await showComposeMessageDialog(
      context,
      api: _api,
      senderId: _senderId!,
    );
    if (sent == true && mounted) {
      await _loadMessages();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Message sent successfully'),
            backgroundColor: AppColors.accentGreen,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
Widget build(BuildContext context) {
  return AdminLayout(
    title: 'Messages',
    selectedIndex: 3,
    onNavSelected: (_) {},
    child: _fetchError != null
        ? ErrorPage(statusCode: _errorCode ?? 500, onRetry: _loadMessages)
        : LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 900;
              return SingleChildScrollView(
                padding: EdgeInsets.all(isNarrow ? 16 : 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _PageHeader(onCompose: _openCompose),
                    const SizedBox(height: 16),
                    _FilterRow(
                      searchCtrl: _searchCtrl,
                      onSearchChanged: (v) {
                        setState(() {
                          _searchQuery = v;
                          _currentPage = 0;
                        });
                        _loadMessages();
                      },
                      selectedType: _selectedType,
                      onTypeChanged: (v) {
                        setState(() {
                          _selectedType = v!;
                          _currentPage = 0;
                        });
                        _loadMessages();
                      },
                      selectedScope: _selectedScope,
                      onScopeChanged: (v) {
                        setState(() {
                          _selectedScope = v!;
                          _currentPage = 0;
                        });
                        _loadMessages();
                      },
                      typeOptions: _typeOptions,
                      scopeOptions: _scopeOptions,
                    ),
                    const SizedBox(height: 14),
                    if (_loading)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 48),
                          child: CircularProgressIndicator(
                            color: AppColors.primaryCyan,
                            strokeWidth: 2,
                          ),
                        ),
                      )
                    else ...[
                      _MessagesTable(
                        rows: _messages,
                        api: _api,
                        onRefresh: _loadMessages,
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
                          _loadMessages();
                        },
                        onPageChanged: (page) {
                          setState(() => _currentPage = page);
                          _loadMessages();
                        },
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
  );
}
  }

// ─── Page Header ──────────────────────────────────────────────────────────────

class _PageHeader extends StatelessWidget {
  const _PageHeader({required this.onCompose});

  final VoidCallback onCompose;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isSmall = constraints.maxWidth < 600;
        final isMobile = constraints.maxWidth < 450;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Messages & Announcements',
                    style: TextStyle(
                      color: AppColors.textWhite,
                      fontSize: isMobile ? 16 : (isSmall ? 18 : 22),
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Send notices to accommodation establishments',
                    style: TextStyle(
                      color: AppColors.textGray,
                      fontSize: isMobile ? 10 : (isSmall ? 11 : 13),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            GestureDetector(
              onTap: onCompose,
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: isMobile ? 12 : 16,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.gradientStart, AppColors.gradientEnd],
                  ),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primaryBlue.withOpacity(0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.send_rounded, color: Colors.white, size: 15),
                    const SizedBox(width: 7),
                    Text(
                      isSmall ? 'Compose' : 'Compose Message',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ─── Filter Row ───────────────────────────────────────────────────────────────

class _FilterRow extends StatelessWidget {
  const _FilterRow({
    required this.searchCtrl,
    required this.onSearchChanged,
    required this.selectedType,
    required this.onTypeChanged,
    required this.selectedScope,
    required this.onScopeChanged,
    required this.typeOptions,
    required this.scopeOptions,
  });

  final TextEditingController searchCtrl;
  final ValueChanged<String> onSearchChanged;
  final String selectedType;
  final ValueChanged<String?> onTypeChanged;
  final String selectedScope;
  final ValueChanged<String?> onScopeChanged;
  final List<String> typeOptions;
  final List<String> scopeOptions;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isSmall = constraints.maxWidth < 800;
        return isSmall
            ? Column(
                children: [
                  _SearchField(
                    controller: searchCtrl,
                    onChanged: onSearchChanged,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _DropdownFilter(
                          value: selectedType,
                          items: typeOptions,
                          onChanged: onTypeChanged,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _DropdownFilter(
                          value: selectedScope,
                          items: scopeOptions,
                          onChanged: onScopeChanged,
                        ),
                      ),
                    ],
                  ),
                ],
              )
            : Row(
                children: [
                  SizedBox(
                    height: 38,
                    width: 220,
                    child: _SearchField(
                      controller: searchCtrl,
                      onChanged: onSearchChanged,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _DropdownFilter(
                      value: selectedType,
                      items: typeOptions,
                      onChanged: onTypeChanged,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _DropdownFilter(
                      value: selectedScope,
                      items: scopeOptions,
                      onChanged: onScopeChanged,
                    ),
                  ),
                ],
              );
      },
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: const TextStyle(color: AppColors.textWhite, fontSize: 13),
        decoration: const InputDecoration(
          hintText: 'Search subject...',
          hintStyle: TextStyle(color: AppColors.textSubtle, fontSize: 13),
          prefixIcon: Icon(
            Icons.search_rounded,
            color: AppColors.textSubtle,
            size: 18,
          ),
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          isDense: true,
        ),
      ),
    );
  }
}

class _DropdownFilter extends StatelessWidget {
  const _DropdownFilter({
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String value;
  final List<String> items;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isDense: true,
          isExpanded: true,
          dropdownColor: AppColors.cardBackground,
          iconEnabledColor: AppColors.textGray,
          style: const TextStyle(color: AppColors.textGray, fontSize: 13),
          items: items
              .map((e) => DropdownMenuItem(value: e, child: Text(e)))
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}


// ─── Messages Table ───────────────────────────────────────────────────────────

class _MessagesTable extends StatelessWidget {
  const _MessagesTable({
    required this.rows,
    required this.api,
    required this.onRefresh,
  });

  final List<Message> rows;
  final MessagesApi api;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMedium = constraints.maxWidth < 900;

        final table = Column(
          children: [
            const _TableHeader(),
            const Divider(color: AppColors.cardBorder, height: 1),
            rows.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text(
                        'No messages found.',
                        style: TextStyle(color: AppColors.textGray),
                      ),
                    ),
                  )
                : LayoutBuilder(
                  builder: (_, lc) => ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: rows.length,
                    separatorBuilder: (_, __) => lc.maxWidth < 900
                        ? const SizedBox(height: 10)
                        : const Divider(color: AppColors.cardBorder, height: 1),
                    itemBuilder: (_, i) => _MessageRow(
                      message: rows[i],
                      api: api,
                      onRefresh: onRefresh,
                    ),
                  ),
                ),
          ],
        );

        if (isMedium) return table;

        return Container(
          decoration: BoxDecoration(
            color: AppColors.cardBackground,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: table,
        );
      },
    );
  }
}

// ─── Table Header ─────────────────────────────────────────────────────────────

class _TableHeader extends StatelessWidget {
  const _TableHeader();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMedium = constraints.maxWidth < 900;
        if (isMedium) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            children: const [
              Expanded(flex: 2, child: _HeaderCell('Type')),
              Expanded(flex: 5, child: _HeaderCell('Subject')),
              Expanded(flex: 2, child: _HeaderCell('Scope')),
              Expanded(flex: 2, child: _HeaderCell('Sent At')),
              Expanded(
                flex: 1,
                child: _HeaderCell('View', alignment: Alignment.center),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell(this.label, {this.alignment = Alignment.centerLeft});
  final String label;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Text(
          label,
          style: const TextStyle(
            color: AppColors.textGray,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

// ─── Message Row ──────────────────────────────────────────────────────────────

class _MessageRow extends StatelessWidget {
  const _MessageRow({
    required this.message,
    required this.api,
    required this.onRefresh,
  });

  final Message message;
  final MessagesApi api;
  final VoidCallback onRefresh;

  String _fmt(DateTime dt) {
    const m = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${m[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  /// Opens the view dialog; also lazily loads the delivery report.
  void _openMessage(BuildContext context) {
    final typeLabel = switch (message.messageType) {
      MessageType.compliance => 'COMPLIANCE NOTICE',
      MessageType.announcement => 'ANNOUNCEMENT',
      MessageType.general => 'GENERAL NOTICE',
    };

    showMessageViewDialog(
      context,
      api,
      MessageViewData(
        subject: message.subject,
        // Show "All Businesses (Broadcast)" for broadcast messages;
        // for targeted, the delivery report in the dialog can list recipients.
        recipient: message.isBroadcast
            ? 'All Businesses (Broadcast)'
            : 'Targeted Recipients',
        date: _fmt(message.createdAt),
        messageType: typeLabel,
        messageContent: message.content,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = _fmt(message.createdAt);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMedium = constraints.maxWidth < 900;

        if (isMedium) {
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.cardBackground,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.cardBorder),
            ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _TypeBadge(type: message.messageType),
                      const Spacer(),
                      ActionIconButton(
                        icon: Icons.remove_red_eye_outlined,
                        label: 'View',
                        color: AppColors.primaryCyan,
                        showBorder: true,
                        onTap: () => _openMessage(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _CardDetail(
                    label: 'Subject',
                    child: Text(
                      message.subject,
                      style: const TextStyle(
                        color: AppColors.textWhite,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  _CardDetail(
                    label: 'Scope',
                    child: _ScopeBadge(isBroadcast: message.isBroadcast),
                  ),
                  const SizedBox(height: 6),
                  _CardDetail(
                    label: 'Sent',
                    child: Text(
                      dateStr,
                      style: const TextStyle(
                        color: AppColors.textGray,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            );
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(
            children: [
              Expanded(
                flex: 2,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _TypeBadge(type: message.messageType),
                ),
              ),
              Expanded(
                flex: 5,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    message.subject,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textWhite,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _ScopeBadge(isBroadcast: message.isBroadcast),
                ),
              ),
              Expanded(
                flex: 2,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    dateStr,
                    style: const TextStyle(
                      color: AppColors.textGray,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ActionIconButton(
                icon: Icons.remove_red_eye_outlined,
                label: 'View',
                color: AppColors.primaryCyan,
                showBorder: true,
                onTap: () => _openMessage(context),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─── Type Badge ───────────────────────────────────────────────────────────────

class _TypeBadge extends StatelessWidget {
  const _TypeBadge({required this.type});

  final MessageType type;

  static ({Color color}) _style(MessageType t) => switch (t) {
    MessageType.compliance => (color: const Color(0xFFFF4D6A)),
    MessageType.announcement => (color: const Color(0xFF9B8AFB)),
    MessageType.general => (color: const Color(0xFF1A6FFF)),
  };

  @override
  Widget build(BuildContext context) {
    final s = _style(type);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: s.color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: s.color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(type.icon, style: const TextStyle(fontSize: 11)),
          const SizedBox(width: 5),
          Text(
            type.label,
            style: TextStyle(
              color: s.color,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Scope Badge (Broadcast vs Targeted) ─────────────────────────────────────

class _ScopeBadge extends StatelessWidget {
  const _ScopeBadge({required this.isBroadcast});

  final bool isBroadcast;

  @override
  Widget build(BuildContext context) {
    const broadcastColor = Color(0xFF22C55E);
    const targetColor = Color(0xFFF59E0B);

    final color = isBroadcast ? broadcastColor : targetColor;
    final label = isBroadcast ? 'Broadcast' : 'Targeted';
    final icon = isBroadcast
        ? Icons.campaign_rounded
        : Icons.person_pin_rounded;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Card Detail ──────────────────────────────────────────────────────────────

class _CardDetail extends StatelessWidget {
  const _CardDetail({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.textSubtle,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Flexible(
          fit: FlexFit.loose,
          child: child,
        ),
      ],
    );
  }
}
