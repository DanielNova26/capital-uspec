"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.whatsappRuntime = void 0;
// Sin claves privadas descargables. Solo estas funciones reciben los secretos
// y usan la identidad dedicada con acceso a datos operativos y al bucket.
exports.whatsappRuntime = {
    serviceAccount: "whatsapp-runtime@integra360-94704.iam.gserviceaccount.com",
    secrets: ["WHATSAPP_CLOUD_ACCESS_TOKEN", "WHATSAPP_API_KEY"],
    maxInstances: 3,
};
