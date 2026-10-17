# AWS · API Gateway · Troubleshooting

Orden: **¿qué código devuelve? (401/403 = autorización; 429 = throttling; 5XX = integración) → logs de acceso con `requestId` → ¿ruta e integración correctas? → ¿autorizador (issuer, audience, caché)? → ¿permiso de invocación/VPC Link? → ¿timeout/tamaño?**

| Síntoma | Causa probable | Cómo comprobarlo | Solución |
|---|---|---|---|
| `401 Unauthorized` | Token ausente/expirado, `issuer` o `audience` no coinciden | Decodifica el JWT; configuración del autorizador | Alinear issuer/audience; renovar token |
| `403 Forbidden` | Autorizador Lambda niega, IAM sin `execute-api:Invoke`, WAF o política de recurso | Logs de acceso; política | Corregir permisos |
| `403 Missing Authentication Token` (REST) | Ruta o método inexistente (mensaje engañoso) | Rutas de la API | Corregir la URL/método |
| `404` | Ruta no definida o etapa incorrecta en la URL | Rutas y etapa | Añadir ruta; URL con etapa |
| `429 Too Many Requests` | Throttling de ruta/etapa/cuenta | Métricas `Count`, límites | Subir límite, caché, backoff en el cliente |
| `500` / `502` con Lambda | Excepción o respuesta con formato inválido (proxy) | Logs de Lambda | Devolver `statusCode`, `headers`, `body` correctos |
| `503` | Integración no disponible (VPC Link, backend caído) | Estado del VPC Link; destinos del ALB | Revisar SG y salud |
| `504 Endpoint request timed out` | La integración tardó más del límite | Duración del backend | Hacerlo asíncrono; optimizar |
| `413` | Carga mayor al límite | Tamaño | URL prefirmada a S3 |
| Error CORS en el navegador | Falta CORS o la respuesta de error no lo incluye | Cabeceras de la respuesta (OPTIONS) | Configurar CORS con orígenes explícitos |
| Lambda no se invoca desde la API | Falta `lambda:InvokeFunction` para `apigateway.amazonaws.com` | Política de recurso de la función | `aws_lambda_permission` con `source_arn` |
| Autorizador Lambda devuelve datos viejos | Caché del autorizador | TTL configurado | Reducir TTL / cambiar clave de caché |
| Dominio propio no resuelve | Falta mapeo, certificado o DNS alias | Dominio y mapeos | Crear mapeo y registro alias |
