# Azure · Managed Identity · Casos reales

## Caso 1 · La clave del storage en el repositorio
- **Problema:** la API de ModaLima leía imágenes con la clave de la cuenta, guardada en la configuración y en el repositorio.
- **Solución:** identidad administrada en la aplicación + *Storage Blob Data Reader* + `shared_access_key_enabled = false`.
- **Resultado:** cero secretos en Git y nada que rotar.
- **Lección:** la mejor clave es la que no existe.

## Caso 2 · Carrera de despliegue con system-assigned
- **Problema:** Terraform creaba un Container App y, en el mismo despliegue, la asignación de rol de su identidad. A veces la app arrancaba antes de que el rol se propagara y fallaba al leer secretos.
- **Solución:** cambiar a identidad **user-assigned** creada y con roles asignados **antes** del Container App.
- **Lección:** user-assigned permite ordenar bien el despliegue.

## Caso 3 · Dos identidades y la equivocada
- **Problema:** una App Service tenía dos identidades user-assigned y el código recibía 403.
- **Causa:** `DefaultAzureCredential` sin `client_id` eligió la identidad incorrecta (la que no tenía roles).
- **Solución:** fijar `AZURE_CLIENT_ID` (o `managedIdentityClientId`).
- **Lección:** con varias identidades, siempre especifica cuál.

## Caso 4 · "En mi laptop no funciona"
- **Problema:** el código funcionaba en Azure, pero fallaba en local con `ManagedIdentityCredential authentication unavailable`.
- **Causa:** el desarrollador usaba `ManagedIdentityCredential` directamente; en local no existe.
- **Solución:** `DefaultAzureCredential`, que en local cae a `az login`.
- **Lección:** usa la credencial encadenada, no una fija, salvo que quieras forzar el comportamiento.

## Caso 5 · Base de datos sin contraseña
- **Problema:** la cadena de conexión a PostgreSQL tenía contraseña en variables de entorno.
- **Solución:** usuario de base de datos ligado a la identidad administrada y token de Entra ID como contraseña (plugin de autenticación del driver).
- **Lección:** también las bases de datos pueden ir sin contraseña estática.

## Caso 6 · Identidad comodín
- **Problema:** una sola identidad "app-general" con Contributor en toda la suscripción servía a 12 servicios. Un fallo en uno comprometía a todos.
- **Solución:** una identidad por servicio con roles de datos mínimos.
- **Lección:** el radio de impacto se reduce separando identidades.
