import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

const String _kFont = 'Arial';

/// Abre el dictado sobre [controller] y deja el resultado en él.
///
/// Lo dictado se SUMA a lo que ya estaba escrito (26 sep 2026). Devuelve
/// `true` si la persona usó el texto; `false` si canceló.
Future<bool> dictarEnCampo(
  BuildContext context, {
  required TextEditingController controller,
  String titulo = 'Dictar',
}) async {
  final texto = await showDialog<String>(
    context: context,
    builder: (_) => DictadoDialog(inicial: controller.text, titulo: titulo),
  );
  if (texto == null) return false;
  final limpio = texto.trim();
  controller.value = TextEditingValue(
    text: limpio,
    selection: TextSelection.collapsed(offset: limpio.length),
  );
  return true;
}

/// Botón de micrófono para el `suffixIcon` de un campo de texto.
class DictadoSuffixButton extends StatelessWidget {
  final TextEditingController controller;
  final String titulo;
  final VoidCallback? onDictado;

  const DictadoSuffixButton({
    super.key,
    required this.controller,
    this.titulo = 'Dictar',
    this.onDictado,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: titulo,
      icon: const Icon(Icons.mic_none_rounded),
      onPressed: () async {
        final usado = await dictarEnCampo(
          context,
          controller: controller,
          titulo: titulo,
        );
        if (usado) onDictado?.call();
      },
    );
  }
}

/// Dictado por voz. Lo dictado se SUMA a lo que ya estaba escrito (26 sep
/// 2026): antes lo reemplazaba y se perdía lo que se había tecleado.
///
/// Nació en Visitas; Tareas lo usa al crear (3 oct 2026: "Crear tarea:
/// permitir dictado"). Un solo diálogo para toda la app.
class DictadoDialog extends StatefulWidget {
  final String inicial;
  final String titulo;
  const DictadoDialog({
    super.key,
    required this.inicial,
    this.titulo = 'Dictar observación',
  });
  @override
  State<DictadoDialog> createState() => _DictadoDialogState();
}

class _DictadoDialogState extends State<DictadoDialog>
    with SingleTickerProviderStateMixin {
  final _speech = stt.SpeechToText();

  /// Latido del micrófono mientras escucha (1 oct 2026: "que salga algo de
  /// hable ahora"): sin él no se sabía si ya se podía hablar.
  late final AnimationController _latido = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
    lowerBound: .85,
    upperBound: 1.15,
  );
  late String _texto = widget.inicial;

  /// Lo que había antes de esta tanda de dictado.
  late String _base = widget.inicial.trim();
  bool _disponible = false;
  bool _escuchando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final ok = await _speech.initialize(
      onStatus: (s) {
        if (mounted) _alEscuchar(s == 'listening');
      },
      onError: (e) {
        if (mounted) setState(() => _error = e.errorMsg);
      },
    );
    if (!mounted) return;
    setState(() => _disponible = ok);
    if (ok) _escuchar();
  }

  /// Cambia el estado del micrófono y su latido fuera de `build`.
  void _alEscuchar(bool escuchando) {
    setState(() => _escuchando = escuchando);
    if (escuchando) {
      _latido.repeat(reverse: true);
    } else {
      _latido.stop();
    }
  }

  Future<void> _escuchar() async {
    setState(() {
      _error = null;
      _base = _texto.trim();
    });
    _alEscuchar(true);
    await _speech.listen(
      localeId: 'es_CO',
      listenOptions: stt.SpeechListenOptions(
        listenMode: stt.ListenMode.dictation,
        partialResults: true,
      ),
      onResult: (r) {
        if (!mounted) return;
        final palabras = r.recognizedWords.trim();
        if (palabras.isEmpty) return;
        setState(
          () => _texto = _base.isEmpty
              ? _mayuscula(palabras)
              : '$_base${_base.endsWith('.') ? ' ' : '. '}${_mayuscula(palabras)}',
        );
      },
    );
  }

  String _mayuscula(String t) =>
      t.isEmpty ? t : '${t[0].toUpperCase()}${t.substring(1)}';

  @override
  void dispose() {
    _speech.cancel();
    _latido.dispose();
    super.dispose();
  }

  /// "Hable ahora" mientras el micrófono escucha; si se detuvo, cómo seguir.
  Widget _avisoMicrofono() {
    final color = _escuchando ? const Color(0xFFDC2626) : Colors.black54;
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: _escuchando
              ? const Color(0xFFFEE2E2)
              : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            ScaleTransition(
              scale: _latido,
              child: Icon(
                _escuchando ? Icons.mic : Icons.mic_off,
                color: color,
                size: 28,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _escuchando
                    ? 'Hable ahora…'
                    : 'Micrófono en pausa. Toque «Dictar más» para seguir.',
                style: TextStyle(
                  fontFamily: _kFont,
                  fontSize: _escuchando ? 16 : 12,
                  fontWeight: _escuchando ? FontWeight.w900 : FontWeight.w600,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Row(
      children: [
        Icon(
          _escuchando ? Icons.mic : Icons.mic_off,
          color: _escuchando ? Colors.red : Colors.grey,
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(widget.titulo)),
      ],
    ),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!_disponible && _error == null)
              const Text(
                'Preparando el micrófono…',
                style: TextStyle(fontFamily: _kFont, fontSize: 12),
              ),
            if (_disponible && _error == null) _avisoMicrofono(),
            if (_error != null)
              Text(
                'No se pudo dictar: $_error',
                style: const TextStyle(
                  fontFamily: _kFont,
                  fontSize: 12,
                  color: Colors.red,
                ),
              ),
            const SizedBox(height: 8),
            Text(
              _texto.isEmpty ? '…' : _texto,
              style: const TextStyle(fontFamily: _kFont),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      if (_disponible && !_escuchando)
        TextButton(onPressed: _escuchar, child: const Text('Dictar más')),
      FilledButton(
        onPressed: () async {
          await _speech.stop();
          if (context.mounted) Navigator.pop(context, _texto);
        },
        child: const Text('Usar texto'),
      ),
    ],
  );
}
