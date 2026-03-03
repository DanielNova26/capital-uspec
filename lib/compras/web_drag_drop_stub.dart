// Stub para plataformas no-web (móvil, desktop).
// Los streams nunca emiten eventos.
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' show Offset;

class DroppedFile {
  final Uint8List bytes;
  final String name;
  DroppedFile(this.bytes, this.name);
}

class WebDragDrop {
  static final WebDragDrop instance = WebDragDrop._();
  WebDragDrop._();

  Stream<bool> get isDragging => Stream<bool>.empty();
  Stream<DroppedFile> get droppedFile => Stream<DroppedFile>.empty();
  Offset get lastDropPosition => Offset.zero;

  void enable() {}
  void disable() {}
}
