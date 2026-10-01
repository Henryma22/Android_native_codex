// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Korean (`ko`).
class AppLocalizationsKo extends AppLocalizations {
  AppLocalizationsKo([String locale = 'ko']) : super(locale);

  @override
  String get appTitle => 'Codex';

  @override
  String get cancel => '취소';

  @override
  String get save => '저장';

  @override
  String get delete => '삭제';

  @override
  String get remove => '제거';

  @override
  String get renameSession => '세션 이름 변경';

  @override
  String get pin => '세션 고정';

  @override
  String get unpin => '세션 고정 해제';

  @override
  String get pinProject => '프로젝트 고정';

  @override
  String get unpinProject => '프로젝트 고정 해제';

  @override
  String get sessionNameHint => '세션 이름';

  @override
  String get copy => '복사';

  @override
  String get markdownLinkOpenFailed => '링크를 열 수 없습니다.';

  @override
  String get markdownLinkUnsupported => '지원하지 않는 링크 형식입니다.';

  @override
  String get markdownFileUnavailable => '여기서는 이 파일을 미리 볼 수 없습니다.';

  @override
  String get copied => '복사됨';

  @override
  String get copiedToClipboard => '클립보드에 복사됨';

  @override
  String get start => '시작';

  @override
  String get stop => '중지';

  @override
  String get send => '보내기';

  @override
  String get settings => '설정';

  @override
  String get gallery => '갤러리';

  @override
  String get gitUnavailableTip => 'Git을 찾을 수 없음 — Git 기능을 사용할 수 없습니다';

  @override
  String get gitUnavailableTitle => 'Git을 사용할 수 없음';

  @override
  String get gitUnavailableHint => '이 프로젝트에서는 Git 기능을 사용할 수 없습니다';

  @override
  String get autoModeFallbackDefaultTip =>
      '이 환경에서는 Auto mode를 사용할 수 없어 Default mode로 전환했습니다';

  @override
  String get disconnect => '연결 해제';

  @override
  String get next => '다음';

  @override
  String get done => '완료';

  @override
  String get skip => '건너뛰기';

  @override
  String get edit => '편집';

  @override
  String get share => '공유';

  @override
  String get all => '전체';

  @override
  String get none => '없음';

  @override
  String get stopSession => '세션 중지';

  @override
  String get apiKeyHint => '인증이 없으면 비워 두세요';

  @override
  String get hideSessions => '왼쪽 패널 숨기기';

  @override
  String get running => '실행 중';

  @override
  String get recentSessions => '최근 세션';

  @override
  String get search => '검색';

  @override
  String get searchSessions => '세션 검색...';

  @override
  String get sessionDisplayModeFirst => '처음';

  @override
  String get sessionDisplayModeLast => '마지막';

  @override
  String get sessionDisplayModeSummary => '요약';

  @override
  String get allProjects => '모든 프로젝트';

  @override
  String get named => '이름 있음';

  @override
  String get add => '추가';

  @override
  String get readyToStart => '시작할 준비 완료';

  @override
  String get readyToStartDescription => '+ 버튼을 눌러 새 세션을 만들고 Codex로 코딩을 시작하세요.';

  @override
  String get newSession => '새 세션';

  @override
  String get update => '업데이트';

  @override
  String get projectPath => '프로젝트 경로';

  @override
  String get permission => '권한';

  @override
  String get approval => '승인';

  @override
  String get advanced => '고급';

  @override
  String get effort => '추론 강도';

  @override
  String get model => '모델';

  @override
  String get sandbox => '샌드박스';

  @override
  String get reasoning => '추론';

  @override
  String get planApprovalSummaryCard => '계획을 검토해 승인하거나 계속 수정하세요';

  @override
  String get viewEditPlan => '계획 보기';

  @override
  String get keepPlanning => '계획 계속하기';

  @override
  String get keepPlanningHint => '무엇을 변경할까요...';

  @override
  String get sendFeedbackKeepPlanning => '피드백을 보내고 계획 계속하기';

  @override
  String get acceptAndClear => '수락하고 지우기';

  @override
  String get acceptPlan => '계획 수락';

  @override
  String get continuePlanning => '계속 계획';

  @override
  String get reject => '거부';

  @override
  String get approve => '승인';

  @override
  String get approveOnce => '한 번 허용';

  @override
  String get approveForSession => '이 세션에서 허용';

  @override
  String get approveAlways => '영구 허용';

  @override
  String get approveAlwaysSub => '허용';

  @override
  String get approveSessionMain => '이 세션';

  @override
  String get approveSessionSub => '허용';

  @override
  String get guardianApprovalTitle => '자동 리뷰 승인';

  @override
  String get guardianApprovalMediumRisk => '중간 위험';

  @override
  String get guardianApprovalHighRisk => '높은 위험';

  @override
  String get guardianApprovalDetails => '세부 정보';

  @override
  String get guardianApprovalHideDetails => '세부 정보 숨기기';

  @override
  String guardianApprovalAuthorization(String authorization) {
    return '승인 수준: $authorization';
  }

  @override
  String get messagePlaceholder => 'Codex에게 메시지...';

  @override
  String get codexMessagePlaceholder => 'Codex에게 메시지...';

  @override
  String get queuedInputForNextTurn => '다음 턴 대기열에 추가됨';

  @override
  String get sessionCardQueuedInput => '대기 중';

  @override
  String queuedInputImageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '이미지 $count개',
    );
    return '$_temp0';
  }

  @override
  String get reconnecting => '이 기기의 Codex 연결이 일시적으로 끊겼습니다. 자동으로 다시 연결하는 중...';

  @override
  String get pendingActionWillCreateOnReconnect => '이 기기의 Codex가 재연결되면 생성합니다';

  @override
  String get pendingActionWillResumeOnReconnect => '이 기기의 Codex가 재연결되면 재개합니다';

  @override
  String get pendingActionStatus => '대기 중';

  @override
  String get pendingActionProcessingStatus => '복원 중';

  @override
  String get pendingActionProcessingStartStatus => '준비 중';

  @override
  String get pendingActionProcessingStartDescription =>
      '이 기기의 Codex가 세션을 준비하고 있습니다';

  @override
  String get pendingActionProcessingResumeDescription =>
      '이미지가 많은 세션은 시간이 더 걸릴 수 있습니다';

  @override
  String get pendingActionProcessingStartTitle => '새 세션을 만드는 중';

  @override
  String get pendingActionProcessingResumeTitle => '세션 기록을 불러오는 중';

  @override
  String get tooltipCancelPendingAction => '대기 중인 작업 취소';

  @override
  String get queuedLocally => '로컬에서 대기 중';

  @override
  String get offlinePendingNewSessionTitle => '새 세션 대기 중';

  @override
  String get offlinePendingResumeTitle => '재개 대기 중';

  @override
  String changedLines(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '변경된 줄 $count개',
      one: '변경된 줄 $count개',
    );
    return '$_temp0';
  }

  @override
  String hunkCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '변경 블록 $count개',
      one: '변경 블록 $count개',
    );
    return '$_temp0';
  }

  @override
  String fileCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '파일 $count개',
      one: '파일 $count개',
    );
    return '$_temp0';
  }

  @override
  String get tapInterruptHoldStop => '탭: 중단, 길게 누르기: 정지';

  @override
  String get rewind => '되돌리기';

  @override
  String get rewindToHere => '여기로 되돌리기';

  @override
  String get forkConversation => '대화 분기';

  @override
  String get tapToRetry => '탭하여 재시도';

  @override
  String diffSummaryAddedRemoved(int added, int removed) {
    return '+$added/-$removed줄';
  }

  @override
  String lineCountSummary(int count) {
    return '$count줄';
  }

  @override
  String get toolResult => '도구 결과';

  @override
  String get answered => '응답 완료';

  @override
  String agentIsAsking(Object agent) {
    return '$agent 질문 중';
  }

  @override
  String get submitAllAnswers => '모든 답변 제출';

  @override
  String submitWithCount(int count) {
    return '제출($count개 선택)';
  }

  @override
  String get selectOptionsToSubmit => '제출할 옵션 선택';

  @override
  String get typeYourAnswer => '답변을 입력하세요...';

  @override
  String get orTypeCustomAnswer => '또는 직접 답변 입력...';

  @override
  String get otherAnswer => '기타 답변...';

  @override
  String get selectAllThatApply => '해당하는 항목 모두 선택';

  @override
  String get failedToDownloadImage => '이미지 다운로드 실패';

  @override
  String get failedToShareImage => '이미지 공유 실패';

  @override
  String get refresh => '새로고침';

  @override
  String get viewChanges => '변경 사항 보기';

  @override
  String get promptHistory => '프롬프트 기록';

  @override
  String get working => '작업 중...';

  @override
  String get noActiveSessions => '활성 세션 없음';

  @override
  String get codeFontSize => '코드 글꼴 크기';

  @override
  String get codeFontFamily => '코드 글꼴';

  @override
  String get imagePasteShortcut => '이미지 붙여넣기 단축키';

  @override
  String get theme => '테마';

  @override
  String get language => '언어';

  @override
  String get version => '버전';

  @override
  String get loading => '로딩 중...';

  @override
  String get loadingSessions => '세션 목록을 불러오는 중...';

  @override
  String get imageAttached => '이미지 첨부됨';

  @override
  String get usageDisplayModeRemaining => '남은 양';

  @override
  String get usageDisplayModeUsed => '사용량';

  @override
  String get usageRefreshHint => 'Codex 사용량 새로고침';

  @override
  String get systemNoticeLabel => '시스템';

  @override
  String get codexSessionStarted => '세션 시작됨';

  @override
  String get codexCodeModeFallbackNotice =>
      'Code Mode를 사용할 수 없어 직접 도구로 전환했습니다.';

  @override
  String get optionalMcpWorkerNotice =>
      '현재 MCP는 사용할 수 없지만 로컬 Codex는 계속 사용할 수 있습니다.';

  @override
  String attachedImages(int count) {
    return '첨부 이미지 ($count)';
  }

  @override
  String get failedToLoadImage => '이미지 로드 실패';

  @override
  String get generatedImagePromptLabel => '프롬프트';

  @override
  String get generatedImageDetailsLabel => '세부정보';

  @override
  String get generatedImageHideDetailsLabel => '세부정보 닫기';

  @override
  String get generatedImageStatusLabel => '상태';

  @override
  String get generatedImageSavedPathLabel => '저장된 파일';

  @override
  String get previousImage => '이전 이미지';

  @override
  String get nextImage => '다음 이미지';

  @override
  String generatedImagePositionLabel(int current, int total) {
    return '생성된 이미지 $current / $total';
  }

  @override
  String get noRecentSessions => '최근 세션 없음';

  @override
  String get noSessionsMatchFilters => '현재 필터와 일치하는 세션 없음';

  @override
  String get adjustFiltersAndSearch => '필터나 검색어를 변경해 보세요';

  @override
  String get tooltipDisplayMode => '카드에 표시할 메시지 변경';

  @override
  String get tooltipProjectFilter => '프로젝트로 필터';

  @override
  String get tooltipNamedOnly => '이름을 붙인 세션만';

  @override
  String get tooltipIndent => '들여쓰기 증가';

  @override
  String get tooltipDedent => '들여쓰기 감소';

  @override
  String get tooltipSlashCommand => '명령 또는 스킬 삽입';

  @override
  String get tooltipMention => '파일 또는 플러그인 멘션';

  @override
  String get tooltipDollarMention => '스킬 또는 앱 삽입';

  @override
  String get tooltipAttachImage => '이미지 첨부';

  @override
  String get tooltipPromptHistory => '프롬프트 기록 열기';

  @override
  String get tooltipVoiceInput => '음성 입력 시작';

  @override
  String get tooltipStopRecording => '녹음 중지';

  @override
  String get tooltipSendMessage => '메시지 보내기';

  @override
  String get tooltipRemoveImage => '이미지 제거';

  @override
  String get tooltipClearDiff => 'diff 선택 지우기';

  @override
  String get authErrorTitle => 'Codex 로그인이 필요합니다';

  @override
  String get authErrorBody => '이 앱에서 Codex에 다시 로그인해야 합니다.';

  @override
  String get authErrorPrimaryCommandLabel => '1단계';

  @override
  String get authErrorSecondaryCommandLabel => '2단계';

  @override
  String get authErrorAlternativeLabel => '셸 대안';

  @override
  String get authHelpButton => '단계 보기';

  @override
  String get googleSearchSelectionAction => 'Google 검색';

  @override
  String get fileChangeApprovalTitle => '파일 변경 승인';

  @override
  String get allowFileChanges => '파일 변경 허용';

  @override
  String allowChangesToFile(String path) => '$path 변경 허용';

  @override
  String allowChangesToFiles(int count) => '$count개 파일 변경 허용';

  @override
  String additionalFiles(int count) => '외 $count개';
}
