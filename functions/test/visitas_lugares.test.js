const test = require("node:test");
const assert = require("node:assert/strict");

const {lugaresDesdeRespuesta, primeraClave} = require("../lib/visitas_lugares");

test("Places (New): nombre, dirección, coordenadas y ciudad", () => {
  const lugares = lugaresDesdeRespuesta({
    places: [
      {
        id: "ChIJ-buen-pastor",
        displayName: {text: "Cárcel y Penitenciaría de Mujeres El Buen Pastor"},
        formattedAddress: "Cra. 58 #80-95, Bogotá, Colombia",
        location: {latitude: 4.6853, longitude: -74.0768},
        googleMapsUri: "https://maps.google.com/?cid=1",
        addressComponents: [
          {longText: "Bogotá", types: ["locality", "political"]},
          {longText: "Bogotá, D.C.", types: ["administrative_area_level_1"]},
        ],
      },
      {
        id: "ChIJ-combita",
        displayName: {text: "Establecimiento Penitenciario Cómbita"},
        formattedAddress: "Cómbita, Boyacá",
        location: {latitude: 5.6343, longitude: -73.3229},
        addressComponents: [
          {longText: "Cómbita", types: ["administrative_area_level_2"]},
          {longText: "Boyacá", types: ["administrative_area_level_1"]},
        ],
      },
      // Sin coordenadas: no sirve para el maestro.
      {id: "x", displayName: {text: "Sin sitio"}},
    ],
  });
  assert.equal(lugares.length, 2);
  assert.equal(lugares[0].placeId, "ChIJ-buen-pastor");
  assert.equal(lugares[0].ciudad, "Bogotá");
  assert.equal(lugares[0].departamento, "Bogotá, D.C.");
  assert.equal(lugares[0].lat, 4.6853);
  // Sin localidad, el municipio.
  assert.equal(lugares[1].ciudad, "Cómbita");
  assert.equal(lugares[1].mapsUrl, "");
});

test("sin resultados o respuesta rara: lista vacía", () => {
  assert.deepEqual(lugaresDesdeRespuesta({}), []);
  assert.deepEqual(lugaresDesdeRespuesta(null), []);
  assert.deepEqual(lugaresDesdeRespuesta({places: "no"}), []);
});

test("clave: la misma de Rutas, en el orden de Rutas", () => {
  // Visitas propia (opcional) > empresa en Rutas > nombre viejo > backend.
  assert.equal(primeraClave(undefined, " k-empresa ", "k-vieja", "k-env"),
    "k-empresa");
  assert.equal(primeraClave("", "", "k-vieja", "k-env"), "k-vieja");
  assert.equal(primeraClave(undefined, undefined, undefined, "k-env"), "k-env");
  assert.equal(primeraClave("k-visitas", "k-empresa", "", "k-env"),
    "k-visitas");
  // Algo que no es texto no cuenta como clave.
  assert.equal(primeraClave(123, null, {}, "  "), "");
});
