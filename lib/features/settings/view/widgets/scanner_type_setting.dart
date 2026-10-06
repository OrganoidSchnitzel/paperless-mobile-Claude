import 'package:flutter/material.dart';
import 'package:paperless_mobile/core/extensions/context_extensions.dart';
import 'package:paperless_mobile/core/store/bloc/global_settings_builder.dart';
import 'package:paperless_mobile/core/store/slices/global_settings.dart';
import 'package:paperless_mobile/features/settings/model/scanner_type.dart';
import 'package:paperless_mobile/features/settings/view/widgets/radio_settings_dialog.dart';
import 'package:paperless_mobile/generated/l10n/app_localizations.dart';

class ScannerTypeSetting extends StatelessWidget {
  const ScannerTypeSetting({super.key});

  @override
  Widget build(BuildContext context) {
    final localStore = context.localStore;
    return GlobalSettingsBuilder(
      builder: (context, settings) => ListTile(
        title: Text(S.of(context)!.scannerType),
        subtitle: Text(_label(context, settings.scannerType)),
        onTap: () async {
          final selectedValue = await showDialog<ScannerType>(
            useRootNavigator: false,
            context: context,
            builder: (context) {
              return RadioSettingsDialog<ScannerType>(
                titleText: S.of(context)!.scannerType,
                options: [
                  for (final type in ScannerType.values)
                    RadioOption(
                      value: type,
                      label: _label(context, type),
                      description: _description(context, type),
                    ),
                ],
                initialValue: settings.scannerType,
              );
            },
          );
          if (selectedValue != null) {
            localStore.updateGlobalSettings(
              (state) => state.copyWith(scannerType: selectedValue),
            );
          }
        },
      ),
    );
  }

  String _label(BuildContext context, ScannerType type) {
    return switch (type) {
      ScannerType.automatic => S.of(context)!.scannerTypeAutomatic,
      ScannerType.edgeDetection => S.of(context)!.scannerTypeEdgeDetection,
    };
  }

  String _description(BuildContext context, ScannerType type) {
    return switch (type) {
      ScannerType.automatic => S.of(context)!.scannerTypeAutomaticDescription,
      ScannerType.edgeDetection =>
        S.of(context)!.scannerTypeEdgeDetectionDescription,
    };
  }
}
