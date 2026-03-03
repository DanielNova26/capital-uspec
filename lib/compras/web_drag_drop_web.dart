// Implementación web usando dart:html.
// Escucha eventos nativos del navegador (dragenter, dragleave, dragover, drop)
// directamente en document — funciona con Flutter Web CanvasKit.
import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';
import 'dart:js_util' as js_util;
import 'dart:ui' show Offset;

class DroppedFile {
  final Uint8List bytes;
  final String name;
  DroppedFile(this.bytes, this.name);
}

class WebDragDrop {
  static final WebDragDrop instance = WebDragDrop._();

  final _dragCtrl = StreamController<bool>.broadcast();
  final _fileCtrl = StreamController<DroppedFile>.broadcast();

  Stream<bool> get isDragging => _dragCtrl.stream;
  Stream<DroppedFile> get droppedFile => _fileCtrl.stream;

  // Bound handlers almacenados para poder removerlos exactamente.
  late final void Function(html.Event) _boundEnter;
  late final void Function(html.Event) _boundLeave;
  late final void Function(html.Event) _boundOver;
  late final void Function(html.Event) _boundDrop;

  int _enableCount = 0;
  int _enterCount = 0; // Cuenta para dragleave "falsos" entre hijos del DOM.
  double _lastX = 0, _lastY = 0;

  /// Última posición registrada del cursor durante el arrastre (píxeles CSS = lógicos en Flutter).
  Offset get lastDropPosition => Offset(_lastX, _lastY);

  WebDragDrop._() {
    _boundEnter = _onEnter;
    _boundLeave = _onLeave;
    _boundOver = _onOver;
    _boundDrop = _onDrop;
  }

  /// Activa el listener. Admite múltiples llamadas (conteo de referencia).
  void enable() {
    _enableCount++;
    if (_enableCount == 1) {
      _enterCount = 0;
      html.document.addEventListener('dragenter', _boundEnter);
      html.document.addEventListener('dragleave', _boundLeave);
      html.document.addEventListener('dragover', _boundOver);
      html.document.addEventListener('drop', _boundDrop);
    }
  }

  /// Desactiva el listener cuando ya no hay widgets activos.
  void disable() {
    if (_enableCount <= 0) return;
    _enableCount--;
    if (_enableCount == 0) {
      html.document.removeEventListener('dragenter', _boundEnter);
      html.document.removeEventListener('dragleave', _boundLeave);
      html.document.removeEventListener('dragover', _boundOver);
      html.document.removeEventListener('drop', _boundDrop);
      _enterCount = 0;
      _dragCtrl.add(false);
    }
  }

  void _onEnter(html.Event e) {
    _enterCount++;
    if (_enterCount == 1) _dragCtrl.add(true);
  }

  void _onLeave(html.Event e) {
    if (_enterCount > 0) _enterCount--;
    if (_enterCount == 0) _dragCtrl.add(false);
  }

  void _onOver(html.Event e) {
    e.preventDefault();
    // Registrar posición del cursor para el enrutamiento por widget
    _lastX = (js_util.getProperty<dynamic>(e, 'clientX') as num).toDouble();
    _lastY = (js_util.getProperty<dynamic>(e, 'clientY') as num).toDouble();
  }

  void _onDrop(html.Event e) {
    e.preventDefault();
    _enterCount = 0;
    _dragCtrl.add(false);

    // Acceder a dataTransfer sin cast estático (evita error con dart:html DragEvent)
    final dt = js_util.getProperty<dynamic>(e, 'dataTransfer');
    if (dt == null) return;
    final fileList = js_util.getProperty<dynamic>(dt, 'files');
    if (fileList == null) return;
    final length = js_util.getProperty<int>(fileList, 'length');
    if (length == 0) return;

    // Leer TODOS los archivos arrastrados (cada uno con su propio FileReader)
    for (var i = 0; i < length; i++) {
      final file = js_util.callMethod<html.File>(fileList, 'item', [i]);
      final reader = html.FileReader();
      reader.readAsArrayBuffer(file);
      reader.onLoad.first.then((_) {
        // result de readAsArrayBuffer es un ByteBuffer de dart:typed_data
        final result = reader.result;
        Uint8List bytes;
        if (result is ByteBuffer) {
          bytes = result.asUint8List();
        } else if (result is Uint8List) {
          bytes = result;
        } else {
          // Fallback via JS interop
          try {
            bytes = Uint8List.view(js_util.dartify(result) as ByteBuffer);
          } catch (_) {
            return;
          }
        }
        _fileCtrl.add(DroppedFile(bytes, file.name));
      });
    }
  }
}
