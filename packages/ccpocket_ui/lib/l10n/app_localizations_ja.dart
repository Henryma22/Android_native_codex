// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class AppLocalizationsJa extends AppLocalizations {
  AppLocalizationsJa([String locale = 'ja']) : super(locale);

  @override
  String get appTitle => 'Codex';

  @override
  String get cancel => 'キャンセル';

  @override
  String get save => '保存';

  @override
  String get delete => '削除';

  @override
  String get remove => '削除';

  @override
  String get renameSession => 'セッション名を変更';

  @override
  String get pin => 'セッションをピン留め';

  @override
  String get unpin => 'セッションのピン留めを解除';

  @override
  String get pinProject => 'プロジェクトをピン留め';

  @override
  String get unpinProject => 'プロジェクトのピン留めを解除';

  @override
  String get sessionNameHint => 'セッション名';

  @override
  String get copy => 'コピー';

  @override
  String get markdownLinkOpenFailed => 'リンクを開けませんでした。';

  @override
  String get markdownLinkUnsupported => 'この種類のリンクには対応していません。';

  @override
  String get markdownFileUnavailable => 'このファイルはここではプレビューできません。';

  @override
  String get copied => 'コピーしました';

  @override
  String get copiedToClipboard => 'クリップボードにコピーしました';

  @override
  String get start => '開始';

  @override
  String get stop => '停止';

  @override
  String get send => '送信';

  @override
  String get settings => '設定';

  @override
  String get gallery => 'ギャラリー';

  @override
  String get gitUnavailableTip => 'Git未検出 — Git機能は利用できません';

  @override
  String get gitUnavailableTitle => 'Gitを利用できません';

  @override
  String get gitUnavailableHint => 'このプロジェクトではGit機能を利用できません';

  @override
  String get autoModeFallbackDefaultTip =>
      'Auto mode はこの環境で使えないため Default に切り替えました';

  @override
  String get disconnect => '切断';

  @override
  String get next => '次へ';

  @override
  String get done => '完了';

  @override
  String get skip => 'スキップ';

  @override
  String get edit => '編集';

  @override
  String get share => '共有';

  @override
  String get all => 'すべて';

  @override
  String get none => 'なし';

  @override
  String get stopSession => 'セッションを停止';

  @override
  String get apiKeyHint => '認証なしの場合は空欄';

  @override
  String get hideSessions => '左ペインを隠す';

  @override
  String get running => '実行中';

  @override
  String get recentSessions => '最近のセッション';

  @override
  String get search => '検索';

  @override
  String get searchSessions => 'セッションを検索...';

  @override
  String get sessionDisplayModeFirst => '先頭';

  @override
  String get sessionDisplayModeLast => '末尾';

  @override
  String get sessionDisplayModeSummary => '要約';

  @override
  String get allProjects => 'すべてのプロジェクト';

  @override
  String get named => '名前付き';

  @override
  String get add => '追加';

  @override
  String get readyToStart => '準備完了';

  @override
  String get readyToStartDescription =>
      '+ ボタンを押してセッションを作成し、Codex でコーディングを始めましょう。';

  @override
  String get newSession => '新規セッション';

  @override
  String get update => '更新';

  @override
  String get projectPath => 'プロジェクトパス';

  @override
  String get permission => 'パーミッション';

  @override
  String get approval => '承認';

  @override
  String get advanced => '詳細設定';

  @override
  String get effort => '推論の強度';

  @override
  String get model => 'モデル';

  @override
  String get sandbox => 'Sandbox';

  @override
  String get reasoning => 'Reasoning';

  @override
  String get planApprovalSummaryCard => 'プランを確認して、承認するか計画を続けてください';

  @override
  String get viewEditPlan => 'プランを表示';

  @override
  String get keepPlanning => '計画を続ける';

  @override
  String get keepPlanningHint => '変更点を入力...';

  @override
  String get sendFeedbackKeepPlanning => 'フィードバックを送信して計画を続ける';

  @override
  String get acceptAndClear => '承認 & クリア';

  @override
  String get acceptPlan => 'プラン承認';

  @override
  String get continuePlanning => '計画を続ける';

  @override
  String get reject => '拒否';

  @override
  String get approve => '承認';

  @override
  String get approveOnce => '今回だけ許可';

  @override
  String get approveForSession => 'このセッション中は許可';

  @override
  String get approveAlways => '常に許可';

  @override
  String get approveAlwaysSub => '';

  @override
  String get approveSessionMain => 'セッション中許可';

  @override
  String get approveSessionSub => '';

  @override
  String get guardianApprovalTitle => '自動レビューで承認';

  @override
  String get guardianApprovalMediumRisk => '中リスク';

  @override
  String get guardianApprovalHighRisk => '高リスク';

  @override
  String get guardianApprovalDetails => '詳細';

  @override
  String get guardianApprovalHideDetails => '詳細を閉じる';

  @override
  String guardianApprovalAuthorization(String authorization) {
    return '承認レベル: $authorization';
  }

  @override
  String get messagePlaceholder => 'Codex にメッセージ...';

  @override
  String get codexMessagePlaceholder => 'Codex にメッセージ...';

  @override
  String get queuedInputForNextTurn => '次のターンに送信予定';

  @override
  String get sessionCardQueuedInput => 'キュー中';

  @override
  String queuedInputImageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '画像$count枚',
    );
    return '$_temp0';
  }

  @override
  String get reconnecting => 'この端末の Codex 接続が一時的に切れました。自動で再接続しています...';

  @override
  String get pendingActionWillCreateOnReconnect => 'この端末の Codex 再接続後に作成します';

  @override
  String get pendingActionWillResumeOnReconnect => 'この端末の Codex 再接続後に再開します';

  @override
  String get pendingActionStatus => '待機中';

  @override
  String get pendingActionProcessingStatus => '復元中';

  @override
  String get pendingActionProcessingStartStatus => '準備中';

  @override
  String get pendingActionProcessingStartDescription =>
      'この端末の Codex がセッションを準備しています';

  @override
  String get pendingActionProcessingResumeDescription =>
      '画像が多いセッションは時間がかかることがあります';

  @override
  String get pendingActionProcessingStartTitle => '新規セッションを作成中';

  @override
  String get pendingActionProcessingResumeTitle => 'セッション履歴を読み込んでいます';

  @override
  String get tooltipCancelPendingAction => '待機中の操作をキャンセル';

  @override
  String get queuedLocally => 'ローカルでキュー中';

  @override
  String get offlinePendingNewSessionTitle => '新規セッション待機中';

  @override
  String get offlinePendingResumeTitle => '再開待機中';

  @override
  String changedLines(int count) {
    return '変更$count行';
  }

  @override
  String hunkCount(int count) {
    return '$countハンク';
  }

  @override
  String fileCount(int count) {
    return '$countファイル';
  }

  @override
  String get tapInterruptHoldStop => 'タップ: 中断, 長押し: 停止';

  @override
  String get rewind => '巻き戻す';

  @override
  String get rewindToHere => 'ここまで巻き戻す';

  @override
  String get forkConversation => '会話を分岐';

  @override
  String get tapToRetry => 'タップしてリトライ';

  @override
  String diffSummaryAddedRemoved(int added, int removed) {
    return '+$added/-$removed 行';
  }

  @override
  String lineCountSummary(int count) {
    return '$count 行';
  }

  @override
  String get toolResult => 'ツール結果';

  @override
  String get answered => '回答済み';

  @override
  String agentIsAsking(Object agent) {
    return '$agent が質問しています';
  }

  @override
  String get submitAllAnswers => 'すべての回答を送信';

  @override
  String submitWithCount(int count) {
    return '送信 ($count 件選択)';
  }

  @override
  String get selectOptionsToSubmit => 'オプションを選択してください';

  @override
  String get typeYourAnswer => '回答を入力...';

  @override
  String get orTypeCustomAnswer => 'またはカスタム回答を入力...';

  @override
  String get otherAnswer => 'その他の回答...';

  @override
  String get selectAllThatApply => '該当するものをすべて選択';

  @override
  String get failedToDownloadImage => '画像のダウンロードに失敗しました';

  @override
  String get failedToShareImage => '画像の共有に失敗しました';

  @override
  String get refresh => '更新';

  @override
  String get viewChanges => '変更を確認';

  @override
  String get promptHistory => 'プロンプト履歴';

  @override
  String get working => '処理中...';

  @override
  String get noActiveSessions => 'アクティブなセッションがありません';

  @override
  String get codeFontSize => 'コード文字サイズ';

  @override
  String get codeFontFamily => 'コードフォント';

  @override
  String get imagePasteShortcut => '画像ペーストのショートカット';

  @override
  String get theme => 'テーマ';

  @override
  String get language => '言語';

  @override
  String get version => 'バージョン';

  @override
  String get loading => '読み込み中...';

  @override
  String get loadingSessions => 'セッション一覧を読み込み中...';

  @override
  String get imageAttached => '画像添付';

  @override
  String get usageDisplayModeRemaining => '残量';

  @override
  String get usageDisplayModeUsed => '使用量';

  @override
  String get usageRefreshHint => 'Codex の使用量を更新';

  @override
  String get systemNoticeLabel => 'システム';

  @override
  String get codexSessionStarted => 'セッションを開始しました';

  @override
  String get codexCodeModeFallbackNotice => 'Code Mode は利用できません。直接ツールに切り替えました。';

  @override
  String get optionalMcpWorkerNotice => 'MCP は利用できませんが、ローカル Codex は引き続き使えます。';

  @override
  String attachedImages(int count) {
    return '添付画像 ($count)';
  }

  @override
  String get failedToLoadImage => '画像の読み込みに失敗しました';

  @override
  String get generatedImagePromptLabel => 'プロンプト';

  @override
  String get generatedImageDetailsLabel => '詳細';

  @override
  String get generatedImageHideDetailsLabel => '詳細を閉じる';

  @override
  String get generatedImageStatusLabel => 'ステータス';

  @override
  String get generatedImageSavedPathLabel => '保存先';

  @override
  String get previousImage => '前の画像';

  @override
  String get nextImage => '次の画像';

  @override
  String generatedImagePositionLabel(int current, int total) {
    return '生成画像 $current / $total';
  }

  @override
  String get noRecentSessions => '最近のセッションはありません';

  @override
  String get noSessionsMatchFilters => '現在のフィルター条件に一致するセッションがありません';

  @override
  String get adjustFiltersAndSearch => 'フィルター条件や検索語を変更してください';

  @override
  String get tooltipDisplayMode => 'カードに表示するメッセージを切替';

  @override
  String get tooltipProjectFilter => 'プロジェクトで絞り込み';

  @override
  String get tooltipNamedOnly => '名前を付けたセッションのみ';

  @override
  String get tooltipIndent => 'インデントを増やす';

  @override
  String get tooltipDedent => 'インデントを減らす';

  @override
  String get tooltipSlashCommand => 'コマンド・スキルを入力';

  @override
  String get tooltipMention => 'ファイル・プラグインをメンション';

  @override
  String get tooltipDollarMention => 'スキル・アプリを入力';

  @override
  String get tooltipAttachImage => '画像を添付';

  @override
  String get tooltipPromptHistory => 'プロンプト履歴を開く';

  @override
  String get tooltipVoiceInput => '音声入力を開始';

  @override
  String get tooltipStopRecording => '録音を停止';

  @override
  String get tooltipSendMessage => 'メッセージを送信';

  @override
  String get tooltipRemoveImage => '画像を削除';

  @override
  String get tooltipClearDiff => 'Diff選択を解除';

  @override
  String get authErrorTitle => 'Codexの再ログインが必要です';

  @override
  String get authErrorBody => 'この端末の Codex に再ログインしてください。';

  @override
  String get authErrorPrimaryCommandLabel => '手順1';

  @override
  String get authErrorSecondaryCommandLabel => '手順2';

  @override
  String get authErrorAlternativeLabel => 'シェルから実行する場合';

  @override
  String get authHelpButton => '手順を見る';

  @override
  String get googleSearchSelectionAction => 'Google で検索';

  @override
  String get fileChangeApprovalTitle => 'ファイル変更の承認';

  @override
  String get allowFileChanges => 'ファイルの変更を許可';

  @override
  String allowChangesToFile(String path) => '$path の変更を許可';

  @override
  String allowChangesToFiles(int count) => '$count 個のファイル変更を許可';

  @override
  String additionalFiles(int count) => 'ほか $count 件';
}
