/// What to tell the user about a speech recognition error.
///
/// The `speech_to_text` plugin reports an error as a code such as
/// `error_no_match`; the raw code means nothing to the person holding the
/// phone.
String speechErrorMessage(String raw) {
  final code = raw.toLowerCase();
  if (code.contains('no_match')) {
    return 'Could not understand that. Please try again.';
  }
  if (code.contains('speech_timeout')) {
    return 'No speech heard. Tap the microphone and speak again.';
  }
  if (code.contains('permission')) {
    return 'Microphone permission is needed for voice search.';
  }
  if (code.contains('network')) {
    return 'Voice search needs an internet connection. Please check it and '
        'try again.';
  }
  if (code.contains('busy')) {
    return 'The speech service is busy. Please try again in a moment.';
  }
  if (code.contains('language')) {
    return 'The speech language is not available on this device.';
  }
  return raw.isNotEmpty
      ? 'Voice search failed ($raw). Please try again.'
      : 'An error occurred during voice recognition.';
}
