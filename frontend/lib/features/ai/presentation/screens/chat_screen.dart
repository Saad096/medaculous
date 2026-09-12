import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../notes/domain/markdown_to_quill.dart';
import '../../../notes/presentation/providers/notes_providers.dart';
import '../../../settings/presentation/widgets/usage_limit_dialog.dart';
import '../../domain/conversation.dart';
import '../providers/ai_providers.dart';

const _historyMonthNames = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _formatHistoryDate(DateTime dt) {
  final local = dt.toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final that = DateTime(local.year, local.month, local.day);
  final diffDays = today.difference(that).inDays;
  if (diffDays == 0) return 'Today';
  if (diffDays == 1) return 'Yesterday';
  return '${_historyMonthNames[local.month - 1]} ${local.day}${local.year != now.year ? ', ${local.year}' : ''}';
}

/// Medaculous AI chat — DISCOVERY_REPORT.md §6: streaming chat with Ward/ER/
/// Exam/Auto modes, save-to-library, and a non-negotiable AI-mistake
/// disclaimer. The disclaimer is a persistent banner rather than per-message
/// text — it's shown above every response either way, just without repeating
/// the same sentence after each bubble.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();

  final List<ChatMessage> _messages = [];
  ChatMode _mode = ChatMode.auto;
  String? _conversationId;
  bool _isSaved = false;
  bool _isStreaming = false;
  String? _errorMessage;

  /// GPT-style "jump to latest" arrow: shown once the user has scrolled up
  /// away from the newest message.
  bool _showJumpToBottom = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() => _syncJumpToBottomVisibility();

  /// Recomputes whether the jump-to-bottom arrow should show. Needed as its
  /// own method (not just the scroll listener) because a streaming response
  /// growing the list's content height does NOT fire ScrollController
  /// listeners on its own — Flutter only notifies them on an actual pixel/
  /// offset change, not a content-size change with the offset held still.
  /// Without this, the arrow only ever appeared after the user physically
  /// touched the list. Call after every delta so it appears the moment new
  /// text pushes below the fold, with no interaction required.
  void _syncJumpToBottomVisibility() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final distanceFromBottom =
          _scrollController.position.maxScrollExtent - _scrollController.offset;
      final show = distanceFromBottom > 250;
      if (show != _showJumpToBottom) {
        setState(() => _showJumpToBottom = show);
      }
    });
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom({bool force = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      // Don't yank the view down while the user is reading older messages;
      // the jump-to-bottom arrow is their way back.
      if (!force && _showJumpToBottom) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  /// Bumped whenever a new send starts or the user starts a new chat, so a
  /// stale in-flight stream can detect it has been superseded and stop
  /// touching state.
  int _sendGeneration = 0;

  Future<void> _send() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _isStreaming) return;

    final generation = ++_sendGeneration;
    setState(() {
      _messages.add(ChatMessage(role: 'user', content: text));
      _messages.add(const ChatMessage(role: 'assistant', content: ''));
      _isStreaming = true;
      _errorMessage = null;
    });
    _inputController.clear();
    _scrollToBottom();

    try {
      final stream = ref
          .read(aiApiProvider)
          .streamChat(
            message: text,
            mode: _mode,
            conversationId: _conversationId,
          )
          // Without an inter-event timeout, a half-open connection (server
          // restarted mid-stream, network drop) makes `await for` hang
          // forever and the input stays disabled for good.
          .timeout(const Duration(seconds: 90));
      await for (final event in stream) {
        if (!mounted || generation != _sendGeneration) return;
        switch (event) {
          case ChatStreamStarted(:final conversationId):
            _conversationId = conversationId;
          case ChatStreamDelta(:final text):
            // Deliberately no auto-scroll per delta: once the response
            // starts, the user should be able to read from its start
            // undisturbed while it grows below the fold. The floating
            // down-arrow (see _onScroll/_showJumpToBottom) is the only way
            // to follow the tail of a still-streaming answer.
            setState(() {
              final last = _messages.removeLast();
              _messages.add(
                ChatMessage(role: 'assistant', content: last.content + text),
              );
            });
            _syncJumpToBottomVisibility();
        }
      }
    } on ApiException catch (e) {
      if (mounted && generation == _sendGeneration) {
        setState(() => _messages.removeLast());
        if (e.statusCode == 429) {
          showUsageLimitDialog(context);
        } else {
          setState(() => _errorMessage = e.message);
        }
      }
    } catch (_) {
      // Timeout, socket error, or any other transport failure: keep whatever
      // partial answer streamed in, but tell the user it was cut off.
      if (mounted && generation == _sendGeneration) {
        setState(() {
          if (_messages.isNotEmpty && _messages.last.content.isEmpty) {
            _messages.removeLast();
          }
          _errorMessage = 'Connection lost. Please try again.';
        });
      }
    } finally {
      if (mounted && generation == _sendGeneration) {
        setState(() => _isStreaming = false);
      }
    }
  }

  /// GPT-style stop: supersede the in-flight stream (the generation check
  /// makes it a no-op from here on) and keep whatever text already arrived.
  void _stopStreaming() {
    _sendGeneration++;
    setState(() {
      _isStreaming = false;
      if (_messages.isNotEmpty &&
          _messages.last.role == 'assistant' &&
          _messages.last.content.isEmpty) {
        _messages.removeLast();
      }
    });
  }

  Future<void> _toggleSave() async {
    if (_conversationId == null) return;
    final saved = await ref.read(aiApiProvider).toggleSave(_conversationId!);
    if (mounted) setState(() => _isSaved = saved);
  }

  void _startNewChat() {
    // Supersede any in-flight stream so it can't re-disable the input or
    // append into the fresh conversation.
    _sendGeneration++;
    setState(() {
      _messages.clear();
      _conversationId = null;
      _isSaved = false;
      _isStreaming = false;
      _errorMessage = null;
      _mode = ChatMode.auto;
    });
  }

  Future<void> _openLibrary() async {
    final selected = await showModalBottomSheet<ConversationSummary>(
      context: context,
      isScrollControlled: true,
      builder: (context) => const _HistorySheet(),
    );
    if (selected == null || !mounted) return;

    final detail = await ref.read(aiApiProvider).getConversation(selected.id);
    if (!mounted) return;
    setState(() {
      _conversationId = detail.id;
      _mode = detail.mode;
      _isSaved = detail.isSaved;
      _messages
        ..clear()
        ..addAll(detail.messages);
    });
    _scrollToBottom();
  }

  Future<void> _deleteConversation() async {
    final id = _conversationId;
    if (id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete conversation?'),
        content: const Text(
          'This permanently deletes this conversation and its messages.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Delete', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(aiApiProvider).deleteConversation(id);
    if (!mounted) return;
    _startNewChat();
  }

  Future<void> _saveMessageToNotes(ChatMessage message) async {
    await ref
        .read(notesApiProvider)
        .createNote(
          title: 'Medaculous AI — ${_mode.label}',
          contentHtml: markdownToNoteContent(message.content),
        );
    if (!mounted) return;
    showAppToast(context, 'Saved to Notes');
  }

  Future<void> _addPersonalNote(ChatMessage message) async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add note'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 3,
          maxLines: 6,
          decoration: const InputDecoration(
            hintText: 'Your learning point or reminder…',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (text == null || text.isEmpty || !mounted) return;
    await ref
        .read(notesApiProvider)
        .createNote(
          title: 'Medaculous AI — ${_mode.label}',
          contentHtml: markdownToNoteContent(
            '**My note:**\n$text\n\n---\n**AI response:**\n${message.content}',
          ),
        );
    if (!mounted) return;
    showAppToast(context, 'Note saved');
  }

  @override
  Widget build(BuildContext context) {
    final canPickMode = _messages.isEmpty;
    // Keyboard-open + landscape means very little vertical space is left —
    // the disclaimer banner and mode picker are the first things to give up
    // their room, since the message list and input bar are what the user is
    // actually interacting with at that moment (fixes a real bottom-overflow
    // crash reported when rotating with the keyboard up).
    final keyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;

    return Scaffold(
      // No `leading` override: this screen is pushed (not a nav tab anymore),
      // so the default back arrow must stay available.
      appBar: AppBar(
        title: const Text('Medaculous AI'),
        actions: [
          IconButton(
            icon: const Icon(Icons.collections_bookmark_rounded),
            tooltip: 'Library',
            onPressed: _openLibrary,
          ),
          if (_conversationId != null)
            IconButton(
              icon: Icon(
                _isSaved
                    ? Icons.bookmark_rounded
                    : Icons.bookmark_border_rounded,
              ),
              tooltip: _isSaved ? 'Saved to library' : 'Save to library',
              onPressed: _toggleSave,
            ),
          if (_conversationId != null)
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded),
              tooltip: 'Delete conversation',
              onPressed: _deleteConversation,
            ),
          IconButton(
            icon: const Icon(Icons.add_comment_outlined),
            tooltip: 'New chat',
            onPressed: _startNewChat,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (!keyboardOpen)
              Container(
                width: double.infinity,
                color: AppColors.aiIndigo.withValues(alpha: 0.08),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.sm,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline_rounded,
                      size: 16,
                      color: AppColors.aiIndigo,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'Medaculous AI can make mistakes. Always verify against clinical judgment.',
                        style: AppTextStyles.micro.copyWith(
                          color: AppColors.aiIndigo,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (canPickMode && !keyboardOpen)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                // A Wrap dropped "Exam Prep" onto its own row whenever the 4
                // pills didn't quite fit one line width (client feedback,
                // 2026-08-15: it should sit inline next to ER). A horizontal
                // scroll keeps every mode on one row on any screen width.
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                  child: Row(
                    children: [
                      for (final mode in ChatMode.values) ...[
                        _ModePill(
                          mode: mode,
                          selected: mode == _mode,
                          onTap: () => setState(() => _mode = mode),
                        ),
                        if (mode != ChatMode.values.last) const SizedBox(width: AppSpacing.sm),
                      ],
                    ],
                  ),
                ),
              ),
            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.sm,
                ),
                child: Text(
                  _errorMessage!,
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.danger,
                  ),
                ),
              ),
            Expanded(
              child: Stack(
                children: [
                  _messages.isEmpty
                      ? Center(
                          child: Text(
                            'Ask about a case, a drug, or exam prep.',
                            style: AppTextStyles.body.copyWith(
                              color: AppColors.slate400,
                            ),
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(AppSpacing.lg),
                          itemCount: _messages.length,
                          itemBuilder: (context, index) => _MessageBubble(
                            message: _messages[index],
                            onSave: () =>
                                _saveMessageToNotes(_messages[index]),
                            onAddNote: () =>
                                _addPersonalNote(_messages[index]),
                          ),
                        ),
                  Positioned(
                    bottom: AppSpacing.sm,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: AnimatedScale(
                        scale: _showJumpToBottom ? 1 : 0,
                        duration: const Duration(milliseconds: 150),
                        child: Material(
                          shape: const CircleBorder(),
                          elevation: 3,
                          color: Theme.of(context).brightness ==
                                  Brightness.dark
                              ? AppColors.slate700
                              : Colors.white,
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () => _scrollToBottom(force: true),
                            child: const Padding(
                              padding: EdgeInsets.all(8),
                              child: Icon(
                                Icons.arrow_downward_rounded,
                                size: 22,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            _InputBar(
              controller: _inputController,
              isStreaming: _isStreaming,
              onSend: _send,
              onStop: _stopStreaming,
            ),
          ],
        ),
      ),
    );
  }
}

class _ModePill extends StatelessWidget {
  const _ModePill({
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  final ChatMode mode;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = mode.accentColor;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.pill),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadii.pill),
          border: Border.all(
            color: selected ? color : AppColors.slate200,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              mode.icon,
              size: 16,
              color: selected ? color : AppColors.slate500,
            ),
            const SizedBox(width: 6),
            Text(
              mode.label,
              style: AppTextStyles.caption.copyWith(
                color: selected ? color : AppColors.slate500,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.onSave,
    required this.onAddNote,
  });

  final ChatMessage message;
  final VoidCallback onSave;
  final VoidCallback onAddNote;

  /// The AI response bubble is always rendered on a fixed light background
  /// (`AppColors.slate100`), regardless of app theme/brightness, so it reads
  /// as a distinct "answer card" — like a printed report — in both light and
  /// dark mode. Every text style below must therefore be an explicit,
  /// WCAG-AA-contrasting dark color, never derived from `Theme.of(context)`:
  /// in dark mode the ambient text theme is light-on-dark, which previously
  /// made headings/tables/etc. nearly invisible against this light card
  /// (only the paragraph style was overridden, everything else silently
  /// inherited the theme's light text color).
  static final MarkdownStyleSheet _aiBubbleMarkdownStyleSheet =
      MarkdownStyleSheet(
        a: const TextStyle(color: AppColors.primaryDark, decoration: TextDecoration.underline),
        p: AppTextStyles.body.copyWith(color: AppColors.slate900),
        pPadding: const EdgeInsets.only(bottom: AppSpacing.xs),
        code: AppTextStyles.body.copyWith(
          color: AppColors.slate900,
          backgroundColor: AppColors.slate200,
          fontFamily: 'monospace',
          fontSize: 13,
        ),
        h1: AppTextStyles.headline.copyWith(color: AppColors.slate900),
        h1Padding: const EdgeInsets.only(bottom: AppSpacing.xs),
        h2: AppTextStyles.title.copyWith(color: AppColors.slate900),
        h2Padding: const EdgeInsets.only(top: AppSpacing.xs, bottom: 2),
        h3: AppTextStyles.bodyStrong.copyWith(color: AppColors.slate900, fontSize: 16),
        h3Padding: const EdgeInsets.only(top: AppSpacing.xs, bottom: 2),
        h4: AppTextStyles.bodyStrong.copyWith(color: AppColors.slate900),
        h5: AppTextStyles.bodyStrong.copyWith(color: AppColors.slate900),
        h6: AppTextStyles.bodyStrong.copyWith(color: AppColors.slate900),
        em: AppTextStyles.body.copyWith(color: AppColors.slate900, fontStyle: FontStyle.italic),
        strong: AppTextStyles.bodyStrong.copyWith(color: AppColors.slate900),
        // Fixed light-bubble palette: AI bubbles keep a light background in
        // both themes, so this stylesheet must not follow the app theme.
        del: AppTextStyles.body.copyWith(color: AppColors.slate500, decoration: TextDecoration.lineThrough),
        blockquote: AppTextStyles.body.copyWith(color: AppColors.slate700, fontStyle: FontStyle.italic),
        blockquotePadding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
        blockquoteDecoration: const BoxDecoration(
          border: Border(left: BorderSide(color: AppColors.slate400, width: 3)),
        ),
        img: AppTextStyles.body.copyWith(color: AppColors.slate900),
        checkbox: AppTextStyles.body.copyWith(color: AppColors.primary),
        listBullet: AppTextStyles.body.copyWith(color: AppColors.slate900),
        tableHead: AppTextStyles.bodyStrong.copyWith(color: AppColors.slate900),
        tableBody: AppTextStyles.body.copyWith(color: AppColors.slate900),
        tableBorder: TableBorder.all(color: AppColors.slate200),
        tableCellsPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
        codeblockPadding: const EdgeInsets.all(AppSpacing.sm),
        codeblockDecoration: BoxDecoration(
          color: AppColors.slate200,
          borderRadius: BorderRadius.circular(8),
        ),
        horizontalRuleDecoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.slate200, width: 1)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    final isComplete = message.content.isNotEmpty;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: isUser
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.8,
            ),
            margin: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: isUser ? AppColors.primary : AppColors.slate100,
              borderRadius: BorderRadius.circular(16),
            ),
            child: message.content.isEmpty
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : isUser
                ? Text(
                    message.content,
                    style: AppTextStyles.body.copyWith(color: Colors.white),
                  )
                : MarkdownBody(
                    data: message.content,
                    styleSheet: _aiBubbleMarkdownStyleSheet,
                  ),
          ),
          if (!isUser && isComplete)
            Padding(
              padding: const EdgeInsets.only(
                left: AppSpacing.sm,
                bottom: AppSpacing.sm,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _MessageAction(
                    icon: Icons.bookmark_add_outlined,
                    label: 'Save',
                    onTap: onSave,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  _MessageAction(
                    icon: Icons.edit_note_rounded,
                    label: 'Add note',
                    onTap: onAddNote,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _MessageAction extends StatelessWidget {
  const _MessageAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: context.secondaryText),
            const SizedBox(width: 4),
            Text(
              label,
              style: AppTextStyles.micro.copyWith(color: context.secondaryText),
            ),
          ],
        ),
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.isStreaming,
    required this.onSend,
    required this.onStop,
  });

  final TextEditingController controller;
  final bool isStreaming;
  final VoidCallback onSend;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              // Stays enabled while streaming (GPT behavior): the user can
              // draft the next message; only sending waits.
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              style: TextStyle(
                color: isDark ? Colors.white : AppColors.slate900,
              ),
              decoration: InputDecoration(
                hintText: 'Message Medaculous AI…',
                filled: true,
                fillColor: isDark ? AppColors.slate800 : AppColors.slate100,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.sm,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          // While the answer streams the send arrow becomes a stop square,
          // then flips back once the response is complete.
          IconButton.filled(
            onPressed: isStreaming ? onStop : onSend,
            tooltip: isStreaming ? 'Stop generating' : 'Send',
            icon: Icon(
              isStreaming ? Icons.stop_rounded : Icons.arrow_upward_rounded,
            ),
          ),
        ],
      ),
    );
  }
}

class _HistorySheet extends ConsumerStatefulWidget {
  const _HistorySheet();

  @override
  ConsumerState<_HistorySheet> createState() => _HistorySheetState();
}

class _HistorySheetState extends ConsumerState<_HistorySheet> {
  bool _savedOnly = true;
  List<ConversationSummary>? _all;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final conversations = await ref.read(aiApiProvider).listConversations();
    if (mounted) setState(() => _all = conversations);
  }

  Future<void> _rename(ConversationSummary c) async {
    final controller = TextEditingController(text: c.title);
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename conversation'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 80,
          decoration: const InputDecoration(hintText: 'Conversation title'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (title == null || title.isEmpty || title == c.title) return;
    await ref.read(aiApiProvider).renameConversation(c.id, title);
    _load();
  }

  Future<void> _delete(ConversationSummary c) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete conversation?'),
        content: Text(
          '"${c.title}" and its messages will be permanently deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Delete', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(aiApiProvider).deleteConversation(c.id);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      expand: false,
      builder: (context, scrollController) {
        final all = _all;
        if (all == null) {
          return const Center(child: CircularProgressIndicator());
        }
        var conversations = _savedOnly
            ? all.where((c) => c.isSaved).toList()
            : all;
        if (_query.isNotEmpty) {
          final q = _query.toLowerCase();
          conversations = conversations
              .where((c) => c.title.toLowerCase().contains(q))
              .toList();
        }
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                0,
              ),
              child: Row(
                children: [
                  Text('Chats', style: AppTextStyles.title),
                  const Spacer(),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: true, label: Text('Saved')),
                      ButtonSegment(value: false, label: Text('All')),
                    ],
                    selected: {_savedOnly},
                    onSelectionChanged: (s) =>
                        setState(() => _savedOnly = s.first),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                0,
              ),
              child: TextField(
                onChanged: (value) => setState(() => _query = value.trim()),
                decoration: InputDecoration(
                  hintText: 'Search chats…',
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                ),
              ),
            ),
            Expanded(
              child: conversations.isEmpty
                  ? Center(
                      child: Text(
                        _query.isNotEmpty
                            ? 'No chats match "$_query".'
                            : _savedOnly
                            ? 'No saved conversations yet.'
                            : 'No conversations yet.',
                        style: AppTextStyles.body.copyWith(
                          color: AppColors.slate400,
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.all(AppSpacing.md),
                      itemCount: conversations.length,
                      itemBuilder: (context, index) {
                        final c = conversations[index];
                        return ListTile(
                          leading: Icon(
                            c.isSaved
                                ? Icons.bookmark_rounded
                                : Icons.chat_bubble_outline_rounded,
                            color: AppColors.aiIndigo,
                          ),
                          title: Text(
                            c.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.bodyStrong,
                          ),
                          subtitle: Text(
                            '${c.mode.label} · ${_formatHistoryDate(c.updatedAt)}',
                            style: AppTextStyles.caption.copyWith(
                              color: context.secondaryText,
                            ),
                          ),
                          trailing: PopupMenuButton<String>(
                            icon: const Icon(Icons.more_vert_rounded, size: 20),
                            onSelected: (action) {
                              if (action == 'rename') _rename(c);
                              if (action == 'delete') _delete(c);
                            },
                            itemBuilder: (context) => [
                              const PopupMenuItem(
                                value: 'rename',
                                child: ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  dense: true,
                                  leading: Icon(Icons.edit_outlined, size: 20),
                                  title: Text('Rename'),
                                ),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  dense: true,
                                  leading: Icon(
                                    Icons.delete_outline_rounded,
                                    size: 20,
                                    color: AppColors.danger,
                                  ),
                                  title: Text(
                                    'Delete',
                                    style: TextStyle(color: AppColors.danger),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          onTap: () => Navigator.of(context).pop(c),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}
