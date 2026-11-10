/// Keeping a changed profile photo from being served out of the image cache.
///
/// `/web/image` answers the same URL for the same user whatever the photo is,
/// so once an avatar has been fetched the cached copy is shown for good — a
/// tester uploaded a new photo and kept seeing the old one. Odoo's own web
/// client avoids this by hanging the record's write date off the URL. The app
/// has no write date to hand for every account row, so it uses the moment the
/// change was heard, which serves the same purpose: a URL that differs from
/// the one already cached.
library;

class AvatarCache {
  AvatarCache._();

  static int _epoch = 0;

  /// Changes every time a profile is saved anywhere in the app.
  static int get epoch => _epoch;

  /// Call when a profile may have a new photo.
  static void invalidate() => _epoch++;

  /// [url] with the current [epoch] attached.
  static String versioned(String url) =>
      '$url${url.contains('?') ? '&' : '?'}unique=$_epoch';

  /// A cache key that stops two databases on one server sharing an avatar,
  /// and changes with [epoch] so a saved photo is fetched again.
  static String keyFor({
    required String serverUrl,
    required String database,
    required Object userId,
  }) => '${serverUrl}_${database}_${userId}_avatar_$_epoch';
}
