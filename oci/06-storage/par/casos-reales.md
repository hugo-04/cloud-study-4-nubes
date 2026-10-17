# Oracle OCI · Storage · PAR · Casos reales

## 1. El enlace que se reenvió
**Qué pasó:** un cliente reenvió el enlace de su comprobante a un grupo; meses después seguía funcionando.
**Causa:** PAR de lectura con vencimiento a un año.
**Arreglo:** PAR de 10 minutos generada al hacer clic en «descargar».
**Lección:** genera la PAR al momento de usarla, no al enviar el correo.

## 2. El socio que veía todo
**Qué pasó:** un proveedor de Café Andino podía listar y descargar archivos de otros proveedores.
**Causa:** PAR `AnyObjectReadWrite` sobre todo el bucket con listado permitido.
**Arreglo:** una PAR `AnyObjectWrite` por proveedor, limitada a su prefijo y sin listado.
**Lección:** el prefijo y el tipo de acceso son la frontera.

## 3. La URL en los registros
**Qué pasó:** una auditoría encontró URLs de PAR válidas en los registros de la aplicación.
**Causa:** se registraba la respuesta completa del servicio.
**Arreglo:** registrar solo el id y la expiración; enmascarar `/p/…/`.
**Lección:** una PAR es una credencial.

## 4. La foto con otro nombre
**Qué pasó:** un usuario subió un archivo enorme con un nombre que pisaba la imagen de otro producto.
**Causa:** PAR `AnyObjectWrite` y el cliente elegía el nombre.
**Arreglo:** PAR `ObjectWrite` para un nombre fijo generado por el backend y validación posterior.
**Lección:** el backend decide dónde se escribe.

## Resumen
| # | Síntoma | Causa | Arreglo |
|---|---|---|---|
| 1 | Enlace eterno | Vencimiento largo | PAR al momento, minutos |
| 2 | Acceso cruzado | `Any*` en todo el bucket | Prefijo por socio, sin listado |
| 3 | Credenciales en registros | Se registró la URL | Solo el id |
| 4 | Objeto pisado | Cliente elige nombre | `ObjectWrite` con nombre fijo |
