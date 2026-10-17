# AWS · S3 · Repaso

## Preguntas
1. ¿Qué es un objeto y qué es una clave?
   - *Datos + metadatos; la clave es su identificador completo (los «/» son solo parte del nombre).*
2. ¿S3 es un sistema de archivos?
   - *No: no hay renombrar, bloqueos ni append; para eso EFS.*
3. ¿Para qué sirve Block Public Access?
   - *Impedir acceso público por política o ACL, en cuenta y bucket.*
4. ¿Qué hace el versionado y qué riesgo trae?
   - *Conserva versiones y permite deshacer; sin ciclo de vida, el costo crece.*
5. ¿Qué dos autorizaciones hay con SSE-KMS?
   - *S3 (objeto) y KMS (generar/descifrar la clave de datos).*
6. ¿Cuándo usar multiparte?
   - *Archivos grandes (≥ ~100 MB) para paralelizar y reintentar por partes; obligatorio sobre 5 GiB.*
7. ¿Por qué el ETag no es siempre el MD5?
   - *En multiparte y con KMS es otro valor; usa checksums SHA-256/CRC.*
8. ¿Qué evita que dos procesos se pisen?
   - *Claves únicas o escritura condicional (`If-None-Match`/`If-Match`).*
9. ¿Qué se cobra además del almacenamiento?
   - *Solicitudes, transferencia a Internet, recuperación en clases frías, KMS.*
10. ¿Cómo sirves un sitio estático de forma privada?
    - *S3 privado + CloudFront con OAC.*

## Ejercicios
1. Escribe la política de bucket que niegue todo el tráfico sin TLS.
2. Diseña el ciclo de vida: IA a 30 días, expirar versiones no actuales a 60, abortar multipartes a 7.
3. Calcula el tamaño de parte para un archivo de 200 GiB sin pasar de 10 000 partes.
4. Define el prefijo y los permisos para que el servicio de facturas solo vea `facturas/{tenant}/`.

## Autoevaluación
- [ ] Sé crear un bucket privado, cifrado y con versionado.
- [ ] Sé escribir permisos mínimos por prefijo.
- [ ] Entiendo cuándo cuesta más el KMS que el almacenamiento.
- [ ] Sé diagnosticar un `AccessDenied` con KMS.
