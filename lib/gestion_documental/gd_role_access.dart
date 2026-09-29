import '../utils/user_company.dart';
import 'gd_models.dart';

const gdReadOnlyLevel = 'consulta';
const gdRoleLevelLabels = <String, String>{
  gdReadOnlyLevel: 'Consulta de publicados',
  GdRoles.redactor: 'Redactor',
  GdRoles.revisor: 'Revisor',
  GdRoles.aprobador: 'Aprobador',
  GdRoles.firmante: 'Firmante',
  GdRoles.adminDoc: 'Administrador documental',
};

const gdActionLabels = <String, String>{
  'enviar_revision': 'Enviar a revisión',
  'observar': 'Registrar observaciones',
  'reenviar': 'Reenviar a revisión',
  'aprobar': 'Aprobar',
  'validar_formato': 'Validar formato',
  'firmar': 'Firmar',
  'marcar_vigente': 'Publicar como vigente',
  'subir_pdf': 'Crear y cargar documentos',
  'nueva_version': 'Crear versiones',
  'eliminar_documento': 'Eliminar documentos y copiar biblioteca',
};

List<String> gdActionsForLevel(String level) => [
  for (final action in GdRoles.permisosAccion.keys)
    if (GdRoles.puedeEjecutar(action, level)) action,
];

String gdLevelDescription(String level) {
  final actions = gdActionsForLevel(level);
  return actions.isEmpty
      ? 'Consultar documentos publicados. Sin acciones de flujo.'
      : 'Consultar documentos y versiones. ${actions.map((a) => gdActionLabels[a] ?? a).join(', ')}.';
}

/// La existencia de un campo específico, incluso vacío, es una decisión de
/// esta empresa. Vacío, consulta o valor desconocido no recuperan el rol raíz.
String? resolveGdDocumentalRole(Map<String, dynamic>? user, String empresaId) {
  if (user == null || !personaHabilitadaEn(user, empresaId)) return null;
  if (isDeveloperUser(user, empresaId: empresaId)) return GdRoles.desarrollador;
  final detail = getUserCompanyDetail(user, empresaId);
  final raw = detail?.containsKey('rolDocumental') == true
      ? detail!['rolDocumental']
      : raizEsDeEmpresa(user, empresaId)
      ? user['rolDocumental']
      : null;
  final role = (raw ?? '').toString().trim().toLowerCase();
  return role != gdReadOnlyLevel && gdRoleLevelLabels.containsKey(role)
      ? role
      : null;
}

bool gdCanReadDocument(
  Map<String, dynamic>? user,
  String empresaId,
  DocumentoDoc document,
) {
  if (user == null ||
      document.empresaId != empresaId ||
      !personaHabilitadaEn(user, empresaId)) {
    return false;
  }
  if (isDeveloperUser(user, empresaId: empresaId)) return true;
  if (!userBelongsToEmpresa(user, empresaId) ||
      !userHasApp(
        user,
        'bibliotecadocumentaldashboard',
        empresaId: empresaId,
      )) {
    return false;
  }
  return resolveGdDocumentalRole(user, empresaId) != null ||
      document.estado == GdEstado.vigente;
}

/// Consulta muestra únicamente el archivo vigente del documento publicado.
/// El historial de versiones y los archivos en proceso pertenecen a los niveles operativos.
List<VersionDoc> gdVersionsForReader(
  String? role,
  DocumentoDoc document,
  List<VersionDoc> versions,
) {
  if (role != null) return versions;
  if (document.estado != GdEstado.vigente) return const [];
  final publishedId = (document.versionVigenteId ?? '').trim();
  return versions
      .where(
        (version) =>
            version.docId == document.docId &&
            version.empresaId == document.empresaId &&
            version.estado == GdEstado.vigente &&
            (publishedId.isNotEmpty
                ? version.versionId == publishedId
                : version.esVigente ||
                      version.etiqueta == document.versionActual),
      )
      .toList();
}
