import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../home/widgets/home_shared_widgets.dart';
import '../services/seed_excel_parser.dart';
import '../services/seeder_service.dart';
import '../widgets/internal_module_layout.dart';
import 'organizational_structure_screen.dart';
import 'personnel_template_service.dart';

const Color _kPrimary = Color(0xFFC28942);
const Color _kNavy = Color(0xFF173B5E);
const Color _kInk = Color(0xFF17212B);
const Color _kMuted = Color(0xFF64748B);
const Color _kBorder = Color(0xFFDCE5EC);
const String _kFont = 'Arial';

class PersonnelImportScreen extends StatefulWidget {
  final String userId;
  final String empresaId;

  const PersonnelImportScreen({
    super.key,
    required this.userId,
    required this.empresaId,
  });

  @override
  State<PersonnelImportScreen> createState() => _PersonnelImportScreenState();
}

class _PersonnelImportScreenState extends State<PersonnelImportScreen> {
  SeedWorkbook? _workbook;
  String? _fileName;
  String _empresaNombre = '';
  bool _loadingCompany = true;
  bool _reading = false;
  bool _importing = false;
  bool _downloading = false;
  bool _crearUsuarios = true;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    _loadCompany();
  }

  Future<void> _loadCompany() async {
    try {
      await _ensureAuth();
      final doc = await FirebaseFirestore.instance
          .collection('TBL_EMPRESAS')
          .doc(widget.empresaId)
          .get();
      final data = doc.data();
      final name =
          (data?['nombre'] ??
                  data?['nombreEmpresa'] ??
                  data?['razonSocial'] ??
                  widget.empresaId)
              .toString()
              .trim();
      if (!mounted) {
        return;
      }
      setState(() => _empresaNombre = name.isEmpty ? widget.empresaId : name);
    } catch (_) {
      if (mounted) setState(() => _empresaNombre = widget.empresaId);
    } finally {
      if (mounted) setState(() => _loadingCompany = false);
    }
  }

  Future<void> _ensureAuth() async {
    if (FirebaseAuth.instance.currentUser == null) {
      throw StateError(
        'La sesión venció. Inicia sesión nuevamente para continuar.',
      );
    }
  }

  Future<void> _downloadTemplate() async {
    setState(() => _downloading = true);
    try {
      await _ensureAuth();
      final export = await PersonnelTemplateService().buildForCompany(
        empresaId: widget.empresaId,
        empresaNombre: _empresaNombre,
      );
      await FileSaver.instance.saveFile(
        name: 'plantilla_personal_talento_humano',
        bytes: export.bytes,
        fileExtension: 'xlsx',
        mimeType: MimeType.microsoftExcel,
      );
      if (!mounted) return;
      _message(
        'Plantilla actualizada: ${export.areas} áreas, ${export.cargos} cargos, '
        '${export.centrosCostos} centros y ${export.apps} apps.',
      );
    } catch (e) {
      if (mounted) {
        _message('No fue posible descargar la plantilla: $e', error: true);
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _pickExcel() async {
    setState(() {
      _reading = true;
      _completed = false;
    });
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['xlsx', 'xlsm', 'xls'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      final Uint8List? bytes = file.bytes;
      if (bytes == null) {
        throw StateError('El navegador no entregó el contenido del archivo.');
      }
      final workbook = await SeedExcelParser().parseBytes(bytes);
      if (workbook.personal.isEmpty) {
        throw const FormatException(
          'No se encontraron personas válidas en la hoja PERSONAL.',
        );
      }
      if (!mounted) return;
      setState(() {
        _fileName = file.name;
        _workbook = workbook;
      });
    } catch (e) {
      if (mounted) _message('No se pudo leer el Excel: $e', error: true);
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  Future<void> _import() async {
    final workbook = _workbook;
    if (workbook == null || _empresaNombre.isEmpty) return;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confirmar carga de personal'),
        content: Text(
          'Se procesarán ${workbook.personal.length} persona(s) para '
          '$_empresaNombre. Si una cédula ya existe, sus datos se actualizarán; '
          'no se borrarán personas ni historiales.',
          style: const TextStyle(fontFamily: _kFont, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Seguir revisando'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Confirmar carga'),
          ),
        ],
      ),
    );
    if (accepted != true) return;

    setState(() => _importing = true);
    try {
      await _ensureAuth();
      await SeederService().importWorkbook(
        wb: workbook,
        empresaId: widget.empresaId,
        empresaNombre: _empresaNombre,
        crearUsuarios: _crearUsuarios,
      );
      if (!mounted) return;
      setState(() => _completed = true);
      _message(
        '${workbook.personal.length} persona(s) procesadas correctamente.',
      );
    } catch (e) {
      if (mounted) _message('La carga no pudo completarse: $e', error: true);
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  void _message(String text, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text, style: const TextStyle(fontFamily: _kFont)),
        backgroundColor: error
            ? const Color(0xFFB42318)
            : const Color(0xFF176B45),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final desktop = MediaQuery.sizeOf(context).width >= 900;
    return InternalModuleLayout(
      userId: widget.userId,
      empresaId: widget.empresaId,
      title: 'Cargar personal',
      subtitle: 'Importación guiada desde Excel para la empresa activa',
      accentColor: _kPrimary,
      headerActions: [
        if (desktop) ...[
          CompanyLogoAvatar(empresaId: widget.empresaId, radius: 17),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: CompanyNameWidget(
              empresaId: widget.empresaId,
              style: const TextStyle(
                color: _kNavy,
                fontFamily: _kFont,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ),
        ] else
          CompanyLogoAvatar(
            empresaId: widget.empresaId,
            radius: 15,
            backgroundColor: Colors.white,
            foregroundColor: _kNavy,
          ),
      ],
      child: SingleChildScrollView(
        child: InternalModuleViewport(
          maxWidth: 1180,
          padding: EdgeInsets.fromLTRB(
            desktop ? 28 : 16,
            20,
            desktop ? 28 : 16,
            32,
          ),
          child: desktop ? _desktopBody() : _mobileBody(),
        ),
      ),
    );
  }

  Widget _desktopBody() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 270, child: _stepsPanel()),
        const SizedBox(width: 22),
        Expanded(child: _mainPanel()),
      ],
    );
  }

  Widget _mobileBody() {
    return Column(
      children: [
        _stepsPanel(compact: true),
        const SizedBox(height: 16),
        _mainPanel(),
      ],
    );
  }

  Widget _stepsPanel({bool compact = false}) {
    final active = _completed ? 4 : (_workbook == null ? 2 : 3);
    return _Panel(
      padding: EdgeInsets.all(compact ? 16 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Así funciona',
            style: TextStyle(
              fontFamily: _kFont,
              fontWeight: FontWeight.w900,
              fontSize: 17,
              color: _kInk,
            ),
          ),
          const SizedBox(height: 16),
          _StepItem(
            number: 1,
            title: 'Descarga la plantilla',
            done: true,
            active: active == 1,
          ),
          _StepItem(
            number: 2,
            title: 'Selecciona el Excel',
            done: active > 2,
            active: active == 2,
          ),
          _StepItem(
            number: 3,
            title: 'Revisa el resumen',
            done: active > 3,
            active: active == 3,
          ),
          _StepItem(
            number: 4,
            title: 'Confirma la carga',
            done: _completed,
            active: active == 4,
            last: true,
          ),
          if (!compact) ...[
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F7FB),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                _loadingCompany
                    ? 'Identificando empresa activa…'
                    : 'La carga quedará únicamente en:\n$_empresaNombre',
                style: const TextStyle(
                  fontFamily: _kFont,
                  color: _kNavy,
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _mainPanel() {
    final wb = _workbook;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Panel(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 650;
              final text = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Importa sin cambiar de empresa',
                    style: TextStyle(
                      fontFamily: _kFont,
                      fontWeight: FontWeight.w900,
                      fontSize: 21,
                      color: _kInk,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'La plantilla se genera con las áreas, cargos, centros de costos y apps de la empresa activa. Antes de guardar verás exactamente qué encontró el sistema.',
                    style: TextStyle(
                      fontFamily: _kFont,
                      color: _kMuted,
                      height: 1.4,
                      fontSize: 13,
                    ),
                  ),
                  if (_fileName != null) ...[
                    const SizedBox(height: 12),
                    _FilePill(name: _fileName!),
                  ],
                ],
              );
              final actions = Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.end,
                children: [
                  OutlinedButton.icon(
                    onPressed: _downloading ? null : _downloadTemplate,
                    icon: _downloading
                        ? const _SmallLoader()
                        : const Icon(Icons.download_rounded),
                    label: const Text('Descargar plantilla actualizada'),
                  ),
                  FilledButton.icon(
                    onPressed: _reading ? null : _pickExcel,
                    icon: _reading
                        ? const _SmallLoader(light: true)
                        : const Icon(Icons.upload_file_rounded),
                    label: Text(
                      wb == null ? 'Seleccionar Excel' : 'Cambiar Excel',
                    ),
                    style: FilledButton.styleFrom(backgroundColor: _kNavy),
                  ),
                ],
              );
              if (narrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [text, const SizedBox(height: 18), actions],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: text),
                  const SizedBox(width: 20),
                  actions,
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 18),
        if (wb == null)
          _emptyState()
        else ...[
          _summary(wb),
          const SizedBox(height: 18),
          _preview(wb),
          const SizedBox(height: 18),
          _importOptions(wb),
        ],
      ],
    );
  }

  Widget _emptyState() {
    return _Panel(
      child: Column(
        children: [
          Container(
            width: 66,
            height: 66,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF4FB),
              borderRadius: BorderRadius.circular(22),
            ),
            child: const Icon(
              Icons.table_view_rounded,
              size: 32,
              color: _kNavy,
            ),
          ),
          const SizedBox(height: 15),
          const Text(
            'Aquí aparecerá la revisión del archivo',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: _kFont,
              fontWeight: FontWeight.w900,
              fontSize: 17,
              color: _kInk,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'No se guardará nada hasta que selecciones el Excel y confirmes la carga.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: _kFont,
              color: _kMuted,
              height: 1.4,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _summary(SeedWorkbook wb) {
    final counts = [
      (
        'Personas',
        wb.personal.length,
        Icons.people_alt_rounded,
        const Color(0xFF2563EB),
      ),
      (
        'Áreas',
        wb.areas.length,
        Icons.apartment_rounded,
        const Color(0xFF0F766E),
      ),
      (
        'Cargos',
        wb.cargos.length,
        Icons.badge_rounded,
        const Color(0xFF7C3AED),
      ),
      (
        'Centros',
        wb.centrosCostos.length,
        Icons.account_balance_rounded,
        const Color(0xFFEA580C),
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Resumen encontrado',
          style: TextStyle(
            fontFamily: _kFont,
            fontWeight: FontWeight.w900,
            fontSize: 17,
            color: _kInk,
          ),
        ),
        const SizedBox(height: 11),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth < 650
                ? (constraints.maxWidth - 10) / 2
                : (constraints.maxWidth - 30) / 4;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final item in counts)
                  SizedBox(
                    width: width,
                    child: _CountCard(
                      label: item.$1,
                      count: item.$2,
                      icon: item.$3,
                      color: item.$4,
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _preview(SeedWorkbook wb) {
    final rows = wb.personal.take(6).toList();
    return _Panel(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Vista previa de personal',
                    style: TextStyle(
                      fontFamily: _kFont,
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                      color: _kInk,
                    ),
                  ),
                ),
                Text(
                  'Primeras ${rows.length} de ${wb.personal.length}',
                  style: const TextStyle(
                    fontFamily: _kFont,
                    color: _kMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: _kBorder),
          for (var i = 0; i < rows.length; i++) ...[
            _PersonPreview(row: rows[i]),
            if (i < rows.length - 1)
              const Divider(height: 1, indent: 68, color: _kBorder),
          ],
        ],
      ),
    );
  }

  Widget _importOptions(SeedWorkbook wb) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _crearUsuarios,
            onChanged: _importing
                ? null
                : (value) => setState(() => _crearUsuarios = value),
            title: const Text(
              'Crear acceso para colaboradores nuevos',
              style: TextStyle(
                fontFamily: _kFont,
                fontWeight: FontWeight.w800,
                color: _kInk,
              ),
            ),
            subtitle: const Text(
              'Déjalo activo si estas personas también deben ingresar a la plataforma.',
              style: TextStyle(
                fontFamily: _kFont,
                color: _kMuted,
                fontSize: 12,
              ),
            ),
            activeThumbColor: _kPrimary,
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: _importing || _loadingCompany ? null : _import,
            icon: _importing
                ? const _SmallLoader(light: true)
                : Icon(
                    _completed
                        ? Icons.check_circle_rounded
                        : Icons.cloud_upload_rounded,
                  ),
            label: Text(
              _completed
                  ? 'Carga completada'
                  : 'Cargar ${wb.personal.length} persona(s)',
            ),
            style: FilledButton.styleFrom(
              backgroundColor: _completed ? const Color(0xFF176B45) : _kPrimary,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
          if (_completed) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (_) => OrganizationalStructureScreen(
                    userId: widget.userId,
                    empresaId: widget.empresaId,
                  ),
                ),
              ),
              icon: const Icon(Icons.groups_2_rounded),
              label: const Text('Ver personal cargado'),
            ),
          ],
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const _Panel({required this.child, this.padding = const EdgeInsets.all(20)});
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: padding,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: _kBorder),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0A0F172A),
          blurRadius: 12,
          offset: Offset(0, 4),
        ),
      ],
    ),
    child: child,
  );
}

class _StepItem extends StatelessWidget {
  final int number;
  final String title;
  final bool done;
  final bool active;
  final bool last;
  const _StepItem({
    required this.number,
    required this.title,
    required this.done,
    required this.active,
    this.last = false,
  });
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: done
                  ? const Color(0xFF176B45)
                  : (active ? _kPrimary : const Color(0xFFF1F5F9)),
            ),
            child: Center(
              child: done
                  ? const Icon(
                      Icons.check_rounded,
                      size: 17,
                      color: Colors.white,
                    )
                  : Text(
                      '$number',
                      style: TextStyle(
                        fontFamily: _kFont,
                        fontWeight: FontWeight.w900,
                        color: active ? Colors.white : _kMuted,
                      ),
                    ),
            ),
          ),
          if (!last)
            Container(
              width: 2,
              height: 30,
              color: done ? const Color(0xFF9CD8BA) : _kBorder,
            ),
        ],
      ),
      const SizedBox(width: 11),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            title,
            style: TextStyle(
              fontFamily: _kFont,
              fontSize: 13,
              fontWeight: active || done ? FontWeight.w800 : FontWeight.w600,
              color: active ? _kInk : _kMuted,
            ),
          ),
        ),
      ),
    ],
  );
}

class _CountCard extends StatelessWidget {
  final String label;
  final int count;
  final IconData icon;
  final Color color;
  const _CountCard({
    required this.label,
    required this.count,
    required this.icon,
    required this.color,
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(15),
      border: Border.all(color: _kBorder),
    ),
    child: Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: color.withValues(alpha: .1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 20, color: color),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$count',
                style: const TextStyle(
                  fontFamily: _kFont,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: _kInk,
                ),
              ),
              Text(
                label,
                style: const TextStyle(
                  fontFamily: _kFont,
                  fontSize: 11,
                  color: _kMuted,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _FilePill extends StatelessWidget {
  final String name;
  const _FilePill({required this.name});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
    decoration: BoxDecoration(
      color: const Color(0xFFE9F8F0),
      borderRadius: BorderRadius.circular(11),
      border: Border.all(color: const Color(0xFFB9E2CD)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.check_circle_rounded,
          size: 16,
          color: Color(0xFF176B45),
        ),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            name,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: _kFont,
              color: Color(0xFF176B45),
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ),
      ],
    ),
  );
}

class _PersonPreview extends StatelessWidget {
  final Map<String, dynamic> row;
  const _PersonPreview({required this.row});
  String _text(String key) => (row[key] ?? '').toString().trim();
  @override
  Widget build(BuildContext context) {
    final fullName = _text('nombreCompleto').isNotEmpty
        ? _text('nombreCompleto')
        : '${_text('nombres')} ${_text('apellidos')}'.trim();
    final detail = [
      _text('cargo'),
      _text('area'),
    ].where((value) => value.isNotEmpty).join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: const Color(0xFFEAF4FB),
            foregroundColor: _kNavy,
            child: Text(
              fullName.isEmpty ? '?' : fullName.substring(0, 1).toUpperCase(),
              style: const TextStyle(
                fontFamily: _kFont,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fullName.isEmpty ? 'Sin nombre' : fullName,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: _kFont,
                    fontWeight: FontWeight.w800,
                    color: _kInk,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  detail.isEmpty ? 'Sin cargo o área' : detail,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: _kFont,
                    color: _kMuted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _text('cedula'),
            style: const TextStyle(
              fontFamily: _kFont,
              color: _kMuted,
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _SmallLoader extends StatelessWidget {
  final bool light;
  const _SmallLoader({this.light = false});
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 16,
    height: 16,
    child: CircularProgressIndicator(
      strokeWidth: 2,
      color: light ? Colors.white : _kNavy,
    ),
  );
}
