import 'dart:io';

import 'package:image_picker/image_picker.dart';

/// The photo a previous `pickImage` call lost, or null when there is none.
///
/// Taking a photo puts the camera in front and this app in the background.
/// On Android the system is free to destroy it there to reclaim memory, and
/// on a real device under real memory pressure it regularly does — which is
/// why this is never seen on an emulator. Pressing OK in the camera then
/// relaunches the app from the start, the `pickImage` future that was waiting
/// is gone with the process that created it, and the photo is simply lost.
///
/// Android keeps that result aside for exactly this case. Asking for it when
/// the screen opens again recovers the picture instead of silently dropping
/// it and leaving the user to wonder what they did wrong.
///
/// Returns null on every other platform, where the call is not implemented,
/// and on any failure — a recovery that itself fails must not stop a screen
/// from opening.
Future<XFile?> recoverLostImage(ImagePicker picker) async {
  if (!Platform.isAndroid) return null;
  try {
    final response = await picker.retrieveLostData();
    if (response.isEmpty) return null;
    return response.file;
  } catch (_) {
    return null;
  }
}
