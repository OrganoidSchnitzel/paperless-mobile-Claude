import 'dart:async';
import 'dart:typed_data';

import 'package:cached_query_flutter/cached_query_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:paperless_mobile/api/paperless_api.dart';
import 'package:paperless_mobile/core/extensions/context_extensions.dart';
import 'package:paperless_mobile/core/extensions/flutter_extensions.dart';
import 'package:paperless_mobile/core/translation/error_code_localization_mapper.dart';
import 'package:paperless_mobile/core/widgets/form_builder_fields/form_builder_localized_date_picker.dart';
import 'package:paperless_mobile/core/widgets/future_or_builder.dart';
import 'package:paperless_mobile/features/labels/tags/view/widgets/tags_form_field.dart';
import 'package:paperless_mobile/features/labels/view/widgets/single_label_form_field.dart';
import 'package:paperless_mobile/features/logging/data/logger.dart';
import 'package:paperless_mobile/features/sharing/view/widgets/file_thumbnail.dart';
import 'package:paperless_mobile/features/tasks/model/pending_tasks_notifier.dart';
import 'package:paperless_mobile/generated/l10n/app_localizations.dart';
import 'package:paperless_mobile/helpers/message_helpers.dart';
import 'package:paperless_mobile/routing/routes/labels_route.dart';

class DocumentUploadResult {
  final bool success;
  final String? taskId;

  DocumentUploadResult(this.success, this.taskId);
}

enum _UploadStatus {
  /// The document has not been uploaded yet (or the upload failed).
  idle,
  uploading,

  /// The document has been uploaded and is being processed by Paperless.
  processing,
  processed,
  processingFailed,

  /// The document has been uploaded, but its processing status could not be
  /// determined.
  processingUnknown;

  bool get isUploaded =>
      this != _UploadStatus.idle && this != _UploadStatus.uploading;
}

class DocumentUploadPreparationPage extends StatefulWidget {
  final FutureOr<Uint8List> fileBytes;
  final String? title;
  final String? filename;
  final String? fileExtension;
  final bool instantUpload;

  /// If true, the page stays open after the upload and shows whether the
  /// document has been processed by Paperless. Otherwise, the page is closed
  /// as soon as the document has been uploaded.
  final bool trackProcessing;

  const DocumentUploadPreparationPage({
    super.key,
    required this.fileBytes,
    this.title,
    this.filename,
    this.fileExtension,
    this.instantUpload = false,
    this.trackProcessing = false,
  });

  @override
  State<DocumentUploadPreparationPage> createState() =>
      _DocumentUploadPreparationPageState();
}

class _DocumentUploadPreparationPageState
    extends State<DocumentUploadPreparationPage> {
  static const fkFileName = "filename";
  static final fileNameDateFormat = DateFormat("yyyy_MM_ddTHH_mm_ss");

  final GlobalKey<FormBuilderState> _formKey = GlobalKey();
  final _now = DateTime.now();

  Map<String, String> _errors = {};
  late bool _syncTitleAndFilename;

  _UploadStatus _status = _UploadStatus.idle;
  double? _uploadProgress;
  String? _uploadError;
  String? _taskId;
  TasksView? _task;
  PendingTasksNotifier? _tasksNotifier;

  @override
  void initState() {
    super.initState();
    _syncTitleAndFilename = widget.filename == null && widget.title == null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.instantUpload) {
        _onSubmit();
      }
    });
  }

  @override
  void dispose() {
    _tasksNotifier?.removeListener(_onTasksChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<DocumentUploadResult>(
      // Prevent leaving the page while uploading, otherwise the caller cannot
      // know whether the upload succeeded.
      canPop: !_status.isUploaded && _status != _UploadStatus.uploading,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _status.isUploaded) {
          _close();
        }
      },
      child: _buildScaffold(context),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: false,
      resizeToAvoidBottomInset: true,
      floatingActionButton: Visibility(
        visible:
            MediaQuery.of(context).viewInsets.bottom == 0 &&
            _status == _UploadStatus.idle,
        child: FloatingActionButton.extended(
          heroTag: "fab_document_upload",
          onPressed: _onSubmit,
          label: Text(
            _uploadError == null
                ? S.of(context)!.upload
                : S.of(context)!.retry,
          ),
          icon: Icon(_uploadError == null ? Icons.upload : Icons.refresh),
        ),
      ),
      bottomNavigationBar: _buildStatusPanel(context),
      body: FormBuilder(
        key: _formKey,
        enabled: _status == _UploadStatus.idle,
        child: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) => [
            SliverOverlapAbsorber(
              handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
              sliver: SliverAppBar(
                leading: const BackButton(),
                pinned: true,
                expandedHeight: 150,
                flexibleSpace: FlexibleSpaceBar(
                  background: FutureOrBuilder<Uint8List>(
                    future: widget.fileBytes,
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const SizedBox.shrink();
                      }
                      return Stack(
                        alignment: AlignmentGeometry.topCenter,
                        children: [
                          FileThumbnail(
                            bytes: snapshot.data!,
                            fit: BoxFit.fitWidth,
                            width: MediaQuery.sizeOf(context).width,
                          ),
                          Align(
                            alignment: Alignment.bottomCenter,
                            child: Container(
                              height: 72,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.bottomCenter,
                                  end: Alignment.topCenter,
                                  colors: [Colors.black87, Colors.transparent],
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  title: Text(S.of(context)!.prepareDocument),
                  collapseMode: CollapseMode.pin,
                ),
              ),
            ),
          ],
          body: Padding(
            padding: const EdgeInsets.only(top: 16.0),
            child: Builder(
              builder: (context) {
                return CustomScrollView(
                  slivers: [
                    SliverOverlapInjector(
                      handle: NestedScrollView.sliverOverlapAbsorberHandleFor(
                        context,
                      ),
                    ),
                    SliverList.list(
                      children: [
                        // Title
                        FormBuilderTextField(
                          autovalidateMode: AutovalidateMode.always,
                          name: 'title',
                          initialValue:
                              widget.title ??
                              "scan_${fileNameDateFormat.format(_now)}",
                          validator: (value) {
                            if (value?.trim().isEmpty ?? true) {
                              return S.of(context)!.thisFieldIsRequired;
                            }
                            return null;
                          },
                          decoration: InputDecoration(
                            labelText: S.of(context)!.title,
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () {
                                _formKey.currentState?.fields['title']
                                    ?.didChange("");
                                if (_syncTitleAndFilename) {
                                  _formKey.currentState?.fields[fkFileName]
                                      ?.didChange("");
                                }
                              },
                            ),
                            errorText: _errors['title'],
                          ),
                          onChanged: (value) {
                            final String transformedValue = _formatFilename(
                              value ?? '',
                            );
                            if (_syncTitleAndFilename) {
                              _formKey.currentState?.fields[fkFileName]
                                  ?.didChange(transformedValue);
                            }
                          },
                        ),
                        // Filename
                        FormBuilderTextField(
                          autovalidateMode: AutovalidateMode.always,
                          readOnly: _syncTitleAndFilename,
                          enabled: !_syncTitleAndFilename,
                          name: fkFileName,
                          decoration: InputDecoration(
                            labelText: S.of(context)!.fileName,
                            suffixText: widget.fileExtension,
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () => _formKey
                                  .currentState
                                  ?.fields[fkFileName]
                                  ?.didChange(''),
                            ),
                          ),
                          initialValue:
                              widget.filename ??
                              "scan_${fileNameDateFormat.format(_now)}",
                        ),
                        // Synchronize title and filename
                        SwitchListTile(
                          value: _syncTitleAndFilename,
                          onChanged: (value) {
                            setState(() => _syncTitleAndFilename = value);
                            if (_syncTitleAndFilename) {
                              final String transformedValue = _formatFilename(
                                _formKey.currentState?.fields['title']?.value
                                    as String,
                              );
                              if (_syncTitleAndFilename) {
                                _formKey.currentState?.fields[fkFileName]
                                    ?.didChange(transformedValue);
                              }
                            }
                          },
                          title: Text(
                            S.of(context)!.synchronizeTitleAndFilename,
                          ),
                        ),
                        // Created at
                        FormBuilderLocalizedDatePicker(
                          name: 'created',
                          firstDate: DateTime(1000, 1, 1),
                          lastDate: DateTime(9999, 12, 31),
                          labelText: "${S.of(context)!.createdAt} *",
                          allowUnset: true,
                        ),
                        // Correspondent
                        if (context.uiSettings$.canViewCorrespondents)
                          SingleLabelFormField<Correspondent>(
                            query: context.correspondentRepository
                                .getAllQuery(),
                            onAddLabel:
                                context.uiSettings$.canCreateCorrespondents
                                ? (initialName) => CreateLabelRoute(
                                    LabelType.correspondent,
                                    name: initialName,
                                  ).push<Correspondent>(context)
                                : null,
                            addLabelText:
                                context.uiSettings$.canCreateCorrespondents
                                ? S.of(context)!.addCorrespondent
                                : null,
                            labelText: "${S.of(context)!.correspondent} *",
                            name: 'correspondent',
                            prefixIcon: const Icon(Icons.person_outline),
                          ),
                        // Document type
                        if (context.uiSettings$.canViewDocumentTypes)
                          SingleLabelFormField<DocumentType>(
                            onAddLabel:
                                context.uiSettings$.canCreateDocumentTypes
                                ? (initialName) => CreateLabelRoute(
                                    LabelType.documentType,
                                    name: initialName,
                                  ).push<DocumentType>(context)
                                : null,
                            addLabelText:
                                context.uiSettings$.canCreateDocumentTypes
                                ? S.of(context)!.addDocumentType
                                : null,
                            labelText: "${S.of(context)!.documentType} *",
                            name: 'document_type',
                            query: context.documentTypeRepository.getAllQuery(),
                            prefixIcon: const Icon(Icons.description_outlined),
                          ),
                        if (context.uiSettings$.canViewTags)
                          TagsFormField(
                            name: 'tags',
                            allowCreation: true,
                            allowExclude: false,
                          ),
                        Text(
                          "* ${S.of(context)!.uploadInferValuesHint}",
                          style: Theme.of(context).textTheme.bodySmall,
                          textAlign: TextAlign.justify,
                        ).padded(),
                        const SizedBox(height: 300),
                      ].padded(),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  void _onSubmit() async {
    if (_status != _UploadStatus.idle) {
      return;
    }
    if (!(_formKey.currentState?.saveAndValidate() ?? false)) {
      return;
    }
    final formValues = _formKey.currentState!.value;
    final correspondent = formValues['correspondent'] as int?;
    final docType = formValues['document_type'] as int?;
    final tags = formValues['tags'] as TagsQuery?;
    final createdAt = formValues['created'] as FormDateTime?;
    final title = formValues['title'] as String;
    final asn = formValues['asn'] as int?;
    final filename = _padWithExtension(
      formValues[fkFileName] as String,
      widget.fileExtension,
    );

    setState(() {
      _status = _UploadStatus.uploading;
      _uploadProgress = null;
      _uploadError = null;
      _errors = {};
    });
    try {
      final documentRepository = context.documentRepository;
      final mutationState = await documentRepository
          .createDocumentMutation(
            await widget.fileBytes,
            filename: filename,
            title: title,
            documentType: docType,
            correspondent: correspondent,
            tags: tags?.mapOrNull(ids: (value) => value.include) ?? [],
            createdAt: createdAt?.toDateTime(),
            archiveSerialNumber: asn,
            onProgressChanged: _onUploadProgressChanged,
          )
          .mutate();
      // Mutations do not throw, errors are returned as part of the state.
      if (mutationState is MutationError) {
        final error = mutationState as MutationError;
        Error.throwWithStackTrace(error.error, error.stackTrace);
      }

      final taskId = mutationState.data;
      if (!mounted) return;
      if (taskId != null) {
        context.read<PendingTasksNotifier>().listenToTaskChanges(taskId);
      }
      if (!widget.trackProcessing || taskId == null) {
        // For paperless versions older than 1.11.3, the task id is always null,
        // so the processing status cannot be tracked.
        showSnackBar(
          context,
          S.of(context)!.documentSuccessfullyUploadedProcessing,
        );
        context.pop(DocumentUploadResult(true, taskId));
        return;
      }
      setState(() {
        _taskId = taskId;
        _status = _UploadStatus.processing;
      });
      _tasksNotifier = context.read<PendingTasksNotifier>()
        ..addListener(_onTasksChanged);
      _onTasksChanged();
    } on PaperlessApiException catch (error, stackTrace) {
      if (!mounted) return;
      _onUploadFailed(
        translateError(context, error.code),
        details: error.details,
      );
      logger.fe(
        "Document upload failed.",
        className: runtimeType.toString(),
        methodName: "_onSubmit",
        error: error,
        stackTrace: stackTrace,
      );
    } on PaperlessFormValidationException catch (exception) {
      if (!mounted) return;
      setState(() => _errors = exception.validationMessages);
      _onUploadFailed(
        exception.unspecificErrorMessage() ??
            S.of(context)!.couldNotUploadDocument,
        details: exception.validationMessages.entries
            .where((e) => e.key != 'title' && e.key != 'non_field_errors')
            .map((e) => "${e.key}: ${e.value}")
            .join("\n"),
      );
    } catch (error, stackTrace) {
      logger.fe(
        "An unknown error occurred during document upload.",
        className: runtimeType.toString(),
        methodName: "_onSubmit",
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      _onUploadFailed(
        S.of(context)!.couldNotUploadDocument,
        details: error.toString(),
      );
    }
  }

  void _onUploadProgressChanged(double progress) {
    if (!mounted || _status != _UploadStatus.uploading) {
      return;
    }
    // Avoid rebuilding the page for every chunk which is sent.
    final previousPercent = ((_uploadProgress ?? -1) * 100).floor();
    if ((progress * 100).floor() != previousPercent) {
      setState(() => _uploadProgress = progress);
    }
  }

  void _onUploadFailed(String message, {String? details}) {
    setState(() {
      _status = _UploadStatus.idle;
      _uploadProgress = null;
      _uploadError = [
        message,
        if (details != null && details.trim().isNotEmpty) details,
      ].join("\n");
    });
  }

  void _onTasksChanged() {
    final taskId = _taskId;
    final notifier = _tasksNotifier;
    if (!mounted || taskId == null || notifier == null) {
      return;
    }
    final task = notifier.value[taskId];
    if (task != null) {
      setState(() {
        _task = task;
        _status = switch (task.status) {
          StatusEnum.success => _UploadStatus.processed,
          StatusEnum.failure ||
          StatusEnum.revoked => _UploadStatus.processingFailed,
          _ => _UploadStatus.processing,
        };
      });
    } else if (!notifier.isTracking(taskId) &&
        _status == _UploadStatus.processing) {
      // Tracking stopped without a final result, e.g. due to network issues.
      setState(() => _status = _UploadStatus.processingUnknown);
    }
  }

  void _close() {
    context.pop(DocumentUploadResult(true, _taskId));
  }

  Widget? _buildStatusPanel(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final uploadError = _uploadError;
    if (_status == _UploadStatus.idle && uploadError == null) {
      return null;
    }

    final (Widget icon, String title, String? subtitle) = switch (_status) {
      _UploadStatus.idle => (
        Icon(Icons.error_outline, color: colorScheme.error),
        S.of(context)!.documentUploadFailed,
        uploadError,
      ),
      _UploadStatus.uploading => (
        const Icon(Icons.cloud_upload_outlined),
        _uploadProgress == null
            ? S.of(context)!.documentUploadUploading
            : S.of(context)!.documentUploadProgress(
                (_uploadProgress! * 100).round(),
              ),
        null,
      ),
      _UploadStatus.processing => (
        const Icon(Icons.hourglass_top),
        S.of(context)!.documentUploadedWaitingForProcessing,
        S.of(context)!.documentProcessingContinuesInBackground,
      ),
      _UploadStatus.processed => (
        Icon(Icons.check_circle_outline, color: colorScheme.primary),
        S.of(context)!.documentProcessedSuccessfully,
        null,
      ),
      _UploadStatus.processingFailed => (
        Icon(Icons.error_outline, color: colorScheme.error),
        S.of(context)!.documentProcessingFailed,
        _task?.result,
      ),
      _UploadStatus.processingUnknown => (
        const Icon(Icons.cloud_done_outlined),
        S.of(context)!.documentSuccessfullyUploadedProcessing,
        S.of(context)!.documentProcessingContinuesInBackground,
      ),
    };
    final showProgress =
        _status == _UploadStatus.uploading ||
        _status == _UploadStatus.processing;

    return Material(
      color: _status == _UploadStatus.idle
          ? colorScheme.errorContainer
          : colorScheme.surfaceContainerHigh,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showProgress)
              LinearProgressIndicator(
                value: _status == _UploadStatus.uploading
                    ? _uploadProgress
                    : null,
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                children: [
                  icon,
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(title, style: textTheme.titleSmall),
                        if (subtitle != null)
                          Text(
                            subtitle,
                            style: textTheme.bodySmall,
                            maxLines: 5,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  if (_status.isUploaded) ...[
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _close,
                      child: Text(S.of(context)!.done),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _padWithExtension(String source, [String? extension]) {
    final ext = extension ?? '.pdf';
    return source.endsWith(ext) ? source : '$source$ext';
  }

  String _formatFilename(String source) {
    return source.replaceAll(RegExp(r"[\W_]"), "_").toLowerCase();
  }

  // Future<Color> _computeAverageColor() async {
  //   final bitmap = img.decodeImage(await widget.fileBytes);
  //   if (bitmap == null) {
  //     return Colors.black;
  //   }
  //   int redBucket = 0;
  //   int greenBucket = 0;
  //   int blueBucket = 0;
  //   int pixelCount = 0;

  //   for (int y = 0; y < bitmap.height; y++) {
  //     for (int x = 0; x < bitmap.width; x++) {
  //       final c = bitmap.getPixel(x, y);

  //       pixelCount++;
  //       redBucket += c.r.toInt();
  //       greenBucket += c.g.toInt();
  //       blueBucket += c.b.toInt();
  //     }
  //   }

  //   return Color.fromRGBO(
  //     redBucket ~/ pixelCount,
  //     greenBucket ~/ pixelCount,
  //     blueBucket ~/ pixelCount,
  //     1,
  //   );
  // }
}
