import 'dart:async';
import 'dart:io';

import 'package:cached_query_flutter/cached_query_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:listen_sharing_intent/listen_sharing_intent.dart';
import 'package:paperless_mobile/constants.dart';
import 'package:paperless_mobile/core/extensions/context_extensions.dart';
import 'package:paperless_mobile/core/repository/document_repository.dart';
import 'package:paperless_mobile/core/service/connectivity_status_service.dart';
import 'package:paperless_mobile/features/document_upload/view/document_upload_preparation_page.dart';
import 'package:paperless_mobile/features/logging/data/logger.dart';
import 'package:paperless_mobile/features/notifications/services/local_notification_service.dart';
import 'package:paperless_mobile/features/sharing/cubit/receive_share_cubit.dart';
import 'package:paperless_mobile/features/sharing/model/auto_upload_queue.dart';
import 'package:paperless_mobile/features/sharing/services/pending_files_auto_uploader.dart';
import 'package:paperless_mobile/features/sharing/view/dialog/discard_shared_file_dialog.dart';
import 'package:paperless_mobile/features/sharing/view/dialog/pending_files_info_dialog.dart';
import 'package:paperless_mobile/features/tasks/model/pending_tasks_notifier.dart';
import 'package:paperless_mobile/generated/l10n/app_localizations.dart';
import 'package:paperless_mobile/helpers/message_helpers.dart';
import 'package:paperless_mobile/routing/routes/changelog_route.dart';
import 'package:paperless_mobile/routing/routes/scanner_route.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

class EventListenerShell extends StatefulWidget {
  final Widget child;
  const EventListenerShell({super.key, required this.child});

  @override
  State<EventListenerShell> createState() => _EventListenerShellState();
}

class _EventListenerShellState extends State<EventListenerShell>
    with WidgetsBindingObserver {
  StreamSubscription? _subscription;
  StreamSubscription? _documentDeletedSubscription;
  StreamSubscription? _connectivitySubscription;
  Timer? _inboxTimer;
  late final PendingTasksNotifier _pendingTasksNotifier;
  late final PendingFilesAutoUploader _autoUploader;

  @override
  void initState() {
    super.initState();
    _subscription = ReceiveSharingIntent.instance.getMediaStream().listen(
      _onReceiveSharedFiles,
    );
    _pendingTasksNotifier = context.read<PendingTasksNotifier>()
      ..addListener(_onTasksChanged);

    final userId = context.loggedInAppUserId!;
    final consumptionNotifier = context.read<ConsumptionChangeNotifier>();
    final documentRepository = context.documentRepository;
    final autoUploadQueue = AutoUploadQueue(userId: userId);
    _autoUploader = PendingFilesAutoUploader(
      getQueuedFiles: autoUploadQueue.getFiles,
      upload: (file) => _uploadFile(documentRepository, file),
      onUploaded: (file) =>
          consumptionNotifier.discardFile(file, userId: userId),
    );
    _connectivitySubscription = context
        .read<ConnectivityStatusService>()
        .connectivityChanges()
        .where((isConnected) => isConnected)
        .listen((_) => _uploadQueuedFiles());
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onStartup());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The connection might have been restored while the app was in the
    // background.
    if (state == AppLifecycleState.resumed) {
      _uploadQueuedFiles();
    }
  }

  static Future<String?> _uploadFile(
    DocumentRepository documentRepository,
    File file,
  ) async {
    final mutationState = await documentRepository
        .createDocumentMutation(
          await file.readAsBytes(),
          filename: p.basename(file.path),
          title: p.basenameWithoutExtension(file.path),
        )
        .mutate();
    if (mutationState is MutationError) {
      final error = mutationState as MutationError;
      Error.throwWithStackTrace(error.error, error.stackTrace);
    }
    return mutationState.data;
  }

  /// Uploads files which were shared while the device was offline, if enabled
  /// and the app is in the foreground.
  Future<void> _uploadQueuedFiles() async {
    if (!context.localStore.state.globalSettings.autoUploadPendingFiles ||
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }
    final isConnected = await context
        .read<ConnectivityStatusService>()
        .isConnectedToInternet();
    if (!isConnected || !mounted) {
      return;
    }
    final result = await _autoUploader.uploadQueuedFiles();
    if (!mounted) return;
    for (final taskId in result.taskIds) {
      _pendingTasksNotifier.listenToTaskChanges(taskId);
    }
    if (result.failed > 0) {
      showSnackBar(
        context,
        S.of(context)!.couldNotUploadPendingFiles(result.failed),
        type: SnackbarType.error,
      );
    } else if (result.uploaded > 0) {
      showSnackBar(
        context,
        S.of(context)!.pendingFilesUploaded(result.uploaded),
      );
    }
  }

  /// Handles files shared while the app was not running, shows the changelog
  /// and processes files which have not been uploaded yet, one after another
  /// to prevent overlapping dialogs and duplicate uploads.
  Future<void> _onStartup() async {
    final initialFiles = await ReceiveSharingIntent.instance.getInitialMedia();
    // Otherwise, the same files would be received again, e.g. after switching
    // accounts.
    await ReceiveSharingIntent.instance.reset();
    if (!mounted) return;
    if (initialFiles.isNotEmpty) {
      // The app was opened to upload these files, don't show anything else.
      await _onReceiveSharedFiles(initialFiles);
      return;
    }
    if (await _shouldShowChangelog && mounted) {
      await ChangelogRoute().push(context);
    }
    if (!mounted) return;
    await _uploadQueuedFiles();
    if (!mounted) return;
    final userId = context.loggedInUser.appUserId;
    final autoUpload =
        context.localStore.state.globalSettings.autoUploadPendingFiles;
    final notifier = context.read<ConsumptionChangeNotifier>();
    await notifier.isInitialized;
    final autoUploadQueue = AutoUploadQueue(userId: userId);
    final pendingFiles = [
      for (final file in notifier.pendingFiles)
        // Queued files are uploaded automatically once the device is online.
        if (!autoUpload || !await autoUploadQueue.contains(file)) file,
    ];
    if (pendingFiles.isEmpty || !mounted) {
      return;
    }

    final shouldProcess =
        await showDialog<bool>(
          useRootNavigator: false,
          context: context,
          builder: (context) =>
              PendingFilesInfoDialog(pendingFiles: pendingFiles),
        ) ??
        false;
    if (shouldProcess && mounted) {
      await consumeLocalFiles(context, files: pendingFiles, userId: userId);
    }
  }

  Future<bool> get _shouldShowChangelog async {
    try {
      final sp = await SharedPreferences.getInstance();
      final currentBuild = packageInfo.buildNumber;
      final existingVersions = sp.getStringList('changelogSeenForBuilds') ?? [];
      if (existingVersions.contains(currentBuild)) {
        return false;
      } else {
        existingVersions.add(currentBuild);
        await sp.setStringList('changelogSeenForBuilds', existingVersions);
        return true;
      }
    } catch (e) {
      return false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pendingTasksNotifier.removeListener(_onTasksChanged);
    _connectivitySubscription?.cancel();
    _subscription?.cancel();
    _documentDeletedSubscription?.cancel();
    _inboxTimer?.cancel();
    super.dispose();
  }

  void _onTasksChanged() {
    final taskNotifier = context.read<PendingTasksNotifier>();
    for (var task in taskNotifier.value.values) {
      context.read<LocalNotificationService>().notifyTaskChanged(
        task,
        userId: context.loggedInAppUserId!,
      );
    }
  }

  Future<void> _onReceiveSharedFiles(List<SharedMediaFile> sharedFiles) async {
    final files = sharedFiles
        .where((file) => file.path.isNotEmpty)
        .map((file) => File(file.path))
        .toList();
    if (files.isEmpty) {
      return;
    }
    final userId = context.loggedInAppUserId!;
    logger.fi(
      'Received shared files: \n\t${files.map((e) => e.path).join(',\n\t')}',
      className: runtimeType.toString(),
      methodName: '_onReceiveSharedFiles',
    );
    final notifier = context.read<ConsumptionChangeNotifier>();
    final addedLocalFiles = await notifier.addFiles(
      files: files,
      userId: userId,
    );
    if (!mounted) return;
    await consumeLocalFiles(
      context,
      files: addedLocalFiles,
      userId: userId,
      exitAppAfterConsumed: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

Future<void> consumeLocalFile(
  BuildContext context, {
  required File file,
  required String userId,
  bool exitAppAfterConsumed = false,
}) async {
  final shouldDirectlyUpload =
      context.localStore.state.globalSettings.skipDocumentPreprarationOnUpload;
  final consumptionNotifier = context.read<ConsumptionChangeNotifier>();
  final filename = p.basename(file.path);
  final autoUpload =
      context.localStore.state.globalSettings.autoUploadPendingFiles;
  final hasInternetConnection = await context
      .read<ConnectivityStatusService>()
      .isConnectedToInternet();
  if (!hasInternetConnection) {
    if (autoUpload) {
      await AutoUploadQueue(userId: userId).add(file);
    }
    if (context.mounted) {
      showSnackBar(
        context,
        autoUpload
            ? S.of(context)!.fileWillBeUploadedWhenOnline(filename)
            : "Could not consume $filename", //TODO: INTL
        details: S.of(context)!.youreOffline,
      );
    }
    return;
  }

  final bytes = file.readAsBytes();
  // if () {
  //   try {
  //     final taskId = await documentsApi.create(
  //       await bytes,
  //       filename: filename,
  //       title: p.basenameWithoutExtension(file.path),
  //     );

  //     consumptionNotifier.discardFile(file, userId: userId);
  //     taskNotifier.listenToTaskChanges(taskId);
  //   } catch (error) {
  //     if (!context.mounted) return;
  //     await Fluttertoast.showToast(msg: S.of(context)!.couldNotUploadDocument);
  //     return;
  //   } finally {
  //     if (exitAppAfterConsumed) {
  //       SystemNavigator.pop();
  //     }
  //   }
  if (!context.mounted) return;
  final result = await DocumentUploadRoute(
    $extra: bytes,
    filename: p.basenameWithoutExtension(file.path),
    title: p.basenameWithoutExtension(file.path),
    fileExtension: p.extension(file.path),
    instantUpload: shouldDirectlyUpload,
    // Show whether the document has been processed by Paperless before
    // returning to the app the file was shared from.
    trackProcessing: true,
  ).push<DocumentUploadResult?>(context);

  if (result?.success ?? false) {
    await consumptionNotifier.discardFile(file, userId: userId);

    // if (result.taskId != null) {
    //   taskNotifier.listenToTaskChanges(result.taskId!);
    // }
    if (exitAppAfterConsumed) {
      SystemNavigator.pop();
    }
  } else {
    if (!context.mounted) return;
    final shouldDiscard =
        await showDialog<bool>(
          useRootNavigator: false,
          context: context,
          builder: (context) => DiscardSharedFileDialog(bytes: bytes),
        ) ??
        false;
    if (shouldDiscard && context.mounted) {
      await context.read<ConsumptionChangeNotifier>().discardFile(
        file,
        userId: userId,
      );
    }
  }
}

Future<void> consumeLocalFiles(
  BuildContext context, {
  required List<File> files,
  required String userId,
  bool exitAppAfterConsumed = false,
}) async {
  for (int i = 0; i < files.length; i++) {
    final file = files[i];
    await consumeLocalFile(
      context,
      file: file,
      userId: userId,
      exitAppAfterConsumed: exitAppAfterConsumed && (i == files.length - 1),
    );
  }
}
