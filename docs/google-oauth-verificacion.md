# Verificación OAuth de Google — textos para el envío

Proyecto: `integra360-94704` · Scope solicitado: `gmail.readonly`
Los textos van en inglés: el equipo de revisión de Google trabaja en inglés.

---

## 1. Justificación del permiso (por qué necesitas `gmail.readonly`)

To-Do Gestión Empresarial is a corporate correspondence management system used
by organizations to register, classify and track official incoming
communications.

An administrator of the organization voluntarily connects the institution's own
shared mailbox. The app reads that inbox so each incoming message can be turned
into a correspondence record: it captures the sender, subject, date and
attachments, assigns an internal filing code, routes the item to the responsible
area, and tracks it until it is answered and closed.

Read access to the inbox is the only way to capture this automatically. Without
it, staff would have to manually re-type every incoming communication into the
system, which is exactly the error-prone process our clients are replacing, and
it would break the audit trail that Colombian public-sector record-keeping
requires.

We request read-only access. The app never deletes, modifies or sends mail with
this scope.

---

## 2. Uso de datos previsto (cómo usas los datos)

- Data is read only from the single institutional mailbox that an administrator
  explicitly connects. The app never accesses the personal mailboxes of end
  users.
- Message metadata and content are used solely to create and update
  correspondence records inside the organization's own workspace: filing code,
  sender, subject, date, attachments, assigned area and status.
- Data is stored in Cloud Firestore, segregated by company: each organization
  can only read its own records, enforced by security rules and role-based
  permissions.
- Data is never sold, never shared with third parties, never used for
  advertising, and never used to train machine-learning models.
- An administrator can disconnect the mailbox at any time from within the app,
  and any user can revoke the app's access from their Google Account security
  settings.
- Access tokens are stored encrypted and are only used by our Cloud Functions to
  perform the synchronization described above.

---

## 3. Video de demostración (lo tienes que grabar tú)

Súbelo a YouTube como **no listado**. Google exige que se vea, en este orden:

1. El **OAuth consent screen real**, con el nombre "To-Do", el logo, y el scope
   `gmail.readonly` visible en pantalla. Este es el punto que más rechazan si
   falta.
2. Cómo un administrador **conecta el buzón** desde la app (Correo → conectar
   cuenta).
3. Qué hace la app con los datos: la **bandeja sincronizada**, un mensaje
   convertido en registro de correspondencia con su código de radicado, y su
   asignación a un área.
4. Cómo se **desconecta** el buzón.

Habla o rotula en inglés. Dura entre 2 y 4 minutos; no hace falta producción.

---

## 4. Información adicional (campo de 1000 caracteres)

This app is distributed only to authorized client organizations; it is not a
consumer product and accounts cannot be self-created. Reviewers can sign in with
the demo account below, which uses a sample company with no real data.

Username: 900000001
Password: Review2025!

The Gmail integration is configured per organization by an administrator under
the "Correo" module. The demo company has no mailbox connected, so the OAuth
flow is shown in the demonstration video instead.

---

## 5. Lo que viene después, y conviene saberlo ya

`gmail.readonly` es un **scope restringido**. Además de esta verificación, Google
exige una **evaluación de seguridad anual por un tercero (CASA)**, que tiene
costo y toma semanas.

Mientras la app siga sin verificar, el consentimiento OAuth queda limitado a
**100 usuarios** y muestra la pantalla de "app no verificada".

Si el módulo de Correo no es indispensable a corto plazo, hay una salida: quitar
el scope de Gmail del proyecto deja la app fuera del régimen de scopes
restringidos y elimina el requisito de CASA. Es una decisión de producto, no
técnica.
