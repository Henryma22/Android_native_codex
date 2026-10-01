import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ja.dart';
import 'app_localizations_ko.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ja'),
    Locale('en'),
    Locale('ko'),
    Locale('zh'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In ja, this message translates to:
  /// **'CC Pocket'**
  String get appTitle;

  /// No description provided for @cancel.
  ///
  /// In ja, this message translates to:
  /// **'キャンセル'**
  String get cancel;

  /// No description provided for @save.
  ///
  /// In ja, this message translates to:
  /// **'保存'**
  String get save;

  /// No description provided for @delete.
  ///
  /// In ja, this message translates to:
  /// **'削除'**
  String get delete;

  /// No description provided for @remove.
  ///
  /// In ja, this message translates to:
  /// **'削除'**
  String get remove;




  /// No description provided for @renameSession.
  ///
  /// In ja, this message translates to:
  /// **'セッション名を変更'**
  String get renameSession;

  /// No description provided for @pin.
  ///
  /// In ja, this message translates to:
  /// **'セッションをピン留め'**
  String get pin;

  /// No description provided for @unpin.
  ///
  /// In ja, this message translates to:
  /// **'セッションのピン留めを解除'**
  String get unpin;

  /// No description provided for @pinProject.
  ///
  /// In ja, this message translates to:
  /// **'プロジェクトをピン留め'**
  String get pinProject;

  /// No description provided for @unpinProject.
  ///
  /// In ja, this message translates to:
  /// **'プロジェクトのピン留めを解除'**
  String get unpinProject;

  /// No description provided for @sessionNameHint.
  ///
  /// In ja, this message translates to:
  /// **'セッション名'**
  String get sessionNameHint;












  /// No description provided for @copy.
  ///
  /// In ja, this message translates to:
  /// **'コピー'**
  String get copy;

  /// No description provided for @markdownLinkOpenFailed.
  ///
  /// In ja, this message translates to:
  /// **'リンクを開けませんでした。'**
  String get markdownLinkOpenFailed;

  /// No description provided for @markdownLinkUnsupported.
  ///
  /// In ja, this message translates to:
  /// **'この種類のリンクには対応していません。'**
  String get markdownLinkUnsupported;

  /// No description provided for @markdownFileUnavailable.
  ///
  /// In ja, this message translates to:
  /// **'このファイルはここではプレビューできません。'**
  String get markdownFileUnavailable;




  /// No description provided for @copied.
  ///
  /// In ja, this message translates to:
  /// **'コピーしました'**
  String get copied;

  /// No description provided for @copiedToClipboard.
  ///
  /// In ja, this message translates to:
  /// **'クリップボードにコピーしました'**
  String get copiedToClipboard;


  /// No description provided for @start.
  ///
  /// In ja, this message translates to:
  /// **'開始'**
  String get start;

  /// No description provided for @stop.
  ///
  /// In ja, this message translates to:
  /// **'停止'**
  String get stop;

  /// No description provided for @send.
  ///
  /// In ja, this message translates to:
  /// **'送信'**
  String get send;

  /// No description provided for @settings.
  ///
  /// In ja, this message translates to:
  /// **'設定'**
  String get settings;

  /// No description provided for @gallery.
  ///
  /// In ja, this message translates to:
  /// **'ギャラリー'**
  String get gallery;



  /// No description provided for @gitUnavailableTip.
  ///
  /// In ja, this message translates to:
  /// **'Git未検出 — Git機能は利用できません'**
  String get gitUnavailableTip;

  /// No description provided for @gitUnavailableTitle.
  ///
  /// In ja, this message translates to:
  /// **'Gitを利用できません'**
  String get gitUnavailableTitle;

  /// No description provided for @gitUnavailableHint.
  ///
  /// In ja, this message translates to:
  /// **'このプロジェクトではGit機能を利用できません'**
  String get gitUnavailableHint;

  /// No description provided for @autoModeFallbackDefaultTip.
  ///
  /// In ja, this message translates to:
  /// **'Auto mode はこの環境で使えないため Default に切り替えました'**
  String get autoModeFallbackDefaultTip;


  /// No description provided for @disconnect.
  ///
  /// In ja, this message translates to:
  /// **'切断'**
  String get disconnect;


  /// No description provided for @next.
  ///
  /// In ja, this message translates to:
  /// **'次へ'**
  String get next;

  /// No description provided for @done.
  ///
  /// In ja, this message translates to:
  /// **'完了'**
  String get done;

  /// No description provided for @skip.
  ///
  /// In ja, this message translates to:
  /// **'スキップ'**
  String get skip;

  /// No description provided for @edit.
  ///
  /// In ja, this message translates to:
  /// **'編集'**
  String get edit;

  /// No description provided for @share.
  ///
  /// In ja, this message translates to:
  /// **'共有'**
  String get share;

  /// No description provided for @all.
  ///
  /// In ja, this message translates to:
  /// **'すべて'**
  String get all;

  /// No description provided for @none.
  ///
  /// In ja, this message translates to:
  /// **'なし'**
  String get none;











  /// No description provided for @stopSession.
  ///
  /// In ja, this message translates to:
  /// **'セッションを停止'**
  String get stopSession;




















































































  /// No description provided for @apiKeyHint.
  ///
  /// In ja, this message translates to:
  /// **'認証なしの場合は空欄'**
  String get apiKeyHint;




  /// No description provided for @hideSessions.
  ///
  /// In ja, this message translates to:
  /// **'左ペインを隠す'**
  String get hideSessions;




  /// No description provided for @running.
  ///
  /// In ja, this message translates to:
  /// **'実行中'**
  String get running;

  /// No description provided for @recentSessions.
  ///
  /// In ja, this message translates to:
  /// **'最近のセッション'**
  String get recentSessions;

  /// No description provided for @search.
  ///
  /// In ja, this message translates to:
  /// **'検索'**
  String get search;

  /// No description provided for @searchSessions.
  ///
  /// In ja, this message translates to:
  /// **'セッションを検索...'**
  String get searchSessions;

  /// No description provided for @sessionDisplayModeFirst.
  ///
  /// In ja, this message translates to:
  /// **'先頭'**
  String get sessionDisplayModeFirst;

  /// No description provided for @sessionDisplayModeLast.
  ///
  /// In ja, this message translates to:
  /// **'末尾'**
  String get sessionDisplayModeLast;

  /// No description provided for @sessionDisplayModeSummary.
  ///
  /// In ja, this message translates to:
  /// **'要約'**
  String get sessionDisplayModeSummary;


  /// No description provided for @allProjects.
  ///
  /// In ja, this message translates to:
  /// **'すべてのプロジェクト'**
  String get allProjects;

  /// No description provided for @named.
  ///
  /// In ja, this message translates to:
  /// **'名前付き'**
  String get named;



  /// No description provided for @add.
  ///
  /// In ja, this message translates to:
  /// **'追加'**
  String get add;


  /// No description provided for @readyToStart.
  ///
  /// In ja, this message translates to:
  /// **'準備完了'**
  String get readyToStart;

  /// No description provided for @readyToStartDescription.
  ///
  /// In ja, this message translates to:
  /// **'+ ボタンを押してセッションを作成し、Codex でコーディングを始めましょう。'**
  String get readyToStartDescription;

  /// No description provided for @newSession.
  ///
  /// In ja, this message translates to:
  /// **'新規セッション'**
  String get newSession;
























  /// No description provided for @update.
  ///
  /// In ja, this message translates to:
  /// **'更新'**
  String get update;













  /// No description provided for @projectPath.
  ///
  /// In ja, this message translates to:
  /// **'プロジェクトパス'**
  String get projectPath;


  /// No description provided for @permission.
  ///
  /// In ja, this message translates to:
  /// **'パーミッション'**
  String get permission;

  /// No description provided for @approval.
  ///
  /// In ja, this message translates to:
  /// **'承認'**
  String get approval;



  /// No description provided for @advanced.
  ///
  /// In ja, this message translates to:
  /// **'詳細設定'**
  String get advanced;


  /// No description provided for @effort.
  ///
  /// In ja, this message translates to:
  /// **'Effort'**
  String get effort;












  /// No description provided for @model.
  ///
  /// In ja, this message translates to:
  /// **'モデル'**
  String get model;

  /// No description provided for @sandbox.
  ///
  /// In ja, this message translates to:
  /// **'Sandbox'**
  String get sandbox;

  /// No description provided for @reasoning.
  ///
  /// In ja, this message translates to:
  /// **'Reasoning'**
  String get reasoning;





















  /// No description provided for @planApprovalSummaryCard.
  ///
  /// In ja, this message translates to:
  /// **'プランを確認して、承認するか計画を続けてください'**
  String get planApprovalSummaryCard;




  /// No description provided for @viewEditPlan.
  ///
  /// In ja, this message translates to:
  /// **'プランを表示'**
  String get viewEditPlan;

  /// No description provided for @keepPlanning.
  ///
  /// In ja, this message translates to:
  /// **'計画を続ける'**
  String get keepPlanning;

  /// No description provided for @keepPlanningHint.
  ///
  /// In ja, this message translates to:
  /// **'変更点を入力...'**
  String get keepPlanningHint;

  /// No description provided for @sendFeedbackKeepPlanning.
  ///
  /// In ja, this message translates to:
  /// **'フィードバックを送信して計画を続ける'**
  String get sendFeedbackKeepPlanning;

  /// No description provided for @acceptAndClear.
  ///
  /// In ja, this message translates to:
  /// **'承認 & クリア'**
  String get acceptAndClear;

  /// No description provided for @acceptPlan.
  ///
  /// In ja, this message translates to:
  /// **'プラン承認'**
  String get acceptPlan;

  /// No description provided for @continuePlanning.
  ///
  /// In ja, this message translates to:
  /// **'計画を続ける'**
  String get continuePlanning;

  /// No description provided for @reject.
  ///
  /// In ja, this message translates to:
  /// **'拒否'**
  String get reject;

  /// No description provided for @approve.
  ///
  /// In ja, this message translates to:
  /// **'承認'**
  String get approve;


  /// No description provided for @approveOnce.
  ///
  /// In ja, this message translates to:
  /// **'今回だけ許可'**
  String get approveOnce;

  /// No description provided for @approveForSession.
  ///
  /// In ja, this message translates to:
  /// **'このセッション中は許可'**
  String get approveForSession;

  /// No description provided for @approveAlways.
  ///
  /// In ja, this message translates to:
  /// **'常に許可'**
  String get approveAlways;

  /// No description provided for @approveAlwaysSub.
  ///
  /// In ja, this message translates to:
  /// **''**
  String get approveAlwaysSub;

  /// No description provided for @approveSessionMain.
  ///
  /// In ja, this message translates to:
  /// **'セッション中許可'**
  String get approveSessionMain;

  /// No description provided for @approveSessionSub.
  ///
  /// In ja, this message translates to:
  /// **''**
  String get approveSessionSub;














































  /// No description provided for @guardianApprovalTitle.
  ///
  /// In ja, this message translates to:
  /// **'自動レビューで承認'**
  String get guardianApprovalTitle;

  /// No description provided for @guardianApprovalMediumRisk.
  ///
  /// In ja, this message translates to:
  /// **'中リスク'**
  String get guardianApprovalMediumRisk;

  /// No description provided for @guardianApprovalHighRisk.
  ///
  /// In ja, this message translates to:
  /// **'高リスク'**
  String get guardianApprovalHighRisk;

  /// No description provided for @guardianApprovalDetails.
  ///
  /// In ja, this message translates to:
  /// **'詳細'**
  String get guardianApprovalDetails;

  /// No description provided for @guardianApprovalHideDetails.
  ///
  /// In ja, this message translates to:
  /// **'詳細を閉じる'**
  String get guardianApprovalHideDetails;

  /// No description provided for @guardianApprovalAuthorization.
  ///
  /// In ja, this message translates to:
  /// **'承認レベル: {authorization}'**
  String guardianApprovalAuthorization(String authorization);







  /// No description provided for @messagePlaceholder.
  ///
  /// In ja, this message translates to:
  /// **'Codex にメッセージ...'**
  String get messagePlaceholder;

  /// No description provided for @codexMessagePlaceholder.
  ///
  /// In ja, this message translates to:
  /// **'Codex にメッセージ...'**
  String get codexMessagePlaceholder;



  /// No description provided for @queuedInputForNextTurn.
  ///
  /// In ja, this message translates to:
  /// **'次のターンに送信予定'**
  String get queuedInputForNextTurn;

  /// No description provided for @sessionCardQueuedInput.
  ///
  /// In ja, this message translates to:
  /// **'キュー中'**
  String get sessionCardQueuedInput;

  /// No description provided for @queuedInputImageCount.
  ///
  /// In ja, this message translates to:
  /// **'{count, plural, other{画像{count}枚}}'**
  String queuedInputImageCount(int count);




  /// No description provided for @reconnecting.
  ///
  /// In ja, this message translates to:
  /// **'この端末の Codex 接続が一時的に切れました。自動で再接続しています...'**
  String get reconnecting;






  /// No description provided for @pendingActionWillCreateOnReconnect.
  ///
  /// In ja, this message translates to:
  /// **'この端末の Codex 再接続後に作成します'**
  String get pendingActionWillCreateOnReconnect;

  /// No description provided for @pendingActionWillResumeOnReconnect.
  ///
  /// In ja, this message translates to:
  /// **'この端末の Codex 再接続後に再開します'**
  String get pendingActionWillResumeOnReconnect;

  /// No description provided for @pendingActionStatus.
  ///
  /// In ja, this message translates to:
  /// **'待機中'**
  String get pendingActionStatus;

  /// No description provided for @pendingActionProcessingStatus.
  ///
  /// In ja, this message translates to:
  /// **'復元中'**
  String get pendingActionProcessingStatus;

  /// No description provided for @pendingActionProcessingStartStatus.
  ///
  /// In ja, this message translates to:
  /// **'準備中'**
  String get pendingActionProcessingStartStatus;

  /// No description provided for @pendingActionProcessingStartDescription.
  ///
  /// In ja, this message translates to:
  /// **'この端末の Codex がセッションを準備しています'**
  String get pendingActionProcessingStartDescription;

  /// No description provided for @pendingActionProcessingResumeDescription.
  ///
  /// In ja, this message translates to:
  /// **'画像が多いセッションは時間がかかることがあります'**
  String get pendingActionProcessingResumeDescription;

  /// No description provided for @pendingActionProcessingStartTitle.
  ///
  /// In ja, this message translates to:
  /// **'新規セッションを作成中'**
  String get pendingActionProcessingStartTitle;

  /// No description provided for @pendingActionProcessingResumeTitle.
  ///
  /// In ja, this message translates to:
  /// **'セッション履歴を読み込んでいます'**
  String get pendingActionProcessingResumeTitle;

  /// No description provided for @tooltipCancelPendingAction.
  ///
  /// In ja, this message translates to:
  /// **'待機中の操作をキャンセル'**
  String get tooltipCancelPendingAction;

  /// No description provided for @queuedLocally.
  ///
  /// In ja, this message translates to:
  /// **'ローカルでキュー中'**
  String get queuedLocally;


  /// No description provided for @offlinePendingNewSessionTitle.
  ///
  /// In ja, this message translates to:
  /// **'新規セッション待機中'**
  String get offlinePendingNewSessionTitle;

  /// No description provided for @offlinePendingResumeTitle.
  ///
  /// In ja, this message translates to:
  /// **'再開待機中'**
  String get offlinePendingResumeTitle;


  /// No description provided for @changedLines.
  ///
  /// In ja, this message translates to:
  /// **'変更{count}行'**
  String changedLines(int count);

  /// No description provided for @hunkCount.
  ///
  /// In ja, this message translates to:
  /// **'{count}ハンク'**
  String hunkCount(int count);

  /// No description provided for @fileCount.
  ///
  /// In ja, this message translates to:
  /// **'{count}ファイル'**
  String fileCount(int count);

  /// No description provided for @tapInterruptHoldStop.
  ///
  /// In ja, this message translates to:
  /// **'タップ: 中断, 長押し: 停止'**
  String get tapInterruptHoldStop;

  /// No description provided for @rewind.
  ///
  /// In ja, this message translates to:
  /// **'巻き戻す'**
  String get rewind;

  /// No description provided for @rewindToHere.
  ///
  /// In ja, this message translates to:
  /// **'ここまで巻き戻す'**
  String get rewindToHere;










  /// No description provided for @forkConversation.
  ///
  /// In ja, this message translates to:
  /// **'会話を分岐'**
  String get forkConversation;




  /// No description provided for @tapToRetry.
  ///
  /// In ja, this message translates to:
  /// **'タップしてリトライ'**
  String get tapToRetry;

  /// No description provided for @diffSummaryAddedRemoved.
  ///
  /// In ja, this message translates to:
  /// **'+{added}/-{removed} 行'**
  String diffSummaryAddedRemoved(int added, int removed);

  /// No description provided for @lineCountSummary.
  ///
  /// In ja, this message translates to:
  /// **'{count} 行'**
  String lineCountSummary(int count);

  /// No description provided for @toolResult.
  ///
  /// In ja, this message translates to:
  /// **'ツール結果'**
  String get toolResult;

  /// No description provided for @answered.
  ///
  /// In ja, this message translates to:
  /// **'回答済み'**
  String get answered;

  /// No description provided for @agentIsAsking.
  ///
  /// In ja, this message translates to:
  /// **'{agent} が質問しています'**
  String agentIsAsking(Object agent);

  /// No description provided for @submitAllAnswers.
  ///
  /// In ja, this message translates to:
  /// **'すべての回答を送信'**
  String get submitAllAnswers;

  /// No description provided for @submitWithCount.
  ///
  /// In ja, this message translates to:
  /// **'送信 ({count} 件選択)'**
  String submitWithCount(int count);

  /// No description provided for @selectOptionsToSubmit.
  ///
  /// In ja, this message translates to:
  /// **'オプションを選択してください'**
  String get selectOptionsToSubmit;

  /// No description provided for @typeYourAnswer.
  ///
  /// In ja, this message translates to:
  /// **'回答を入力...'**
  String get typeYourAnswer;

  /// No description provided for @orTypeCustomAnswer.
  ///
  /// In ja, this message translates to:
  /// **'またはカスタム回答を入力...'**
  String get orTypeCustomAnswer;

  /// No description provided for @otherAnswer.
  ///
  /// In ja, this message translates to:
  /// **'その他の回答...'**
  String get otherAnswer;

  /// No description provided for @selectAllThatApply.
  ///
  /// In ja, this message translates to:
  /// **'該当するものをすべて選択'**
  String get selectAllThatApply;







  /// No description provided for @failedToDownloadImage.
  ///
  /// In ja, this message translates to:
  /// **'画像のダウンロードに失敗しました'**
  String get failedToDownloadImage;

  /// No description provided for @failedToShareImage.
  ///
  /// In ja, this message translates to:
  /// **'画像の共有に失敗しました'**
  String get failedToShareImage;




  /// No description provided for @refresh.
  ///
  /// In ja, this message translates to:
  /// **'更新'**
  String get refresh;




































































  /// No description provided for @viewChanges.
  ///
  /// In ja, this message translates to:
  /// **'変更を確認'**
  String get viewChanges;












  /// No description provided for @promptHistory.
  ///
  /// In ja, this message translates to:
  /// **'プロンプト履歴'**
  String get promptHistory;








































  /// No description provided for @working.
  ///
  /// In ja, this message translates to:
  /// **'処理中...'**
  String get working;


  /// No description provided for @noActiveSessions.
  ///
  /// In ja, this message translates to:
  /// **'アクティブなセッションがありません'**
  String get noActiveSessions;









  /// No description provided for @codeFontSize.
  ///
  /// In ja, this message translates to:
  /// **'コード文字サイズ'**
  String get codeFontSize;

  /// No description provided for @codeFontFamily.
  ///
  /// In ja, this message translates to:
  /// **'コードフォント'**
  String get codeFontFamily;









  /// No description provided for @imagePasteShortcut.
  ///
  /// In ja, this message translates to:
  /// **'画像ペーストのショートカット'**
  String get imagePasteShortcut;










  /// No description provided for @theme.
  ///
  /// In ja, this message translates to:
  /// **'テーマ'**
  String get theme;




  /// No description provided for @language.
  ///
  /// In ja, this message translates to:
  /// **'言語'**
  String get language;






  /// No description provided for @version.
  ///
  /// In ja, this message translates to:
  /// **'バージョン'**
  String get version;

  /// No description provided for @loading.
  ///
  /// In ja, this message translates to:
  /// **'読み込み中...'**
  String get loading;

  /// No description provided for @loadingSessions.
  ///
  /// In ja, this message translates to:
  /// **'セッション一覧を読み込み中...'**
  String get loadingSessions;



















  /// No description provided for @imageAttached.
  ///
  /// In ja, this message translates to:
  /// **'画像添付'**
  String get imageAttached;







  /// No description provided for @usageDisplayModeRemaining.
  ///
  /// In ja, this message translates to:
  /// **'残量'**
  String get usageDisplayModeRemaining;

  /// No description provided for @usageDisplayModeUsed.
  ///
  /// In ja, this message translates to:
  /// **'使用量'**
  String get usageDisplayModeUsed;

  /// Hint announced when activating the Codex usage summary refresh action.
  String get usageRefreshHint;

  String get systemNoticeLabel;

  String get codexSessionStarted;

  String get codexCodeModeFallbackNotice;

  String get optionalMcpWorkerNotice;


















  /// No description provided for @attachedImages.
  ///
  /// In ja, this message translates to:
  /// **'添付画像 ({count})'**
  String attachedImages(int count);







  /// No description provided for @failedToLoadImage.
  ///
  /// In ja, this message translates to:
  /// **'画像の読み込みに失敗しました'**
  String get failedToLoadImage;

  /// No description provided for @generatedImagePromptLabel.
  ///
  /// In ja, this message translates to:
  /// **'プロンプト'**
  String get generatedImagePromptLabel;

  /// No description provided for @generatedImageDetailsLabel.
  ///
  /// In ja, this message translates to:
  /// **'詳細'**
  String get generatedImageDetailsLabel;

  /// No description provided for @generatedImageHideDetailsLabel.
  ///
  /// In ja, this message translates to:
  /// **'詳細を閉じる'**
  String get generatedImageHideDetailsLabel;

  /// No description provided for @generatedImageStatusLabel.
  ///
  /// In ja, this message translates to:
  /// **'ステータス'**
  String get generatedImageStatusLabel;

  /// No description provided for @generatedImageSavedPathLabel.
  ///
  /// In ja, this message translates to:
  /// **'保存先'**
  String get generatedImageSavedPathLabel;

  /// No description provided for @previousImage.
  ///
  /// In ja, this message translates to:
  /// **'前の画像'**
  String get previousImage;

  /// No description provided for @nextImage.
  ///
  /// In ja, this message translates to:
  /// **'次の画像'**
  String get nextImage;

  /// No description provided for @generatedImagePositionLabel.
  ///
  /// In ja, this message translates to:
  /// **'生成画像 {current} / {total}'**
  String generatedImagePositionLabel(int current, int total);
















  /// No description provided for @noRecentSessions.
  ///
  /// In ja, this message translates to:
  /// **'最近のセッションはありません'**
  String get noRecentSessions;

  /// No description provided for @noSessionsMatchFilters.
  ///
  /// In ja, this message translates to:
  /// **'現在のフィルター条件に一致するセッションがありません'**
  String get noSessionsMatchFilters;

  /// No description provided for @adjustFiltersAndSearch.
  ///
  /// In ja, this message translates to:
  /// **'フィルター条件や検索語を変更してください'**
  String get adjustFiltersAndSearch;

  /// No description provided for @tooltipDisplayMode.
  ///
  /// In ja, this message translates to:
  /// **'カードに表示するメッセージを切替'**
  String get tooltipDisplayMode;


  /// No description provided for @tooltipProjectFilter.
  ///
  /// In ja, this message translates to:
  /// **'プロジェクトで絞り込み'**
  String get tooltipProjectFilter;

  /// No description provided for @tooltipNamedOnly.
  ///
  /// In ja, this message translates to:
  /// **'名前を付けたセッションのみ'**
  String get tooltipNamedOnly;

  /// No description provided for @tooltipIndent.
  ///
  /// In ja, this message translates to:
  /// **'インデントを増やす'**
  String get tooltipIndent;

  /// No description provided for @tooltipDedent.
  ///
  /// In ja, this message translates to:
  /// **'インデントを減らす'**
  String get tooltipDedent;

  /// No description provided for @tooltipSlashCommand.
  ///
  /// In ja, this message translates to:
  /// **'コマンド・スキルを入力'**
  String get tooltipSlashCommand;

  /// No description provided for @tooltipMention.
  ///
  /// In ja, this message translates to:
  /// **'ファイル・プラグインをメンション'**
  String get tooltipMention;

  /// No description provided for @tooltipDollarMention.
  ///
  /// In ja, this message translates to:
  /// **'スキル・アプリを入力'**
  String get tooltipDollarMention;


  /// No description provided for @tooltipAttachImage.
  ///
  /// In ja, this message translates to:
  /// **'画像を添付'**
  String get tooltipAttachImage;

  /// No description provided for @tooltipPromptHistory.
  ///
  /// In ja, this message translates to:
  /// **'プロンプト履歴を開く'**
  String get tooltipPromptHistory;

  /// No description provided for @tooltipVoiceInput.
  ///
  /// In ja, this message translates to:
  /// **'音声入力を開始'**
  String get tooltipVoiceInput;

  /// No description provided for @tooltipStopRecording.
  ///
  /// In ja, this message translates to:
  /// **'録音を停止'**
  String get tooltipStopRecording;

  /// No description provided for @tooltipSendMessage.
  ///
  /// In ja, this message translates to:
  /// **'メッセージを送信'**
  String get tooltipSendMessage;

  /// No description provided for @tooltipRemoveImage.
  ///
  /// In ja, this message translates to:
  /// **'画像を削除'**
  String get tooltipRemoveImage;

  /// No description provided for @tooltipClearDiff.
  ///
  /// In ja, this message translates to:
  /// **'Diff選択を解除'**
  String get tooltipClearDiff;


  /// No description provided for @authErrorTitle.
  ///
  /// In ja, this message translates to:
  /// **'Codexの再ログインが必要です'**
  String get authErrorTitle;

  /// No description provided for @authErrorBody.
  ///
  /// In ja, this message translates to:
  /// **'この端末の Codex に再ログインしてください。'**
  String get authErrorBody;

  /// No description provided for @authErrorPrimaryCommandLabel.
  ///
  /// In ja, this message translates to:
  /// **'手順1'**
  String get authErrorPrimaryCommandLabel;

  /// No description provided for @authErrorSecondaryCommandLabel.
  ///
  /// In ja, this message translates to:
  /// **'手順2'**
  String get authErrorSecondaryCommandLabel;

  /// No description provided for @authErrorAlternativeLabel.
  ///
  /// In ja, this message translates to:
  /// **'シェルから実行する場合'**
  String get authErrorAlternativeLabel;






  /// No description provided for @authHelpButton.
  ///
  /// In ja, this message translates to:
  /// **'手順を見る'**
  String get authHelpButton;































  /// No description provided for @googleSearchSelectionAction.
  ///
  /// In ja, this message translates to:
  /// **'Google で検索'**
  String get googleSearchSelectionAction;

















  String get fileChangeApprovalTitle;

  String get allowFileChanges;

  String allowChangesToFile(String path);

  String allowChangesToFiles(int count);

  String additionalFiles(int count);






























}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ja', 'ko', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ja':
      return AppLocalizationsJa();
    case 'ko':
      return AppLocalizationsKo();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
