// lib/services/demo_seed_service.dart
//
// Utilidad para sembrar una empresa demo con datos completos orientados
// a revisiones de App Store / Play Store. Genera un usuario con acceso a
// los paneles administrativos, personal a cargo, tareas activas y
// notificaciones para que el flujo principal de la app funcione sin
// depender de hojas de cálculo externas.

import 'package:cloud_firestore/cloud_firestore.dart';

/// Resultado de la siembra demo con las credenciales que se deben
/// compartir con el equipo de revisión.
class DemoSeedResult {
  final String empresaId;
  final String username;
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

/// Pregunta/respuesta usada por Recuperar contraseña y el modo administrador.
class DemoSecurityQA {
  final String question;
  final String answer;

  const DemoSecurityQA({required this.question, required this.answer});
}

/// Servicio que crea o actualiza la empresa demo y su dataset mínimo.
class DemoSeedService {
  final FirebaseFirestore _db;

  DemoSeedService({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;

  /// Crea los documentos principales necesarios para que el usuario demo
  /// tenga experiencias completas dentro de la app. Si los documentos ya
  /// existen se actualizan con `merge` para evitar sobrescribir ajustes
  /// personalizados.
  Future<DemoSeedResult> ensureDemoData() async {
    const empresaId = 'DEMO_EMPRESA_APP_REVIEW';
    const empresaNombre = 'ToDo Gestión Empresarial (Demo App Review)';

    const reviewerId = 'demo.reviewer';
    const reviewerCedula = '900000001';
    const reviewerPassword = 'Review2025!';
    const reviewerEmail = 'demo.reviewer@todoapp.com';
    const reviewerNombre = 'Daniel Demo';
    const reviewerApellido = 'Administrador';

    const coordinadorId = 'demo.coordinador';
    const coordinadorCedula = '900000002';
    const coordinadorNombre = 'Carolina Coordinadora';

    const analistaId = 'demo.analista';
    const analistaCedula = '900000003';
    const analistaNombre = 'Juan Analista';

    const areaId = '${empresaId}_gestion_proyectos';
    const areaNombre = 'Gestión de Proyectos';
    const centroId = '${empresaId}_centro_principal';
    const centroNombre = 'Centro Principal';
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

    final now = DateTime.now();
    final createdYesterday = Timestamp.fromDate(now.subtract(const Duration(days: 1)));
    final createdTwoDaysAgo = Timestamp.fromDate(now.subtract(const Duration(days: 2)));
    final dueInThreeDays = Timestamp.fromDate(now.add(const Duration(days: 3)));
    final dueTomorrow = Timestamp.fromDate(now.add(const Duration(days: 1)));

    final batch = _db.batch();
    final serverNow = FieldValue.serverTimestamp();

    batch.set(
      _db.collection('TBL_EMPRESAS').doc(empresaId),
      {
        'empresaId': empresaId,
        'nombre': empresaNombre,
        'esDemo': true,
        'updatedAt': serverNow,
        'createdAt': serverNow,
      },
      SetOptions(merge: true),
    );

    batch.set(
      _db.collection('TBL_CONFIG').doc('SECURITY'),
      {
        'seedAdminPin': adminPin,
        'demoAccountId': reviewerId,
        'updatedAt': serverNow,
      },
      SetOptions(merge: true),
    );

    // Catálogos base
    batch.set(
      _db.collection('TBL_AREAS').doc(areaId),
      {
        'empresaId': empresaId,
        'areaId': areaId,
        'nombre': areaNombre,
        'descripcion': 'Equipo dedicado a proyectos estratégicos de la organización.',
        'createdAt': serverNow,
        'updatedAt': serverNow,
      },
      SetOptions(merge: true),
    );

    final centroData = {
      'empresaId': empresaId,
      'centroId': centroId,
      'nombre': centroNombre,
      'codigo': 'CP-001',
      'createdAt': serverNow,
      'updatedAt': serverNow,
    };
    batch.set(
      _db.collection('TBL_CENTROS_COSTOS').doc(centroId),
      centroData,
      SetOptions(merge: true),
    );
    batch.set(
      _db.collection('TBL_CENTROS_COSTO').doc(centroId),
      centroData,
      SetOptions(merge: true),
    );

    batch.set(
      _db.collection('TBL_APPS').doc('${empresaId}_AdminDashboard'),
      {
        'empresaId': empresaId,
        'appId': 'AdminDashboard',
        'nombre': 'Panel Administrativo',
        'descripcion': 'Gestiona roles, usuarios y catálogos.',
        'enabled': true,
        'createdAt': serverNow,
        'updatedAt': serverNow,
      },
      SetOptions(merge: true),
    );

    batch.set(
      _db.collection('TBL_APPS').doc('${empresaId}_TalentoHumanoDashboard'),
      {
        'empresaId': empresaId,
        'appId': 'TalentoHumanoDashboard',
        'nombre': 'Talento Humano',
        'descripcion': 'Administra áreas, cargos y estructura organizacional.',
        'enabled': true,
        'createdAt': serverNow,
        'updatedAt': serverNow,
      },
      SetOptions(merge: true),
    );

    batch.set(
      _db.collection('TBL_ROLES').doc('${empresaId}_desarrollador'),
      {
        'empresaId': empresaId,
        'roleId': '${empresaId}_desarrollador',
        'name': 'desarrollador',
        'apps': const ['AdminDashboard', 'TalentoHumanoDashboard'],
        'updatedAt': serverNow,
      },
      SetOptions(merge: true),
    );

    // Usuarios demo
    batch.set(
      _db.collection('TBL_USUARIOS').doc(reviewerId),
      {
        'cedula': reviewerCedula,
        'empresaId': empresaId,
        'nombres': reviewerNombre,
        'apellidos': reviewerApellido,
        'email': reviewerEmail,
        'cargo': 'Gerente de Proyectos',
        'telefono': '+57 300 123 4567',
        'role': 'desarrollador',
        'apps': const ['AdminDashboard', 'TalentoHumanoDashboard'],
        'password': reviewerPassword,
        'needsPasswordChange': false,
        'pregunta_seguridad_1': questions[0].question,
        'respuesta_seguridad_1': questions[0].answer.toLowerCase(),
        'pregunta_seguridad_2': questions[1].question,
        'respuesta_seguridad_2': questions[1].answer.toLowerCase(),
        'enabled': true,
        'createdAt': serverNow,
        'updatedAt': serverNow,
      },
      SetOptions(merge: true),
    );

    batch.set(
      _db.collection('TBL_USUARIOS').doc(coordinadorId),
      {
        'cedula': coordinadorCedula,
        'empresaId': empresaId,
        'nombres': coordinadorNombre.split(' ').first,
        'apellidos': coordinadorNombre.split(' ').skip(1).join(' '),
        'email': 'demo.coordinador@todoapp.com',
        'cargo': 'Coordinador de Operaciones',
        'telefono': '+57 300 555 0010',
        'role': 'colaborador',
        'apps': const <String>[],
        'password': 'Demo2025!',
        'needsPasswordChange': false,
        'enabled': true,
        'createdAt': serverNow,
        'updatedAt': serverNow,
      },
      SetOptions(merge: true),
    );

    batch.set(
      _db.collection('TBL_USUARIOS').doc(analistaId),
      {
        'cedula': analistaCedula,
        'empresaId': empresaId,
        'nombres': analistaNombre.split(' ').first,
        'apellidos': analistaNombre.split(' ').skip(1).join(' '),
        'email': 'demo.analista@todoapp.com',
        'cargo': 'Analista de Proyectos',
        'telefono': '+57 301 888 0020',
        'role': 'colaborador',
        'apps': const <String>[],
        'password': 'Demo2025!',
        'needsPasswordChange': false,
        'enabled': true,
        'createdAt': serverNow,
        'updatedAt': serverNow,
      },
      SetOptions(merge: true),
    );

    // Hojas de vida simplificadas (para pantallas de Perfil / Equipo)
    batch.set(
      _db.collection('TBL_HojasVida').doc(reviewerId),
      {
        'primerNombre': reviewerNombre.split(' ').first,
        'segundoNombre': 'Demo',
        'primerApellido': reviewerApellido,
        'segundoApellido': 'Principal',
        'email': reviewerEmail,
        'telefono': '+57 300 123 4567',
        'direccion': 'Calle 100 # 25 - 50, Bogotá',
        'ciudad': 'Bogotá',
        'centro_costos': centroNombre,
        'grupo_centro_costos': 'Operaciones',
        'needsRevision': false,
        'revisionNote': null,
        'createdAt': serverNow,
        'updatedAt': serverNow,
      },
      SetOptions(merge: true),
    );

    batch.set(
      _db.collection('TBL_HojasVida').doc(coordinadorId),
      {
        'primerNombre': 'Carolina',
        'primerApellido': 'Coordinadora',
        'email': 'demo.coordinador@todoapp.com',
        'telefono': '+57 300 555 0010',
        'centro_costos': centroNombre,
        'grupo_centro_costos': 'Operaciones',
        'needsRevision': false,
        'createdAt': serverNow,
        'updatedAt': serverNow,
      },
      SetOptions(merge: true),
    );

    batch.set(
      _db.collection('TBL_HojasVida').doc(analistaId),
      {
        'primerNombre': 'Juan',
        'primerApellido': 'Analista',
        'email': 'demo.analista@todoapp.com',
        'telefono': '+57 301 888 0020',
        'centro_costos': centroNombre,
        'grupo_centro_costos': 'Operaciones',
        'needsRevision': false,
        'createdAt': serverNow,
        'updatedAt': serverNow,
      },
      SetOptions(merge: true),
    );

    // Estructura organizacional
    batch.set(
      _db.collection('TBL_ESTRUCTURA_ORGANIZACIONAL').doc(reviewerId),
      {
        'empresaId': empresaId,
        'nombre': '$reviewerNombre $reviewerApellido',
        'cargo': 'Gerente de Proyectos',
        'centro_costos': centroNombre,
        'centroId': centroId,
        'areaId': areaId,
        'areaNombre': areaNombre,
        'subordinates_ids': const [coordinadorId, analistaId],
        'subordinates_names': const [coordinadorNombre, analistaNombre],
        'updatedAt': serverNow,
      },
      SetOptions(merge: true),
    );

    batch.set(
      _db.collection('TBL_ESTRUCTURA_ORGANIZACIONAL').doc(coordinadorId),
      {
        'empresaId': empresaId,
        'nombre': coordinadorNombre,
        'cargo': 'Coordinador de Operaciones',
        'centro_costos': centroNombre,
        'centroId': centroId,
        'areaId': areaId,
        'areaNombre': areaNombre,
        'jefe_directo': reviewerId,
        'jefe_uid': reviewerId,
        'updatedAt': serverNow,
      },
      SetOptions(merge: true),
    );

    batch.set(
      _db.collection('TBL_ESTRUCTURA_ORGANIZACIONAL').doc(analistaId),
      {
        'empresaId': empresaId,
        'nombre': analistaNombre,
        'cargo': 'Analista de Proyectos',
        'centro_costos': centroNombre,
        'centroId': centroId,
        'areaId': areaId,
        'areaNombre': areaNombre,
        'jefe_directo': coordinadorId,
        'jefe_uid': coordinadorId,
        'updatedAt': serverNow,
      },
      SetOptions(merge: true),
    );

    // Cargos (para pantallas de Talento Humano y Mi equipo)
    batch.set(
      _db.collection('TBL_CARGOS').doc(cargoGerenteId),
      {
        'empresaId': empresaId,
        'cargoId': cargoGerenteId,
        'nombre': 'Gerente de Proyectos',
        'assigned_users_ids': const [reviewerId],
        'assigned_users_names': const ['$reviewerNombre $reviewerApellido'],
        'subordinates_ids': const [coordinadorId, analistaId],
        'subordinates_names': const [coordinadorNombre, analistaNombre],
        'centroId': centroId,
        'areaId': areaId,
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
        'assigned_users_ids': const [coordinadorId],
        'assigned_users_names': const [coordinadorNombre],
        'subordinates_ids': const [analistaId],
        'subordinates_names': const [analistaNombre],
        'centroId': centroId,
        'areaId': areaId,
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
        'assigned_users_ids': const [analistaId],
        'assigned_users_names': const [analistaNombre],
        'subordinates_ids': const <String>[],
        'subordinates_names': const <String>[],
        'centroId': centroId,
        'areaId': areaId,
        'updatedAt': serverNow,
      },
      SetOptions(merge: true),
    );

    // Notificaciones demo para la campana de inicio
    batch.set(
      _db.collection('TBL_NOTIFICACIONES').doc(reviewerId),
      {
        'notifications': [
          {
            'id': 'welcome_demo',
            'title': 'Bienvenido a ToDo',
            'body': 'Explora el panel administrativo y crea tareas con datos de prueba.',
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

    // Tareas demo
    batch.set(
      _db.collection('TBL_TAREAS').doc('demo_task_onboarding'),
      {
        'titulo': 'Completar onboarding del nuevo equipo',
        'descripcion': 'Revisa y aprueba la documentación de inducción de los nuevos ingresos.',
        'estado': 'en_progreso',
        'prioridad': 'alta',
        'asignado_uid': reviewerId,
        'asignado_nombre': '$reviewerNombre $reviewerApellido',
        'jefe_uid': coordinadorId,
        'jefe_nombre': coordinadorNombre,
        'centroId': centroId,
        'areaId': areaId,
        'creador_id': coordinadorId,
        'creador_nombre': coordinadorNombre,
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
        'descripcion': 'Sube las métricas de cumplimiento del trimestre y comparte al equipo.',
        'estado': 'pendiente',
        'prioridad': 'media',
        'asignado_uid': reviewerId,
        'asignado_nombre': '$reviewerNombre $reviewerApellido',
        'jefe_uid': reviewerId,
        'jefe_nombre': '$reviewerNombre $reviewerApellido',
        'centroId': centroId,
        'areaId': areaId,
        'creador_id': reviewerId,
        'creador_nombre': '$reviewerNombre $reviewerApellido',
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
        'asignado_uid': coordinadorId,
        'asignado_nombre': coordinadorNombre,
        'jefe_uid': reviewerId,
        'jefe_nombre': '$reviewerNombre $reviewerApellido',
        'centroId': centroId,
        'areaId': areaId,
        'creador_id': reviewerId,
        'creador_nombre': '$reviewerNombre $reviewerApellido',
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
      username: reviewerId,
      password: reviewerPassword,
      email: reviewerEmail,
      securityQuestions: questions,
      adminPin: adminPin,
      created: true,
    );
  }
}
