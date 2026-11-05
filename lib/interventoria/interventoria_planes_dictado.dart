import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:speech_to_text/speech_recognition_error.dart';

/// Dictado opcional sobre el mismo borrador que se guarda en el compromiso.
class PlanDictado extends StatefulWidget {
  const PlanDictado({super.key, required this.controller, this.enabled = true});
  final TextEditingController controller;
  final bool enabled;
  @override
  State<PlanDictado> createState() => _PlanDictadoState();
}

class _PlanDictadoState extends State<PlanDictado> {
  final _speech = stt.SpeechToText();
  bool _listening = false, _starting = false;
  String _base = '';
  void _onStatus(String status) {
    if (mounted && _ownsSession) {
      setState(() => _listening = status == 'listening');
    }
  }

  void _onError(SpeechRecognitionError _) {
    if (mounted && _ownsSession) {
      setState(() => _listening = false);
      _message();
    }
  }

  bool get _ownsSession => _speech.statusListener == _onStatus;
  @override
  void didUpdateWidget(covariant PlanDictado oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && _listening && _ownsSession) _speech.stop();
  }

  Future<void> _toggle() async {
    if (_listening && _ownsSession) {
      await _speech.stop();
      return;
    }
    setState(() => _starting = true);
    try {
      if (_speech.isListening) await _speech.cancel();
      final available = await _speech.initialize(
        onStatus: _onStatus,
        onError: _onError,
      );
      if (!mounted || !widget.enabled) return;
      if (!available) {
        _message();
        return;
      }
      // La librería es singleton y initialize solo registra callbacks una vez.
      // Cada compromiso reclama su sesión sin conservar la pantalla anterior.
      _speech.statusListener = _onStatus;
      _speech.errorListener = _onError;
      _base = widget.controller.text.trimRight();
      await _speech.listen(
        localeId: 'es_CO',
        listenOptions: stt.SpeechListenOptions(
          listenMode: stt.ListenMode.dictation,
          partialResults: true,
        ),
        onResult: (result) {
          if (!mounted || !widget.enabled || !_ownsSession) return;
          final words = result.recognizedWords.trim();
          if (words.isEmpty) return;
          final text = _base.isEmpty ? words : '$_base $words';
          final limited = text.length > 12000 ? text.substring(0, 12000) : text;
          widget.controller.value = TextEditingValue(
            text: limited,
            selection: TextSelection.collapsed(offset: limited.length),
          );
        },
      );
    } catch (_) {
      if (mounted) _message();
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  void _message() => ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text(
        'No se pudo iniciar el dictado. Revisa el permiso del micrófono y la disponibilidad de voz en el dispositivo.',
      ),
    ),
  );

  @override
  void dispose() {
    if (_ownsSession) _speech.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: TextButton.icon(
      onPressed: widget.enabled && !_starting ? _toggle : null,
      icon: Icon(_listening ? Icons.stop_circle_outlined : Icons.mic_none),
      label: Text(_listening ? 'Detener dictado' : 'Dictar compromiso'),
    ),
  );
}
