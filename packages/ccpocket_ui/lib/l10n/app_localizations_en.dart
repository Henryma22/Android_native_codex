// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Codex';

  @override
  String get cancel => 'Cancel';

  @override
  String get save => 'Save';

  @override
  String get delete => 'Delete';

  @override
  String get remove => 'Remove';

  @override
  String get renameSession => 'Rename Session';

  @override
  String get pin => 'Pin session';

  @override
  String get unpin => 'Unpin session';

  @override
  String get pinProject => 'Pin project';

  @override
  String get unpinProject => 'Unpin project';

  @override
  String get sessionNameHint => 'Session name';

  @override
  String get copy => 'Copy';

  @override
  String get markdownLinkOpenFailed => 'Could not open this link.';

  @override
  String get markdownLinkUnsupported => 'This link type is not supported.';

  @override
  String get markdownFileUnavailable => 'This file cannot be previewed here.';

  @override
  String get copied => 'Copied';

  @override
  String get copiedToClipboard => 'Copied to clipboard';

  @override
  String get start => 'Start';

  @override
  String get stop => 'Stop';

  @override
  String get send => 'Send';

  @override
  String get settings => 'Settings';

  @override
  String get gallery => 'Gallery';

  @override
  String get gitUnavailableTip =>
      'Git not detected — Git features are unavailable';

  @override
  String get gitUnavailableTitle => 'Git Not Available';

  @override
  String get gitUnavailableHint =>
      'Git features are not available for this project';

  @override
  String get autoModeFallbackDefaultTip =>
      'Auto mode is not available in this environment, so Default mode was selected';

  @override
  String get disconnect => 'Disconnect';

  @override
  String get next => 'Next';

  @override
  String get done => 'Done';

  @override
  String get skip => 'Skip';

  @override
  String get edit => 'Edit';

  @override
  String get share => 'Share';

  @override
  String get all => 'All';

  @override
  String get none => 'None';

  @override
  String get stopSession => 'Stop Session';

  @override
  String get apiKeyHint => 'Leave empty if no auth';

  @override
  String get hideSessions => 'Hide left pane';

  @override
  String get running => 'Running';

  @override
  String get recentSessions => 'Recent Sessions';

  @override
  String get search => 'Search';

  @override
  String get searchSessions => 'Search sessions...';

  @override
  String get sessionDisplayModeFirst => 'First';

  @override
  String get sessionDisplayModeLast => 'Last';

  @override
  String get sessionDisplayModeSummary => 'Summary';

  @override
  String get allProjects => 'All Projects';

  @override
  String get named => 'Named';

  @override
  String get add => 'Add';

  @override
  String get readyToStart => 'Ready to start';

  @override
  String get readyToStartDescription =>
      'Press the + button to create a new session and start coding with Codex.';

  @override
  String get newSession => 'New Session';

  @override
  String get update => 'Update';

  @override
  String get projectPath => 'Project Path';

  @override
  String get permission => 'Permission';

  @override
  String get approval => 'Approval';

  @override
  String get advanced => 'Advanced';

  @override
  String get effort => 'Effort';

  @override
  String get model => 'Model';

  @override
  String get sandbox => 'Sandbox';

  @override
  String get reasoning => 'Reasoning';

  @override
  String get planApprovalSummaryCard =>
      'Review the plan and approve or continue planning';

  @override
  String get viewEditPlan => 'View Plan';

  @override
  String get keepPlanning => 'Keep Planning';

  @override
  String get keepPlanningHint => 'What should be changed...';

  @override
  String get sendFeedbackKeepPlanning => 'Send feedback & keep planning';

  @override
  String get acceptAndClear => 'Accept & Clear';

  @override
  String get acceptPlan => 'Accept Plan';

  @override
  String get continuePlanning => 'Keep Planning';

  @override
  String get reject => 'Reject';

  @override
  String get approve => 'Approve';

  @override
  String get approveOnce => 'Allow Once';

  @override
  String get approveForSession => 'Allow for This Session';

  @override
  String get approveAlways => 'Permanently';

  @override
  String get approveAlwaysSub => 'allow';

  @override
  String get approveSessionMain => 'This Session';

  @override
  String get approveSessionSub => 'allow';

  @override
  String get guardianApprovalTitle => 'Auto Review approved';

  @override
  String get guardianApprovalMediumRisk => 'Medium risk';

  @override
  String get guardianApprovalHighRisk => 'High risk';

  @override
  String get guardianApprovalDetails => 'Details';

  @override
  String get guardianApprovalHideDetails => 'Hide details';

  @override
  String guardianApprovalAuthorization(String authorization) {
    return 'Authorization: $authorization';
  }

  @override
  String get messagePlaceholder => 'Message Codex...';

  @override
  String get codexMessagePlaceholder => 'Message Codex...';

  @override
  String get queuedInputForNextTurn => 'Queued for next turn';

  @override
  String get sessionCardQueuedInput => 'Queued';

  @override
  String queuedInputImageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count images',
      one: '$count image',
    );
    return '$_temp0';
  }

  @override
  String get reconnecting =>
      'local runtime connection was interrupted. Reconnecting automatically...';

  @override
  String get pendingActionWillCreateOnReconnect =>
      'Will create when the local runtime reconnects';

  @override
  String get pendingActionWillResumeOnReconnect =>
      'Will resume when the local runtime reconnects';

  @override
  String get pendingActionStatus => 'Pending';

  @override
  String get pendingActionProcessingStatus => 'Restoring';

  @override
  String get pendingActionProcessingStartStatus => 'Preparing';

  @override
  String get pendingActionProcessingStartDescription =>
      'local runtime is preparing the session';

  @override
  String get pendingActionProcessingResumeDescription =>
      'Sessions with many images may take longer';

  @override
  String get pendingActionProcessingStartTitle => 'Creating new session';

  @override
  String get pendingActionProcessingResumeTitle => 'Loading session history';

  @override
  String get tooltipCancelPendingAction => 'Cancel pending action';

  @override
  String get queuedLocally => 'Queued locally';

  @override
  String get offlinePendingNewSessionTitle => 'New session pending';

  @override
  String get offlinePendingResumeTitle => 'Resume pending';

  @override
  String changedLines(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count changed lines',
      one: '$count changed line',
    );
    return '$_temp0';
  }

  @override
  String hunkCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hunks',
      one: '$count hunk',
    );
    return '$_temp0';
  }

  @override
  String fileCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count files',
      one: '$count file',
    );
    return '$_temp0';
  }

  @override
  String get tapInterruptHoldStop => 'Tap: interrupt, Hold: stop';

  @override
  String get rewind => 'Rewind';

  @override
  String get rewindToHere => 'Rewind to here';

  @override
  String get forkConversation => 'Fork conversation';

  @override
  String get tapToRetry => 'Tap to retry';

  @override
  String diffSummaryAddedRemoved(int added, int removed) {
    return '+$added/-$removed lines';
  }

  @override
  String lineCountSummary(int count) {
    return '$count lines';
  }

  @override
  String get toolResult => 'Tool Result';

  @override
  String get answered => 'Answered';

  @override
  String agentIsAsking(Object agent) {
    return '$agent is asking';
  }

  @override
  String get submitAllAnswers => 'Submit All Answers';

  @override
  String submitWithCount(int count) {
    return 'Submit ($count selected)';
  }

  @override
  String get selectOptionsToSubmit => 'Select options to submit';

  @override
  String get typeYourAnswer => 'Type your answer...';

  @override
  String get orTypeCustomAnswer => 'Or type a custom answer...';

  @override
  String get otherAnswer => 'Other answer...';

  @override
  String get selectAllThatApply => 'Select all that apply';

  @override
  String get failedToDownloadImage => 'Failed to download image';

  @override
  String get failedToShareImage => 'Failed to share image';

  @override
  String get refresh => 'Refresh';

  @override
  String get viewChanges => 'View Changes';

  @override
  String get promptHistory => 'Prompt History';

  @override
  String get working => 'Working...';

  @override
  String get noActiveSessions => 'No active sessions';

  @override
  String get codeFontSize => 'Code font size';

  @override
  String get codeFontFamily => 'Code font';

  @override
  String get imagePasteShortcut => 'Image paste shortcut';

  @override
  String get theme => 'Theme';

  @override
  String get language => 'Language';

  @override
  String get version => 'Version';

  @override
  String get loading => 'Loading...';

  @override
  String get loadingSessions => 'Loading sessions...';

  @override
  String get imageAttached => 'Image attached';

  @override
  String get usageDisplayModeRemaining => 'Remaining';

  @override
  String get usageDisplayModeUsed => 'Used';

  @override
  String get usageRefreshHint => 'Refresh Codex usage';

  @override
  String get systemNoticeLabel => 'System';

  @override
  String get codexSessionStarted => 'Session started';

  @override
  String get codexCodeModeFallbackNotice =>
      'Code Mode unavailable; using direct tools.';

  @override
  String get optionalMcpWorkerNotice =>
      'Optional MCP unavailable; local Codex still works.';

  @override
  String attachedImages(int count) {
    return 'Attached Images ($count)';
  }

  @override
  String get failedToLoadImage => 'Failed to load image';

  @override
  String get generatedImagePromptLabel => 'Prompt';

  @override
  String get generatedImageDetailsLabel => 'Details';

  @override
  String get generatedImageHideDetailsLabel => 'Hide details';

  @override
  String get generatedImageStatusLabel => 'Status';

  @override
  String get generatedImageSavedPathLabel => 'Saved file';

  @override
  String get previousImage => 'Previous image';

  @override
  String get nextImage => 'Next image';

  @override
  String generatedImagePositionLabel(int current, int total) {
    return 'Generated image $current of $total';
  }

  @override
  String get noRecentSessions => 'No recent sessions';

  @override
  String get noSessionsMatchFilters => 'No sessions match the current filters';

  @override
  String get adjustFiltersAndSearch => 'Try changing filters or search terms';

  @override
  String get tooltipDisplayMode => 'Change which message is shown on cards';

  @override
  String get tooltipProjectFilter => 'Filter by project';

  @override
  String get tooltipNamedOnly => 'Only sessions you\'ve named';

  @override
  String get tooltipIndent => 'Increase indent';

  @override
  String get tooltipDedent => 'Decrease indent';

  @override
  String get tooltipSlashCommand => 'Insert command or skill';

  @override
  String get tooltipMention => 'Mention file or plugin';

  @override
  String get tooltipDollarMention => 'Insert skill or app';

  @override
  String get tooltipAttachImage => 'Attach image';

  @override
  String get tooltipPromptHistory => 'Open prompt history';

  @override
  String get tooltipVoiceInput => 'Start voice input';

  @override
  String get tooltipStopRecording => 'Stop recording';

  @override
  String get tooltipSendMessage => 'Send message';

  @override
  String get tooltipRemoveImage => 'Remove image';

  @override
  String get tooltipClearDiff => 'Clear diff selection';

  @override
  String get authErrorTitle => 'Codex login required';

  @override
  String get authErrorBody =>
      'Codex needs to sign in again in this app.';

  @override
  String get authErrorPrimaryCommandLabel => 'Step 1';

  @override
  String get authErrorSecondaryCommandLabel => 'Step 2';

  @override
  String get authErrorAlternativeLabel => 'Shell alternative';

  @override
  String get authHelpButton => 'View steps';

  @override
  String get googleSearchSelectionAction => 'Search with Google';

  @override
  String get fileChangeApprovalTitle => 'File Change Approval';

  @override
  String get allowFileChanges => 'Allow file changes';

  @override
  String allowChangesToFile(String path) => 'Allow changes to $path';

  @override
  String allowChangesToFiles(int count) => 'Allow changes to $count files';

  @override
  String additionalFiles(int count) => '+$count more';
}
