import '../../../l10n/app_strings.dart';

/// These names came from older protocol/discovery defaults, not user input.
/// Keep custom room names exactly as supplied by the paired room.
String localizedRoomName(AppStrings strings, String? name) {
  final normalized = name?.trim() ?? '';
  if (const {
    '',
    'Bebek Odası',
    'MiuCam Bebek Odası',
    'Manual IP Server',
  }.contains(normalized)) {
    return strings.ui('babyRoomName');
  }
  return name!;
}
