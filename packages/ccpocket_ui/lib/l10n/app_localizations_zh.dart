// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'Codex';

  @override
  String get cancel => '取消';

  @override
  String get save => '保存';

  @override
  String get delete => '删除';

  @override
  String get remove => '移除';

  @override
  String get renameSession => '重命名会话';

  @override
  String get pin => '置顶会话';

  @override
  String get unpin => '取消置顶会话';

  @override
  String get pinProject => '置顶项目';

  @override
  String get unpinProject => '取消置顶项目';

  @override
  String get sessionNameHint => '会话名称';

  @override
  String get copy => '复制';

  @override
  String get markdownLinkOpenFailed => '无法打开此链接。';

  @override
  String get markdownLinkUnsupported => '不支持此类型的链接。';

  @override
  String get markdownFileUnavailable => '无法在此处预览此文件。';

  @override
  String get copied => '已复制';

  @override
  String get copiedToClipboard => '已复制到剪贴板';

  @override
  String get start => '开始';

  @override
  String get stop => '停止';

  @override
  String get send => '发送';

  @override
  String get settings => '设置';

  @override
  String get gallery => '图库';

  @override
  String get gitUnavailableTip => '未检测到 Git — Git 功能不可用';

  @override
  String get gitUnavailableTitle => 'Git 不可用';

  @override
  String get gitUnavailableHint => '此项目无法使用 Git 功能';

  @override
  String get autoModeFallbackDefaultTip =>
      '当前环境不支持 Auto mode，已切换为 Default mode';

  @override
  String get disconnect => '断开连接';

  @override
  String get next => '下一步';

  @override
  String get done => '完成';

  @override
  String get skip => '跳过';

  @override
  String get edit => '编辑';

  @override
  String get share => '分享';

  @override
  String get all => '全部';

  @override
  String get none => '无';

  @override
  String get stopSession => '停止会话';

  @override
  String get apiKeyHint => '如果没有认证可留空';

  @override
  String get hideSessions => '隐藏左侧面板';

  @override
  String get running => '进行中';

  @override
  String get recentSessions => '最近会话';

  @override
  String get search => '搜索';

  @override
  String get searchSessions => '搜索会话...';

  @override
  String get sessionDisplayModeFirst => '开头';

  @override
  String get sessionDisplayModeLast => '结尾';

  @override
  String get sessionDisplayModeSummary => '摘要';

  @override
  String get allProjects => '全部项目';

  @override
  String get named => '已命名';

  @override
  String get add => '添加';

  @override
  String get readyToStart => '准备就绪';

  @override
  String get readyToStartDescription => '点击 + 按钮创建新会话，并开始用 Codex 编码。';

  @override
  String get newSession => '新建会话';

  @override
  String get update => '更新';

  @override
  String get projectPath => '项目路径';

  @override
  String get permission => '权限';

  @override
  String get approval => '审批';

  @override
  String get advanced => '高级';

  @override
  String get effort => '推理强度';

  @override
  String get model => '模型';

  @override
  String get sandbox => '沙箱';

  @override
  String get reasoning => 'Reasoning';

  @override
  String get planApprovalSummaryCard => '请查看计划，并选择批准或继续规划';

  @override
  String get viewEditPlan => '查看计划';

  @override
  String get keepPlanning => '继续规划';

  @override
  String get keepPlanningHint => '需要改什么...';

  @override
  String get sendFeedbackKeepPlanning => '发送反馈并继续规划';

  @override
  String get acceptAndClear => '批准并清除';

  @override
  String get acceptPlan => '批准计划';

  @override
  String get continuePlanning => '继续规划';

  @override
  String get reject => '拒绝';

  @override
  String get approve => '批准';

  @override
  String get approveOnce => '仅此一次';

  @override
  String get approveForSession => '本次会话期间允许';

  @override
  String get approveAlways => '始终允许';

  @override
  String get approveAlwaysSub => '';

  @override
  String get approveSessionMain => '本次会话允许';

  @override
  String get approveSessionSub => '';

  @override
  String get guardianApprovalTitle => '自动审查已批准';

  @override
  String get guardianApprovalMediumRisk => '中等风险';

  @override
  String get guardianApprovalHighRisk => '高风险';

  @override
  String get guardianApprovalDetails => '详细信息';

  @override
  String get guardianApprovalHideDetails => '收起详细信息';

  @override
  String guardianApprovalAuthorization(String authorization) {
    return '授权级别：$authorization';
  }

  @override
  String get messagePlaceholder => '给 Codex 发消息...';

  @override
  String get codexMessagePlaceholder => '给 Codex 发消息...';

  @override
  String get queuedInputForNextTurn => '已排队到下一轮';

  @override
  String get sessionCardQueuedInput => '已排队';

  @override
  String queuedInputImageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 张图片',
    );
    return '$_temp0';
  }

  @override
  String get reconnecting => '此设备的 Codex 连接暂时中断，正在自动重新连接……';

  @override
  String get pendingActionWillCreateOnReconnect => '此设备的 Codex 重连后将创建';

  @override
  String get pendingActionWillResumeOnReconnect => '此设备的 Codex 重连后将恢复';

  @override
  String get pendingActionStatus => '等待中';

  @override
  String get pendingActionProcessingStatus => '正在恢复';

  @override
  String get pendingActionProcessingStartStatus => '准备中';

  @override
  String get pendingActionProcessingStartDescription => '此设备的 Codex 正在准备会话';

  @override
  String get pendingActionProcessingResumeDescription => '包含大量图片的会话可能需要更长时间';

  @override
  String get pendingActionProcessingStartTitle => '正在创建新会话';

  @override
  String get pendingActionProcessingResumeTitle => '正在加载会话历史';

  @override
  String get tooltipCancelPendingAction => '取消等待中的操作';

  @override
  String get queuedLocally => '已在本地排队';

  @override
  String get offlinePendingNewSessionTitle => '新会话等待中';

  @override
  String get offlinePendingResumeTitle => '恢复等待中';

  @override
  String changedLines(int count) {
    return '$count 行变更';
  }

  @override
  String hunkCount(int count) {
    return '$count 个 hunk';
  }

  @override
  String fileCount(int count) {
    return '$count 个文件';
  }

  @override
  String get tapInterruptHoldStop => '点按：中断，长按：停止';

  @override
  String get rewind => '回退';

  @override
  String get rewindToHere => '回退到这里';

  @override
  String get forkConversation => '分叉对话';

  @override
  String get tapToRetry => '点按重试';

  @override
  String diffSummaryAddedRemoved(int added, int removed) {
    return '+$added/-$removed 行';
  }

  @override
  String lineCountSummary(int count) {
    return '$count 行';
  }

  @override
  String get toolResult => '工具结果';

  @override
  String get answered => '已回答';

  @override
  String agentIsAsking(Object agent) {
    return '$agent 正在提问';
  }

  @override
  String get submitAllAnswers => '提交全部答案';

  @override
  String submitWithCount(int count) {
    return '提交（已选择 $count 项）';
  }

  @override
  String get selectOptionsToSubmit => '请选择要提交的选项';

  @override
  String get typeYourAnswer => '输入你的回答...';

  @override
  String get orTypeCustomAnswer => '或输入自定义回答...';

  @override
  String get otherAnswer => '其他回答...';

  @override
  String get selectAllThatApply => '选择所有适用项';

  @override
  String get failedToDownloadImage => '下载图片失败';

  @override
  String get failedToShareImage => '分享图片失败';

  @override
  String get refresh => '刷新';

  @override
  String get viewChanges => '查看变更';

  @override
  String get promptHistory => '提示词历史';

  @override
  String get working => '进行中...';

  @override
  String get noActiveSessions => '没有活动中的会话';

  @override
  String get codeFontSize => '代码字体大小';

  @override
  String get codeFontFamily => '代码字体';

  @override
  String get imagePasteShortcut => '图片粘贴快捷键';

  @override
  String get theme => '主题';

  @override
  String get language => '语言';

  @override
  String get version => '版本';

  @override
  String get loading => '加载中...';

  @override
  String get loadingSessions => '正在加载会话列表...';

  @override
  String get imageAttached => '图片已附加';

  @override
  String get usageDisplayModeRemaining => '剩余';

  @override
  String get usageDisplayModeUsed => '已用';

  @override
  String get usageRefreshHint => '刷新 Codex 用量';

  @override
  String get systemNoticeLabel => '系统';

  @override
  String get codexSessionStarted => '会话已启动';

  @override
  String get codexCodeModeFallbackNotice => '代码模式不可用，已改用直接工具。';

  @override
  String get optionalMcpWorkerNotice => '网络下可选 MCP 不可用；本地 Codex 仍可继续。';

  @override
  String attachedImages(int count) {
    return '已附加图片 ($count)';
  }

  @override
  String get failedToLoadImage => '加载图片失败';

  @override
  String get generatedImagePromptLabel => '提示词';

  @override
  String get generatedImageDetailsLabel => '详情';

  @override
  String get generatedImageHideDetailsLabel => '收起详情';

  @override
  String get generatedImageStatusLabel => '状态';

  @override
  String get generatedImageSavedPathLabel => '已保存文件';

  @override
  String get previousImage => '上一张图片';

  @override
  String get nextImage => '下一张图片';

  @override
  String generatedImagePositionLabel(int current, int total) {
    return '生成的图片 $current / $total';
  }

  @override
  String get noRecentSessions => '没有最近会话';

  @override
  String get noSessionsMatchFilters => '没有会话匹配当前筛选条件';

  @override
  String get adjustFiltersAndSearch => '试试修改筛选条件或搜索词';

  @override
  String get tooltipDisplayMode => '切换卡片上显示的消息';

  @override
  String get tooltipProjectFilter => '按项目筛选';

  @override
  String get tooltipNamedOnly => '只显示你已命名的会话';

  @override
  String get tooltipIndent => '增加缩进';

  @override
  String get tooltipDedent => '减少缩进';

  @override
  String get tooltipSlashCommand => '输入命令或技能';

  @override
  String get tooltipMention => '提及文件或插件';

  @override
  String get tooltipDollarMention => '输入技能或应用';

  @override
  String get tooltipAttachImage => '附加图片';

  @override
  String get tooltipPromptHistory => '打开提示词历史';

  @override
  String get tooltipVoiceInput => '开始语音输入';

  @override
  String get tooltipStopRecording => '停止录音';

  @override
  String get tooltipSendMessage => '发送消息';

  @override
  String get tooltipRemoveImage => '移除图片';

  @override
  String get tooltipClearDiff => '清除 diff 选择';

  @override
  String get authErrorTitle => '需要重新登录 Codex';

  @override
  String get authErrorBody => '此应用中的 Codex 需要重新登录。';

  @override
  String get authErrorPrimaryCommandLabel => '步骤 1';

  @override
  String get authErrorSecondaryCommandLabel => '步骤 2';

  @override
  String get authErrorAlternativeLabel => 'Shell 方式';

  @override
  String get authHelpButton => '查看步骤';

  @override
  String get googleSearchSelectionAction => '用 Google 搜索';

  @override
  String get fileChangeApprovalTitle => '文件变更审批';

  @override
  String get allowFileChanges => '允许文件变更';

  @override
  String allowChangesToFile(String path) => '允许修改 $path';

  @override
  String allowChangesToFiles(int count) => '允许修改 $count 个文件';

  @override
  String additionalFiles(int count) => '另有 $count 个文件';
}
