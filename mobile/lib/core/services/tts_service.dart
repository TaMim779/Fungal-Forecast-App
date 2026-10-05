import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Voice-first helper: reads localized explanations aloud for low-literacy users.
class TtsService extends ChangeNotifier {
  TtsService({FlutterTts? tts}) : _tts = tts ?? FlutterTts() {
    _tts.setCompletionHandler(() {
      _speaking = false;
      notifyListeners();
    });
    _tts.setErrorHandler((_) {
      _speaking = false;
      notifyListeners();
    });
  }

  final FlutterTts _tts;
  bool _speaking = false;
  bool get speaking => _speaking;

  static const _locales = {'en': 'en-US', 'bn': 'bn-BD', 'hi': 'hi-IN'};

  Future<void> speak(String text, String lang) async {
    if (text.trim().isEmpty) return;
    try {
      await _tts.stop();
      await _tts.setLanguage(_locales[lang] ?? 'en-US');
      await _tts.setSpeechRate(0.45);
      _speaking = true;
      notifyListeners();
      await _tts.speak(text);
    } catch (e) {
      debugPrint('TTS unavailable: $e');
      _speaking = false;
      notifyListeners();
    }
  }

  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
    _speaking = false;
    notifyListeners();
  }
}
