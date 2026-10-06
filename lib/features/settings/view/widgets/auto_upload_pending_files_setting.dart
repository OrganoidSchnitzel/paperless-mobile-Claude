import 'package:flutter/material.dart';
import 'package:paperless_mobile/core/extensions/context_extensions.dart';
import 'package:paperless_mobile/core/store/bloc/global_settings_builder.dart';
import 'package:paperless_mobile/core/store/slices/global_settings.dart';
import 'package:paperless_mobile/generated/l10n/app_localizations.dart';

class AutoUploadPendingFilesSetting extends StatelessWidget {
  const AutoUploadPendingFilesSetting({super.key});

  @override
  Widget build(BuildContext context) {
    final localStore = context.localStore;
    return GlobalSettingsBuilder(
      builder: (context, settings) => SwitchListTile(
        title: Text(S.of(context)!.autoUploadPendingFiles),
        subtitle: Text(S.of(context)!.autoUploadPendingFilesDescription),
        value: settings.autoUploadPendingFiles,
        onChanged: (value) {
          localStore.updateGlobalSettings(
            (state) => state.copyWith(autoUploadPendingFiles: value),
          );
        },
      ),
    );
  }
}
