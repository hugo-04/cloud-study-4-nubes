# AWS · URLs prefirmadas · Troubleshooting

Orden: **¿caducó? → ¿cabeceras iguales a las firmadas? → ¿región y bucket correctos? → ¿permisos del firmante hoy? → ¿CORS? → ¿política de bucket (IP/VPCe)? → ¿KMS?**

| Síntoma | Causa probable | Cómo comprobarlo | Solución |
|---|---|---|---|
| `SignatureDoesNotMatch` | Cabecera distinta a la firmada, clave con caracteres sin codificar, reloj desfasado | Comparar `SignedHeaders` con lo enviado | Enviar exactamente las cabeceras devueltas; codificar la clave |
| `AccessDenied` / `Request has expired` | URL caducada o credenciales del rol expiradas | `X-Amz-Date` + `X-Amz-Expires` | URL nueva; caducidad efectiva |
| `AccessDenied` aunque no caducó | El firmante no tiene permiso hoy (o SCP/política lo niega) | Simulador de IAM con el rol firmante | Arreglar permisos del rol |
| Error CORS en el navegador | Falta origen/método/cabecera en CORS | Consola del navegador, respuesta del preflight | `AllowedOrigins`, `AllowedMethods`, `AllowedHeaders` exactos |
| `PermanentRedirect` / 307 | Firmaste con la región equivocada | Región del bucket | Presigner con la región del bucket |
| `AccessDenied` solo con KMS | Falta `kms:GenerateDataKey` al firmante | CloudTrail | Permiso de KMS al rol |
| La subida funciona pero el objeto no cumple | PUT no limita tamaño ni valida tipo | `head-object` | POST con política o validar tras subir |
| Descarga abre en vez de bajar | Sin `Content-Disposition` | Cabecera de respuesta | `response-content-disposition` firmado |
| `403` desde la red de la empresa | Política de bucket con `aws:SourceIp`/`SourceVpce` | Política | Excepción para el origen de los clientes |
| `InvalidAccessKeyId` | Clave del firmante rotada o borrada | IAM | Usar rol, no claves de larga duración |
| URL demasiado larga | Token de sesión + cabeceras | Longitud | Menos parámetros; considerar CloudFront |
