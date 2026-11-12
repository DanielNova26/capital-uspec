import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';
import 'package:share_plus/share_plus.dart';

import 'mantenimiento_service.dart';

String nuevoIdMantenimiento() {
  final random = Random.secure();
  return List.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

class ArchivosOrdenEditor extends StatefulWidget {
  const ArchivosOrdenEditor({
    super.key,
    required this.clase,
    required this.pendientes,
    required this.vistaWeb,
    this.guardados = const [],
    this.retirados,
    this.onChanged,
  });

  final ClaseArchivoOrden clase;
  final List<ArchivoPendienteOrden> pendientes;
  final List<ArchivoOrden> guardados;
  final Set<String>? retirados;
  final bool vistaWeb;
  final VoidCallback? onChanged;

  @override
  State<ArchivosOrdenEditor> createState() => _ArchivosOrdenEditorState();
}

class _ArchivosOrdenEditorState extends State<ArchivosOrdenEditor> {
  bool _ocupado = false;
  String? _error;

  Future<void> _elegir({required bool camara}) async {
    if (_ocupado) return;
    setState(() {
      _ocupado = true;
      _error = null;
    });
    try {
      final XFile? archivo;
      if (camara) {
        archivo = await ImagePicker().pickImage(
          source: ImageSource.camera,
          maxWidth: 1800,
          imageQuality: 80,
        );
      } else {
        final elegido = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: [
            'jpg',
            'jpeg',
            'png',
            if (!widget.clase.soloFotos) 'pdf',
          ],
        );
        archivo = elegido?.xFiles.single;
      }
      if (!mounted || archivo == null) return;
      if (await archivo.length() > 5 * 1024 * 1024) {
        throw StateError('Cada archivo puede pesar hasta 5 MB.');
      }
      final bytes = await archivo.readAsBytes();
      final mime = lookupMimeType('', headerBytes: bytes);
      if (mime != 'image/jpeg' &&
          mime != 'image/png' &&
          (widget.clase.soloFotos || mime != 'application/pdf')) {
        throw StateError(
          widget.clase.soloFotos ? 'Usa JPG o PNG.' : 'Usa PDF, JPG o PNG.',
        );
      }
      if (!mounted) return;
      widget.pendientes.add((
        archivo: (
          id: nuevoIdMantenimiento(),
          nombre: String.fromCharCodes(archivo.name.runes.take(75)),
          mime: mime!,
          clase: widget.clase,
        ),
        bytes: bytes,
      ));
      widget.onChanged?.call();
    } catch (error) {
      if (mounted) {
        _error = error is StateError
            ? error.message
            : 'No se pudo abrir el archivo.';
      }
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final guardados = widget.guardados.where(
      (a) =>
          a.clase == widget.clase &&
          !(widget.retirados?.contains(a.id) ?? false),
    );
    final pendientes = widget.pendientes.where(
      (a) => a.archivo.clase == widget.clase,
    );
    final llenos = guardados.length + pendientes.length >= 6;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.clase.label, style: Theme.of(context).textTheme.titleSmall),
        for (final a in guardados)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(a.nombre),
            trailing: IconButton(
              tooltip: 'Quitar archivo',
              onPressed: () => setState(() {
                widget.retirados?.add(a.id);
                widget.onChanged?.call();
              }),
              icon: const Icon(Icons.close),
            ),
          ),
        for (final a in pendientes)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: a.archivo.mime.startsWith('image/')
                ? Image.memory(
                    a.bytes,
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                    cacheWidth: 144,
                    errorBuilder: (_, _, _) => const Icon(Icons.image_outlined),
                  )
                : const Icon(Icons.picture_as_pdf_outlined),
            title: Text(a.archivo.nombre),
            trailing: IconButton(
              tooltip: 'Quitar archivo',
              onPressed: () => setState(() {
                widget.pendientes.remove(a);
                widget.onChanged?.call();
              }),
              icon: const Icon(Icons.close),
            ),
          ),
        Wrap(
          spacing: 8,
          children: [
            if (widget.clase.soloFotos && !widget.vistaWeb)
              OutlinedButton.icon(
                onPressed: _ocupado || llenos
                    ? null
                    : () => _elegir(camara: true),
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Tomar foto'),
              ),
            OutlinedButton.icon(
              onPressed: _ocupado || llenos
                  ? null
                  : () => _elegir(camara: false),
              icon: const Icon(Icons.attach_file),
              label: Text(
                widget.clase.soloFotos ? 'Elegir foto' : 'Adjuntar archivo',
              ),
            ),
          ],
        ),
        if (_error != null)
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ],
    );
  }
}

class ArchivoOrdenBoton extends StatefulWidget {
  const ArchivoOrdenBoton({
    super.key,
    required this.archivo,
    required this.service,
    required this.ordenId,
  });

  final ArchivoOrden archivo;
  final MantenimientoService service;
  final String ordenId;

  @override
  State<ArchivoOrdenBoton> createState() => _ArchivoOrdenBotonState();
}

class _ArchivoOrdenBotonState extends State<ArchivoOrdenBoton> {
  bool _cargando = false;

  Future<void> _abrir() async {
    setState(() => _cargando = true);
    final a = widget.archivo;
    try {
      final bytes = await widget.service.leerArchivo(widget.ordenId, a.id);
      if (!mounted) return;
      if (a.mime.startsWith('image/')) {
        await showDialog<void>(
          context: context,
          builder: (context) => Dialog(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760, maxHeight: 700),
              child: Column(
                children: [
                  Align(
                    alignment: AlignmentDirectional.topEnd,
                    child: IconButton(
                      tooltip: 'Cerrar foto',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ),
                  Expanded(
                    child: InteractiveViewer(
                      child: Image.memory(bytes, fit: BoxFit.contain),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      } else {
        final box = context.findRenderObject() as RenderBox?;
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile.fromData(bytes, mimeType: a.mime)],
            fileNameOverrides: [a.nombre],
            sharePositionOrigin: box == null
                ? null
                : box.localToGlobal(Offset.zero) & box.size,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo abrir el archivo.')),
        );
      }
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: _cargando ? null : _abrir,
    icon: Icon(
      widget.archivo.mime.startsWith('image/')
          ? Icons.image_outlined
          : Icons.picture_as_pdf_outlined,
    ),
    label: Text(_cargando ? 'Abriendo…' : widget.archivo.nombre),
  );
}
