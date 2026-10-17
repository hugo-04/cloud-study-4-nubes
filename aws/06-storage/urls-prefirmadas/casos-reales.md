# AWS · URLs prefirmadas · Casos reales

Historias de ModaLima y Café Andino (ficticias).

## 1. La API que se caía subiendo videos
**Qué pasó:** los videos de producto pasaban por la API (Spring MVC) y agotaban memoria y conexiones. **Solución:** URL prefirmada de PUT; la API solo firma (milisegundos) y S3 recibe los bytes. **Lección:** que los bytes no pasen por tu servicio.

## 2. «La URL funciona 10 minutos y se muere»
**Qué pasó:** se pedían URLs de 6 horas desde una tarea de ECS; dejaban de servir antes porque las credenciales del rol caducaban antes. **Solución:** calcular la caducidad efectiva y pedir URLs de 15 minutos. **Lección:** con roles, la sesión manda.

## 3. Archivos de 2 GB cuando se esperaban 5 MB
**Qué pasó:** un PUT prefirmado no limita tamaño; alguien subió un video enorme a un prefijo de avatares. **Solución:** POST prefirmado con `content-length-range` y regla de ciclo de vida para el prefijo temporal. **Lección:** el PUT no pone techo.

## 4. CORS: el navegador no sube
**Qué pasó:** la subida funcionaba con `curl` pero fallaba en el navegador con error de CORS. **Solución:** CORS del bucket con el origen exacto, método `PUT` y cabecera `Content-Type` permitida (y `ExposeHeaders: ETag`). **Lección:** el navegador exige permiso previo (preflight).

## 5. El enlace compartido por WhatsApp
**Qué pasó:** un cliente reenvió su enlace de descarga de factura y otra persona la vio. **Solución:** vida de 5 minutos, URL generada al hacer clic, `Content-Disposition` y registro de la solicitud. **Lección:** quien tiene el enlace tiene el permiso.

## 6. Firma inválida por un espacio
**Qué pasó:** el móvil enviaba `Content-Type: image/png; charset=utf-8` y la firma esperaba `image/png`. **Solución:** el backend devuelve las cabeceras a enviar y el cliente las copia sin modificar. **Lección:** cabecera firmada = cabecera exacta.

| Problema | Solución |
|---|---|
| La API saturada por bytes | PUT prefirmado directo a S3 |
| URL muere antes | Caducidad efectiva (sesión del rol) |
| Archivos enormes | POST con `content-length-range` |
| Error CORS | CORS exacto + `ExposeHeaders` |
| Enlace compartido | Vida corta + registro |
| `SignatureDoesNotMatch` | Cabeceras exactas |
