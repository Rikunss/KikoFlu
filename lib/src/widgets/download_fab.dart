import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../services/download_service.dart';
import '../models/download_task.dart';
import '../screens/downloads_screen.dart';

/// 下载任务浮动按钮
/// 始终显示，以提供下载列表入口。
/// 有活跃下载任务时，显示带数字的徽章。
class DownloadFab extends StatelessWidget {
  const DownloadFab({super.key});

  void _navigateToDownloads(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const DownloadsScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<DownloadTask>>(
      stream: DownloadService.instance.tasksStream,
      builder: (context, snapshot) {
        final tasks = snapshot.data ?? [];
        final badgeCount = tasks.where((t) =>
            t.status == DownloadStatus.downloading ||
            t.status == DownloadStatus.pending).length;

        return Badge(
          isLabelVisible: badgeCount > 0,
          label: Text('$badgeCount'),
          child: FloatingActionButton(
            onPressed: () => _navigateToDownloads(context),
            tooltip: S.of(context).downloadTasks,
            child: const Icon(Icons.download),
          ),
        );
      },
    );
  }
}