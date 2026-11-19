"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.PLANEACION_NIVELES = exports.PLANEACION_APP = void 0;
exports.exigir = exigir;
exports.fecha = fecha;
exports.positivo = positivo;
exports.unidad = unidad;
exports.redondear = redondear;
exports.puedePlaneacion = puedePlaneacion;
exports.calcularPlaneacion = calcularPlaneacion;
exports.seleccionSalida = seleccionSalida;
exports.PLANEACION_APP = "planeaciondashboard";
exports.PLANEACION_NIVELES = ["consulta", "planificador", "bodega", "administrador"];
function exigir(condicion, mensaje) {
    if (!condicion)
        throw new Error(mensaje);
}
function fecha(valor) {
    exigir(typeof valor === "string" && /^\d{4}-\d{2}-\d{2}$/.test(valor), "Fecha inválida (AAAA-MM-DD).");
    const d = new Date(`${valor}T12:00:00Z`);
    exigir(Number.isFinite(d.getTime()) && d.toISOString().slice(0, 10) === valor, "Fecha inexistente.");
    return valor;
}
function positivo(valor, entero = false) {
    exigir(typeof valor === "number" && Number.isFinite(valor) && valor > 0 && valor <= 1e9 &&
        (!entero || Number.isInteger(valor)), "La cantidad debe ser positiva y válida.");
    return valor;
}
function unidad(valor) {
    const v = String(valor ?? "").trim().toLowerCase();
    if (["kg", "kl", "kilo", "kilos", "kilogramo", "kilogramos"].includes(v))
        return "kg";
    if (["l", "lt", "litro", "litros"].includes(v))
        return "l";
    if (["und", "un", "unidad", "unidades"].includes(v))
        return "und";
    return v;
}
function redondear(n) {
    return Math.round((n + Number.EPSILON) * 1e6) / 1e6;
}
function puedePlaneacion(nivel, accion) {
    if (!exports.PLANEACION_NIVELES.includes(nivel))
        return false;
    if (accion === "cargar")
        return true;
    if (["guardarMenu", "guardarPrecio", "guardarParte", "guardarCiclo", "enviar"].includes(accion)) {
        return ["planificador", "administrador"].includes(nivel);
    }
    return ["alistar", "despachar"].includes(accion) && ["bodega", "administrador"].includes(nivel);
}
function calcularPlaneacion(programacion, menus, productos, precios) {
    exigir(programacion.length > 0 && programacion.length <= 124, "Programa entre 1 y 124 consumos.");
    const codigos = new Map();
    for (const p of productos) {
        const codigo = String(p.codigo ?? "").trim();
        if (!codigo)
            continue;
        exigir(!codigos.has(codigo), `Código de producto duplicado en Compras: ${codigo}.`);
        codigos.set(codigo, p);
    }
    const lineas = [];
    const claves = new Set();
    for (const [index, s] of programacion.entries()) {
        fecha(s.fecha);
        positivo(s.raciones, true);
        const clave = `${s.centroId}|${s.fecha}`;
        exigir(!claves.has(clave), "Hay dos menús para el mismo establecimiento y día. Usa un menú diario completo.");
        claves.add(clave);
        const opciones = menus.filter((m) => m.codigo === s.menuCodigo && m.activo !== false);
        exigir(opciones.length === 1, `Menú inexistente, inactivo o duplicado: ${s.menuCodigo}.`);
        const menu = opciones[0];
        exigir(Array.isArray(menu.ingredientes) && menu.ingredientes.length > 0, "El menú no tiene receta.");
        for (const i of menu.ingredientes) {
            const p = codigos.get(i.productoCodigo);
            exigir(p && p.activo !== false, `Producto inexistente o inactivo: ${i.productoCodigo}.`);
            const um = unidad(p.unidadMedida);
            exigir(um && unidad(i.unidad) === um, `Revisa la unidad de ${p.nombre}.`);
            const cantidad = redondear(positivo(i.cantidadPorRacion) * s.raciones);
            const vigentes = precios.filter((v) => v.productoCodigo === p.codigo &&
                v.desde <= s.fecha && v.hasta >= s.fecha && unidad(v.unidad) === um && v.activo !== false);
            exigir(vigentes.length <= 1, `Precios superpuestos para ${p.nombre} el ${s.fecha}.`);
            const precio = vigentes.length ? positivo(vigentes[0].precio) : null;
            lineas.push({ programacionId: String(index), centroId: s.centroId, centroNombre: s.centroNombre,
                fecha: s.fecha, menuCodigo: menu.codigo, menuNombre: menu.nombre, raciones: s.raciones,
                tiempo: i.tiempo, preparacion: i.preparacion, productoCodigo: p.codigo,
                productoId: p.id, producto: p.nombre, categoria: p.categoria ?? "", unidad: um,
                cantidadPorRacion: i.cantidadPorRacion, cantidad, precio,
                costo: precio === null ? null : redondear(cantidad * precio) });
        }
    }
    exigir(lineas.length <= 5000, "Divide el ciclo: supera 5.000 líneas de receta.");
    const grupos = new Map();
    for (const l of lineas) {
        const k = l.productoCodigo;
        const g = grupos.get(k) ?? { productoCodigo: k, productoId: l.productoId, producto: l.producto,
            categoria: l.categoria, unidad: l.unidad, cantidad: 0, costo: 0, sinPrecio: false };
        g.cantidad = redondear(g.cantidad + l.cantidad);
        g.sinPrecio || (g.sinPrecio = l.precio === null);
        g.costo = g.sinPrecio ? null : redondear(g.costo + l.costo);
        grupos.set(k, g);
    }
    const totales = [...grupos.values()].sort((a, b) => a.producto.localeCompare(b.producto));
    return { lineas, totales, sinPrecio: totales.filter((g) => g.sinPrecio).length,
        costoTotal: totales.some((g) => g.sinPrecio) ? null : redondear(totales.reduce((n, g) => n + g.costo, 0)) };
}
function seleccionSalida(ciclo, desde, hasta, tipo) {
    fecha(desde);
    fecha(hasta);
    exigir(desde <= hasta, "El rango de salida está invertido.");
    const ids = ciclo.programacion.map((s, i) => ({ s, id: String(i) }))
        .filter(({ s }) => s.fecha >= desde && s.fecha <= hasta).map(({ id }) => id);
    exigir(ids.length > 0, "No hay consumos en ese rango.");
    const existentes = ciclo[tipo === "alistar" ? "alistados" : "despachados"] ?? [];
    exigir(ids.every((id) => !existentes.includes(id)), "Hay consumos ya procesados. Selecciona solo fechas pendientes.");
    if (tipo === "despachar")
        exigir(ids.every((id) => (ciclo.alistados ?? []).includes(id)), "Primero alista todos los consumos seleccionados.");
    return ids;
}
