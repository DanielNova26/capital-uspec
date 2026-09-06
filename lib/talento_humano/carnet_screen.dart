// lib/talento_humano/carnet_screen.dart
//
// Carnets: diseño de la empresa a la izquierda, personal a la derecha.
//
// Las dos cosas están en la misma pantalla porque son la misma tarea: nadie
// configura colores "en abstracto", los elige mirando el carnet de alguien. Un
// panel de ajustes aparte obligaría a ir y volver para ver el efecto.
//
// Web y móvil comparten datos, permisos y PDF, pero no composición: en
// escritorio los dos paneles van lado a lado, y en el teléfono el diseño se
// pliega en una tarjeta desplegable para que la lista de personal ocupe la
// pantalla, que es lo que se usa en operación.

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../core/guarded_module_page.dart';
import '../widgets/internal_module_layout.dart';
import '../widgets/paged_list.dart';
import '../widgets/user_avatar.dart';
import 'carnet_marca.dart';
import 'carnet_pdf.dart';
import 'carnet_preview.dart';
import 'carnet_service.dart';
import 'foto_carnet_captura.dart';

const Color _khPrimary = Color(0xffc28942);
const Color _khBorde = Color(0xFFE2E8F0);
const Color _khTexto = Color(0xFF0F172A);
const Color _khSuave = Color(0xFF64748B);
const String _kFont = 'Arial';

/// Cómo sale el PDF.
enum CarnetSalida {
  /// Hoja carta con varios y marcas de corte. Para imprimir en papel y cortar.
  hoja,

  /// Una página por carnet, del tamaño de la tarjeta. Para impresora de PVC.
  individual,
}

class CarnetScreen extends StatefulWidget {
  final String userId;
  final String empresaId;

  const CarnetScreen({
    super.key,
    required this.userId,
    required this.empresaId,
  });

  @override
  State<CarnetScreen> createState() => _CarnetScreenState();
}

class _CarnetScreenState extends State<CarnetScreen> {
  final _svc = CarnetService();
  final _marcaSvc = CarnetMarcaService();
  final _buscarCtrl = TextEditingController();

  CarnetMarca? _marca;

  /// Marca tal como está guardada. Sirve para saber si hay cambios sin guardar.
  CarnetMarca? _marcaGuardada;

  List<CarnetCandidato> _candidatos = const [];
  final Set<String> _seleccion = <String>{};

  /// RH por persona, para la vista previa. Se pide solo del que se está
  /// mirando: traerlo de todo el padrón sería una lectura por persona.
  final Map<String, String> _rhPreview = <String, String>{};

  CarnetFormato _formato = CarnetFormato.tarjeta;
  CarnetSalida _salida = CarnetSalida.hoja;
  bool _soloActivos = true;
  bool _cargando = true;
  bool _guardando = false;
  bool _generando = false;
  bool _disenoAbiertoEnMovil = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _buscarCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final marca = await _marcaSvc.cargar(widget.empresaId);
      final candidatos = await _svc.cargarCandidatos(widget.empresaId);
      if (!mounted) return;
      setState(() {
        _marca = marca;
        _marcaGuardada = marca;
        _candidatos = candidatos;
        _seleccion.removeWhere((id) => !candidatos.any((c) => c.userId == id));
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _cargando = false;
      });
    }
  }

  List<CarnetCandidato> get _visibles {
    final consulta = _buscarCtrl.text;
    return _candidatos
        .where((c) => !_soloActivos || c.activo)
        .where((c) => c.coincideCon(consulta))
        .toList();
  }

  List<CarnetCandidato> get _seleccionados =>
      _candidatos.where((c) => _seleccion.contains(c.userId)).toList();

  bool get _hayCambiosDeMarca =>
      _marca != null &&
      _marcaGuardada != null &&
      (_marca!.colorPrimario != _marcaGuardada!.colorPrimario ||
          _marca!.colorSecundario != _marcaGuardada!.colorSecundario);

  /// A quién se le muestra el carnet en la vista previa.
  ///
  /// Si hay alguien seleccionado se usa el primero: ver el carnet real de una
  /// persona dice más que un ejemplo inventado. Cuando no hay nadie, un ejemplo
  /// con los campos más largos que se van a encontrar, para que quien elige los
  /// colores vea de una vez cómo se comporta el diseño con un nombre largo.
  /// Cambia la selección y refresca el RH de la vista previa.
  void _cambiarSeleccion(VoidCallback cambio) {
    setState(cambio);
    _asegurarRhPreview();
  }

  /// Trae el RH de quien se está previsualizando, una sola vez por persona.
  Future<void> _asegurarRhPreview() async {
    final elegidos = _seleccionados;
    if (elegidos.isEmpty) return;
    final userId = elegidos.first.userId;
    if (_rhPreview.containsKey(userId)) return;
    try {
      final rh = await _svc.tipoSangreDe(userId);
      if (!mounted) return;
      setState(() => _rhPreview[userId] = rh);
    } catch (_) {
      // Sin RH la vista previa se dibuja igual; el PDF lo vuelve a consultar.
    }
  }

  CarnetPersona get _personaPreview {
    final elegidos = _seleccionados;
    if (elegidos.isNotEmpty) {
      final c = elegidos.first;
      return CarnetPersona(
        userId: c.userId,
        nombres: c.nombres,
        apellidos: c.apellidos,
        cargo: c.cargo,
        cedula: c.cedula,
        rh: _rhPreview[c.userId] ?? '',
        fotoUrl: c.fotoUrl,
      );
    }
    return const CarnetPersona(
      userId: '_ejemplo',
      nombres: 'María Fernanda',
      apellidos: 'Rodríguez Cárdenas',
      cargo: 'Auxiliar de Servicios Generales',
      cedula: '1.020.304.050',
      rh: 'O+',
    );
  }

  @override
  Widget build(BuildContext context) {
    final ancho = MediaQuery.of(context).size.width;
    final escritorio = ancho >= 900;

    return GuardedModulePage(
      userIdentity: widget.userId,
      appId: 'talentohumanodashboard',
      pageTitle: 'Carnets',
      fallbackEmpresaId: widget.empresaId,
      child: InternalModuleLayout(
        userId: widget.userId,
        empresaId: widget.empresaId,
        title: 'Carnets',
        subtitle: 'Diseño de la empresa e impresión del personal',
        accentColor: _khPrimary,
        child: _cuerpo(escritorio),
      ),
    );
  }

  Widget _cuerpo(bool escritorio) {
    if (_cargando) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 44, color: Colors.orange),
              const SizedBox(height: 12),
              const Text(
                'No se pudo cargar el personal',
                style: TextStyle(
                  fontFamily: _kFont,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: _kFont,
                  fontSize: 12,
                  color: _khSuave,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _cargar,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    if (escritorio) {
      return SingleChildScrollView(
        child: InternalModuleViewport(
          maxWidth: 1180,
          padding: const EdgeInsets.all(28),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 340, child: _panelDiseno(compacto: false)),
              const SizedBox(width: 24),
              Expanded(child: _panelPersonal()),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      child: InternalModuleViewport(
        maxWidth: 680,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _disenoPlegable(),
            const SizedBox(height: 16),
            _panelPersonal(),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- diseño

  /// En el teléfono el diseño arranca cerrado: la tarea diaria es imprimir, no
  /// cambiar los colores de la empresa, y la vista previa se come la pantalla.
  Widget _disenoPlegable() {
    return ModuleCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          ListTile(
            leading: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: Color(_marca!.colorPrimario),
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            title: const Text(
              'Diseño del carnet',
              style: TextStyle(fontFamily: _kFont, fontWeight: FontWeight.w800),
            ),
            subtitle: Text(
              _hayCambiosDeMarca
                  ? 'Cambios sin guardar'
                  : 'Colores y logo de la empresa',
              style: TextStyle(
                fontFamily: _kFont,
                fontSize: 12,
                color: _hayCambiosDeMarca ? Colors.orange.shade800 : _khSuave,
              ),
            ),
            trailing: Icon(
              _disenoAbiertoEnMovil
                  ? Icons.expand_less_rounded
                  : Icons.expand_more_rounded,
            ),
            onTap: () =>
                setState(() => _disenoAbiertoEnMovil = !_disenoAbiertoEnMovil),
          ),
          if (_disenoAbiertoEnMovil)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: _contenidoDiseno(compacto: true),
            ),
        ],
      ),
    );
  }

  Widget _panelDiseno({required bool compacto}) {
    return ModuleCard(
      padding: const EdgeInsets.all(20),
      child: _contenidoDiseno(compacto: compacto),
    );
  }

  Widget _contenidoDiseno({required bool compacto}) {
    final marca = _marca!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!compacto) ...[
          const Text(
            'Diseño del carnet',
            style: TextStyle(
              fontFamily: _kFont,
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: _khTexto,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'El modelo es el mismo para todas las empresas. Solo cambian '
            'los colores y el logo.',
            style: TextStyle(fontFamily: _kFont, fontSize: 12, color: _khSuave),
          ),
          const SizedBox(height: 18),
        ],
        Center(
          child: CarnetPreview(
            persona: _personaPreview,
            marca: marca,
            formato: _formato,
            ancho: compacto ? 200 : 230,
          ),
        ),
        const SizedBox(height: 18),
        _selectorColor(
          etiqueta: 'Color principal',
          ayuda: 'Banda del cargo',
          valor: marca.colorPrimario,
          onChanged: (c) =>
              setState(() => _marca = marca.copyWith(colorPrimario: c)),
        ),
        const SizedBox(height: 12),
        _selectorColor(
          etiqueta: 'Color de acento',
          ayuda: 'Arcos decorativos',
          valor: marca.colorSecundario,
          onChanged: (c) =>
              setState(() => _marca = marca.copyWith(colorSecundario: c)),
        ),
        const SizedBox(height: 14),
        _avisoLogo(marca),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: _khPrimary),
            onPressed: (!_hayCambiosDeMarca || _guardando)
                ? null
                : _guardarMarca,
            icon: _guardando
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.save_rounded, size: 18),
            label: Text(
              _guardando ? 'Guardando…' : 'Guardar diseño de la empresa',
              style: const TextStyle(
                fontFamily: _kFont,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// El logo no se sube desde aquí a propósito.
  ///
  /// Es el mismo `logoUrl` que usan notificaciones y planillas. Si esta
  /// pantalla lo dejara cambiar, terminaríamos con dos logos por empresa y uno
  /// de los dos desactualizado.
  Widget _avisoLogo(CarnetMarca marca) {
    final hay = marca.logoUrl.trim().isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: hay ? const Color(0xFFF1F5F9) : const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            hay ? Icons.image_outlined : Icons.warning_amber_rounded,
            size: 18,
            color: hay ? _khSuave : const Color(0xFF92400E),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              hay
                  ? 'El logo es el de la empresa. Se cambia en Admin › Empresas.'
                  : 'Esta empresa no tiene logo cargado: el carnet imprime el '
                        'nombre en su lugar. Se sube en Admin › Empresas.',
              style: TextStyle(
                fontFamily: _kFont,
                fontSize: 11.5,
                height: 1.35,
                color: hay ? _khSuave : const Color(0xFF92400E),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _selectorColor({
    required String etiqueta,
    required String ayuda,
    required int valor,
    required ValueChanged<int> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              etiqueta,
              style: const TextStyle(
                fontFamily: _kFont,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: _khTexto,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '· $ayuda',
              style: const TextStyle(
                fontFamily: _kFont,
                fontSize: 11.5,
                color: _khSuave,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final preset in _presets) ...[
              _muestra(
                color: preset,
                elegido: preset == valor,
                onTap: () => onChanged(preset),
              ),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: _campoHex(valor: valor, onChanged: onChanged),
            ),
          ],
        ),
      ],
    );
  }

  Widget _muestra({
    required int color,
    required bool elegido,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: Color(color),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: elegido ? _khTexto : _khBorde,
            width: elegido ? 2 : 1,
          ),
        ),
      ),
    );
  }

  /// Campo de color escrito a mano.
  ///
  /// Hace falta porque los colores corporativos casi nunca coinciden con una
  /// paleta de muestras: al diseñador le dan un `#1B1B64` exacto y ese es el
  /// que hay que poder poner.
  Widget _campoHex({required int valor, required ValueChanged<int> onChanged}) {
    return TextFormField(
      key: ValueKey('hex_$valor'),
      initialValue: hexDeColor(valor),
      textCapitalization: TextCapitalization.characters,
      style: const TextStyle(fontFamily: _kFont, fontSize: 12.5),
      decoration: const InputDecoration(
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        border: OutlineInputBorder(),
        hintText: '#1B1B64',
      ),
      onChanged: (texto) {
        // Solo se aplica cuando el texto YA es un color completo: si no, cada
        // tecla intermedia repintaría la vista previa de un color distinto.
        final limpio = texto.trim().replaceAll('#', '');
        if (limpio.length != 6) return;
        onChanged(colorDesdeHex(texto, valor));
      },
    );
  }

  static const List<int> _presets = [
    kCarnetAzulPorDefecto,
    kCarnetDoradoPorDefecto,
    0xFF0F766E,
    0xFF991B1B,
  ];

  Future<void> _guardarMarca() async {
    if (_guardando || _marca == null) return;
    setState(() => _guardando = true);
    try {
      await _marcaSvc.guardar(_marca!);
      if (!mounted) return;
      setState(() {
        _marcaGuardada = _marca;
        _guardando = false;
      });
      _aviso('Diseño guardado para esta empresa.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _guardando = false);
      _aviso('No se pudo guardar: $e', error: true);
    }
  }

  // -------------------------------------------------------------- personal

  Widget _panelPersonal() {
    final visibles = _visibles;
    return ModuleCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Personal',
            style: TextStyle(
              fontFamily: _kFont,
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: _khTexto,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _buscarCtrl,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(fontFamily: _kFont, fontSize: 13.5),
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Icons.search, size: 20),
              hintText: 'Buscar por nombre, cédula o cargo',
              border: const OutlineInputBorder(),
              suffixIcon: _buscarCtrl.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => setState(_buscarCtrl.clear),
                    ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilterChip(
                label: const Text(
                  'Solo personal activo',
                  style: TextStyle(fontFamily: _kFont, fontSize: 12),
                ),
                selected: _soloActivos,
                onSelected: (v) => setState(() => _soloActivos = v),
              ),
              TextButton.icon(
                onPressed: visibles.isEmpty
                    ? null
                    : () => setState(() {
                        _seleccion.addAll(visibles.map((c) => c.userId));
                        _asegurarRhPreview();
                      }),
                icon: const Icon(Icons.done_all, size: 16),
                label: Text(
                  'Seleccionar los ${visibles.length} visibles',
                  style: const TextStyle(fontFamily: _kFont, fontSize: 12),
                ),
              ),
              if (_seleccion.isNotEmpty)
                TextButton.icon(
                  onPressed: () => setState(_seleccion.clear),
                  icon: const Icon(Icons.clear_all, size: 16),
                  label: const Text(
                    'Quitar selección',
                    style: TextStyle(fontFamily: _kFont, fontSize: 12),
                  ),
                ),
            ],
          ),
          const Divider(height: 24, color: _khBorde),
          if (visibles.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 30),
              child: Center(
                child: Text(
                  'No hay personal que coincida.',
                  style: TextStyle(
                    fontFamily: _kFont,
                    fontSize: 13,
                    color: _khSuave,
                  ),
                ),
              ),
            )
          else
            PagedListSection<CarnetCandidato>(
              items: visibles,
              etiqueta: 'personas',
              separator: const Divider(height: 1, color: _khBorde),
              itemBuilder: (_, candidato, _) => _fila(candidato),
            ),
          const SizedBox(height: 18),
          _barraGenerar(),
        ],
      ),
    );
  }

  Widget _fila(CarnetCandidato c) {
    final elegido = _seleccion.contains(c.userId);
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      onTap: () => _cambiarSeleccion(() {
        if (elegido) {
          _seleccion.remove(c.userId);
        } else {
          _seleccion.add(c.userId);
        }
      }),
      // Ancho fijo: `leading` lleva dos cosas y ListTile calcula la posición del
      // título a partir de su ancho. Sin fijarlo, los títulos de las filas no
      // arrancan todos en la misma columna.
      leading: SizedBox(
        width: 72,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Checkbox(
              value: elegido,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onChanged: (v) => _cambiarSeleccion(() {
                if (v == true) {
                  _seleccion.add(c.userId);
                } else {
                  _seleccion.remove(c.userId);
                }
              }),
            ),
            const SizedBox(width: 8),
            UserAvatar(
              userId: c.userId,
              nameHint: c.nombreCompleto,
              fotoUrlHint: c.fotoUrl,
              radius: 16,
            ),
          ],
        ),
      ),
      // La corrección de foto vive aquí y no en la hoja de vida porque es aquí
      // donde se descubre el problema: se ve la miniatura mala justo antes de
      // mandar el carnet a imprimir.
      trailing: IconButton(
        tooltip: c.tieneFoto
            ? 'Cambiar la foto del carnet'
            : 'Tomar la foto del carnet',
        icon: Icon(
          c.tieneFoto
              ? Icons.photo_camera_outlined
              : Icons.add_a_photo_outlined,
          size: 20,
          color: c.tieneFoto ? _khSuave : Colors.orange.shade800,
        ),
        onPressed: _generando ? null : () => _corregirFoto(c),
      ),
      title: UserNameText(
        c.userId,
        fallbackName: c.nombreCompleto,
        style: const TextStyle(
          fontFamily: _kFont,
          fontSize: 13.5,
          fontWeight: FontWeight.w700,
          color: _khTexto,
        ),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              c.cargo.isEmpty ? 'Sin cargo' : c.cargo,
              style: const TextStyle(
                fontFamily: _kFont,
                fontSize: 11.5,
                color: _khSuave,
              ),
            ),
            if (!c.activo) _etiqueta('Retirado', Colors.red),
            if (!c.tieneFoto) _etiqueta('Sin foto', Colors.orange),
            if (!c.hojaAprobada) _etiqueta('HV sin aprobar', Colors.orange),
            if (c.tieneCarnet) _etiqueta('Ya tiene carnet', Colors.blueGrey),
          ],
        ),
      ),
    );
  }

  /// Reemplaza la foto de una persona sin salir de la pantalla.
  ///
  /// Escribe en la hoja de vida, que es donde vive la foto: no se guarda una
  /// "foto de carnet" aparte, porque tener dos caras de la misma persona
  /// termina siempre con una de las dos vieja.
  Future<void> _corregirFoto(CarnetCandidato c) async {
    final url = await capturarFotoDeCarnet(
      context,
      userId: c.userId,
      nombreVisible: c.nombreCompleto,
    );
    if (url == null || !mounted) return;
    // Se repinta con la URL nueva en vez de recargar todo el padrón: el
    // listado puede tener cientos de personas y solo cambió una.
    setState(() {
      _candidatos = [
        for (final actual in _candidatos)
          if (actual.userId == c.userId)
            CarnetCandidato(
              userId: actual.userId,
              cedula: actual.cedula,
              nombres: actual.nombres,
              apellidos: actual.apellidos,
              cargo: actual.cargo,
              fotoUrl: url,
              activo: actual.activo,
              hojaAprobada: actual.hojaAprobada,
              tieneCarnet: actual.tieneCarnet,
            )
          else
            actual,
      ];
    });
    _aviso('Foto actualizada en la hoja de vida.');
  }

  Widget _etiqueta(String texto, MaterialColor color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.shade200),
      ),
      child: Text(
        texto,
        style: TextStyle(
          fontFamily: _kFont,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color.shade800,
        ),
      ),
    );
  }

  // -------------------------------------------------------------- generar

  Widget _barraGenerar() {
    final n = _seleccion.length;
    final hojas = n == 0
        ? 0
        : _salida == CarnetSalida.hoja
        ? (n / carnetsPorHoja(_formato)).ceil()
        : n;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Impresión',
          style: TextStyle(
            fontFamily: _kFont,
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: _khTexto,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _grupoBotones<CarnetFormato>(
              valor: _formato,
              opciones: {for (final f in CarnetFormato.values) f: f.etiqueta},
              onChanged: (f) => setState(() => _formato = f),
            ),
            _grupoBotones<CarnetSalida>(
              valor: _salida,
              opciones: const {
                CarnetSalida.hoja: 'Hoja para recortar',
                CarnetSalida.individual: 'Una página por carnet',
              },
              onChanged: (s) => setState(() => _salida = s),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          n == 0
              ? 'Selecciona al menos una persona.'
              : _salida == CarnetSalida.hoja
              ? '$n carnet(s) · $hojas hoja(s) carta con marcas de corte.'
              : '$n carnet(s) · $hojas página(s) de ${_formato.etiqueta}.',
          style: const TextStyle(
            fontFamily: _kFont,
            fontSize: 12,
            color: _khSuave,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: _khPrimary,
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: (n == 0 || _generando) ? null : _generar,
            icon: _generando
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.badge_rounded),
            label: Text(
              _generando ? 'Generando…' : 'Generar $n carnet(s)',
              style: const TextStyle(
                fontFamily: _kFont,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _grupoBotones<T>({
    required T valor,
    required Map<T, String> opciones,
    required ValueChanged<T> onChanged,
  }) {
    return SegmentedButton<T>(
      showSelectedIcon: false,
      style: const ButtonStyle(visualDensity: VisualDensity.compact),
      segments: [
        for (final e in opciones.entries)
          ButtonSegment<T>(
            value: e.key,
            label: Text(
              e.value,
              style: const TextStyle(fontFamily: _kFont, fontSize: 12),
            ),
          ),
      ],
      selected: {valor},
      onSelectionChanged: (s) => onChanged(s.first),
    );
  }

  Future<void> _generar() async {
    if (_generando) return;
    final elegidos = _seleccionados;
    if (elegidos.isEmpty) return;

    if (!await _confirmarPendientes(elegidos)) return;

    setState(() => _generando = true);
    try {
      final personas = await _svc.prepararLote(
        candidatos: elegidos,
        empresaId: widget.empresaId,
      );
      // La marca que se imprime es la GUARDADA, no la que está en pantalla:
      // imprimir con un color que nadie guardó deja carnets que no se pueden
      // reproducir después.
      final marca = _marcaGuardada ?? _marca!;
      final recursos = await cargarRecursosCarnet(
        marca: marca,
        personas: personas,
      );
      final bytes = _salida == CarnetSalida.hoja
          ? await buildCarnetsHojaPdf(
              personas: personas,
              marca: marca,
              formato: _formato,
              recursos: recursos,
            )
          : await buildCarnetsIndividualesPdf(
              personas: personas,
              marca: marca,
              formato: _formato,
              recursos: recursos,
            );
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'carnets_${widget.empresaId}_${personas.length}.pdf',
      );
      if (!mounted) return;
      // El listado se recarga para que la etiqueta "Ya tiene carnet" refleje
      // los tokens que se acaban de crear.
      await _cargar();
    } catch (e) {
      if (!mounted) return;
      _aviso('No se pudieron generar los carnets: $e', error: true);
    } finally {
      if (mounted) setState(() => _generando = false);
    }
  }

  /// Avisa de lo que va a salir mal impreso ANTES de gastar la tarjeta.
  ///
  /// No bloquea: hay casos legítimos (reimprimir el carnet de alguien que se
  /// retiró para reemplazarlo). Solo obliga a verlo.
  Future<bool> _confirmarPendientes(List<CarnetCandidato> elegidos) async {
    final sinFoto = elegidos.where((c) => !c.tieneFoto).toList();
    final sinAprobar = elegidos.where((c) => !c.hojaAprobada).toList();
    final retirados = elegidos.where((c) => !c.activo).toList();
    if (sinFoto.isEmpty && sinAprobar.isEmpty && retirados.isEmpty) return true;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Revisa antes de imprimir'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (sinFoto.isNotEmpty)
              _lineaAviso(
                '${sinFoto.length} sin foto',
                'El carnet sale con la inicial en el círculo.',
                sinFoto,
              ),
            if (sinAprobar.isNotEmpty)
              _lineaAviso(
                '${sinAprobar.length} con la hoja de vida sin aprobar',
                'El cargo y el nombre pueden no estar revisados.',
                sinAprobar,
              ),
            if (retirados.isNotEmpty)
              _lineaAviso(
                '${retirados.length} sin vínculo vigente',
                'Al escanear el QR, la página dirá que no está vinculado.',
                retirados,
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Imprimir de todas formas'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Widget _lineaAviso(
    String titulo,
    String detalle,
    List<CarnetCandidato> quienes,
  ) {
    final nombres = quienes.take(3).map((c) => c.nombreCompleto).join(', ');
    final resto = quienes.length > 3 ? ' y ${quienes.length - 3} más' : '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titulo,
            style: const TextStyle(
              fontFamily: _kFont,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
          Text(
            detalle,
            style: const TextStyle(
              fontFamily: _kFont,
              fontSize: 12,
              color: _khSuave,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '$nombres$resto',
            style: const TextStyle(
              fontFamily: _kFont,
              fontSize: 11.5,
              fontStyle: FontStyle.italic,
              color: _khSuave,
            ),
          ),
        ],
      ),
    );
  }

  void _aviso(String texto, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(texto),
        backgroundColor: error ? Colors.red : const Color(0xFF176B45),
      ),
    );
  }
}
