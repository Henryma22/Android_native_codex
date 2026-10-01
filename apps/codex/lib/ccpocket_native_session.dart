import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show ValueGetter, ValueListenable, clampDouble;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import 'package:ccpocket_ui/features/chat_session/widgets/codex_settings_sheet.dart';
import 'package:ccpocket_ui/l10n/app_localizations.dart';
import 'package:ccpocket_ui/models/messages.dart' as pocket;
import 'package:ccpocket_ui/theme/app_theme.dart' as pocket_theme;
import 'package:ccpocket_ui/widgets/chat_input_bar.dart';
import 'package:ccpocket_ui/widgets/codex_effort_slider.dart';
import 'package:ccpocket_ui/widgets/message_bubble.dart';
import 'package:ccpocket_ui/widgets/bubbles/inline_edit_diff.dart';
import 'package:ccpocket_ui/utils/diff_parser.dart';

import 'core/application/agent_file_change_preview.dart';
import 'core/application/codex_auth_client.dart';
import 'core/application/codex_model_catalog.dart';
import 'core/domain/session.dart';
import 'core/domain/transcript.dart';
import 'core/domain/image_attachment.dart';

/// The live assistant/reasoning projection is updated independently from the
/// surrounding session chrome. Keeping it as one immutable value lets a
/// streaming delta repaint only the message list instead of rebuilding the
/// app bar, mode bar, composer, and retained session pages.
class CcpocketNativeStreamingSnapshot {
  const CcpocketNativeStreamingSnapshot({
    this.assistant = '',
    this.thinking = '',
  });

  final String assistant;
  final String thinking;
}

/// The local Android session surface is assembled from CC Pocket's actual
/// presentation widgets.  Only the adapter below knows how the local
/// app-server transcript and lifecycle map onto CC Pocket's message model.
/// No remote client, socket, or machine/session service is created here.
class CcpocketNativeSessionSurface extends StatelessWidget {
  const CcpocketNativeSessionSurface({
    required this.entries,
    required this.status,
    required this.controller,
    required this.onSend,
    required this.onStop,
    required this.onInterrupt,
    required this.onSlashCommand,
    required this.onMention,
    required this.onShowPromptHistory,
    required this.onIndent,
    required this.onDedent,
    required this.header,
    this.streamingAssistant = '',
    this.streamingThinking = '',
    this.queuedPrompts = const <String>[],
    this.onRemoveQueuedPrompt,
    this.approval,
    this.userInput,
    this.modeBar,
    this.accountUsageSummary,
    this.usageSummary,
    this.attachedImages = const <ImageAttachment>[],
    this.onAttachImage,
    this.onClearImage,
    this.streamingSnapshot,
    this.localizeEntry,
    this.inputBlocked = false,
    this.reverse = true,
    super.key,
  });

  final List<String> entries;
  final String status;
  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback onStop;
  final VoidCallback onInterrupt;
  final VoidCallback onSlashCommand;
  final VoidCallback onMention;
  final VoidCallback onShowPromptHistory;
  final VoidCallback onIndent;
  final VoidCallback onDedent;
  final Widget? header;
  final String streamingAssistant;
  final String streamingThinking;
  final List<String> queuedPrompts;
  final ValueChanged<int>? onRemoveQueuedPrompt;
  final Widget? approval;
  final Widget? userInput;
  final Widget? modeBar;

  /// CC Pocket's compact 5h/1w account quota summary for the conversation.
  final Widget? accountUsageSummary;

  /// CC Pocket's per-conversation token/tool summary strip.
  final Widget? usageSummary;
  final List<ImageAttachment> attachedImages;
  final VoidCallback? onAttachImage;
  final void Function([int? index])? onClearImage;
  final ValueListenable<CcpocketNativeStreamingSnapshot>? streamingSnapshot;

  /// Optional adapter for display-only localization of persisted local rows.
  /// The stored transcript remains unchanged so switching locale does not
  /// rewrite session history.
  final String Function(String entry)? localizeEntry;
  final bool inputBlocked;
  final bool reverse;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context);
    final surface = Column(
      children: [
        if (accountUsageSummary case final summary?) summary,
        if (usageSummary case final summary?) summary,
        if (modeBar case final summary?) summary,
        if (header case final sessionHeader?)
          Flexible(
            fit: FlexFit.loose,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
              child: sessionHeader,
            ),
          ),
        Expanded(
          child: streamingSnapshot == null
              ? CcpocketNativeMessageList(
                  entries: entries,
                  status: status,
                  streamingAssistant: streamingAssistant,
                  streamingThinking: streamingThinking,
                  localizeEntry: localizeEntry,
                  reverse: reverse,
                )
              : ValueListenableBuilder<CcpocketNativeStreamingSnapshot>(
                  valueListenable: streamingSnapshot!,
                  builder: (_, snapshot, _) {
                    return CcpocketNativeMessageList(
                      entries: entries,
                      status: status,
                      streamingAssistant: snapshot.assistant,
                      streamingThinking: snapshot.thinking,
                      localizeEntry: localizeEntry,
                      reverse: reverse,
                    );
                  },
                ),
        ),
        if (approval case final approvalWidget?) approvalWidget,
        if (userInput case final userInputWidget?) userInputWidget,
        if (queuedPrompts.isNotEmpty)
          _QueuedPromptStrip(
            prompts: queuedPrompts,
            onRemove: onRemoveQueuedPrompt,
          ),
        CcpocketNativeComposer(
          controller: controller,
          status: status,
          inputBlocked: inputBlocked,
          onSend: onSend,
          onStop: onStop,
          onInterrupt: onInterrupt,
          onSlashCommand: onSlashCommand,
          onMention: onMention,
          onShowPromptHistory: onShowPromptHistory,
          onIndent: onIndent,
          onDedent: onDedent,
          attachedImages: attachedImages,
          onAttachImage: onAttachImage,
          onClearImage: onClearImage,
        ),
      ],
    );
    return Localizations(
      // Preserve CC Pocket's ambient app locale instead of forcing the copied
      // session surface back to English.
      locale: locale,
      delegates: AppLocalizations.localizationsDelegates,
      child: theme.extension<pocket_theme.AppColors>() == null
          ? Theme(data: pocket_theme.AppTheme.lightTheme, child: surface)
          : surface,
    );
  }
}

/// CC Pocket's chat list uses a reverse list and real ChatEntry widgets.  The
/// local client keeps a compact durable transcript, so this adapter projects
/// each persisted record into the original CC Pocket message bubbles.
class CcpocketNativeMessageList extends StatefulWidget {
  const CcpocketNativeMessageList({
    required this.entries,
    required this.status,
    this.streamingAssistant = '',
    this.streamingThinking = '',
    this.localizeEntry,
    this.reverse = true,
    super.key,
  });

  final List<String> entries;
  final String status;
  final String streamingAssistant;
  final String streamingThinking;
  final String Function(String entry)? localizeEntry;
  final bool reverse;

  @override
  State<CcpocketNativeMessageList> createState() =>
      _CcpocketNativeMessageListState();
}

/// Same viewport-stability rule used by CC Pocket's ChatMessageList. A
/// composer, keyboard, approval card or user-input card can resize the
/// viewport while the user is reading older history; preserve that reading
/// position unless the list is following the newest message.
class _MaintainReadingPositionPhysics extends ScrollPhysics {
  const _MaintainReadingPositionPhysics({
    required this.shouldMaintain,
    super.parent,
  });

  final ValueGetter<bool> shouldMaintain;

  @override
  _MaintainReadingPositionPhysics applyTo(ScrollPhysics? ancestor) {
    return _MaintainReadingPositionPhysics(
      shouldMaintain: shouldMaintain,
      parent: buildParent(ancestor),
    );
  }

  @override
  double adjustPositionForNewDimensions({
    required ScrollMetrics oldPosition,
    required ScrollMetrics newPosition,
    required bool isScrolling,
    required double velocity,
  }) {
    final adjusted = super.adjustPositionForNewDimensions(
      oldPosition: oldPosition,
      newPosition: newPosition,
      isScrolling: isScrolling,
      velocity: velocity,
    );
    if (isScrolling || !shouldMaintain()) return adjusted;
    final viewportDelta =
        oldPosition.viewportDimension - newPosition.viewportDimension;
    if (viewportDelta.abs() <= 1) return adjusted;
    return clampDouble(
      newPosition.pixels + viewportDelta,
      newPosition.minScrollExtent,
      newPosition.maxScrollExtent,
    );
  }
}

class _CcpocketNativeMessageListState extends State<CcpocketNativeMessageList> {
  final _scrollController = ScrollController();
  // Streaming deltas rebuild the session surface several times per second.
  // Parsing every persisted JSON transcript record on every rebuild made the
  // cost grow with history length and caused input/scroll jank on phones.
  // Keep the CC Pocket entry objects stable and only parse a raw record once.
  // The source row is the cache key rather than its localized projection, so
  // streaming rebuilds do not repeat JSON/localization work for visible
  // history and two different source rows cannot alias just because they
  // render to the same localized text.
  final Map<String, pocket.ChatEntry?> _entryCache =
      <String, pocket.ChatEntry?>{};
  String? _entryCacheLocale;
  var _followLatest = true;
  var _lastRenderedItemCount = -1;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_trackReadingPosition);
  }

  void _trackReadingPosition() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final distanceToLatest = widget.reverse
        ? position.pixels
        : position.maxScrollExtent - position.pixels;
    _followLatest = distanceToLatest <= 48;
  }

  void _scheduleLatestPosition({required bool force}) {
    if (!force && !_followLatest) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final target = widget.reverse
          ? 0.0
          : _scrollController.position.maxScrollExtent;
      if ((_scrollController.position.pixels - target).abs() < 1) return;
      _scrollController.jumpTo(target);
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_trackReadingPosition);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localeKey = Localizations.localeOf(context).languageCode;
    if (_entryCacheLocale != localeKey) {
      _entryCacheLocale = localeKey;
      _entryCache.clear();
    }
    final hasStreaming =
        widget.streamingAssistant.trim().isNotEmpty ||
        widget.streamingThinking.trim().isNotEmpty ||
        widget.status.toLowerCase().contains('running');
    final itemCount = widget.entries.length + (hasStreaming ? 1 : 0);
    if (itemCount != _lastRenderedItemCount) {
      final previousCount = _lastRenderedItemCount;
      final force = previousCount < 0 || itemCount < previousCount;
      _lastRenderedItemCount = itemCount;
      if (force) _followLatest = true;
      _scheduleLatestPosition(force: force);
    }
    if (itemCount == 0 || !_hasVisibleEntry(hasStreaming)) {
      final emptyStateCopy = switch (Localizations.localeOf(context)
          .languageCode) {
        'zh' => ('开始对话', '输入消息，即可开始这个 Codex 会话。'),
        'ja' => ('会話を始めましょう', 'メッセージを入力して、この Codex セッションを開始してください。'),
        'ko' => ('대화를 시작하세요', '메시지를 입력하여 이 Codex 세션을 시작하세요.'),
        _ => (
          'Start your conversation',
          'Send a message to begin this Codex session.',
        ),
      };
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.auto_awesome_outlined,
                size: 34,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 12),
              Text(
                emptyStateCopy.$1,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                emptyStateCopy.$2,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollStartNotification &&
            notification.dragDetails != null) {
          FocusScope.of(context).unfocus();
        }
        return false;
      },
      child: ListView.builder(
        key: const ValueKey('ccpocket_native_message_list'),
        controller: _scrollController,
        reverse: widget.reverse,
        physics: _MaintainReadingPositionPhysics(
          shouldMaintain: () => !_followLatest,
        ),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.only(top: 16, bottom: 8),
        itemCount: itemCount,
        itemBuilder: (context, index) {
          final logicalIndex = widget.reverse ? itemCount - index - 1 : index;
          final streamingIndex = widget.entries.length;
          final isStreaming = hasStreaming && logicalIndex == streamingIndex;
          final entry = isStreaming
              ? pocket.StreamingChatEntry(
                  text: widget.streamingAssistant,
                  thinking: widget.streamingThinking,
                )
              : _cachedChatEntry(widget.entries[logicalIndex]);
          if (entry == null) return const SizedBox.shrink();
          final previous = logicalIndex == 0
              ? null
              : _entryAt(logicalIndex - 1, hasStreaming: hasStreaming);
          return KeyedSubtree(
            key: ValueKey('ccpocket_native_entry_$logicalIndex'),
            child: RepaintBoundary(
              child: ChatEntryWidget(
                entry: entry,
                previous: previous,
                isCodex: true,
              ),
            ),
          );
        },
      ),
    );
  }

  bool _hasVisibleEntry(bool hasStreaming) {
    if (hasStreaming) return true;
    // Most transcripts end in a visible user, assistant, or tool entry. Walk
    // backward only across filtered housekeeping lines instead of parsing the
    // complete history just to decide whether to show the empty state.
    for (final raw in widget.entries.reversed) {
      if (_cachedChatEntry(raw) != null) return true;
    }
    return false;
  }

  pocket.ChatEntry? _entryAt(int index, {required bool hasStreaming}) {
    if (index < 0) return null;
    if (hasStreaming && index == widget.entries.length) {
      return pocket.StreamingChatEntry(
        text: widget.streamingAssistant,
        thinking: widget.streamingThinking,
      );
    }
    if (index >= widget.entries.length) return null;
    return _cachedChatEntry(widget.entries[index]);
  }

  pocket.ChatEntry? _cachedChatEntry(String raw) {
    if (_entryCache.containsKey(raw)) {
      final entry = _entryCache.remove(raw);
      _entryCache[raw] = entry;
      return entry;
    }
    final displayRaw = widget.localizeEntry?.call(raw) ?? raw;
    final entry = _toChatEntry(displayRaw);
    // Keep visible/recent messages hot without retaining an unbounded
    // presentation cache for a long-running session.
    if (_entryCache.length >= 512) {
      _entryCache.remove(_entryCache.keys.first);
    }
    _entryCache[raw] = entry;
    return entry;
  }
}

pocket.ChatEntry? _toChatEntry(String raw) {
  final local = CodexTranscriptEntry.fromStored(raw);
  final message = local.text;
  // Older local histories may contain the harmless Android arg0 janitor
  // diagnostic that was emitted before the runtime ownership fix. Do not
  // project that stderr line as a conversation bubble, otherwise it shifts
  // the restored message stack and becomes the first thing the user sees.
  if (_isBenignArg0CleanupWarning(message) ||
      _isBenignArg0CleanupWarning(local.displayLine)) {
    return null;
  }
  final timestamp = local.timestamp;

  if (local.kind == CodexTranscriptKind.user) {
    return pocket.UserChatEntry(
      message,
      timestamp: timestamp,
      clientMessageId: local.id,
      status: pocket.MessageStatus.sent,
    );
  }
  if (local.kind == CodexTranscriptKind.assistant) {
    return pocket.ServerChatEntry(
      pocket.AssistantServerMessage(
        message: pocket.AssistantMessage(
          id: local.id,
          role: 'assistant',
          model: local.model,
          content: [pocket.TextContent(text: message)],
        ),
      ),
      timestamp: timestamp,
    );
  }
  if (local.kind == CodexTranscriptKind.reasoning) {
    return pocket.ServerChatEntry(
      pocket.AssistantServerMessage(
        message: pocket.AssistantMessage(
          id: local.id,
          role: 'assistant',
          model: local.model,
          content: [pocket.ThinkingContent(thinking: message)],
        ),
      ),
      timestamp: timestamp,
    );
  }
  if (local.kind == CodexTranscriptKind.tool ||
      local.kind == CodexTranscriptKind.toolResult) {
    final item = local.data;
    final toolId =
        _firstText(item, const ['toolUseId', 'callId', 'id']) ?? local.id;
    final toolName =
        local.toolName ??
        _firstText(item, const ['toolName', 'name', 'type']) ??
        'Codex tool';
    if (local.kind == CodexTranscriptKind.toolResult ||
        _looksLikeToolResult(item)) {
      return pocket.ServerChatEntry(
        pocket.ToolResultMessage(
          toolUseId: toolId,
          toolName: toolName,
          content: _toolResultText(item, message),
        ),
        timestamp: timestamp,
      );
    }
    return pocket.ServerChatEntry(
      pocket.AssistantServerMessage(
        message: pocket.AssistantMessage(
          id: local.id,
          role: 'assistant',
          model: local.model,
          content: [
            pocket.ToolUseContent(
              id: toolId,
              name: toolName,
              input: _toolInput(item, message),
            ),
          ],
        ),
      ),
      timestamp: timestamp,
    );
  }
  if (local.kind == CodexTranscriptKind.error) {
    return pocket.ServerChatEntry(
      pocket.ErrorMessage(message: message),
      timestamp: timestamp,
    );
  }
  if (local.kind == CodexTranscriptKind.status) {
    return pocket.ServerChatEntry(
      pocket.StatusMessage(
        status: pocket.ProcessStatus.fromString(message.toLowerCase()),
      ),
      timestamp: timestamp,
    );
  }
  if (local.kind == CodexTranscriptKind.system) {
    return pocket.ServerChatEntry(
      pocket.SystemMessage(subtype: _systemNoticeSubtype(message)),
      timestamp: timestamp,
    );
  }
  return pocket.ServerChatEntry(
    pocket.SystemMessage(subtype: _systemNoticeSubtype(message)),
    timestamp: timestamp,
  );
}

bool _isBenignArg0CleanupWarning(String value) {
  return isBenignCodexRuntimeDiagnostic(value);
}

String _systemNoticeSubtype(String message) {
  final normalized = message.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (normalized.isEmpty) return 'notice';
  if (normalized.length <= 240) return normalized;
  return '${normalized.substring(0, 237)}…';
}

String? _firstText(Map<String, dynamic> value, List<String> keys) {
  for (final key in keys) {
    final candidate = value[key]?.toString().trim();
    if (candidate != null && candidate.isNotEmpty) return candidate;
  }
  return null;
}

bool _looksLikeToolResult(Map<String, dynamic> item) {
  return const [
    'output',
    'aggregatedOutput',
    'result',
    'content',
    'error',
  ].any(item.containsKey);
}

Map<String, dynamic> _toolInput(Map<String, dynamic> item, String fallback) {
  final input = item['input'];
  if (input is Map) {
    return <String, dynamic>{
      for (final entry in input.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
  }
  if (item.isNotEmpty) return Map<String, dynamic>.from(item);
  return <String, dynamic>{'text': fallback};
}

String _toolResultText(Map<String, dynamic> item, String fallback) {
  for (final key in const [
    'output',
    'aggregatedOutput',
    'result',
    'content',
    'error',
  ]) {
    final value = item[key];
    if (value is String && value.trim().isNotEmpty) return value;
    if (value is List) {
      final text = value
          .whereType<Map>()
          .map((part) => part['text']?.toString() ?? '')
          .where((part) => part.trim().isNotEmpty)
          .join('\n');
      if (text.isNotEmpty) return text;
    }
  }
  return fallback;
}

class CcpocketNativeComposer extends StatefulWidget {
  const CcpocketNativeComposer({
    required this.controller,
    required this.status,
    required this.inputBlocked,
    required this.onSend,
    required this.onStop,
    required this.onInterrupt,
    required this.onSlashCommand,
    required this.onMention,
    required this.onShowPromptHistory,
    required this.onIndent,
    required this.onDedent,
    this.attachedImages = const <ImageAttachment>[],
    this.onAttachImage,
    this.onClearImage,
    super.key,
  });

  final TextEditingController controller;
  final String status;
  final bool inputBlocked;
  final VoidCallback onSend;
  final VoidCallback onStop;
  final VoidCallback onInterrupt;
  final VoidCallback onSlashCommand;
  final VoidCallback onMention;
  final VoidCallback onShowPromptHistory;
  final VoidCallback onIndent;
  final VoidCallback onDedent;
  final List<ImageAttachment> attachedImages;
  final VoidCallback? onAttachImage;
  final void Function([int? index])? onClearImage;

  @override
  State<CcpocketNativeComposer> createState() => _CcpocketNativeComposerState();
}

class _CcpocketNativeComposerState extends State<CcpocketNativeComposer> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  @override
  void didUpdateWidget(covariant CcpocketNativeComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  pocket.ProcessStatus get _processStatus {
    final normalized = widget.status.toLowerCase();
    if (widget.inputBlocked && normalized.contains('starting')) {
      return pocket.ProcessStatus.starting;
    }
    if (normalized.contains('waiting')) {
      return pocket.ProcessStatus.waitingApproval;
    }
    if (normalized.contains('running') || normalized.contains('thinking')) {
      return pocket.ProcessStatus.running;
    }
    return pocket.ProcessStatus.idle;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return KeyedSubtree(
      key: const ValueKey('local_codex_composer'),
      child: ChatInputBar(
        inputController: widget.controller,
        status: _processStatus,
        hasInputText: widget.controller.text.trim().isNotEmpty,
        isInputEmpty: widget.controller.text.isEmpty,
        isVoiceAvailable: false,
        isRecording: false,
        onSend: widget.inputBlocked ? () {} : widget.onSend,
        onStop: widget.onStop,
        onInterrupt: widget.onInterrupt,
        onToggleVoice: () {},
        onIndent: widget.onIndent,
        onDedent: widget.onDedent,
        canDedent: _canDedent(widget.controller),
        onSlashCommand: widget.onSlashCommand,
        onMention: widget.onMention,
        isInMentionContext: false,
        showDollarButton: false,
        onShowPromptHistory: widget.onShowPromptHistory,
        onAttachImage: widget.onAttachImage,
        attachedImages: widget.attachedImages
            .map<({Uint8List bytes, String mimeType})>(
              (image) => (bytes: image.bytes, mimeType: image.mimeType),
            )
            .toList(growable: false),
        onClearImage: widget.onClearImage,
        hintText: l.codexMessagePlaceholder,
      ),
    );
  }
}

bool _canDedent(TextEditingController controller) {
  final selection = controller.selection;
  final start = selection.start < 0 ? controller.text.length : selection.start;
  final lineStart =
      (start <= 0 ? -1 : controller.text.lastIndexOf('\n', start - 1)) + 1;
  return controller.text.substring(lineStart, start).startsWith(' ');
}

class _QueuedPromptStrip extends StatelessWidget {
  const _QueuedPromptStrip({required this.prompts, this.onRemove});

  final List<String> prompts;
  final ValueChanged<int>? onRemove;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
      color: cs.surfaceContainerLow,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            Chip(
              avatar: Icon(Icons.schedule, size: 16),
              label: Text(l.sessionCardQueuedInput),
            ),
            for (var index = 0; index < prompts.length; index++)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: InputChip(
                  label: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 220),
                    child: Text(
                      prompts[index],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  onDeleted: onRemove == null ? null : () => onRemove!(index),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class CcpocketNativeModeBar extends StatelessWidget {
  const CcpocketNativeModeBar({
    required this.model,
    required this.effort,
    required this.approvalPolicy,
    required this.sandbox,
    required this.planMode,
    required this.onOpenSettings,
    required this.onOpenPermissions,
    required this.onTogglePlan,
    this.onOpenEffortSettings,
    this.showCodexControls = true,
    this.rootMode = false,
    super.key,
  });

  final String model;
  final String effort;
  final String approvalPolicy;
  final String sandbox;
  final bool planMode;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenPermissions;
  final VoidCallback onTogglePlan;
  final VoidCallback? onOpenEffortSettings;
  final bool showCodexControls;
  final bool rootMode;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final appColors =
        Theme.of(context).extension<pocket_theme.AppColors>() ??
        pocket_theme.AppColors.light();
    final effortValue = pocket.ReasoningEffort.fromValue(effort);
    final effortLabel = _nativeEffortLabel(effortValue, zh: zh);
    final modelLabel = showCodexControls && onOpenEffortSettings == null
        ? '${codexModelDisplayName(model)} $effortLabel'
        : codexModelDisplayName(model);
    final permissions = pocket.codexPermissionsModeFromSettings(
      approvalPolicy: approvalPolicy,
      approvalsReviewer: 'user',
      sandboxMode: sandbox,
    );
    final permissionsStyle = sandbox == 'read-only'
        ? (
            Icons.visibility_outlined,
            zh ? '只读' : 'Read only',
            cs.onSurfaceVariant,
          )
        : rootMode
        ? (Icons.admin_panel_settings_outlined, 'Root', cs.primary)
        : switch (permissions) {
            pocket.CodexPermissionsMode.defaultPermissions => (
              Icons.back_hand_outlined,
              zh ? '默认' : 'Default',
              cs.onSurfaceVariant,
            ),
            pocket.CodexPermissionsMode.autoReview => (
              Icons.shield_outlined,
              zh ? '自动审查' : 'Auto Review',
              cs.primary,
            ),
            pocket.CodexPermissionsMode.fullAccess => (
              Icons.warning_amber_outlined,
              zh ? '完全访问' : 'Full',
              cs.error,
            ),
            pocket.CodexPermissionsMode.custom => (
              Icons.settings_outlined,
              zh ? '自定义' : 'Custom',
              cs.primary,
            ),
          };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 1),
          decoration: BoxDecoration(
            color: isDark
                ? cs.surface.withValues(alpha: 0.92)
                : cs.surface.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.1)
                  : Colors.white.withValues(alpha: 0.6),
            ),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _NativeModeChip(
                  key: const ValueKey('local_codex_model_chip'),
                  label: modelLabel,
                  color: cs.onSurfaceVariant,
                  onTap: onOpenSettings,
                  maxWidth: 150,
                ),
                if (onOpenEffortSettings != null) ...[
                  _NativeModeDivider(color: cs.outlineVariant),
                  _NativeModeChip(
                    key: const ValueKey('local_codex_effort_chip'),
                    label: effortLabel,
                    color: cs.onSurfaceVariant,
                    onTap: onOpenEffortSettings!,
                  ),
                ],
                if (showCodexControls) ...[
                  _NativeModeDivider(color: cs.outlineVariant),
                  _NativeModeChip(
                    key: const ValueKey('local_codex_plan_mode_chip'),
                    label: planMode
                        ? (zh ? '计划开启' : 'Plan On')
                        : (zh ? '计划关闭' : 'Plan Off'),
                    color: planMode
                        ? appColors.statusPlan
                        : cs.onSurfaceVariant,
                    onTap: onTogglePlan,
                  ),
                  _NativeModeDivider(color: cs.outlineVariant),
                  _NativeModeChip(
                    key: const ValueKey('local_codex_execution_mode_chip'),
                    icon: permissionsStyle.$1,
                    label: permissionsStyle.$2,
                    color: permissionsStyle.$3,
                    onTap: onOpenPermissions,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NativeModeDivider extends StatelessWidget {
  const _NativeModeDivider({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 18,
      child: VerticalDivider(
        width: 1,
        thickness: 1,
        color: color.withValues(alpha: 0.4),
      ),
    );
  }
}

class _NativeModeChip extends StatelessWidget {
  const _NativeModeChip({
    required this.label,
    required this.color,
    required this.onTap,
    this.icon,
    this.maxWidth,
    super.key,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;
  final IconData? icon;
  final double? maxWidth;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 44, minHeight: 34),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 13, color: color),
                    const SizedBox(width: 3),
                  ],
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxWidth ?? 110),
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.arrow_drop_down,
                    size: 14,
                    color: color.withValues(alpha: 0.5),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _nativeEffortLabel(pocket.ReasoningEffort effort, {required bool zh}) {
  if (!zh) return effort.label;
  return switch (effort.value) {
    'none' => '无',
    'minimal' => '最小',
    'low' => '低',
    'medium' => '中',
    'high' => '高',
    'xhigh' => '极高',
    'max' => '最大',
    'ultra' => '超级',
    _ => effort.label,
  };
}

Future<void> showCcpocketNativeCodexSettings({
  required BuildContext context,
  required String model,
  required String effort,
  List<CodexModelDescriptor> models = const <CodexModelDescriptor>[],
  Future<CodexModelCatalog> Function()? loadModelCatalog,
  required ValueChanged<String> onModelChanged,
  required ValueChanged<String> onEffortChanged,
}) async {
  var availableModels = models;
  await showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) => StatefulBuilder(
      builder: (context, setSheetState) {
        final descriptors = <String, CodexModelDescriptor>{
          for (final descriptor in availableModels) descriptor.id: descriptor,
          if (!availableModels.any((descriptor) => descriptor.id == model))
            model: CodexModelDescriptor(
              id: model,
              displayName: model,
              reasoningEfforts: <String>[effort],
            ),
        };
        final modelIds = descriptors.keys.toList(growable: false);
        final modelEfforts = <String, List<pocket.ReasoningEffort>>{
          for (final modelId in modelIds)
            modelId: [
              for (final rawEffort
                  in descriptors[modelId]!.reasoningEfforts.isEmpty
                      ? const <String>['low']
                      : descriptors[modelId]!.reasoningEfforts)
                pocket.ReasoningEffort.fromValue(rawEffort),
            ],
        };
        final requestedEffort = pocket.ReasoningEffort.fromValue(effort);
        final supportedEfforts = modelEfforts[model]!;
        final initialEffort = supportedEfforts.contains(requestedEffort)
            ? requestedEffort
            : supportedEfforts.first;

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CodexSettingsSheet(
                models: modelIds,
                loadModelOptions: loadModelCatalog == null
                    ? null
                    : () async {
                        final catalog = await loadModelCatalog();
                        if (sheetContext.mounted) {
                          setSheetState(() => availableModels = catalog.models);
                        }
                        return catalog.models
                            .map((model) => model.id)
                            .toList(growable: false);
                      },
                modelEfforts: modelEfforts,
                modelServiceTiers: const {},
                initialModel: model,
                initialEffort: initialEffort,
                initialSpeed: pocket.CodexSpeed.standard,
                showExtendedEfforts: true,
                // The thread chip is explicitly a model control. Put model
                // selection in the first sheet state instead of hiding it
                // behind CC Pocket's quick-effort view and an extra toggle.
                initialShowAdvanced: true,
                onModelChanged: (next, nextEffort) {
                  onModelChanged(next);
                  onEffortChanged(nextEffort.value);
                },
                onEffortChanged: (_, next) => onEffortChanged(next.value),
                onSpeedChanged: (_) {},
              ),
            ],
          ),
        );
      },
    ),
  );
}

Future<void> showCcpocketNativeProviderEffortSettings({
  required BuildContext context,
  required String model,
  required String effort,
  required ValueChanged<String> onEffortChanged,
}) async {
  const efforts = <pocket.ReasoningEffort>[
    pocket.ReasoningEffort.none,
    pocket.ReasoningEffort.low,
    pocket.ReasoningEffort.high,
    pocket.ReasoningEffort.max,
  ];
  final initialEffort = switch (effort.trim().toLowerCase()) {
    'none' => pocket.ReasoningEffort.none,
    'minimal' || 'low' => pocket.ReasoningEffort.low,
    'medium' || 'high' || 'xhigh' => pocket.ReasoningEffort.high,
    'max' || 'ultra' => pocket.ReasoningEffort.max,
    _ => pocket.ReasoningEffort.low,
  };
  await showModalBottomSheet<void>(
    context: context,
    builder: (context) => CodexSettingsSheet(
      models: <String>[model],
      modelEfforts: <String, List<pocket.ReasoningEffort>>{model: efforts},
      modelServiceTiers: const <String, List<String>>{},
      initialModel: model,
      initialEffort: initialEffort,
      initialSpeed: pocket.CodexSpeed.standard,
      showExtendedEfforts: true,
      onModelChanged: (_, nextEffort) => onEffortChanged(nextEffort.value),
      onEffortChanged: (_, nextEffort) => onEffortChanged(nextEffort.value),
      onSpeedChanged: (_) {},
    ),
  );
}

class _LocalizedFileChangePermissionMessage
    extends pocket.PermissionRequestMessage {
  const _LocalizedFileChangePermissionMessage({
    required super.toolUseId,
    required super.input,
    required this.localizations,
  }) : super(toolName: 'FileChange');

  final AppLocalizations localizations;

  @override
  pocket.PermissionPresentation get presentation {
    final base = super.presentation;
    final paths = _fileChangeApprovalPaths(input['changes']);
    final summary = switch (paths.length) {
      0 => localizations.allowFileChanges,
      1 => localizations.allowChangesToFile(paths.first),
      _ => localizations.allowChangesToFiles(paths.length),
    };
    final target = paths.length < 2
        ? (paths.isEmpty ? null : paths.first)
        : '${paths.first} ${localizations.additionalFiles(paths.length - 1)}';

    return pocket.PermissionPresentation(
      title: localizations.fileChangeApprovalTitle,
      summary: _nonEmptyApprovalReason(input['reason']) ?? summary,
      rawDetails: base.rawDetails,
      riskBadge: base.riskBadge,
      scopeLabel: base.scopeLabel,
      primaryTargetLabel: base.primaryTargetLabel,
      primaryTarget: target,
      secondaryDetails: base.secondaryDetails,
    );
  }
}

List<String> _fileChangeApprovalPaths(Object? rawChanges) {
  if (rawChanges is! List) return const <String>[];
  return rawChanges
      .whereType<Map>()
      .map((change) => change['file'] ?? change['path'] ?? change['target'])
      .whereType<String>()
      .where((path) => path.trim().isNotEmpty)
      .map((path) => path.trim())
      .toList(growable: false);
}

String? _nonEmptyApprovalReason(Object? rawReason) {
  if (rawReason is! String || rawReason.trim().isEmpty) return null;
  return rawReason.trim();
}

class CcpocketNativeApprovalPanel extends StatelessWidget {
  const CcpocketNativeApprovalPanel({
    required this.approval,
    required this.onApprove,
    required this.onReject,
    this.onApproveForSession,
    this.onApplyPolicyAmendment,
    this.allowPersistentApprovals = true,
    this.fileChanges,
    this.policyNotice,
    this.approvalBlocked = false,
    super.key,
  });

  final CodexSessionEvent approval;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback? onApproveForSession;
  final ValueChanged<Map<String, dynamic>>? onApplyPolicyAmendment;
  final bool allowPersistentApprovals;
  final List<AgentFileChangePreview>? fileChanges;
  final String? policyNotice;
  final bool approvalBlocked;

  @override
  Widget build(BuildContext context) {
    final params = approval.params ?? const <String, dynamic>{};
    final l = AppLocalizations.of(context);
    final toolName = _toolName(approval.requestMethod, params);
    final input = <String, dynamic>{
      ...params,
      if (params['command'] != null) 'command': params['command'],
    };
    final message = toolName == 'FileChange'
        ? _LocalizedFileChangePermissionMessage(
            toolUseId: '${approval.requestId}',
            input: input,
            localizations: l,
          )
        : pocket.PermissionRequestMessage(
            toolUseId: '${approval.requestId}',
            toolName: toolName,
            input: input,
          );
    final decisions = _approvalDecisionNames(params, approval.requestMethod);
    final canReject =
        decisions.contains('decline') || decisions.contains('cancel');
    final canApproveForSession =
        allowPersistentApprovals &&
        onApproveForSession != null &&
        decisions.contains('acceptForSession');
    final policyChoices = allowPersistentApprovals
        ? _persistentApprovalChoices(
            params,
            languageCode: Localizations.localeOf(context).languageCode,
          )
        : const <_PersistentApprovalChoice>[];
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ChatEntryWidget(
            entry: pocket.ServerChatEntry(message),
            isCodex: true,
          ),
          if (fileChanges != null) ...[
            const SizedBox(height: 4),
            _AgentFileChangePreviewList(previews: fileChanges!),
          ],
          if (policyNotice != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Container(
                key: const ValueKey('local_codex_root_policy_notice'),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  policyNotice!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                if (canReject)
                  OutlinedButton(
                    key: const ValueKey('local_codex_reject_button'),
                    onPressed: onReject,
                    child: Text(
                      decisions.contains('cancel') &&
                              !decisions.contains('decline')
                          ? l.cancel
                          : l.reject,
                    ),
                  ),
                for (var index = 0; index < policyChoices.length; index++)
                  OutlinedButton(
                    key: ValueKey('local_codex_persistent_approval_$index'),
                    onPressed: approvalBlocked || onApplyPolicyAmendment == null
                        ? null
                        : () => onApplyPolicyAmendment!(
                            policyChoices[index].decision,
                          ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 260),
                      child: Text(
                        policyChoices[index].label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                if (canApproveForSession)
                  OutlinedButton(
                    key: const ValueKey(
                      'local_codex_approve_for_session_button',
                    ),
                    onPressed: approvalBlocked ? null : onApproveForSession,
                    child: Text(l.approveForSession),
                  ),
                if (decisions.contains('accept'))
                  FilledButton(
                    key: const ValueKey('local_codex_approve_button'),
                    onPressed: approvalBlocked ? null : onApprove,
                    child: Text(approvalBlocked ? '策略阻止' : l.approve),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _toolName(String? method, Map<String, dynamic> params) {
    final explicit = params['toolName']?.toString().trim();
    if (explicit != null && explicit.isNotEmpty) return explicit;
    if (method?.contains('fileChange') == true) return 'FileChange';
    if (method?.contains('commandExecution') == true) return 'Bash';
    if (method?.contains('requestUserInput') == true) return 'User input';
    return 'Codex tool';
  }
}

class _PersistentApprovalChoice {
  const _PersistentApprovalChoice({
    required this.label,
    required this.decision,
  });

  final String label;
  final Map<String, dynamic> decision;
}

Set<String> _approvalDecisionNames(
  Map<String, dynamic> params,
  String? method,
) {
  final raw = params['availableDecisions'];
  if (raw is List) return raw.whereType<String>().toSet();
  switch (method) {
    case 'item/permissions/requestApproval':
      return <String>{'accept', 'acceptForSession', 'decline'};
    case 'item/fileChange/requestApproval':
      return <String>{'accept', 'acceptForSession', 'decline', 'cancel'};
    case 'item/commandExecution/requestApproval':
      return <String>{
        'accept',
        'decline',
        'cancel',
        if (params['networkApprovalContext'] is Map &&
            params['additionalPermissions'] == null)
          'acceptForSession',
      };
    default:
      return const <String>{};
  }
}

List<_PersistentApprovalChoice> _persistentApprovalChoices(
  Map<String, dynamic> params, {
  required String languageCode,
}) {
  final rawDecisions = params['availableDecisions'];
  final decisions = <Object?>[];
  if (rawDecisions is List) {
    decisions.addAll(rawDecisions);
  } else if (params['networkApprovalContext'] is Map) {
    final proposed = params['proposedNetworkPolicyAmendments'];
    if (proposed is List) {
      for (final rule in proposed.whereType<Map>()) {
        if (rule['action']?.toString() != 'allow') continue;
        decisions.add(<String, dynamic>{
          'applyNetworkPolicyAmendment': <String, dynamic>{
            'network_policy_amendment': Map<String, dynamic>.from(rule),
          },
        });
        break;
      }
    }
  } else if (params['additionalPermissions'] == null) {
    final proposed = params['proposedExecpolicyAmendment'];
    if (proposed is List &&
        proposed.isNotEmpty &&
        proposed.every((part) => part is String)) {
      decisions.add(<String, dynamic>{
        'acceptWithExecpolicyAmendment': <String, dynamic>{
          'execpolicy_amendment': List<String>.from(proposed),
        },
      });
    }
  }

  final result = <_PersistentApprovalChoice>[];
  for (final raw in decisions) {
    if (raw is! Map || raw.length != 1) continue;
    final decision = Map<String, dynamic>.from(raw);
    final kind = decision.keys.single;
    final payload = decision[kind];
    if (kind == 'acceptWithExecpolicyAmendment' && payload is Map) {
      final amendment = payload['execpolicy_amendment'];
      if (amendment is! List || amendment.isEmpty) continue;
      final command = amendment.map((part) => part.toString()).join(' ');
      result.add(
        _PersistentApprovalChoice(
          label: switch (languageCode) {
            'zh' => '后续允许命令前缀：$command',
            'ja' => '今後このコマンド接頭辞を許可：$command',
            'ko' => '이 명령어 접두사를 계속 허용: $command',
            _ => 'Allow future command prefix: $command',
          },
          decision: decision,
        ),
      );
      continue;
    }
    if (kind == 'applyNetworkPolicyAmendment' && payload is Map) {
      final amendment = payload['network_policy_amendment'];
      if (amendment is! Map) continue;
      final host = amendment['host']?.toString().trim() ?? '';
      final action = amendment['action']?.toString();
      if (host.isEmpty || (action != 'allow' && action != 'deny')) continue;
      result.add(
        _PersistentApprovalChoice(
          label: switch ((languageCode, action)) {
            ('zh', 'allow') => '后续允许网络访问：$host',
            ('zh', 'deny') => '后续阻止网络访问：$host',
            ('ja', 'allow') => '今後このホストへの通信を許可：$host',
            ('ja', 'deny') => '今後このホストへの通信を拒否：$host',
            ('ko', 'allow') => '이 호스트의 향후 네트워크 접근 허용: $host',
            ('ko', 'deny') => '이 호스트의 향후 네트워크 접근 차단: $host',
            (_, 'allow') => 'Allow this host in future: $host',
            _ => 'Block this host in future: $host',
          },
          decision: decision,
        ),
      );
    }
  }
  return result;
}

/// The original CC Pocket question interaction is kept intact for Codex's
/// app-server `item/tool/requestUserInput` requests.  The local adapter only
/// translates the answer back to the JSON-RPC response shape; it does not
/// replace the question widget with a generic approval dialog.
class CcpocketNativeUserInputPanel extends StatelessWidget {
  const CcpocketNativeUserInputPanel({
    required this.request,
    required this.onAnswer,
    required this.onCancel,
    super.key,
  });

  final CodexSessionEvent request;
  final ValueChanged<String> onAnswer;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final requestId = '${request.requestId ?? 'user-input'}';
    final input = request.params ?? const <String, dynamic>{};
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    return Column(
      key: const ValueKey('local_codex_user_input_panel'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AskUserQuestionWidget(
          key: const ValueKey('local_codex_ask_user_question'),
          toolUseId: requestId,
          input: input,
          agentName: 'Codex',
          onAnswer: (_, result) => onAnswer(result),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextButton(
              key: const ValueKey('local_codex_user_input_cancel_button'),
              onPressed: onCancel,
              child: Text(zh ? '取消' : 'Cancel'),
            ),
          ),
        ),
      ],
    );
  }
}

typedef McpElicitationResponseCallback = Future<void> Function({
  required String action,
  Map<String, dynamic>? content,
  String? persist,
});

typedef McpElicitationUrlOpener = Future<bool> Function(String url);

/// Native UI for app-server MCP form and URL elicitations. It keeps the
/// server's schema-shaped content intact and only exposes persistent approval
/// actions when the server explicitly advertises them in `_meta.persist`.
class CcpocketNativeMcpElicitationPanel extends StatefulWidget {
  const CcpocketNativeMcpElicitationPanel({
    required this.request,
    required this.onRespond,
    required this.onOpenUrl,
    this.allowPersistentApprovals = true,
    super.key,
  });

  final CodexSessionEvent request;
  final McpElicitationResponseCallback onRespond;
  final McpElicitationUrlOpener onOpenUrl;
  final bool allowPersistentApprovals;

  @override
  State<CcpocketNativeMcpElicitationPanel> createState() =>
      _CcpocketNativeMcpElicitationPanelState();
}

class _CcpocketNativeMcpElicitationPanelState
    extends State<CcpocketNativeMcpElicitationPanel> {
  final Map<String, TextEditingController> _textControllers = {};
  final Map<String, String?> _selections = {};
  final Map<String, Set<String>> _multiSelections = {};
  final Map<String, bool> _booleans = {};
  String? _validationError;
  bool _urlOpened = false;

  Map<String, dynamic> get _params =>
      widget.request.params ?? const <String, dynamic>{};

  Map<String, dynamic> get _meta => _asMap(_params['_meta'] ?? _params['meta']);

  String get _mode => _params['mode']?.toString() ?? '';

  bool get _isForm =>
      _mode == 'form' || _mode == 'openai/form' || _mode == 'openaiForm';

  bool get _isMcpToolApproval =>
      _meta['codex_approval_kind'] == 'mcp_tool_call';

  Map<String, dynamic> get _schema => _asMap(_params['requestedSchema']);

  Map<String, dynamic> get _properties => _asMap(_schema['properties']);

  bool get _hasValidSchema =>
      _schema['type'] == 'object' && _schema['properties'] is Map;

  bool get _isMessageOnly => _hasValidSchema && _properties.isEmpty;

  bool get _isApprovalAction => _isMcpToolApproval && _isMessageOnly;

  Set<String> get _persistentModes {
    if (!widget.allowPersistentApprovals) return const <String>{};
    final raw = _meta['persist'];
    if (raw is String) return <String>{raw};
    if (raw is List) return raw.whereType<String>().toSet();
    return const <String>{};
  }

  bool get _schemaSupported {
    if (!_isForm || !_hasValidSchema) return false;
    final required =
        (_schema['required'] as List?)?.whereType<String>() ??
        const Iterable<String>.empty();
    if (required.any((id) => !_properties.containsKey(id))) return false;
    for (final entry in _properties.entries) {
      final field = _asMap(entry.value);
      final type = field['type'];
      if (type == 'string' || type == 'number' || type == 'integer') {
        if (_enumChoices(field).isEmpty &&
            (field['enum'] != null ||
                field['oneOf'] != null ||
                field['anyOf'] != null)) {
          return false;
        }
        continue;
      }
      if (type == 'boolean') continue;
      if (type == 'array' && _arrayChoices(field).isNotEmpty) continue;
      return false;
    }
    return true;
  }

  @override
  void initState() {
    super.initState();
    _resetFormState();
  }

  @override
  void didUpdateWidget(covariant CcpocketNativeMcpElicitationPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.request.requestId != widget.request.requestId) {
      _resetFormState();
    }
  }

  void _resetFormState() {
    for (final controller in _textControllers.values) {
      controller.dispose();
    }
    _textControllers.clear();
    _selections.clear();
    _multiSelections.clear();
    _booleans.clear();
    _validationError = null;
    _urlOpened = false;
    for (final entry in _properties.entries) {
      final field = _asMap(entry.value);
      final id = entry.key;
      final type = field['type'];
      if (type == 'string' || type == 'number' || type == 'integer') {
        final choices = _enumChoices(field);
        if (choices.isNotEmpty) {
          final fallback = field['default']?.toString();
          _selections[id] = choices.any((choice) => choice.$1 == fallback)
              ? fallback
              : null;
        } else {
          _textControllers[id] = TextEditingController(
            text: field['default']?.toString() ?? '',
          );
        }
      } else if (type == 'boolean') {
        _booleans[id] = field['default'] == true;
      } else if (type == 'array') {
        final defaults = field['default'];
        _multiSelections[id] = defaults is List
            ? defaults.whereType<String>().toSet()
            : <String>{};
      }
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final controller in _textControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final copy = _McpElicitationCopy.of(context);
    final server = _params['serverName']?.toString().trim();
    final title = server == null || server.isEmpty ? 'MCP' : server;
    final message = _params['message']?.toString().trim() ?? '';
    final isUrl = _mode == 'url';
    final isUnsupported = !_isForm && !isUrl;
    final url = _params['url']?.toString() ?? '';
    final properties = _properties;
    final requiredFields =
        (_schema['required'] as List?)?.whereType<String>().toSet() ??
        const <String>{};

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Card(
        key: const ValueKey('local_codex_mcp_elicitation_panel'),
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    _isApprovalAction
                        ? Icons.security_outlined
                        : Icons.hub_outlined,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _isApprovalAction
                          ? copy.toolApproval(title)
                          : copy.requestFrom(title),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                ],
              ),
              if (message.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(message),
                ),
              if (_isApprovalAction) ...[
                if (_meta['tool_title'] is String ||
                    _meta['tool_name'] is String)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      (_meta['tool_title'] ?? _meta['tool_name']).toString(),
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                ..._approvalParameterLines(copy),
              ],
              if (_isForm && !_isApprovalAction && _schemaSupported)
                if (properties.isNotEmpty)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 220),
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          for (final entry in properties.entries)
                            _buildField(
                              context,
                              entry.key,
                              _asMap(entry.value),
                              requiredFields.contains(entry.key),
                            ),
                        ],
                      ),
                    ),
                  ),
              if (_isForm && !_schemaSupported)
                _notice(context, copy.unsupportedForm),
              if (isUnsupported) _notice(context, copy.unsupportedMode(_mode)),
              if (isUrl) ...[
                if (_isSafeUrl(url)) ...[
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 56),
                    child: SingleChildScrollView(child: SelectableText(url)),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      key: const ValueKey('local_codex_mcp_copy_url'),
                      onPressed: () =>
                          Clipboard.setData(ClipboardData(text: url)),
                      icon: const Icon(Icons.copy, size: 18),
                      label: Text(copy.copyUrl),
                    ),
                  ),
                ] else
                  _notice(context, copy.invalidUrl),
              ],
              if (_validationError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    _validationError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 4),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 4,
                children: _buildActions(copy, isUrl, isUnsupported),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildActions(
    _McpElicitationCopy copy,
    bool isUrl,
    bool isUnsupported,
  ) {
    if (_isApprovalAction) {
      return [
        OutlinedButton(
          key: const ValueKey('local_codex_mcp_cancel'),
          onPressed: () => _respond('cancel'),
          child: Text(copy.cancel),
        ),
        if (_persistentModes.contains('always'))
          OutlinedButton(
            key: const ValueKey('local_codex_mcp_allow_always'),
            onPressed: () => _respond(
              'accept',
              content: <String, dynamic>{},
              persist: 'always',
            ),
            child: Text(copy.allowAlways),
          ),
        if (_persistentModes.contains('session'))
          OutlinedButton(
            key: const ValueKey('local_codex_mcp_allow_session'),
            onPressed: () => _respond(
              'accept',
              content: <String, dynamic>{},
              persist: 'session',
            ),
            child: Text(copy.allowSession),
          ),
        FilledButton(
          key: const ValueKey('local_codex_mcp_allow_once'),
          onPressed: () => _respond('accept', content: <String, dynamic>{}),
          child: Text(copy.allowOnce),
        ),
      ];
    }
    if (isUnsupported) {
      return [
        FilledButton.tonal(
          key: const ValueKey('local_codex_mcp_decline'),
          onPressed: () => _respond('decline'),
          child: Text(copy.decline),
        ),
        OutlinedButton(
          key: const ValueKey('local_codex_mcp_cancel'),
          onPressed: () => _respond('cancel'),
          child: Text(copy.cancel),
        ),
      ];
    }
    if (isUrl) {
      final canOpen = _isSafeUrl(_params['url']?.toString() ?? '');
      return [
        OutlinedButton(
          key: const ValueKey('local_codex_mcp_cancel'),
          onPressed: () => _respond('cancel'),
          child: Text(copy.cancel),
        ),
        if (canOpen)
          OutlinedButton.icon(
            key: const ValueKey('local_codex_mcp_open_url'),
            onPressed: _openUrl,
            icon: const Icon(Icons.open_in_browser, size: 18),
            label: Text(copy.openUrl),
          ),
        FilledButton(
          key: const ValueKey('local_codex_mcp_url_continue'),
          onPressed: canOpen && _urlOpened
              ? () => _respond('accept', content: <String, dynamic>{})
              : null,
          child: Text(copy.continueLabel),
        ),
      ];
    }
    return [
      OutlinedButton(
        key: const ValueKey('local_codex_mcp_decline'),
        onPressed: () => _respond('decline'),
        child: Text(copy.decline),
      ),
      OutlinedButton(
        key: const ValueKey('local_codex_mcp_cancel'),
        onPressed: () => _respond('cancel'),
        child: Text(copy.cancel),
      ),
      FilledButton(
        key: const ValueKey('local_codex_mcp_accept'),
        onPressed: _schemaSupported ? _submitForm : null,
        child: Text(copy.submit),
      ),
    ];
  }

  Widget _buildField(
    BuildContext context,
    String id,
    Map<String, dynamic> schema,
    bool required,
  ) {
    final title = schema['title']?.toString().trim();
    final label = title == null || title.isEmpty ? id : title;
    final description = schema['description']?.toString();
    final choices = _enumChoices(schema);
    if (choices.isNotEmpty) {
      final current = _selections[id] ?? schema['default']?.toString();
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: required ? '$label *' : label,
            helperText: description,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              key: ValueKey('local_codex_mcp_field_$id'),
              isExpanded: true,
              value: choices.any((choice) => choice.$1 == current)
                  ? current
                  : null,
              hint: Text(_McpElicitationCopy.of(context).selectValue),
              items: [
                for (final choice in choices)
                  DropdownMenuItem<String>(
                    value: choice.$1,
                    child: Text(choice.$2),
                  ),
              ],
              onChanged: (value) => setState(() => _selections[id] = value),
            ),
          ),
        ),
      );
    }
    if (schema['type'] == 'array') {
      final selected = _multiSelections[id] ?? <String>{};
      final options = _arrayChoices(schema);
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: required ? '$label *' : label,
            helperText: description,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          child: Wrap(
            spacing: 6,
            children: [
              for (final option in options)
                FilterChip(
                  key: ValueKey('local_codex_mcp_multi_${id}_${option.$1}'),
                  label: Text(option.$2),
                  selected: selected.contains(option.$1),
                  onSelected: (checked) => setState(() {
                    final updated = Set<String>.of(selected);
                    if (checked) {
                      updated.add(option.$1);
                    } else {
                      updated.remove(option.$1);
                    }
                    _multiSelections[id] = updated;
                  }),
                ),
            ],
          ),
        ),
      );
    }
    if (schema['type'] == 'boolean') {
      return CheckboxListTile(
        key: ValueKey('local_codex_mcp_field_$id'),
        contentPadding: EdgeInsets.zero,
        title: Text(label),
        subtitle: description == null ? null : Text(description),
        value: _booleans[id] ?? false,
        onChanged: (value) => setState(() => _booleans[id] = value == true),
      );
    }
    final number = schema['type'] == 'number' || schema['type'] == 'integer';
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: TextField(
        key: ValueKey('local_codex_mcp_field_$id'),
        controller: _textControllers[id],
        keyboardType: number
            ? const TextInputType.numberWithOptions(decimal: true, signed: true)
            : TextInputType.text,
        decoration: InputDecoration(
          labelText: required ? '$label *' : label,
          helperText: description,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        onChanged: (_) => setState(() => _validationError = null),
      ),
    );
  }

  List<Widget> _approvalParameterLines(_McpElicitationCopy copy) {
    final raw = _meta['tool_params_display'];
    final values = <String>[];
    if (raw is List) {
      for (final item in raw.take(3)) {
        final param = _asMap(item);
        final name = param['display_name'] ?? param['name'];
        if (name == null || !param.containsKey('value')) continue;
        values.add('$name: ${_shortValue(param['value'])}');
      }
    }
    if (values.isEmpty) {
      final params = _asMap(_meta['tool_params']);
      for (final entry in params.entries.take(3)) {
        values.add('${entry.key}: ${_shortValue(entry.value)}');
      }
    }
    if (values.isEmpty) return const <Widget>[];
    return [
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          values.join('\n'),
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ];
  }

  Widget _notice(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Text(
      text,
      style: TextStyle(color: Theme.of(context).colorScheme.error),
    ),
  );

  Future<void> _openUrl() async {
    final url = _params['url']?.toString() ?? '';
    final opened = await widget.onOpenUrl(url);
    if (mounted && opened) setState(() => _urlOpened = true);
  }

  Future<void> _submitForm() async {
    final content = <String, dynamic>{};
    for (final entry in _properties.entries) {
      final id = entry.key;
      final schema = _asMap(entry.value);
      final required = ((_schema['required'] as List?) ?? const <Object?>[])
          .contains(id);
      final type = schema['type'];
      if (type == 'boolean') {
        content[id] = _booleans[id] ?? false;
      } else if (type == 'array') {
        final values = (_multiSelections[id] ?? const <String>{}).toList();
        final minimum = schema['minItems'];
        final maximum = schema['maxItems'];
        if (minimum is num && values.length < minimum ||
            maximum is num && values.length > maximum) {
          return _setValidation(
            _McpElicitationCopy.of(context).invalid(label: id),
          );
        }
        if (required && values.isEmpty) {
          return _setValidation(
            _McpElicitationCopy.of(context).required(label: id),
          );
        }
        if (values.isNotEmpty) content[id] = values;
      } else {
        final choices = _enumChoices(schema);
        if (choices.isNotEmpty) {
          final value = _selections[id] ?? schema['default']?.toString();
          if (required && (value == null || value.isEmpty)) {
            return _setValidation(
              _McpElicitationCopy.of(context).required(label: id),
            );
          }
          if (value != null && value.isNotEmpty) content[id] = value;
          continue;
        }
        final raw = _textControllers[id]?.text.trim() ?? '';
        if (raw.isEmpty) {
          if (required) {
            return _setValidation(
              _McpElicitationCopy.of(context).required(label: id),
            );
          }
          continue;
        }
        final minLength = schema['minLength'];
        final maxLength = schema['maxLength'];
        if (minLength is num && raw.length < minLength ||
            maxLength is num && raw.length > maxLength) {
          return _setValidation(
            _McpElicitationCopy.of(context).invalid(label: id),
          );
        }
        final pattern = schema['pattern'];
        if (pattern is String && pattern.isNotEmpty) {
          try {
            if (!RegExp(pattern).hasMatch(raw)) {
              return _setValidation(
                _McpElicitationCopy.of(context).invalid(label: id),
              );
            }
          } on FormatException {
            return _setValidation(
              _McpElicitationCopy.of(context).invalid(label: id),
            );
          }
        }
        if (type == 'string') {
          final validFormat = switch (schema['format']) {
            'email' => RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(raw),
            'uri' => _isAbsoluteUri(raw),
            'date' || 'date-time' => DateTime.tryParse(raw) != null,
            _ => true,
          };
          if (!validFormat) {
            return _setValidation(
              _McpElicitationCopy.of(context).invalid(label: id),
            );
          }
          content[id] = raw;
        } else {
          final number = num.tryParse(raw);
          if (number == null ||
              type == 'integer' && number % 1 != 0 ||
              schema['minimum'] is num && number < (schema['minimum'] as num) ||
              schema['maximum'] is num && number > (schema['maximum'] as num)) {
            return _setValidation(
              _McpElicitationCopy.of(context).invalid(label: id),
            );
          }
          content[id] = type == 'integer' ? number.toInt() : number;
        }
      }
    }
    await widget.onRespond(action: 'accept', content: content);
  }

  void _setValidation(String message) {
    if (mounted) setState(() => _validationError = message);
  }

  Future<void> _respond(
    String action, {
    Map<String, dynamic>? content,
    String? persist,
  }) => widget.onRespond(action: action, content: content, persist: persist);

  List<(String, String)> _enumChoices(Map<String, dynamic> schema) {
    final values = schema['enum'];
    final names = schema['enumNames'];
    if (values is List && values.every((value) => value is String)) {
      return [
        for (var index = 0; index < values.length; index++)
          (
            values[index] as String,
            names is List && index < names.length
                ? '${names[index]}'
                : values[index] as String,
          ),
      ];
    }
    final alternatives = schema['oneOf'] ?? schema['anyOf'];
    if (alternatives is List) {
      return [
        for (final raw in alternatives)
          if (_asMap(raw)['const'] is String)
            (
              _asMap(raw)['const'] as String,
              _asMap(raw)['title']?.toString() ??
                  _asMap(raw)['const'] as String,
            ),
      ];
    }
    return const <(String, String)>[];
  }

  List<(String, String)> _arrayChoices(Map<String, dynamic> schema) {
    final items = _asMap(schema['items']);
    final simple = items['enum'];
    if (simple is List && simple.every((value) => value is String)) {
      return [for (final value in simple.cast<String>()) (value, value)];
    }
    final alternatives = items['oneOf'] ?? items['anyOf'];
    if (alternatives is List) {
      return [
        for (final raw in alternatives)
          if (_asMap(raw)['const'] is String)
            (
              _asMap(raw)['const'] as String,
              _asMap(raw)['title']?.toString() ??
                  _asMap(raw)['const'] as String,
            ),
      ];
    }
    return const <(String, String)>[];
  }

  static Map<String, dynamic> _asMap(Object? value) {
    if (value is! Map) return <String, dynamic>{};
    return <String, dynamic>{
      for (final entry in value.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
  }

  static String _shortValue(Object? value) {
    final text = value is String ? value : value.toString();
    return text.length > 120 ? '${text.substring(0, 117)}…' : text;
  }

  static bool _isAbsoluteUri(String value) {
    final uri = Uri.tryParse(value);
    return uri != null && uri.hasScheme;
  }

  static bool _isSafeUrl(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
      return false;
    }
    final scheme = uri.scheme.toLowerCase();
    if (scheme == 'https') return uri.port == 0 || uri.port == 443;
    return scheme == 'http' &&
        const <String>{
          'localhost',
          '127.0.0.1',
          '::1',
        }.contains(uri.host.toLowerCase());
  }
}

class _McpElicitationCopy {
  const _McpElicitationCopy(this.languageCode);

  final String languageCode;

  bool get isChinese => languageCode == 'zh';
  bool get isJapanese => languageCode == 'ja';
  bool get isKorean => languageCode == 'ko';

  static _McpElicitationCopy of(BuildContext context) =>
      _McpElicitationCopy(Localizations.localeOf(context).languageCode);

  String requestFrom(String name) => switch (languageCode) {
    'zh' => '$name 请求输入',
    'ja' => '$name が入力を要求しています',
    'ko' => '$name 입력 요청',
    _ => '$name requests input',
  };
  String toolApproval(String name) => switch (languageCode) {
    'zh' => '允许 $name 调用工具？',
    'ja' => '$name のツール呼び出しを許可しますか？',
    'ko' => '$name 도구 호출을 허용할까요?',
    _ => 'Allow $name to call this tool?',
  };
  String get allowOnce => switch (languageCode) {
    'zh' => '仅本次允许',
    'ja' => '今回のみ許可',
    'ko' => '이번만 허용',
    _ => 'Allow once',
  };
  String get allowSession => switch (languageCode) {
    'zh' => '本会话允许',
    'ja' => 'このセッションで許可',
    'ko' => '이 세션에서 허용',
    _ => 'Allow for session',
  };
  String get allowAlways => switch (languageCode) {
    'zh' => '始终允许',
    'ja' => '常に許可',
    'ko' => '항상 허용',
    _ => 'Always allow',
  };
  String get decline => switch (languageCode) {
    'zh' => '拒绝',
    'ja' => '拒否',
    'ko' => '거부',
    _ => 'Decline',
  };
  String get cancel => switch (languageCode) {
    'zh' => '取消',
    'ja' => 'キャンセル',
    'ko' => '취소',
    _ => 'Cancel',
  };
  String get submit => switch (languageCode) {
    'zh' => '提交',
    'ja' => '送信',
    'ko' => '제출',
    _ => 'Submit',
  };
  String get continueLabel => switch (languageCode) {
    'zh' => '完成，继续',
    'ja' => '完了して続行',
    'ko' => '완료하고 계속',
    _ => 'Done, continue',
  };
  String get openUrl => switch (languageCode) {
    'zh' => '打开页面',
    'ja' => 'ページを開く',
    'ko' => '페이지 열기',
    _ => 'Open page',
  };
  String get copyUrl => switch (languageCode) {
    'zh' => '复制链接',
    'ja' => 'リンクをコピー',
    'ko' => '링크 복사',
    _ => 'Copy link',
  };
  String get selectValue => switch (languageCode) {
    'zh' => '请选择',
    'ja' => '選択してください',
    'ko' => '선택하세요',
    _ => 'Select a value',
  };
  String get unsupportedForm => switch (languageCode) {
    'zh' => '此 MCP 表单包含当前界面无法安全处理的字段；为避免误提交，请拒绝或取消。',
    'ja' => 'この MCP フォームには未対応の項目があります。誤送信を防ぐため、拒否またはキャンセルしてください。',
    'ko' => '지원되지 않는 MCP 양식 항목이 있습니다. 잘못된 제출을 방지하려면 거부하거나 취소하세요.',
    _ => 'This MCP form contains fields this UI cannot safely handle. Decline or cancel it.',
  };
  String unsupportedMode(String mode) => switch (languageCode) {
    'zh' => '暂不支持此 MCP 请求模式（$mode）；不会自动批准。',
    'ja' => 'この MCP リクエスト形式（$mode）は未対応です。自動承認しません。',
    'ko' => '지원되지 않는 MCP 요청 모드($mode)입니다. 자동으로 승인하지 않습니다.',
    _ =>
      'Unsupported MCP request mode ($mode). It will not be approved automatically.',
  };
  String get invalidUrl => switch (languageCode) {
    'zh' => '仅允许 HTTPS 或本机回环 HTTP 链接打开。',
    'ja' => 'HTTPS またはローカルループバック HTTP のみ開けます。',
    'ko' => 'HTTPS 또는 로컬 루프백 HTTP 링크만 열 수 있습니다.',
    _ => 'Only HTTPS or loopback HTTP URLs can be opened.',
  };
  String required({required String label}) => switch (languageCode) {
    'zh' => '请填写必填项：$label',
    'ja' => '必須項目を入力してください：$label',
    'ko' => '필수 항목을 입력하세요: $label',
    _ => 'Required field: $label',
  };
  String invalid({required String label}) => switch (languageCode) {
    'zh' => '“$label”的值无效或超出允许范围。',
    'ja' => '「$label」の値が無効か、許可範囲外です。',
    'ko' => '$label 값이 유효하지 않거나 허용 범위를 벗어났습니다.',
    _ => 'Invalid or out-of-range value for "$label".',
  };
}

class _AgentFileChangePreviewList extends StatelessWidget {
  const _AgentFileChangePreviewList({required this.previews});

  final List<AgentFileChangePreview> previews;

  @override
  Widget build(BuildContext context) {
    if (previews.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Card(
        key: const ValueKey('local_codex_file_change_preview'),
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const ListTile(
              dense: true,
              leading: Icon(Icons.difference_outlined),
              title: Text('文件变更预览'),
              subtitle: Text('审批前检查将要写入的内容'),
            ),
            for (final preview in previews)
              _AgentFileChangePreviewTile(preview: preview),
          ],
        ),
      ),
    );
  }
}

class _AgentFileChangePreviewTile extends StatelessWidget {
  const _AgentFileChangePreviewTile({required this.preview});

  final AgentFileChangePreview preview;

  @override
  Widget build(BuildContext context) {
    final parsed = parseDiff(preview.diff);
    return ExpansionTile(
      key: ValueKey('local_codex_file_change_${preview.path}'),
      leading: Icon(
        preview.issue == null
            ? Icons.edit_note_outlined
            : Icons.warning_amber_outlined,
        color: preview.issue == null
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.error,
      ),
      title: Text(preview.path, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        preview.issue ??
            '${preview.kind} · ${preview.isManaged ? '可备份' : '仅预览'}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      children: [
        if (preview.issue != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              preview.issue!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (preview.diff.trim().isNotEmpty && parsed.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final file in parsed)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: InlineEditDiff(diffFile: file),
                  ),
              ],
            ),
          )
        else if (preview.diff.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: SelectableText(
              preview.diff,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
          ),
      ],
    );
  }
}

class CcpocketNativeRecoveryBanner extends StatelessWidget {
  const CcpocketNativeRecoveryBanner({
    required this.reason,
    required this.onResume,
    required this.onStartNew,
    super.key,
  });

  final String reason;
  final VoidCallback? onResume;
  final VoidCallback onStartNew;

  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    return MaterialBanner(
      content: Text(reason),
      leading: const Icon(Icons.cloud_off_outlined),
      actions: [
        TextButton(
          onPressed: onStartNew,
          child: Text(zh ? '新会话' : 'New session'),
        ),
        if (onResume != null)
          FilledButton(onPressed: onResume, child: Text(zh ? '恢复' : 'Resume')),
      ],
    );
  }
}

class CcpocketNativeRetryBanner extends StatelessWidget {
  const CcpocketNativeRetryBanner({
    required this.reason,
    required this.onRetry,
    super.key,
  });

  final String reason;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    return MaterialBanner(
      content: Text(reason),
      leading: const Icon(Icons.sync_problem_outlined),
      actions: [
        TextButton(onPressed: onRetry, child: Text(zh ? '重试' : 'Retry')),
      ],
    );
  }
}

/// Login card follows the original CC Pocket local-runtime auth surface.  It
/// receives only the local app's bounded auth state and callbacks; no remote
/// connection or machine state is part of the contract.
class CcpocketNativeAuthCard extends StatelessWidget {
  const CcpocketNativeAuthCard({
    required this.status,
    required this.loginStatus,
    this.error,
    required this.busy,
    required this.pending,
    required this.authenticated,
    required this.selectedMode,
    required this.apiKeyController,
    required this.challenge,
    required this.onModeChanged,
    required this.onStart,
    required this.onRefresh,
    required this.onCancel,
    required this.onLogout,
    required this.onCopyCode,
    required this.onOpenUrl,
    this.showChallenge = true,
    super.key,
  });

  final String? status;
  final String? loginStatus;
  final String? error;
  final bool busy;
  final bool pending;
  final bool authenticated;
  final CodexAuthMode selectedMode;
  final TextEditingController apiKeyController;
  final CodexAuthChallenge? challenge;
  final ValueChanged<CodexAuthMode> onModeChanged;
  final VoidCallback onStart;
  final VoidCallback onRefresh;
  final VoidCallback onCancel;
  final VoidCallback onLogout;
  final VoidCallback onCopyCode;
  final VoidCallback onOpenUrl;
  final bool showChallenge;

  @override
  Widget build(BuildContext context) {
    // Codex's account/login/start replaces the current primary credential.
    // Keep the method selector available after a successful login so the
    // Settings page can switch between device code, browser OAuth, and API
    // key without forcing the user through a dead-end disabled card.
    final modeSelectable = !busy && !pending;
    final browser = pending && selectedMode == CodexAuthMode.browser;
    final apiKey = selectedMode == CodexAuthMode.apiKey;
    final copy = _NativeAuthCopy.of(context);
    final startLabel = switch (selectedMode) {
      CodexAuthMode.deviceAuth => copy.deviceLogin,
      CodexAuthMode.browser => copy.browserLogin,
      CodexAuthMode.apiKey => copy.apiKeyLogin,
    };
    final effectiveStartLabel = authenticated
        ? copy.reauthenticate
        : startLabel;
    return Card(
      key: const ValueKey('local_codex_auth_card'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              copy.title,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              '${copy.status}: ${browser ? copy.waitingForBrowser : copy.statusText(status)}',
            ),
            if (loginStatus != null) ...[
              const SizedBox(height: 4),
              Text(copy.statusText(loginStatus)),
            ],
            if (error != null && error!.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                copy.statusText(error),
                key: const ValueKey('local_codex_auth_error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 8),
            Text(copy.method),
            _modeTile(
              context,
              CodexAuthMode.deviceAuth,
              copy.deviceCode,
              modeSelectable,
            ),
            _modeTile(
              context,
              CodexAuthMode.browser,
              copy.browserOauth,
              modeSelectable,
            ),
            _modeTile(
              context,
              CodexAuthMode.apiKey,
              copy.apiKey,
              modeSelectable,
            ),
            if (apiKey)
              TextField(
                key: const ValueKey('local_codex_auth_api_key_field'),
                controller: apiKeyController,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                enabled: !busy && !pending,
                maxLines: 1,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) {
                  if (!busy && !pending) onStart();
                },
                decoration: InputDecoration(
                  labelText: copy.apiKeyLabel,
                  hintText: copy.apiKeyHint,
                  prefixIcon: const Icon(Icons.key_outlined),
                  filled: true,
                  border: const OutlineInputBorder(),
                ),
              ),
            if (browser) ...[const SizedBox(height: 8), Text(copy.browserHint)],
            if (challenge != null && showChallenge) ...[
              const SizedBox(height: 10),
              _NativeAuthChallengePanel(
                challenge: challenge!,
                enabled: pending || !busy,
                onCopyCode: onCopyCode,
                onOpenUrl: onOpenUrl,
                copy: copy,
              ),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (!pending)
                  FilledButton.icon(
                    key: const ValueKey('local_codex_login_button'),
                    onPressed: busy ? null : onStart,
                    icon: const Icon(Icons.login),
                    label: Text(effectiveStartLabel),
                  ),
                if (pending)
                  OutlinedButton.icon(
                    key: const ValueKey('local_codex_login_button'),
                    onPressed: onCancel,
                    icon: const Icon(Icons.close),
                    label: Text(copy.cancel),
                  ),
                if (!authenticated)
                  OutlinedButton.icon(
                    key: const ValueKey('local_codex_check_login_button'),
                    onPressed: busy || pending ? null : onRefresh,
                    icon: const Icon(Icons.refresh),
                    label: Text(copy.checkLogin),
                  ),
                if (authenticated)
                  OutlinedButton.icon(
                    key: const ValueKey('local_codex_logout_button'),
                    onPressed: busy || pending ? null : onLogout,
                    icon: const Icon(Icons.logout),
                    label: Text(copy.logout),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _modeTile(
    BuildContext context,
    CodexAuthMode mode,
    String title,
    bool enabled,
  ) {
    return RadioListTile<CodexAuthMode>(
      key: ValueKey('local_codex_auth_mode_' + mode.wireValue),
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(title),
      value: mode,
      groupValue: selectedMode,
      onChanged: enabled ? (value) => onModeChanged(value!) : null,
    );
  }
}

class _NativeAuthChallengePanel extends StatelessWidget {
  const _NativeAuthChallengePanel({
    required this.challenge,
    required this.enabled,
    required this.onCopyCode,
    required this.onOpenUrl,
    required this.copy,
  });

  final CodexAuthChallenge challenge;
  final bool enabled;
  final VoidCallback onCopyCode;
  final VoidCallback onOpenUrl;
  final _NativeAuthCopy copy;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            copy.deviceAuthorization,
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          if (challenge.oneTimeCode != null) ...[
            Text(copy.oneTimeCode),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: SelectableText(
                    copy.code(challenge.oneTimeCode!),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                TextButton.icon(
                  onPressed: enabled ? onCopyCode : null,
                  icon: const Icon(Icons.copy),
                  label: Text(copy.copy),
                ),
              ],
            ),
          ],
          if (challenge.verificationUrl != null) ...[
            const SizedBox(height: 4),
            Text(
              challenge.verificationUrl!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: enabled ? onOpenUrl : null,
                icon: const Icon(Icons.open_in_new),
                label: Text(copy.openLoginPage),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The copied CC Pocket widgets use the app locale for all presentation.
/// Keep the local-only auth adapter in that same locale instead of leaking a
/// separate English debug surface into the Chinese session UI.
class _NativeAuthCopy {
  const _NativeAuthCopy(this.isChinese);

  final bool isChinese;

  static _NativeAuthCopy of(BuildContext context) =>
      _NativeAuthCopy(Localizations.localeOf(context).languageCode == 'zh');

  String get title => isChinese ? 'Codex 登录' : 'Codex login';
  String get status => isChinese ? '状态' : 'Status';
  String get method => isChinese ? '登录方式' : 'Login method';
  String get deviceCode => isChinese ? '设备码' : 'Device code';
  String get browserOauth => isChinese ? '浏览器 OAuth' : 'Browser OAuth';
  String get apiKey => isChinese ? 'API 密钥' : 'API key';
  String get apiKeyLabel => isChinese ? 'API 密钥' : 'API key';
  String get apiKeyHint =>
      isChinese ? '仅用于本次登录' : 'Enter the key for this login only';
  String get deviceLogin => isChinese ? '使用设备码登录' : 'Login with device code';
  String get browserLogin => isChinese ? '在浏览器中登录' : 'Login in browser';
  String get apiKeyLogin => isChinese ? '使用 API 密钥登录' : 'Login with API key';
  String get reauthenticate => isChinese ? '切换登录方式' : 'Change login method';
  String get waitingForBrowser =>
      isChinese ? '等待浏览器登录' : 'Waiting for browser login';
  String get browserHint => isChinese
      ? '完成官方浏览器登录后返回此处。本地 Codex 进程会接管回调。'
      : 'Finish the official browser login, then return here. The local Codex process owns the callback.';
  String get cancel => isChinese ? '取消登录' : 'Cancel login';
  String get checkLogin => isChinese ? '检查登录状态' : 'Check login';
  String get logout => isChinese ? '退出登录' : 'Log out';
  String get deviceAuthorization => isChinese ? '设备授权' : 'Device authorization';
  String get oneTimeCode => isChinese ? '一次性代码' : 'One-time code';
  String get copy => isChinese ? '复制' : 'Copy';
  String get openLoginPage => isChinese ? '打开登录页面' : 'Open login page';

  String code(String value) => isChinese ? '代码：$value' : 'Code: $value';

  String statusText(String? value) {
    final text = value ?? (isChinese ? '未检查' : 'Not checked');
    if (!isChinese) return text;
    final appServerExit = RegExp(
      r'^Codex app-server exited with code (-?\d+)\.$',
    ).firstMatch(text);
    if (appServerExit != null) {
      return 'Codex app-server 已以代码 ${appServerExit.group(1)} 退出。';
    }
    return switch (text) {
      'Not checked' => '未检查',
      'Not logged in' => '未登录',
      'Logged in' => '已登录',
      'No Codex runtime is installed in the app or root runtime slots.' =>
        '应用或 Root 运行时目录中均未安装 Codex 运行环境。',
      'Login process failed.' => '登录进程失败。',
      'Login process stopped.' => '登录进程已停止。',
      'Login process completed.' => '登录进程已完成。',
      'Login process exited with an error.' => '登录进程以错误退出。',
      'Failed to check login status.' => '登录状态检查失败。',
      'Login canceled.' => '已取消登录。',
      'Login process completed; check login status.' => '登录进程已完成，请检查登录状态。',
      'Login could not start.' => '无法启动登录。',
      'Starting device code…' => '正在启动设备码登录…',
      'Starting browser oauth…' => '正在启动浏览器 OAuth…',
      'Starting api key…' => '正在启动 API 密钥登录…',
      'API key accepted; waiting for Codex to finish login.' =>
        'API 密钥已接收，正在等待 Codex 完成登录。',
      'Device authorization is waiting for completion.' => '等待完成设备授权。',
      'Browser authorization is waiting for completion.' => '等待完成浏览器授权。',
      'Browser authorization completed.' => '浏览器授权已完成。',
      'Codex did not return a browser login URL.' => 'Codex 没有返回浏览器登录地址。',
      'Codex returned an unverified browser login URL.' =>
        'Codex 返回的浏览器登录地址未通过校验。',
      'Codex did not return a device login challenge.' => 'Codex 没有返回设备登录挑战。',
      'Codex returned an unverified device login challenge.' =>
        'Codex 返回的设备登录挑战未通过校验。',
      'Codex returned an unexpected API key login response.' =>
        'Codex 返回了意外的 API 密钥登录响应。',
      'Codex returned an unexpected browser login response.' =>
        'Codex 返回了意外的浏览器登录响应。',
      'Codex returned an unexpected device login response.' =>
        'Codex 返回了意外的设备登录响应。',
      _ => text,
    };
  }
}

class CcpocketNativeStatusLine extends StatelessWidget
    implements PreferredSizeWidget {
  const CcpocketNativeStatusLine({required this.status, super.key});

  final String status;

  @override
  Size get preferredSize => const Size.fromHeight(20);

  @override
  Widget build(BuildContext context) {
    final normalized = status.trim().toLowerCase();
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final color = switch (normalized) {
      'running' || 'thinking' => Colors.blue,
      'reconnecting' || 'resuming' || 'queued' => Colors.blue,
      'waiting approval' || 'waiting' => Colors.orange,
      'ready' || 'idle' => Colors.green,
      'failed' || 'error' || 'disconnected' => Colors.red,
      _ => Theme.of(context).colorScheme.onSurfaceVariant,
    };
    return SizedBox(
      height: preferredSize.height,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.only(left: 16, bottom: 2),
          child: Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  _nativeStatusLabel(status, zh: zh),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _nativeStatusLabel(String status, {required bool zh}) {
  if (!zh) return status;
  return switch (status.trim().toLowerCase()) {
    'saved' => '已保存',
    'stopped' => '已停止',
    'starting' => '启动中',
    'running' => '运行中',
    'thinking' => '思考中',
    'reconnecting' => '重新连接中',
    'resuming' => '恢复中',
    'queued' => '排队中',
    'waiting approval' || 'waiting' => '等待审批',
    'ready' || 'idle' => '就绪',
    'failed' => '失败',
    'error' => '错误',
    'cancelled' || 'canceled' => '已取消',
    'disconnected' => '已断开',
    final other => other,
  };
}
