import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/utils/speech_errors.dart';

void main() {
  test('plugin error codes become sentences', () {
    expect(speechErrorMessage('error_no_match'), contains('understand'));
    expect(speechErrorMessage('error_speech_timeout'), contains('No speech'));
    expect(speechErrorMessage('error_permission'), contains('permission'));
    expect(speechErrorMessage('error_network'), contains('internet'));
    expect(speechErrorMessage('error_busy'), contains('busy'));
    expect(
      speechErrorMessage('error_language_unavailable'),
      contains('language'),
    );
  });

  test('an unknown or empty error still reads as a sentence', () {
    expect(speechErrorMessage('error_weird'), contains('error_weird'));
    expect(
      speechErrorMessage(''),
      'An error occurred during voice recognition.',
    );
  });
}
