// lib/services/demo_seed_service.dart
//
// Siembra una empresa demo para App Review con datos coherentes con el
// modelo actual (SeederService + CreateTaskScreen).
//
// ✅ Usa UNA sola colección de centros: TBL_CENTROS_COSTOS
// ✅ DocId de usuarios = cédula (como tu PROD)
// ✅ Campos estandarizados: centroId/centroCostos, areaId/area, cargoId/cargo, jefeId/jefeNombre, etc.

import 'package:cloud_firestore/cloud_firestore.dart';

class DemoSeedResult {
  final String empresaId;
  final String username; // en este modelo = cédula
  final String password;
  final String email;
  final List<DemoSecurityQA> securityQuestions;
  final String adminPin;
  final bool created;

  const DemoSeedResult({
    required this.empresaId,
    required this.username,
    required this.password,
    required this.email,
    required this.securityQuestions,
    required this.adminPin,
    required this.created,
  });
}

class DemoSecurityQA {
  final String question;
  final String answer;

  const DemoSecurityQA({required this.question, required this.answer});
}

class DemoSeedService {
  final FirebaseFirestore _db;

  DemoSeedService({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  Future<DemoSeedResult> ensureDemoData() async {
    const empresaId = 'DEMO_EMPRESA_APP_REVIEW';
    const empresaNombre = 'ToDo Gestión Empresarial (Demo App Review)';

    // ✅ En tu app lo más estable es que docId = cédula (como PROD)
    const reviewerCedula = '900000001';
    const reviewerPassword = 'Review2025!';
    const reviewerEmail = 'demo.reviewer@todoapp.com';
    const reviewerNombres = 'Daniel Demo';
    const reviewerApellidos = 'Administrador';

    const coordinadorCedula = '900000002';
    const coordinadorEmail = 'demo.coordinador@todoapp.com';
    const coordinadorNombreCompleto = 'Carolina Coordinadora';

    const analistaCedula = '900000003';
    const analistaEmail = 'demo.analista@todoapp.com';
    const analistaNombreCompleto = 'Juan Analista';

    // Catálogos IDs
    const centroId = '${empresaId}_centro_principal';
    const centroNombre = 'Centro Principal';

    const areaId = '${empresaId}_gestion_proyectos';
    const areaNombre = 'Gestión de Proyectos';

    const cargoGerenteId = '${empresaId}_gerente_proyectos';
    const cargoCoordinadorId = '${empresaId}_coordinador_operaciones';
    const cargoAnalistaId = '${empresaId}_analista_proyectos';

    const adminPin = '2468';

    final questions = const [
      DemoSecurityQA(
        question: '¿Cuál es el nombre de tu ciudad favorita?',
        answer: 'Cartagena',
      ),
      DemoSecurityQA(
        question: '¿Cuál fue el nombre de tu primera mascota?',
        answer: 'Capuccino',
      ),
    ];

    // Timestamps “bonitos” para que se vea real en review
    final now = DateTime.now();
    final createdYesterday =
    Timestamp.fromDate(now.subtract(const Duration(days: 1)));
    final createdTwoDaysAgo =
    Timestamp.fromDate(now.subtract(const Duration(days: 2)));
    final dueInThreeDays = Timestamp.fromDate(now.add(const Duration(days: 3)));
    final dueTomorrow = Timestamp.fromDate(now.add(const Duration(days: 1)));

    final batch = _db.batch();
    final serverNow = FieldValue.serverTimestamp();

    // ===================== EMPRESA =====================
    batch.set(
      _db.collection('TBL_EMPRESAS').doc(empresaId),
      {
        'empresaId': empresaId,
        'nombre': empresaNombre,
        'esDemo': true,
        'createdAt': serverNow,
        'updatedAt': serverNow,
      },
      SetOptions(merge: true),
    );

    // Config seguridad (PIN admin / cuenta demo)
    batch.set(
      _db.collection('TBL_CONFIG').doc('SECURITY'),
      {
        'seedAdminPin': adminPin,
        'demoAccountId': reviewerCedula, // docId real del demo admin
        'updatedAt': serverNow,
      },
      SetOptions(merge: true),
    );

    // ===================== CATÁLOGOS =====================
    // Centro de costos (✅ SOLO esta colección)
    batch.set(
      _db.collection('TBL_CENTROS_COSTOS').doc(centroId),
      {
        'empresaId': empresaId,
        'centroId': centroId,
        'codigo': 'CP-001',
        'nombre': centroNombre,
        'createdAt': serverNow,
        'updatedAt': serverNow,
      },
      SetOptions(merge: true),
    );

    // Área (idealmente relacionada al centro para tu filtro centro -> área)
    batch.set(
      _db.collection('TBL_AREAS').doc(areaId),
      {
        'empresaId': empresaId,
        'areaId': areaId,
        'nombre': areaNombre,
        'descripcion': 'Equipo dedicado a proyectos estratégicos.',
        'centroId': centroId, // 👈 clave para filtro por centro
        'createdAt': serverNow,
        'updatedAt': serverNow,
      },
      SetOptions(merge: true),
    );

    // Cargos (relacionados a área y centro)
    batch.set(
      _db.collection('TBL_CARGOS').doc(cargoGerenteId),
      {
        'empresaId': empresaId,
        'cargoId': cargoGerenteId,
        'nombre': 'Gerente de Proyectos',
        'area': areaNombre,
        'areaId': areaId,
        'centroId': centroId,
        'createdAt': serverNow,
        'updatedAt': serverNow,
      },
      SetOptions(merge: true),
    );

    batch.set(
      _db.collection('TBL_CARGOS').doc(cargoCoordinadorId),
      {
        'empresaId': empresaId,
        'cargoId': cargoCoordinadorId,
        'nombre': 'Coordinador de Operaciones',
        'area': areaNombre,
        'areaId': areaId,
        'centroId': centroId,
        'createdAt': serverNow,
        'updatedAt': serverNow,
      },
      SetOptions(merge: true),
    );

    batch.set(
      _db.collection('TBL_CARGOS').doc(cargoAnalistaId),
      {
        'empresaId': empresaId,
        'cargoId': cargoAnalistaId,
        'nombre': 'Analista de Proyectos',
        'area': areaNombre,
        'areaId': areaId,
        'centroId': centroId,
        'createdAt': serverNow,
        'updatedAt': serverNow,
      },
      SetOptions(merge: true),
    );

    // Apps (docs con id compuesto empresaId_appId)
    Future<void> _setApp(
        String appId,
        String nombre,
        String descripcion,
        ) async {
      batch.set(
        _db.collection('TBL_APPS').doc('${empresaId}_$appId'),
        {
          'empresaId': empresaId,
          'appId': appId,
          'nombre': nombre,
          'descripcion': descripcion,
          'enabled': true,
          'createdAt': serverNow,
          'updatedAt': serverNow,
        },
        SetOptions(merge: true),
      );
    }

    await _setApp(
      'AdminDashboard',
      'Panel Administrativo',
      'Gestiona roles, usuarios y catálogos.',
    );
    await _setApp(
      'TalentoHumanoDashboard',
      'Talento Humano',
      'Administra áreas, cargos y estructura.',
    );
    await _setApp(
      'GerenciaDashboard',
      'Dashboard de Gerencia',
      'Control visual de tareas y desempeño.',
    );
    await _setApp(
      'GestionDocumental',
      'Gestión Documental',
      'Control de versiones, firmas y estados de documentos.',
    );
    // Role demo
    batch.set(
      _db.collection('TBL_ROLES').doc('${empresaId}_desarrollador'),
      {
        'empresaId': empresaId,
        'roleId': '${empresaId}_desarrollador',
        'name': 'desarrollador',
        'apps': const ['AdminDashboard', 'TalentoHumanoDashboard'],
        'updatedAt': serverNow,
        'createdAt': serverNow,
      },
      SetOptions(merge: true),
    );

    // ===================== USUARIOS =====================
    Map<String, String> _splitName(String full) {
      final parts = full.trim().split(RegExp(r'\s+'));
      if (parts.isEmpty) return {'nombres': '', 'apellidos': ''};
      if (parts.length == 1) return {'nombres': parts[0], 'apellidos': ''};
      return {
        'nombres': parts.sublist(0, parts.length - 1).join(' '),
        'apellidos': parts.last,
      };
    }

    final coordParts = _splitName(coordinadorNombreCompleto);
    final analParts = _splitName(analistaNombreCompleto);

    // Admin/reviewer (docId = cedula)
    batch.set(
      _db.collection('TBL_USUARIOS').doc(reviewerCedula),
      {
        'usuario': reviewerCedula,
        'cedula': reviewerCedula,
        'tipo_documento': 'CC',
        'nombres': reviewerNombres,
        'apellidos': reviewerApellidos,
        'correo': reviewerEmail,

        // Empresa multi-empresa compatible
        'empresaId': empresaId,
        'empresaNombre': empresaNombre,
        'empresas': const [empresaId],
        'empresasDetalle': {
          empresaId: {
            'empresaId': empresaId,
            'empresaNombre': empresaNombre,
            'area': areaNombre,
            'areaId': areaId,
            'cargo': 'Gerente de Proyectos',
            'cargoId': cargoGerenteId,
            'centroCostos': centroNombre,
            'centroId': centroId,
            'jefeId': null,
            'jefeNombre': null,
            'cargoJefe': null,
          }
        },

        // Campos top-level (los usa tu CreateTaskScreen)
        'area': areaNombre,
        'areaId': areaId,
        'cargo': 'Gerente de Proyectos',
        'cargoId': cargoGerenteId,
        'centroCostos': centroNombre,
        'centroId': centroId,
        'jefeId': null,
        'jefeNombre': null,
        'cargoJefe': null,

        // Apps y credenciales
        'apps': const [
          'AdminDashboard',
          'TalentoHumanoDashboard',
          'GerenciaDashboard',
          'GestionDocumental',
        ],
        'password': reviewerPassword,
        'needsPasswordChange': false,

        'pregunta_seguridad_1': questions[0].question,
        'respuesta_seguridad_1': questions[0].answer.toLowerCase(),
        'pregunta_seguridad_2': questions[1].question,
        'respuesta_seguridad_2': questions[1].answer.toLowerCase(),

        'estado': 'activo',
        'enabled': true,
        'createdAt': serverNow,
        'updatedAt': serverNow,
      },
      SetOptions(merge: true),
    );

    // Coordinador
    batch.set(
      _db.collection('TBL_USUARIOS').doc(coordinadorCedula),
      {
        'usuario': coordinadorCedula,
        'cedula': coordinadorCedula,
        'tipo_documento': 'CC',
        'nombres': coordParts['nombres'],
        'apellidos': coordParts['apellidos'],
        'correo': coordinadorEmail,

        'empresaId': empresaId,
        'empresaNombre': empresaNombre,
        'empresas': const [empresaId],
        'empresasDetalle': {
          empresaId: {
            'empresaId': empresaId,
            'empresaNombre': empresaNombre,
            'area': areaNombre,
            'areaId': areaId,
            'cargo': 'Coordinador de Operaciones',
            'cargoId': cargoCoordinadorId,
            'centroCostos': centroNombre,
            'centroId': centroId,
            'jefeId': reviewerCedula,
            'jefeNombre': '$reviewerNombres $reviewerApellidos',
            'cargoJefe': 'Gerente de Proyectos',
          }
        },

        'area': areaNombre,
        'areaId': areaId,
        'cargo': 'Coordinador de Operaciones',
        'cargoId': cargoCoordinadorId,
        'centroCostos': centroNombre,
        'centroId': centroId,
        'jefeId': reviewerCedula,
        'jefeNombre': '$reviewerNombres $reviewerApellidos',
        'cargoJefe': 'Gerente de Proyectos',

        'apps': const <String>[],
        'password': 'Demo2025!',
        'needsPasswordChange': false,

        'estado': 'activo',
        'enabled': true,
        'createdAt': serverNow,
        'updatedAt': serverNow,
      },
      SetOptions(merge: true),
    );

    // Analista
    batch.set(
      _db.collection('TBL_USUARIOS').doc(analistaCedula),
      {
        'usuario': analistaCedula,
        'cedula': analistaCedula,
        'tipo_documento': 'CC',
        'nombres': analParts['nombres'],
        'apellidos': analParts['apellidos'],
        'correo': analistaEmail,

        'empresaId': empresaId,
        'empresaNombre': empresaNombre,
        'empresas': const [empresaId],
        'empresasDetalle': {
          empresaId: {
            'empresaId': empresaId,
            'empresaNombre': empresaNombre,
            'area': areaNombre,
            'areaId': areaId,
            'cargo': 'Analista de Proyectos',
            'cargoId': cargoAnalistaId,
            'centroCostos': centroNombre,
            'centroId': centroId,
            'jefeId': coordinadorCedula,
            'jefeNombre': coordinadorNombreCompleto,
            'cargoJefe': 'Coordinador de Operaciones',
          }
        },

        'area': areaNombre,
        'areaId': areaId,
        'cargo': 'Analista de Proyectos',
        'cargoId': cargoAnalistaId,
        'centroCostos': centroNombre,
        'centroId': centroId,
        'jefeId': coordinadorCedula,
        'jefeNombre': coordinadorNombreCompleto,
        'cargoJefe': 'Coordinador de Operaciones',

        'apps': const <String>[],
        'password': 'Demo2025!',
        'needsPasswordChange': false,

        'estado': 'activo',
        'enabled': true,
        'createdAt': serverNow,
        'updatedAt': serverNow,
      },
      SetOptions(merge: true),
    );

    // ===================== CEDULAS (para tu validación por cédula) =====================
    void _seedCedula(String cedula) {
      batch.set(
        _db.collection('TBL_CEDULAS').doc(cedula),
        {
          'cedula': cedula,
          'empresaId': empresaId,
          'empresas': FieldValue.arrayUnion([empresaId]),
          'createdAt': serverNow,
          'updatedAt': serverNow,
        },
        SetOptions(merge: true),
      );
    }

    _seedCedula(reviewerCedula);
    _seedCedula(coordinadorCedula);
    _seedCedula(analistaCedula);

    // ===================== ESTRUCTURA ORGANIZACIONAL =====================
    // (compat con tu CreateTaskScreen: areaId/cargoId/centroId/jefeId/jefeNombre/cargoJefe)
    void _seedEstructura({
      required String cedula,
      required String cargo,
      required String cargoId,
      required String? jefeId,
      required String? jefeNombre,
      required String? cargoJefe,
    }) {
      batch.set(
        _db.collection('TBL_ESTRUCTURA_ORGANIZACIONAL').doc(cedula),
        {
          'empresaId': empresaId,
          'cedula': cedula,
          'area': areaNombre,
          'areaId': areaId,
          'cargo': cargo,
          'cargoId': cargoId,
          'centroCostos': centroNombre,
          'centroId': centroId,
          'jefeId': jefeId,
          'jefeNombre': jefeNombre,
          'cargoJefe': cargoJefe,
          'updatedAt': serverNow,
          'createdAt': serverNow,
        },
        SetOptions(merge: true),
      );
    }

    _seedEstructura(
      cedula: reviewerCedula,
      cargo: 'Gerente de Proyectos',
      cargoId: cargoGerenteId,
      jefeId: null,
      jefeNombre: null,
      cargoJefe: null,
    );
    _seedEstructura(
      cedula: coordinadorCedula,
      cargo: 'Coordinador de Operaciones',
      cargoId: cargoCoordinadorId,
      jefeId: reviewerCedula,
      jefeNombre: '$reviewerNombres $reviewerApellidos',
      cargoJefe: 'Gerente de Proyectos',
    );
    _seedEstructura(
      cedula: analistaCedula,
      cargo: 'Analista de Proyectos',
      cargoId: cargoAnalistaId,
      jefeId: coordinadorCedula,
      jefeNombre: coordinadorNombreCompleto,
      cargoJefe: 'Coordinador de Operaciones',
    );

    // ===================== NOTIFICACIONES DEMO =====================
    batch.set(
      _db.collection('TBL_NOTIFICACIONES').doc(reviewerCedula),
      {
        'notifications': [
          {
            'id': 'welcome_demo',
            'title': 'Bienvenido a ToDo',
            'body':
            'Explora el panel administrativo y crea tareas con datos de prueba.',
            'read': false,
            'createdAt': createdYesterday,
          },
          {
            'id': 'reunion_equipo',
            'title': 'Reunión semanal',
            'body': 'Revisa las tareas pendientes antes de la reunión del miércoles.',
            'read': false,
            'createdAt': createdTwoDaysAgo,
          },
        ],
      },
      SetOptions(merge: true),
    );

    // ===================== TAREAS DEMO =====================
    // Ojo: jefe_uid debe ser realmente el jefe del asignado (coherencia)
    batch.set(
      _db.collection('TBL_TAREAS').doc('demo_task_onboarding'),
      {
        'titulo': 'Completar onboarding del nuevo equipo',
        'descripcion':
        'Revisa y aprueba la documentación de inducción de los nuevos ingresos.',
        'estado': 'en_progreso',
        'prioridad': 'alta',
        'asignado_uid': reviewerCedula,
        'asignado_nombre': '$reviewerNombres $reviewerApellidos',
        'jefe_uid': reviewerCedula,
        'jefe_nombre': '$reviewerNombres $reviewerApellidos',
        'centroId': centroId,
        'areaId': areaId,
        'empresaId': empresaId,
        'creador_id': coordinadorCedula,
        'creador_nombre': coordinadorNombreCompleto,
        'fecha_creacion': createdTwoDaysAgo,
        'fecha_limite': dueTomorrow,
        'adjuntos': const [
          {
            'name': 'Plan de inducción.pdf',
            'url': 'https://www.orimi.com/pdf-test.pdf',
          }
        ],
        'notify': true,
      },
      SetOptions(merge: true),
    );

    batch.set(
      _db.collection('TBL_TAREAS').doc('demo_task_dashboard'),
      {
        'titulo': 'Actualizar tablero de indicadores',
        'descripcion':
        'Sube las métricas de cumplimiento del trimestre y comparte al equipo.',
        'estado': 'pendiente',
        'prioridad': 'media',
        'asignado_uid': reviewerCedula,
        'asignado_nombre': '$reviewerNombres $reviewerApellidos',
        'jefe_uid': reviewerCedula,
        'jefe_nombre': '$reviewerNombres $reviewerApellidos',
        'centroId': centroId,
        'areaId': areaId,
        'empresaId': empresaId,
        'creador_id': reviewerCedula,
        'creador_nombre': '$reviewerNombres $reviewerApellidos',
        'fecha_creacion': createdYesterday,
        'fecha_limite': dueInThreeDays,
        'notify': true,
      },
      SetOptions(merge: true),
    );

    batch.set(
      _db.collection('TBL_TAREAS').doc('demo_task_capacitacion'),
      {
        'titulo': 'Capacitación en protocolos de seguridad',
        'descripcion': 'Coordina con Talento Humano la sesión virtual del viernes.',
        'estado': 'completada',
        'prioridad': 'alta',
        'asignado_uid': coordinadorCedula,
        'asignado_nombre': coordinadorNombreCompleto,
        'jefe_uid': reviewerCedula,
        'jefe_nombre': '$reviewerNombres $reviewerApellidos',
        'centroId': centroId,
        'areaId': areaId,
        'empresaId': empresaId,
        'creador_id': reviewerCedula,
        'creador_nombre': '$reviewerNombres $reviewerApellidos',
        'fecha_creacion': createdTwoDaysAgo,
        'fecha_limite': createdYesterday,
        'fecha_cierre': createdYesterday,
        'notify': true,
      },
      SetOptions(merge: true),
    );

    await batch.commit();

    return DemoSeedResult(
      empresaId: empresaId,
      username: reviewerCedula, // 👈 para login en tu modelo actual
      password: reviewerPassword,
      email: reviewerEmail,
      securityQuestions: questions,
      adminPin: adminPin,
      created: true,
    );
  }
}
