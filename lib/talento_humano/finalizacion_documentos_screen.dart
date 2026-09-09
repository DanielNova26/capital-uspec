import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../widgets/internal_module_layout.dart';
import '../widgets/paged_list.dart';
import '../widgets/user_avatar.dart';
import 'disciplinary_service.dart'
    show DisciplinaryPerson, DisciplinaryService;
import 'finalizacion_documentos_service.dart';
import 'plantilla_combinacion.dart';

const _primary = Color(0xFF0F766E);
const _navy = Color(0xFF173B5E);
const _ink = Color(0xFF17212B);
const _muted = Color(0xFF64748B);
const _border = Color(0xFFE2E8F0);
const _surface = Color(0xFFF8FAFC);
const _danger = Color(0xFFB91C1C);
const _warning = Color(0xFFD97706);
const _success = Color(0xFF15803D);
const _font = 'Arial';

/// Documentos de finalización de contrato — vista de Talento Humano.
///
/// Dos trabajos que se hacen en momentos distintos: preparar las plantillas y
/// generar el lote (pestaña "Generar"), y archivar el papel firmado de cada
/// persona para que lo descargue (pestaña "Carpetas").
class FinalizacionDocumentosScreen extends StatefulWidget {
  final String userId;
  final String empresaId;

  const FinalizacionDocumentosScreen({
    super.key,
    required this.userId,
    required this.empresaId,
  });

  @override
  State<FinalizacionDocumentosScreen> createState() =>
      _FinalizacionDocumentosScreenState();
}

class _FinalizacionDocumentosScreenState
    extends State<FinalizacionDocumentosScreen>
    with SingleTickerProviderStateMixin {
  final _service = FinalizacionDocumentosService();
  late final TabController _tabs;
  final _buscador = TextEditingController();

  // Las streams se memorizan en campos: recrearlas en cada build hace que
  // Firestore reviente en web con "INTERNAL ASSERTION FAILED".
  late final Stream<List<CarpetaFinalizacion>> _carpetas;
  late final Stream<Map<String, PlantillaDocumento>> _plantillas;

  late Future<List<DisciplinaryPerson>> _personal;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _carpetas = _service.watchEmpresa(widget.empresaId);
    _plantillas = _service.watchPlantillas(widget.empresaId);
    _personal = _cargarPersonal();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _buscador.dispose();
    super.dispose();
  }

  /// El personal sale del mismo directorio que usa el proceso disciplinario:
  /// activos e inactivos, porque quien se va es justamente quien necesita
  /// estos papeles.
  Future<List<DisciplinaryPerson>> _cargarPersonal() =>
      DisciplinaryService().loadPeople(widget.empresaId);

  @override
  Widget build(BuildContext context) {
    return InternalModuleLayout(
      userId: widget.userId,
      empresaId: widget.empresaId,
      title: 'Documentos de finalización de contrato',
      subtitle: 'Carta laboral, cesantías y orden de exámenes de egreso',
      accentColor: _primary,
      child: Column(
        children: [
          Material(
            color: Colors.white,
            child: TabBar(
              controller: _tabs,
              labelColor: _primary,
              unselectedLabelColor: _muted,
              indicatorColor: _primary,
              tabs: const [
                Tab(
                  icon: Icon(Icons.auto_awesome_motion_rounded),
                  text: 'Generar en lote',
                ),
                Tab(
                  icon: Icon(Icons.folder_shared_outlined),
                  text: 'Carpetas del personal',
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: _border),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [_GenerarTab(
                userId: widget.userId,
                empresaId: widget.empresaId,
                service: _service,
                plantillas: _plantillas,
              ), _carpetasTab()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _carpetasTab() {
    return StreamBuilder<List<CarpetaFinalizacion>>(
      stream: _carpetas,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _ErrorState(
            message: 'No fue posible cargar las carpetas.',
            detail: snapshot.error.toString(),
          );
        }
        final carpetas = {
          for (final carpeta in snapshot.data ?? const <CarpetaFinalizacion>[])
            carpeta.cedula: carpeta,
        };
        return FutureBuilder<List<DisciplinaryPerson>>(
          future: _personal,
          builder: (context, personalSnapshot) {
            if (personalSnapshot.hasError) {
              return _ErrorState(
                message: 'No fue posible cargar el personal.',
                detail: personalSnapshot.error.toString(),
              );
            }
            if (!personalSnapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final termino = _buscador.text.trim().toLowerCase();
            final personas = personalSnapshot.data!.where((persona) {
              if (termino.isEmpty) return true;
              return persona.name.toLowerCase().contains(termino) ||
                  persona.cedula.contains(termino) ||
                  persona.role.toLowerCase().contains(termino);
            }).toList();

            return ColoredBox(
              color: _surface,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 30),
                child: InternalModuleViewport(
                  maxWidth: 1100,
                  padding: EdgeInsets.zero,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _ResumenCarpetas(
                        total: personalSnapshot.data!.length,
                        conCesantias: carpetas.values
                            .where((c) => c.aplicaCesantias)
                            .length,
                        completas: carpetas.values
                            .where((c) => !c.vacia && c.completa)
                            .length,
                        pendientes: carpetas.values
                            .where((c) => !c.vacia && !c.completa)
                            .length,
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _buscador,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          hintText: 'Buscar nombre, cédula o cargo',
                          prefixIcon: const Icon(Icons.search_rounded),
                          filled: true,
                          fillColor: Colors.white,
                          isDense: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: _border),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      if (personas.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(30),
                          child: Text(
                            'No se encontró personal con ese criterio.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: _muted),
                          ),
                        )
                      else
                        PagedListSection(
                          items: personas,
                          etiqueta: 'personas',
                          itemBuilder: (context, persona, _) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _PersonaCard(
                              persona: persona,
                              carpeta: carpetas[persona.cedula],
                              onToggleCesantias: (valor) =>
                                  _marcarCesantias(persona, valor),
                              onSubir: (tipo) => _subir(persona, tipo),
                              onEliminar: (tipo) =>
                                  _eliminar(carpetas[persona.cedula]!, tipo),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _marcarCesantias(DisciplinaryPerson persona, bool valor) async {
    try {
      await _service.marcarCesantias(
        empresaId: widget.empresaId,
        cedula: persona.cedula,
        nombre: persona.name,
        aplica: valor,
        userId: widget.userId,
      );
    } catch (error) {
      _message('No fue posible guardar la marca: $error', error: true);
    }
  }

  Future<void> _subir(DisciplinaryPerson persona, String tipo) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf', 'docx', 'png', 'jpg', 'jpeg'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      final bytes = file.bytes;
      if (bytes == null) {
        throw StateError('El navegador no entregó el contenido del archivo.');
      }
      _message('Subiendo ${file.name}…');
      await _service.subirDocumento(
        empresaId: widget.empresaId,
        cedula: persona.cedula,
        nombre: persona.name,
        tipo: tipo,
        bytes: bytes,
        fileName: file.name,
        userId: widget.userId,
      );
      _message(
        '${DocumentoFinalizacionTipo.label(tipo)} archivada. '
        '${persona.name} ya puede descargarla.',
      );
    } catch (error) {
      _message('No fue posible archivar: $error', error: true);
    }
  }

  Future<void> _eliminar(CarpetaFinalizacion carpeta, String tipo) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Quitar documento'),
        content: Text(
          'Se va a eliminar "${DocumentoFinalizacionTipo.label(tipo)}" de la '
          'carpeta de ${carpeta.nombre}. El archivo se borra y deja de estar '
          'disponible para la persona.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: _danger),
            child: const Text('Quitar'),
          ),
        ],
      ),
    );
    if (confirmado != true) return;
    try {
      await _service.eliminarDocumento(
        carpeta: carpeta,
        tipo: tipo,
        userId: widget.userId,
      );
      _message('Documento eliminado.');
    } catch (error) {
      _message('No fue posible eliminar: $error', error: true);
    }
  }

  void _message(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: error ? _danger : _navy,
      ),
    );
  }
}

/// Pestaña de generación: plantillas guardadas + Excel = .zip.
class _GenerarTab extends StatefulWidget {
  final String userId;
  final String empresaId;
  final FinalizacionDocumentosService service;
  final Stream<Map<String, PlantillaDocumento>> plantillas;

  const _GenerarTab({
    required this.userId,
    required this.empresaId,
    required this.service,
    required this.plantillas,
  });

  @override
  State<_GenerarTab> createState() => _GenerarTabState();
}

class _GenerarTabState extends State<_GenerarTab> {
  String _tipo = DocumentoFinalizacionTipo.cartaLaboral;
  DatosCombinacion? _datos;
  String _nombreExcel = '';
  bool _trabajando = false;
  ResultadoCombinacion? _ultimo;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, PlantillaDocumento>>(
      stream: widget.plantillas,
      builder: (context, snapshot) {
        final plantillas = snapshot.data ?? const <String, PlantillaDocumento>{};
        final plantilla = plantillas[_tipo];
        return ColoredBox(
          color: _surface,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 30),
            child: InternalModuleViewport(
              maxWidth: 900,
              padding: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _Explicacion(),
                  const SizedBox(height: 16),
                  _Paso(
                    numero: 1,
                    titulo: 'Elige el documento',
                    hecho: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final tipo in DocumentoFinalizacionTipo.values)
                          _TipoOption(
                            tipo: tipo,
                            seleccionado: _tipo == tipo,
                            tienePlantilla: plantillas.containsKey(tipo),
                            onTap: _trabajando
                                ? null
                                : () => setState(() => _tipo = tipo),
                          ),
                      ],
                    ),
                  ),
                  _Paso(
                    numero: 2,
                    titulo: 'Plantilla de Word',
                    hecho: plantilla != null,
                    child: _PlantillaBox(
                      plantilla: plantilla,
                      onCargar: _trabajando ? null : _cargarPlantilla,
                    ),
                  ),
                  _Paso(
                    numero: 3,
                    titulo: 'Excel con los datos',
                    hecho: _datos != null,
                    child: _ExcelBox(
                      datos: _datos,
                      nombreArchivo: _nombreExcel,
                      marcadores: plantilla?.marcadores ?? const [],
                      onCargar: _trabajando ? null : _cargarExcel,
                    ),
                  ),
                  _Paso(
                    numero: 4,
                    titulo: 'Generar el .zip',
                    hecho: _ultimo != null,
                    ultimo: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_ultimo != null) ...[
                          _ResultadoBox(resultado: _ultimo!),
                          const SizedBox(height: 12),
                        ],
                        FilledButton.icon(
                          onPressed:
                              _trabajando || plantilla == null || _datos == null
                              ? null
                              : () => _generar(plantilla),
                          icon: _trabajando
                              ? const SizedBox.square(
                                  dimension: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.folder_zip_outlined),
                          label: Text(
                            _datos == null
                                ? 'Falta el Excel'
                                : 'Generar ${_datos!.filas.length} '
                                      'documento(s)',
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: _primary,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _cargarPlantilla() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['docx'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      final bytes = file.bytes;
      if (bytes == null) {
        throw StateError('El navegador no entregó el contenido del archivo.');
      }
      setState(() => _trabajando = true);
      final plantilla = await widget.service.guardarPlantilla(
        empresaId: widget.empresaId,
        tipo: _tipo,
        bytes: bytes,
        fileName: file.name,
        userId: widget.userId,
      );
      _message(
        'Plantilla guardada con ${plantilla.marcadores.length} marcador(es). '
        'No hay que volver a subirla.',
      );
    } catch (error) {
      _message('$error', error: true);
    } finally {
      if (mounted) setState(() => _trabajando = false);
    }
  }

  Future<void> _cargarExcel() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['xlsx'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      final bytes = file.bytes;
      if (bytes == null) {
        throw StateError('El navegador no entregó el contenido del archivo.');
      }
      setState(() => _trabajando = true);
      final datos = leerExcelCombinacion(bytes);
      if (datos.isEmpty) {
        throw StateError(
          'El Excel no tiene filas de datos. La primera fila debe ser los '
          'títulos de las columnas y debajo una fila por persona.',
        );
      }
      setState(() {
        _datos = datos;
        _nombreExcel = file.name;
        _ultimo = null;
      });
      _message('${datos.filas.length} fila(s) leída(s) del Excel.');
    } catch (error) {
      _message('No fue posible leer el Excel: $error', error: true);
    } finally {
      if (mounted) setState(() => _trabajando = false);
    }
  }

  Future<void> _generar(PlantillaDocumento plantilla) async {
    final datos = _datos;
    if (datos == null) return;
    setState(() => _trabajando = true);
    try {
      final bytes = await widget.service.leerPlantilla(plantilla);
      final resultado = combinar(plantilla: bytes, datos: datos);
      if (resultado.documentos.isEmpty) {
        throw StateError('No se pudo generar ningún documento.');
      }
      final zip = empaquetarZip(resultado.documentos);
      await FileSaver.instance.saveFile(
        name:
            '${_tipo}_${widget.empresaId}_'
            '${DateFormat('yyyyMMdd').format(DateTime.now())}',
        bytes: zip,
        fileExtension: 'zip',
        mimeType: MimeType.zip,
      );
      setState(() => _ultimo = resultado);
      _message('${resultado.documentos.length} documento(s) en el .zip.');
    } catch (error) {
      _message('No fue posible generar: $error', error: true);
    } finally {
      if (mounted) setState(() => _trabajando = false);
    }
  }

  void _message(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: error ? _danger : _navy,
      ),
    );
  }
}

class _Explicacion extends StatelessWidget {
  const _Explicacion();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lightbulb_outline_rounded, color: Color(0xFF1D4ED8)),
              SizedBox(width: 9),
              Text(
                'Cómo se arma el lote',
                style: TextStyle(
                  fontFamily: _font,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF1D4ED8),
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          Text(
            'En el Word, escribe donde va cada dato un marcador entre llaves '
            'dobles: {{NOMBRE}}, {{CEDULA}}, {{CARGO}}. En el Excel, la '
            'primera fila son los títulos de las columnas y cada fila de abajo '
            'es una persona. El título de la columna es el que empareja con el '
            'marcador: da igual la tilde y la mayúscula.\n\n'
            'La plantilla se guarda una sola vez. De ahí en adelante, generar '
            'el lote es subir el Excel y nada más.',
            style: TextStyle(
              fontFamily: _font,
              fontSize: 12,
              height: 1.5,
              color: Color(0xFF1E3A8A),
            ),
          ),
        ],
      ),
    );
  }
}

class _Paso extends StatelessWidget {
  final int numero;
  final String titulo;
  final bool hecho;
  final bool ultimo;
  final Widget child;

  const _Paso({
    required this.numero,
    required this.titulo,
    required this.hecho,
    required this.child,
    this.ultimo = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: ultimo ? 0 : 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: hecho ? _primary : _border,
                  shape: BoxShape.circle,
                ),
                child: hecho
                    ? const Icon(Icons.check_rounded,
                        size: 15, color: Colors.white)
                    : Text(
                        '$numero',
                        style: const TextStyle(
                          fontFamily: _font,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          color: _muted,
                        ),
                      ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  titulo,
                  style: const TextStyle(
                    fontFamily: _font,
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                    color: _ink,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

/// Fila seleccionable de tipo de documento. Muestra de una vez si ese tipo ya
/// tiene plantilla, que es lo que decide si el paso 2 está resuelto.
class _TipoOption extends StatelessWidget {
  final String tipo;
  final bool seleccionado;
  final bool tienePlantilla;
  final VoidCallback? onTap;

  const _TipoOption({
    required this.tipo,
    required this.seleccionado,
    required this.tienePlantilla,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: seleccionado ? const Color(0xFFF0FDFA) : Colors.white,
            border: Border.all(color: seleccionado ? _primary : _border),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                seleccionado
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 19,
                color: seleccionado ? _primary : _muted,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      DocumentoFinalizacionTipo.label(tipo),
                      style: const TextStyle(
                        fontFamily: _font,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: _ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      DocumentoFinalizacionTipo.description(tipo),
                      style: const TextStyle(
                        fontFamily: _font,
                        fontSize: 10.5,
                        color: _muted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _Chip(
                label: tienePlantilla ? 'Con plantilla' : 'Sin plantilla',
                color: tienePlantilla ? _success : _warning,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlantillaBox extends StatelessWidget {
  final PlantillaDocumento? plantilla;
  final VoidCallback? onCargar;

  const _PlantillaBox({required this.plantilla, required this.onCargar});

  @override
  Widget build(BuildContext context) {
    final actual = plantilla;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (actual == null)
          const Text(
            'Sube el Word con los marcadores. Queda guardado para este tipo '
            'de documento y no hay que volver a subirlo.',
            style: TextStyle(fontFamily: _font, fontSize: 12, color: _muted),
          )
        else ...[
          Row(
            children: [
              const Icon(Icons.description_rounded, color: _success),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      actual.nombre,
                      style: const TextStyle(
                        fontFamily: _font,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    if (actual.subidaAt != null)
                      Text(
                        'Guardada el ${_fecha(actual.subidaAt!)}',
                        style: const TextStyle(
                          fontFamily: _font,
                          fontSize: 11,
                          color: _muted,
                        ),
                      ),
                  ],
                ),
              ),
              if (actual.url.isNotEmpty)
                IconButton(
                  tooltip: 'Abrir plantilla',
                  onPressed: () => launchUrl(
                    Uri.parse(actual.url),
                    mode: LaunchMode.externalApplication,
                  ),
                  icon: const Icon(Icons.open_in_new_rounded),
                ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Marcadores que trae:',
            style: TextStyle(
              fontFamily: _font,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: _muted,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final marcador in actual.marcadores)
                _Chip(label: marcador, color: _primary),
            ],
          ),
        ],
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: onCargar,
          icon: const Icon(Icons.upload_file_rounded, size: 18),
          label: Text(
            actual == null ? 'Subir plantilla .docx' : 'Reemplazar plantilla',
          ),
        ),
      ],
    );
  }
}

class _ExcelBox extends StatelessWidget {
  final DatosCombinacion? datos;
  final String nombreArchivo;
  final List<String> marcadores;
  final VoidCallback? onCargar;

  const _ExcelBox({
    required this.datos,
    required this.nombreArchivo,
    required this.marcadores,
    required this.onCargar,
  });

  @override
  Widget build(BuildContext context) {
    final actual = datos;
    // Se compara antes de generar: es la diferencia entre avisar ahora y que
    // salgan cien documentos con un campo en blanco.
    final columnas = actual == null
        ? <String>{}
        : actual.filas.first.valores.keys.toSet();
    final faltantes = marcadores
        .where((marcador) => !columnas.contains(marcador))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (actual == null)
          const Text(
            'Sube el Excel con una fila por persona. Este sí cambia en cada '
            'lote.',
            style: TextStyle(fontFamily: _font, fontSize: 12, color: _muted),
          )
        else ...[
          Row(
            children: [
              const Icon(Icons.table_chart_rounded, color: _success),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  '$nombreArchivo · ${actual.filas.length} fila(s)',
                  style: const TextStyle(
                    fontFamily: _font,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          if (faltantes.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                border: Border.all(color: const Color(0xFFFDE68A)),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    faltantes.length == 1
                        ? 'Al Excel le falta una columna'
                        : 'Al Excel le faltan ${faltantes.length} columnas',
                    style: const TextStyle(
                      fontFamily: _font,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                      color: _warning,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'La plantilla los pide y el Excel no los trae: van a salir '
                    'impresos tal cual, entre llaves.',
                    style: TextStyle(
                      fontFamily: _font,
                      fontSize: 11,
                      color: _warning,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final marcador in faltantes)
                        _Chip(label: marcador, color: _warning),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: onCargar,
          icon: const Icon(Icons.upload_file_rounded, size: 18),
          label: Text(actual == null ? 'Subir Excel .xlsx' : 'Cambiar Excel'),
        ),
      ],
    );
  }
}

class _ResultadoBox extends StatelessWidget {
  final ResultadoCombinacion resultado;
  const _ResultadoBox({required this.resultado});

  @override
  Widget build(BuildContext context) {
    final hayProblemas =
        resultado.errores.isNotEmpty || resultado.marcadoresSinDato.isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: hayProblemas ? const Color(0xFFFFFBEB) : const Color(0xFFECFDF5),
        border: Border.all(
          color: hayProblemas
              ? const Color(0xFFFDE68A)
              : const Color(0xFFA7F3D0),
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${resultado.documentos.length} documento(s) generado(s)',
            style: TextStyle(
              fontFamily: _font,
              fontWeight: FontWeight.w900,
              color: hayProblemas ? _warning : _success,
            ),
          ),
          if (resultado.marcadoresSinDato.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Sin dato: ${resultado.marcadoresSinDato.join(", ")}',
              style: const TextStyle(
                fontFamily: _font,
                fontSize: 11,
                color: _warning,
              ),
            ),
          ],
          for (final error in resultado.errores) ...[
            const SizedBox(height: 6),
            Text(
              'Fila ${error.numeroFila}: ${error.detalle}',
              style: const TextStyle(
                fontFamily: _font,
                fontSize: 11,
                color: _danger,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ResumenCarpetas extends StatelessWidget {
  final int total;
  final int conCesantias;
  final int completas;
  final int pendientes;

  const _ResumenCarpetas({
    required this.total,
    required this.conCesantias,
    required this.completas,
    required this.pendientes,
  });

  @override
  Widget build(BuildContext context) {
    final datos = [
      ('Personal', total, Icons.groups_rounded, _navy),
      ('Con cesantías', conCesantias, Icons.savings_rounded, _primary),
      ('Completas', completas, Icons.task_alt_rounded, _success),
      ('Incompletas', pendientes, Icons.pending_actions_rounded, _warning),
    ];
    return LayoutBuilder(
      builder: (context, constraints) => GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: constraints.maxWidth < 640 ? 2 : 4,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: constraints.maxWidth < 640 ? 1.9 : 1.7,
        children: [
          for (final (label, valor, icono, color) in datos)
            Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: _border),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Row(
                children: [
                  Container(
                    width: 37,
                    height: 37,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(icono, color: color, size: 19),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$valor',
                          style: TextStyle(
                            fontFamily: _font,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: color,
                          ),
                        ),
                        Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: _font,
                            color: _muted,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _PersonaCard extends StatelessWidget {
  final DisciplinaryPerson persona;
  final CarpetaFinalizacion? carpeta;
  final ValueChanged<bool> onToggleCesantias;
  final ValueChanged<String> onSubir;
  final ValueChanged<String> onEliminar;

  const _PersonaCard({
    required this.persona,
    required this.carpeta,
    required this.onToggleCesantias,
    required this.onSubir,
    required this.onEliminar,
  });

  @override
  Widget build(BuildContext context) {
    final actual = carpeta;
    final aplicaCesantias = actual?.aplicaCesantias ?? false;
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              UserAvatar(
                userId: persona.cedula,
                nameHint: persona.name,
                fotoUrlHint: persona.photoUrl,
                radius: 20,
                backgroundColor: _navy,
                foregroundColor: Colors.white,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      persona.name,
                      style: const TextStyle(
                        fontFamily: _font,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: _ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        'CC ${persona.cedula}',
                        if (persona.role.isNotEmpty) persona.role,
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: _font,
                        fontSize: 10,
                        color: _muted,
                      ),
                    ),
                  ],
                ),
              ),
              if (actual != null && !actual.vacia)
                _Chip(
                  label: actual.completa
                      ? 'Completa'
                      : '${actual.faltantes.length} pendiente(s)',
                  color: actual.completa ? _success : _warning,
                ),
            ],
          ),
          const SizedBox(height: 10),
          // La marca va antes que los documentos: define cuántos se esperan.
          SwitchListTile(
            value: aplicaCesantias,
            onChanged: onToggleCesantias,
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text(
              'Le corresponde certificado de cesantías',
              style: TextStyle(fontFamily: _font, fontSize: 12),
            ),
            subtitle: const Text(
              'Sin esta marca, el portal no le muestra el espacio.',
              style: TextStyle(fontFamily: _font, fontSize: 10, color: _muted),
            ),
          ),
          const Divider(height: 18, color: _border),
          for (final tipo in DocumentoFinalizacionTipo.values)
            if (!DocumentoFinalizacionTipo.isOptional(tipo) || aplicaCesantias)
              _DocumentoRow(
                tipo: tipo,
                documento: actual?[tipo],
                onSubir: () => onSubir(tipo),
                onEliminar: () => onEliminar(tipo),
              ),
        ],
      ),
    );
  }
}

class _DocumentoRow extends StatelessWidget {
  final String tipo;
  final DocumentoFinalizacion? documento;
  final VoidCallback onSubir;
  final VoidCallback onEliminar;

  const _DocumentoRow({
    required this.tipo,
    required this.documento,
    required this.onSubir,
    required this.onEliminar,
  });

  @override
  Widget build(BuildContext context) {
    final actual = documento;
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        children: [
          Icon(
            actual == null
                ? Icons.radio_button_unchecked_rounded
                : Icons.check_circle_rounded,
            size: 17,
            color: actual == null ? _muted : _success,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  DocumentoFinalizacionTipo.label(tipo),
                  style: const TextStyle(
                    fontFamily: _font,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _ink,
                  ),
                ),
                Text(
                  actual == null ? 'Sin cargar' : actual.nombre,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: _font,
                    fontSize: 10,
                    color: actual == null ? _muted : _success,
                  ),
                ),
              ],
            ),
          ),
          if (actual != null) ...[
            IconButton(
              tooltip: 'Abrir',
              visualDensity: VisualDensity.compact,
              onPressed: actual.url.isEmpty
                  ? null
                  : () => launchUrl(
                      Uri.parse(actual.url),
                      mode: LaunchMode.externalApplication,
                    ),
              icon: const Icon(Icons.open_in_new_rounded, size: 17),
            ),
            IconButton(
              tooltip: 'Quitar',
              visualDensity: VisualDensity.compact,
              onPressed: onEliminar,
              icon: const Icon(Icons.delete_outline_rounded, size: 17),
            ),
          ],
          TextButton(
            onPressed: onSubir,
            child: Text(actual == null ? 'Cargar' : 'Reemplazar'),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  const _Chip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: _font,
          fontSize: 9,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final String detail;
  const _ErrorState({required this.message, required this.detail});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 48, color: _danger),
            const SizedBox(height: 12),
            Text(message, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _muted, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

String _fecha(DateTime value) {
  String dos(int n) => n.toString().padLeft(2, '0');
  return '${dos(value.day)}/${dos(value.month)}/${value.year}';
}
