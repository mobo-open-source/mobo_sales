import 'dart:async';

import 'package:flutter/material.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../shared/widgets/mobo/mobo_dialog_buttons.dart';
import '../utils/speech_errors.dart';

/// The part of speech recognition the voice search pop-up needs, so the pop-up
/// can be driven by a fake in tests and by the device's recognizer in the app.
abstract class SpeechEngine {
  /// Prepares recognition. False when the device cannot do it. [onStatus] and
  /// [onError] belong to the caller: a second call replaces the first's.
  Future<bool> initialize({
    required void Function(String status) onStatus,
    required void Function(String error) onError,
  });

  /// Starts a listening session; [onResult] gets every partial and the final
  /// transcript so far.
  Future<void> listen({
    required void Function(String words, bool isFinal) onResult,
  });

  /// Ends the session and discards anything not yet delivered.
  Future<void> cancel();
}

/// The device's recognizer, through the `speech_to_text` plugin.
///
/// The plugin keeps the callbacks of its *first* `initialize` and ignores the
/// ones passed later, so every pop-up after the first would have been left
/// listening to a pop-up that no longer exists. The plugin is therefore given
/// one pair of callbacks for good, and they forward to whichever pop-up is
/// current.
class PluginSpeechEngine implements SpeechEngine {
  PluginSpeechEngine._();

  static final PluginSpeechEngine instance = PluginSpeechEngine._();

  final stt.SpeechToText _speech = stt.SpeechToText();
  void Function(String status)? _onStatus;
  void Function(String error)? _onError;

  @override
  Future<bool> initialize({
    required void Function(String status) onStatus,
    required void Function(String error) onError,
  }) {
    _onStatus = onStatus;
    _onError = onError;
    return _speech.initialize(
      onStatus: (status) => _onStatus?.call(status),
      onError: (error) => _onError?.call(error.errorMsg),
    );
  }

  @override
  Future<void> listen({
    required void Function(String words, bool isFinal) onResult,
  }) {
    return _speech.listen(
      onResult: (result) =>
          onResult(result.recognizedWords, result.finalResult),
      listenOptions: stt.SpeechListenOptions(
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 3),
        partialResults: true,
        cancelOnError: false,
        listenMode: stt.ListenMode.dictation,
      ),
    );
  }

  @override
  Future<void> cancel() async {
    _onStatus = null;
    _onError = null;
    await _speech.cancel();
  }
}

/// Opens the voice search pop-up and returns the words to search for.
///
/// Returns null when the pop-up is cancelled. Words are returned only when the
/// user taps Search: recognition on its own never produces a result, and
/// nothing outside the pop-up hears the words as they come in.
Future<String?> showVoiceSearchDialog(
  BuildContext context, {
  SpeechEngine? engine,
}) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) =>
        VoiceSearchDialog(engine: engine ?? PluginSpeechEngine.instance),
  );
}

class VoiceSearchDialog extends StatefulWidget {
  const VoiceSearchDialog({super.key, required this.engine});

  final SpeechEngine engine;

  @override
  State<VoiceSearchDialog> createState() => _VoiceSearchDialogState();
}

class _VoiceSearchDialogState extends State<VoiceSearchDialog> {
  String _words = '';
  String? _error;
  bool _listening = false;
  bool _starting = true;

  /// Bumped for every listening session, so a late event of an earlier one
  /// (the recognizer reports `done` after it has been stopped) is ignored.
  int _session = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  @override
  void dispose() {
    unawaited(widget.engine.cancel());
    super.dispose();
  }

  Future<void> _start() async {
    final session = ++_session;
    setState(() {
      _words = '';
      _error = null;
      _starting = true;
      _listening = false;
    });

    try {
      // Whatever an earlier session left running ends first.
      await widget.engine.cancel();
      if (!mounted || session != _session) return;
      final ready = await widget.engine.initialize(
        onStatus: (status) => _onStatus(session, status),
        onError: (error) => _onError(session, error),
      );
      if (!mounted || session != _session) return;
      if (!ready) {
        setState(() {
          _starting = false;
          _error =
              'Voice search is not available on this device. Make sure the '
              'Google app (Speech Recognition & Synthesis) is installed and '
              'enabled.';
        });
        return;
      }

      await widget.engine.listen(
        onResult: (words, isFinal) => _onResult(session, words),
      );
      if (!mounted || session != _session) return;
      setState(() {
        _starting = false;
        _listening = true;
      });
    } catch (e) {
      if (!mounted || session != _session) return;
      setState(() {
        _starting = false;
        _listening = false;
        _error = speechErrorMessage(e.toString());
      });
    }
  }

  void _onResult(int session, String words) {
    if (!mounted || session != _session) return;
    setState(() {
      _words = words;
      if (words.isNotEmpty) _error = null;
    });
  }

  void _onStatus(int session, String status) {
    if (!mounted || session != _session) return;
    setState(() {
      switch (status) {
        case 'listening':
          _starting = false;
          _listening = true;
        case 'done':
        case 'notListening':
          _starting = false;
          _listening = false;
      }
    });
  }

  void _onError(int session, String error) {
    if (!mounted || session != _session) return;
    setState(() {
      _starting = false;
      _listening = false;
      // An error after words were heard (the recognizer finding nothing more)
      // is not worth replacing them with.
      if (_words.isEmpty) _error = speechErrorMessage(error);
    });
  }

  void _search() {
    final words = _words.trim();
    if (words.isEmpty) return;
    Navigator.of(context).pop(words);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = theme.colorScheme.primary;
    final muted = isDark ? Colors.grey[400] : Colors.grey[600];
    final heard = _words.trim().isNotEmpty;

    final status = _starting
        ? 'Starting microphone...'
        : _listening
        ? 'Listening...'
        : heard
        ? 'Finished listening'
        : _error != null
        ? 'Nothing heard'
        : 'Ready to listen';

    // Search needs words; with none and no session running, the same button
    // starts another try.
    final canTryAgain = !_starting && !_listening && !heard;

    return AlertDialog(
      backgroundColor: isDark ? Colors.grey[900] : Colors.white,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: isDark ? Colors.grey[800]! : Colors.grey[300]!),
      ),
      title: Text(
        'Voice Search',
        style: TextStyle(
          color: isDark ? Colors.white : Colors.black87,
          fontWeight: FontWeight.w600,
          fontSize: 20,
        ),
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              Center(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: primary.withValues(alpha: 0.1),
                      ),
                    ),
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: primary.withValues(alpha: 0.2),
                      ),
                    ),
                    SizedBox(
                      width: 48,
                      height: 48,
                      child: _listening || _starting
                          ? LoadingAnimationWidget.staggeredDotsWave(
                              color: isDark ? Colors.white : primary,
                              size: 48,
                            )
                          : Icon(
                              heard
                                  ? Icons.check_circle_outline
                                  : Icons.mic_none,
                              color: isDark ? Colors.white : primary,
                              size: 36,
                            ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Semantics(
                liveRegion: true,
                child: Text(
                  status,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: isDark ? Colors.grey[300] : Colors.grey[800],
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey[850] : Colors.grey[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark ? Colors.grey[700]! : Colors.grey[200]!,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Recognized Text:',
                      style: TextStyle(
                        color: muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 48),
                      child: Text(
                        heard
                            ? _words
                            : 'Start speaking clearly into your microphone...'
                                  '\n\nTry saying: "laptop", "phone", "shoes".',
                        style: TextStyle(
                          color: heard
                              ? (isDark ? Colors.white : Colors.black87)
                              : muted,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (_error != null && !heard) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red, fontSize: 13),
                ),
              ],
              if (heard && !_listening && !_starting) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _start,
                    icon: const Icon(Icons.mic, size: 18),
                    label: const Text('Speak again'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
      actions: [
        MoboDialogButtons(
          secondaryLabel: 'Cancel',
          onSecondary: () => Navigator.of(context).pop(),
          primaryLabel: canTryAgain ? 'Try Again' : 'Search',
          onPrimary: canTryAgain ? _start : (heard ? _search : null),
        ),
      ],
    );
  }
}
