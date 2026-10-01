import 'package:flutter/material.dart';

import 'core/application/batch_text_change_service.dart';
import 'core/domain/backend.dart';
import 'core/domain/workspace.dart';

class BatchTextChangePage extends StatefulWidget {
  const BatchTextChangePage({
    required this.backend,
    required this.workspace,
    super.key,
  });

  final Backend backend;
  final WorkspaceRef workspace;

  @override
  State<BatchTextChangePage> createState() => _BatchTextChangePageState();
}

class _BatchTextChangePageState extends State<BatchTextChangePage> {
  final _service = BatchTextChangeService();
  final _searchController = TextEditingController();
  final _replacementController = TextEditingController();
  WorkspaceHandle? _workspace;
  BatchScanResult? _scan;
  BatchCommitResult? _commit;
  BatchRestoreResult? _restore;
  String? _error;
  bool _busy = false;

  String _text(String zh, String en) =>
      Localizations.localeOf(context).languageCode == 'zh' ? zh : en;

  @override
  void dispose() {
    _searchController.dispose();
    _replacementController.dispose();
    super.dispose();
  }

  Future<void> _scanMatches() async {
    setState(() {
      _busy = true;
      _error = null;
      _scan = null;
      _commit = null;
      _restore = null;
    });
    try {
      final workspace = _workspace ??= await widget.backend.openWorkspace(
        widget.workspace,
      );
      final scan = await _service.scan(
        backend: widget.backend,
        workspace: workspace,
        search: _searchController.text,
        replacement: _replacementController.text,
      );
      if (!mounted) return;
      setState(() {
        _scan = scan;
        _busy = false;
      });
    } catch (error) {
      _showError(_errorMessage(error));
    }
  }

  Future<void> _commitMatches() async {
    final scan = _scan;
    if (scan == null || scan.previews.isEmpty) return;
    final approved = await _confirm(
      title: _text('批准批量写入？', 'Approve batch write?'),
      message: _text(
        '逐个写入 ${scan.previews.length} 个匹配文件？每个文件都会单独进行版本检查并创建备份；发生冲突时可能只完成部分文件。',
        'Write ${scan.previews.length} matching file(s) one at a time? '
            'Each file gets its own version check and backup. A conflict can '
            'produce a partial result.',
      ),
      confirmLabel: _text('批准批量写入', 'Approve batch write'),
    );
    if (!approved || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
      _restore = null;
    });
    try {
      final workspace = _workspace;
      if (workspace == null) {
        throw const BackendException('Workspace is not open.');
      }
      final commit = await _service.commit(backend: widget.backend, scan: scan);
      if (!mounted) return;
      setState(() {
        _commit = commit;
        _busy = false;
      });
    } catch (error) {
      _showError(_errorMessage(error));
    }
  }

  Future<void> _restoreMatches() async {
    final commit = _commit;
    if (commit == null || commit.successfulCount == 0) return;
    final approved = await _confirm(
      title: _text('恢复批量备份？', 'Restore batch backups?'),
      message: _text(
        '恢复 ${commit.successfulCount} 个已成功写入文件的备份？每次恢复前都会再次检查当前版本。',
        'Restore the backups for ${commit.successfulCount} successfully '
            'written file(s)? Current versions are checked again before each '
            'restore.',
      ),
      confirmLabel: _text('恢复备份', 'Restore backups'),
    );
    if (!approved || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final restore = await _service.restore(
        backend: widget.backend,
        commit: commit,
      );
      if (!mounted) return;
      setState(() {
        _restore = restore;
        _busy = false;
      });
    } catch (error) {
      _showError(_errorMessage(error));
    }
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(_text('取消', 'Cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(confirmLabel),
              ),
            ],
          ),
        ) ??
        false;
  }

  String _errorMessage(Object error) {
    return _localizeBatchIssue(
      error is BackendException ? error.message : '$error',
    );
  }

  String _localizeBatchIssue(String message) {
    if (Localizations.localeOf(context).languageCode != 'zh') return message;
    switch (message) {
      case 'Search text must not be empty.':
        return '搜索文本不能为空。';
      case 'Batch scan limits must be positive.':
        return '批量扫描限制必须为正数。';
      case 'symbolic links are not eligible for batch writes':
        return '符号链接不能用于批量写入。';
    }
    final depth = RegExp(r'^maximum scan depth (\d+) reached$')
        .firstMatch(message);
    if (depth != null) return '已达到扫描深度上限：${depth.group(1)}。';
    final files = RegExp(r'^maximum file limit (\d+) reached$')
        .firstMatch(message);
    if (files != null) return '已达到文件数量上限：${files.group(1)}。';
    final bytes = RegExp(r'^file exceeds the (\d+)-byte text limit$')
        .firstMatch(message);
    if (bytes != null) return '文件超过文本大小上限：${bytes.group(1)} 字节。';
    return message;
  }

  void _showError(String message) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scan = _scan;
    final commit = _commit;
    final restore = _restore;
    final canWrite =
        widget.backend.descriptor.capabilities.managedChangesSupported;
    return Scaffold(
      appBar: AppBar(title: Text(_text('批量替换', 'Batch replace'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          Text(
            _text('批量文本替换', 'Batch text replacement'),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(widget.workspace.displayPath),
          const SizedBox(height: 8),
          Text(
            _text(
              '工作区会在文件数量和大小限制内递归扫描。每个匹配文件都有独立的预览、备份、乐观写入和恢复结果。',
              'The workspace is scanned recursively with bounded file and size '
                  'limits. Every matched file gets a separate preview, backup, '
                  'optimistic write, and restore result.',
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('batch-search'),
            controller: _searchController,
            enabled: !_busy,
            decoration: InputDecoration(
              labelText: _text('搜索文本', 'Search text'),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('batch-replacement'),
            controller: _replacementController,
            enabled: !_busy,
            decoration: InputDecoration(
              labelText: _text('替换文本', 'Replacement text'),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const Key('batch-scan'),
            onPressed: _busy ? null : _scanMatches,
            icon: const Icon(Icons.search),
            label: Text(_text('扫描匹配项', 'Scan matches')),
          ),
          if (_busy) ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
          ],
          if (_error != null) ...[
            const SizedBox(height: 16),
            _BatchMessageCard(
              message: '${_text('后端异常', 'BackendException')}: $_error',
            ),
          ],
          if (scan != null) ...[
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _text('扫描摘要', 'Scan summary'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _text(
                        '已扫描文件：${scan.scannedFiles}',
                        'Scanned files: ${scan.scannedFiles}',
                      ),
                    ),
                    Text(
                      _text(
                        '匹配文件：${scan.previews.length}',
                        'Matched files: ${scan.previews.length}',
                      ),
                    ),
                    Text(
                      _text(
                        '问题：${scan.issues.length}',
                        'Issues: ${scan.issues.length}',
                      ),
                    ),
                    if (scan.issues.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      for (final issue in scan.issues)
                        Text(
                          _text(
                            '已跳过 ${issue.path}：${_localizeBatchIssue(issue.message)}',
                            'Skipped ${issue.path}: ${issue.message}',
                          ),
                        ),
                    ],
                    if (scan.previews.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      if (canWrite)
                        FilledButton.icon(
                          key: const Key('batch-commit'),
                          onPressed: _busy ? null : _commitMatches,
                          icon: const Icon(Icons.save_outlined),
                          label: Text(
                            _text('使用备份提交匹配项', 'Commit matches with backups'),
                          ),
                        )
                      else
                        Text(
                          _text(
                            '当前后端只提供预览，暂不支持批量写入。',
                            'This backend exposes previews only; batch writes '
                                'are not available.',
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
            for (final preview in scan.previews)
              Card(
                child: ExpansionTile(
                  // Keep the result list compact on phones. A batch can
                  // contain many previews, and expanding every diff at once
                  // pushes the actionable commit/result controls far below
                  // the fold. Each preview remains available on demand.
                  initiallyExpanded: false,
                  title: Text(preview.relativePath),
                  subtitle: Text(
                    '${preview.changeSet.before.version} · '
                    '${preview.changeSet.before.sizeBytes} bytes',
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: SelectableText(
                        preview.changeSet.diff,
                        style: const TextStyle(fontFamily: 'monospace'),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          if (commit != null) ...[
            const SizedBox(height: 16),
            _BatchResultCard(
              title: _text('批量写入结果', 'Batch write results'),
              successfulCount: commit.successfulCount,
              failedCount: commit.failedCount,
              children: [
                for (final file in commit.files)
                  ListTile(
                    leading: Icon(
                      file.succeeded ? Icons.check_circle : Icons.error,
                    ),
                    title: Text(file.preview.relativePath),
                    subtitle: Text(
                      file.succeeded
                          ? _text(
                              '备份：${file.receipt!.backupId}',
                              'backup: ${file.receipt!.backupId}',
                            )
                          : _text(
                              '失败：${_localizeBatchIssue(file.error ?? '')}',
                              'failed: ${file.error}',
                            ),
                    ),
                  ),
                if (commit.successfulCount > 0)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: FilledButton.icon(
                      key: const Key('batch-restore'),
                      onPressed: _busy ? null : _restoreMatches,
                      icon: const Icon(Icons.restore),
                      label: Text(_text('恢复成功文件', 'Restore successful files')),
                    ),
                  ),
              ],
            ),
          ],
          if (restore != null) ...[
            const SizedBox(height: 16),
            _BatchResultCard(
              title: _text('批量恢复结果', 'Batch restore results'),
              successfulCount: restore.successfulCount,
              failedCount: restore.failedCount,
              children: [
                for (final file in restore.files)
                  ListTile(
                    leading: Icon(
                      file.succeeded ? Icons.check_circle : Icons.error,
                    ),
                    title: Text(file.commit.preview.relativePath),
                    subtitle: Text(
                      file.succeeded
                          ? _text(
                              '已恢复：${file.receipt!.backupId}',
                              'restored: ${file.receipt!.backupId}',
                            )
                          : _text(
                              '失败：${_localizeBatchIssue(file.error ?? '')}',
                              'failed: ${file.error}',
                            ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _BatchResultCard extends StatelessWidget {
  const _BatchResultCard({
    required this.title,
    required this.successfulCount,
    required this.failedCount,
    required this.children,
  });

  final String title;
  final int successfulCount;
  final int failedCount;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                Localizations.localeOf(context).languageCode == 'zh'
                    ? '成功：$successfulCount · 失败：$failedCount'
                    : 'Succeeded: $successfulCount · Failed: $failedCount',
              ),
            ),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _BatchMessageCard extends StatelessWidget {
  const _BatchMessageCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(padding: const EdgeInsets.all(16), child: Text(message)),
    );
  }
}
