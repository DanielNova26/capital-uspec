"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.GD_CIERRE_JUSTIFICACION_MAX = exports.GD_CIERRE_JUSTIFICACION_MIN = exports.GD_CIERRE_MOTIVOS = void 0;
exports.validateGdCierre = validateGdCierre;
exports.gdCierreEventDetail = gdCierreEventDetail;
/**
 * Motivo con el que se cierra un expediente de correspondencia.
 *
 * Cerrar no es lo mismo que contestar: un correo de una entidad de salud que
 * no nos compete se cierra sin respuesta, y eso tiene que quedar dicho con
 * palabras, no deducirse de que `enviadoAt` esté vacío. Por eso el cierre
 * lleva motivo y justificación, y el backend exige la justificación cuando el
 * expediente se cierra sin respuesta registrada o con un motivo distinto a
 * "gestión completa".
 *
 * El mismo catálogo vive en `gd_correspondencia_models.dart`
 * (`GdMotivoCierre`); si se agrega uno aquí hay que agregarlo allá.
 */
exports.GD_CIERRE_MOTIVOS = {
    gestion_completa: "Gestión completa",
    no_corresponde: "No corresponde a la entidad",
    no_requiere_respuesta: "No requiere respuesta",
    duplicado: "Duplicado de otro expediente",
    otro: "Otro motivo",
};
exports.GD_CIERRE_JUSTIFICACION_MIN = 10;
exports.GD_CIERRE_JUSTIFICACION_MAX = 2000;
/**
 * Normaliza y valida lo que llega del cliente. Devuelve el mensaje de error
 * ya redactado para el usuario, o el cierre listo para guardar.
 * @param {object} input Motivo y justificación crudos, y si el expediente tiene respuesta.
 * @return {object} `{error}` con el mensaje para el usuario, o `{cierre}` validado.
 */
function validateGdCierre(input) {
    const motivo = String(input.motivo ?? "").trim().toLowerCase() || "gestion_completa";
    if (!Object.prototype.hasOwnProperty.call(exports.GD_CIERRE_MOTIVOS, motivo)) {
        return { error: "El motivo de cierre no es válido." };
    }
    const justificacion = String(input.justificacion ?? "").trim()
        .slice(0, exports.GD_CIERRE_JUSTIFICACION_MAX);
    const sinRespuesta = !input.tieneRespuesta;
    const requiereJustificacion = motivo !== "gestion_completa" || sinRespuesta;
    if (requiereJustificacion && justificacion.length < exports.GD_CIERRE_JUSTIFICACION_MIN) {
        return {
            error: sinRespuesta
                ? "Este expediente no tiene respuesta registrada: explica por qué se cierra sin responder."
                : "Explica el motivo del cierre.",
        };
    }
    return { cierre: { motivo, justificacion, sinRespuesta } };
}
/**
 * Texto de la bitácora: quién cerró, con qué motivo y qué dijo.
 * @param {object} input Si cerró un tercero y el cierre ya validado.
 * @return {string} Detalle legible para la bitácora del expediente.
 */
function gdCierreEventDetail(input) {
    const quien = input.cerradoPorTercero
        ? "Un administrador del módulo"
        : "El responsable";
    const etiqueta = exports.GD_CIERRE_MOTIVOS[input.cierre.motivo] ?? input.cierre.motivo;
    const partes = [`${quien} marcó el proceso como terminado.`, `Motivo: ${etiqueta}.`];
    if (input.cierre.sinRespuesta)
        partes.push("Se cerró sin respuesta registrada.");
    if (input.cierre.justificacion)
        partes.push(input.cierre.justificacion);
    return partes.join(" ");
}
