// Sin claves privadas descargables. Solo estas funciones reciben los secretos
// y usan la identidad dedicada con acceso a datos operativos y al bucket.
export const whatsappRuntime = {
  serviceAccount: "whatsapp-runtime@integra360-94704.iam.gserviceaccount.com",
  secrets: ["WHATSAPP_CLOUD_ACCESS_TOKEN", "WHATSAPP_API_KEY"],
  maxInstances: 3,
};
