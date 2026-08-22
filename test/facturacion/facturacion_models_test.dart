import 'package:flutter_test/flutter_test.dart';
import 'package:todo/facturacion/facturacion_models.dart';

void main() {
  group('roles de Facturación', () {
    test('normaliza nombres antiguos y visibles', () {
      expect(normalizeFacRole('Facturación'), kRolFacturacion);
      expect(normalizeFacRole('gestor facturacion'), kRolFacturacion);
      expect(normalizeFacRole('Visor'), kRolFacVisor);
      expect(normalizeFacRole('solo lectura'), kRolFacVisor);
    });

    test('usuario con módulo y sin rol entra como consulta', () {
      expect(
        resolveFacAccessMode(const FacUserInfo(rol: '')),
        FacAccessMode.viewer,
      );
    });

    test('establecimiento configurado solo accede a su flujo', () {
      expect(
        resolveFacAccessMode(
          const FacUserInfo(
            rol: kRolEstablecimiento,
            establecimientoId: 'centro-1',
          ),
        ),
        FacAccessMode.establishment,
      );
    });

    test('establecimiento sin centro no cae en la consulta global', () {
      expect(
        resolveFacAccessMode(const FacUserInfo(rol: kRolEstablecimiento)),
        FacAccessMode.missingEstablishment,
      );
    });

    test('desarrollador conserva acceso de gestión', () {
      expect(
        resolveFacAccessMode(
          const FacUserInfo(rol: ''),
          developerOverride: true,
        ),
        FacAccessMode.manager,
      );
    });

    test('rol explícito de establecimiento prevalece sobre desarrollador', () {
      expect(
        resolveFacAccessMode(
          const FacUserInfo(
            rol: kRolEstablecimiento,
            establecimientoId: 'centro-1',
          ),
          developerOverride: true,
        ),
        FacAccessMode.establishment,
      );
    });
  });

  group('meses de Facturación', () {
    test('muestra el mes sin separadores internos', () {
      expect(facMesLabel('Junio_2026'), 'Junio 2026');
      expect(facMesLabel('junio_2026'), 'Junio 2026');
      expect(facMesLabel('Sin_asignar'), 'Sin asignar');
    });

    test('unifica el mismo mes aunque Storage cambie mayúsculas', () {
      expect(normalizeFacMesKeys(['Junio_2026', 'junio_2026', 'JUNIO_2026']), [
        'Junio_2026',
      ]);
    });

    test('ordena por año y mes real, no alfabéticamente', () {
      final meses = [
        'Diciembre_2025',
        'Enero_2026',
        'Noviembre_2026',
        'Marzo_2025',
      ]..sort(compareFacMesDesc);

      expect(meses, [
        'Noviembre_2026',
        'Enero_2026',
        'Diciembre_2025',
        'Marzo_2025',
      ]);
    });

    test('deja valores no asignados después de los meses válidos', () {
      final meses = ['Sin asignar', 'Julio_2026']..sort(compareFacMesDesc);

      expect(meses, ['Julio_2026', 'Sin asignar']);
    });
  });

  group('maestro de obligaciones', () {
    test('genera códigos estables sin tildes ni espacios', () {
      expect(facObligacionCodigo('Servicio de Energía'), 'servicio_de_energia');
      expect(
        facObligacionCodigo('  Nóminas / Seguridad  '),
        'nominas_seguridad',
      );
    });

    test('la semilla conserva el catálogo histórico y su orden', () {
      final items = FacObligacion.legacy('empresa-a');

      expect(items.map((item) => item.nombre), kFacDocumentos);
      expect(items.first.orden, 0);
      expect(items.last.orden, kFacDocumentos.length - 1);
      expect(items.every((item) => item.empresaId == 'empresa-a'), isTrue);
    });

    test('calcula meta, cargados, faltantes y no aplica por obligación', () {
      final obligacion = FacObligacion.legacy('empresa-a').first;
      FacProgresoEst row({required bool uploaded, bool ignored = false}) =>
          FacProgresoEst(
            establecimiento: FacEstablecimiento(
              id: uploaded
                  ? 'uno'
                  : ignored
                  ? 'tres'
                  : 'dos',
              empresaId: 'empresa-a',
              nombre: 'Centro',
              mes: 'Agosto_2026',
              ignoredDocs: {obligacion.nombre: ignored},
            ),
            subidos: uploaded ? 1 : 0,
            requeridos: ignored ? 0 : 1,
            ignorados: ignored ? 1 : 0,
            docSubido: {obligacion.nombre: uploaded},
          );

      final result = calcularAvanceObligaciones(
        [obligacion],
        [
          row(uploaded: true),
          row(uploaded: false),
          row(uploaded: false, ignored: true),
        ],
      ).single;

      expect(result.meta, 2);
      expect(result.cargados, 1);
      expect(result.faltantes, 1);
      expect(result.noAplica, 1);
      expect(result.progreso, 0.5);
    });
  });

  group('enlace con Admin Dashboard', () {
    test('lee el rol guardado en la empresa activa', () {
      final info = resolveFacUserInfoFromData({
        'rolFac': kRolFacVisor,
        'empresasDetalle': {
          'empresa-a': {'rolFac': kRolFacturacion},
        },
      }, 'empresa-a');

      expect(info.rol, kRolFacturacion);
    });

    test('un rol retirado no hereda el rol global de otra empresa', () {
      final info = resolveFacUserInfoFromData({
        'rolFac': kRolFacturacion,
        'empresasDetalle': {
          'empresa-a': {
            'apps': [kFacAppId],
          },
        },
      }, 'empresa-a');

      expect(info.rol, isEmpty);
    });

    test(
      'mantiene compatibilidad global cuando no existe scope de empresa',
      () {
        final info = resolveFacUserInfoFromData({
          'rolFac': 'Facturación',
        }, 'empresa-a');

        expect(info.rol, kRolFacturacion);
      },
    );

    test('el establecimiento de otra empresa no se filtra a la activa', () {
      final info = resolveFacUserInfoFromData({
        'establecimientoFacId': 'centro-global',
        'empresasDetalle': {
          'empresa-a': {'rolFac': kRolEstablecimiento},
        },
      }, 'empresa-a');

      expect(info.establecimientoId, isNull);
    });
  });

  group('tareas de observaciones documentales', () {
    test('reconstruye el destino exacto de carga desde la tarea', () {
      final target = FacDocumentTaskTarget.fromTaskData('task-1', {
        'origen': kFacTaskOrigin,
        'empresaId': 'empresa-a',
        'facEstablecimientoId': 'global',
        'facEstablecimientoNombre': 'Global',
        'facMes': 'junio_2026',
        'facDocTipo': 'Cuadro de Raciones',
        'asignado_uid': '123456',
      });

      expect(target, isNotNull);
      expect(target!.empresaId, 'empresa-a');
      expect(target.establecimientoId, 'global');
      expect(target.mes, 'Junio_2026');
      expect(target.docTipo, 'Cuadro de Raciones');
      expect(target.asignadoUid, '123456');
    });

    test('no trata una tarea común como requerimiento de Facturación', () {
      final target = FacDocumentTaskTarget.fromTaskData('task-2', {
        'origen': 'manual',
        'empresaId': 'empresa-a',
      });

      expect(target, isNull);
    });

    test(
      'rechaza metadatos incompletos para evitar navegar al lugar errado',
      () {
        final target = FacDocumentTaskTarget.fromTaskData('task-3', {
          'origen': kFacTaskOrigin,
          'empresaId': 'empresa-a',
          'facEstablecimientoId': 'global',
          'facMes': 'Junio_2026',
          'asignado_uid': '123456',
        });

        expect(target, isNull);
      },
    );
  });

  group('flujo de revisión documental', () {
    test('solo reconoce los tres estados del flujo', () {
      expect(parseFacEstadoRevision('pendiente'), FacEstadoRevision.pendiente);
      expect(parseFacEstadoRevision('APROBADA'), FacEstadoRevision.aprobado);
      expect(parseFacEstadoRevision('rechazado'), FacEstadoRevision.rechazado);
      expect(
        parseFacEstadoRevision('valor antiguo'),
        FacEstadoRevision.pendiente,
      );
    });

    test('expone etiquetas coherentes para cargador y revisor', () {
      expect(
        facEstadoRevisionLabel(FacEstadoRevision.pendiente),
        'Pendiente de revisión',
      );
      expect(facEstadoRevisionValue(FacEstadoRevision.aprobado), 'aprobado');
      expect(facEstadoRevisionValue(FacEstadoRevision.rechazado), 'rechazado');
    });
  });
}
