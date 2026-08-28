import 'abastecimiento_models.dart';
import 'compras_models.dart';

String normalizarClaveAbastecimiento(String value) => value
    .trim()
    .toLowerCase()
    .replaceAll('á', 'a')
    .replaceAll('é', 'e')
    .replaceAll('í', 'i')
    .replaceAll('ó', 'o')
    .replaceAll('ú', 'u')
    .replaceAll('ü', 'u')
    .replaceAll('ñ', 'n')
    .replaceAll(RegExp(r'[^a-z0-9]+'), '')
    .trim();

/// Relaciona una programación con una recepción usando primero el vínculo
/// explícito y, para recepciones creadas directamente, OC + proveedor + grupo
/// + producto. La OC nunca se omite porque es el identificador operativo.
bool abastecimientoCoincideConRecepcion(
  AbastecimientoDoc entrega,
  RecepcionDoc recepcion,
) {
  if (entrega.eliminado ||
      entrega.estado == AbastecimientoEstado.cancelado ||
      entrega.empresaId.trim() != recepcion.empresaId.trim()) {
    return false;
  }

  if (recepcion.abastecimientoIds.contains(entrega.id)) return true;

  final ocEntrega = normalizarClaveAbastecimiento(entrega.ordenCompra);
  final ocRecepcion = normalizarClaveAbastecimiento(recepcion.ordenCompra);
  if (ocEntrega.isEmpty || ocRecepcion.isEmpty || ocEntrega != ocRecepcion) {
    return false;
  }

  if (entrega.proveedorId.isNotEmpty && recepcion.proveedorId.isNotEmpty) {
    if (entrega.proveedorId != recepcion.proveedorId) return false;
  } else if (normalizarClaveAbastecimiento(entrega.proveedor) !=
      normalizarClaveAbastecimiento(recepcion.razonSocial)) {
    return false;
  }

  if (entrega.grupoId.isNotEmpty && recepcion.grupoId.isNotEmpty) {
    if (entrega.grupoId != recepcion.grupoId) return false;
  }

  if (entrega.productoId.isNotEmpty && recepcion.productoIds.isNotEmpty) {
    return recepcion.productoIds.contains(entrega.productoId);
  }

  final producto = normalizarClaveAbastecimiento(entrega.producto);
  return producto.isNotEmpty &&
      recepcion.productos.any(
        (item) => normalizarClaveAbastecimiento(item.nombre) == producto,
      );
}
