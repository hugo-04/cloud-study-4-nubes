# Azure · SAS tokens · Casos reales

(ModaLima y Café Andino son empresas inventadas para estudiar.)

## Caso 1 · Subida directa de fotos de producto
- **Problema:** las fotos pasaban por la API y la saturaban (CPU y ancho de banda).
- **Solución:** la API genera una **SAS de escritura de 10 minutos** a un nombre con UUID; el navegador sube directo al storage; luego avisa a la API para confirmar.
- **Resultado:** la API dejó de ser el cuello de botella; la subida usa bloques paralelos del navegador.
- **Lección:** el archivo viaja por el storage, no por tu backend.

## Caso 2 · Boleta en PDF con enlace temporal
- **Problema:** enviar boletas por correo como adjuntos exponía datos y llenaba buzones.
- **Solución:** el correo trae un enlace a tu sitio; al hacer clic, tras validar la sesión, la API genera una **SAS de lectura de 5 minutos** y redirige (con `rscd` para nombrar el archivo).
- **Lección:** mejor generar la URL **al momento del clic** que enviarla por correo con vigencia larga.

## Caso 3 · Proveedor externo que sube un CSV diario
- **Problema:** el proveedor usaba la clave de la cuenta compartida por correo.
- **Solución:** SAS de servicio con **política almacenada** (permiso `cw`, prefijo del proveedor, renovación semanal) y restricción por IP; análisis del archivo antes de moverlo a la zona de procesamiento. Si hay incidente, se borra la política y todo queda revocado.
- **Lección:** acceso externo = mínimo, con vencimiento, revocable y con revisión del contenido.

## Caso 4 · Archivos de 2 GB desde el navegador
- **Problema:** subidas grandes fallaban a mitad y volvían a empezar.
- **Solución:** el navegador divide en bloques de 8 MiB, sube en paralelo con `Put Block` usando la misma SAS (`cw`, 60 min) y confirma con `Put Block List`; reintenta solo los bloques fallidos.
- **Lección:** SAS más ventana razonable para el tamaño; los bloques hacen robusta la subida.

## Caso 5 · "403 AuthenticationFailed" misterioso
- **Problema:** SAS recién generadas fallaban al azar.
- **Causa:** `st` (inicio) igual a la hora actual del servidor y relojes desfasados unos segundos.
- **Solución:** quitar `st` o poner el inicio 5 minutos atrás.
- **Lección:** el desfase de reloj existe; no uses inicio exacto.

## Caso 6 · SAS que dejó de funcionar sola
- **Problema:** varias SAS de delegación vigentes fallaron a mitad del día con 403.
- **Causa:** se quitó el rol *Storage Blob Data Contributor* a la identidad firmante durante una limpieza de permisos.
- **Solución:** restaurar el rol; documentar que la SAS de delegación depende del permiso del firmante.
- **Lección:** acceso efectivo = SAS ∩ permisos del firmante.

## Caso 7 · La URL en los logs
- **Problema:** un APM registraba las URLs completas y quedaron SAS de lectura en el sistema de observabilidad.
- **Solución:** enmascarar el parámetro `sig` y `sp` en los logs, SAS de 5 minutos, y revisión de accesos con `AuthenticationType = SAS`.
- **Lección:** una URL firmada es un secreto temporal; trátala como tal en trazas.

## Caso 8 · Revocación de emergencia
- **Problema:** se filtró un enlace de descarga con SAS de 1 hora hacía 10 minutos.
- **Solución:** como era de **delegación**, se ejecutó `revoke-delegation-keys` (invalida todas las SAS de delegación) y se emitieron nuevas; para terceros se usa política almacenada.
- **Lección:** planifica la revocación **antes** de necesitarla; una SAS ad hoc no se puede revocar sola.

## Caso 9 · Subida de 5 GB de basura
- **Problema:** un usuario subió un archivo enorme con la SAS de escritura y disparó el costo.
- **Causa:** una SAS no limita el tamaño.
- **Solución:** evento `BlobCreated` → función que comprueba tamaño/tipo y **borra** lo que excede; cuota por usuario en la API; ventana de SAS corta.
- **Lección:** la validación de tamaño ocurre **después**; diséñala.

## Caso 10 · SAS en una cuenta privada
- **Problema:** usuarios en casa recibían timeout al subir.
- **Causa:** la cuenta tenía solo Private Endpoint.
- **Solución:** un endpoint de subida público restringido (otra cuenta, solo `subidas/`, con análisis) y movimiento a la cuenta privada tras validar.
- **Lección:** la SAS no cambia la red: el cliente debe poder llegar al endpoint.

## Caso 11 · Descarga con nombre correcto
- **Problema:** los PDF se descargaban como `0f1a…uuid` sin extensión.
- **Solución:** parámetro `rscd` (`attachment; filename="boleta-123.pdf"`) y `rsct` en la SAS.
- **Lección:** los nombres internos (UUID) no tienen por qué ser los que ve el usuario.
