# AWS · URLs prefirmadas · Repaso

## Preguntas
1. ¿Qué es una URL prefirmada?
   - *Enlace temporal a un objeto con la firma de quien lo creó.*
2. ¿Qué permisos tiene?
   - *Los del firmante en el momento de usarla, solo para la operación firmada.*
3. ¿Hasta cuándo es válida con un rol?
   - *Hasta lo pedido o hasta que caduque la sesión del rol, lo que ocurra primero.*
4. ¿Cómo limito el tamaño de una subida?
   - *POST prefirmado con `content-length-range` (el PUT no puede), o validar después.*
5. ¿Por qué falla `SignatureDoesNotMatch` con un `Content-Type` distinto?
   - *Está firmado: el cliente debe enviar el valor exacto.*
6. ¿Quién debe elegir la clave del objeto?
   - *El backend, no el cliente.*
7. ¿Qué es CORS y cuándo hace falta?
   - *Permiso del bucket para peticiones desde el navegador a otro origen.*
8. ¿Por qué no registrar la URL?
   - *Es un secreto temporal: quien la lea puede usarla.*
9. ¿Cuándo usar CloudFront en vez de URL de S3?
   - *Muchas descargas o usuarios globales: caché y URLs firmadas del borde.*
10. ¿Cómo sabes que lo subido es correcto?
    - *Evento/confirmación + validación de tamaño, tipo y checksum.*

## Ejercicios
1. Diseña el endpoint `POST /uploads` con validación de tipo y tamaño.
2. Escribe la política de CORS para `https://app.modalima.com`.
3. Calcula la caducidad efectiva con una sesión que expira en 12 minutos y una petición de 1 hora.
4. Describe cómo forzar el nombre de descarga `factura-001.pdf`.

## Autoevaluación
- [ ] Sé firmar PUT y GET con el SDK.
- [ ] Sé cuándo usar POST con política.
- [ ] Entiendo por qué las cabeceras deben coincidir.
- [ ] Sé configurar CORS y diagnosticar un error de firma.
