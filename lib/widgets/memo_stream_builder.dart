// lib/widgets/memo_stream_builder.dart
//
// `StreamBuilder` que NO recrea la suscripción en cada build.
//
// Crear `.snapshots()` dentro de `build` abre un listener nuevo de Firestore
// cada vez que la pantalla se redibuja: cada tecla, cada filtro, cada tab.
// En web eso termina en "FIRESTORE INTERNAL ASSERTION FAILED", y a partir de
// ahí toda escritura de la sesión falla con el críptico "Dart exception
// thrown from converted Future". Fue lo que les pasó a varios registradores
// al guardar actas el 14 sep 2026.
//
// Aquí la stream se crea una vez y se conserva mientras [memoKey] no cambie.
// Si cambia (otra empresa, otro centro), se crea otra.

import 'package:flutter/widgets.dart';

class MemoStreamBuilder<T> extends StatefulWidget {
  /// Lo que identifica la consulta: empresa, centro, filtros. Cuando cambia,
  /// se vuelve a crear la stream. Usa un `String` o un record con `==`.
  final Object memoKey;
  final Stream<T> Function() create;
  final AsyncWidgetBuilder<T> builder;
  final T? initialData;

  const MemoStreamBuilder({
    super.key,
    required this.memoKey,
    required this.create,
    required this.builder,
    this.initialData,
  });

  @override
  State<MemoStreamBuilder<T>> createState() => _MemoStreamBuilderState<T>();
}

class _MemoStreamBuilderState<T> extends State<MemoStreamBuilder<T>> {
  late Stream<T> _stream = widget.create();
  late Object _memoKey = widget.memoKey;

  @override
  void didUpdateWidget(covariant MemoStreamBuilder<T> old) {
    super.didUpdateWidget(old);
    if (widget.memoKey != _memoKey) {
      _memoKey = widget.memoKey;
      _stream = widget.create();
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<T>(
    stream: _stream,
    initialData: widget.initialData,
    builder: widget.builder,
  );
}
