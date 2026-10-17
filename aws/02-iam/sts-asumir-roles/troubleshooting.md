# AWS · STS y asumir roles · Troubleshooting

Orden: **¿quién soy (`get-caller-identity`)? → ¿el origen tiene `sts:AssumeRole` sobre ese ARN? → ¿la confianza del destino incluye al origen y cumple condiciones (ExternalId, MFA, cuenta)? → ¿SCP o límite recortan? → ¿la sesión caducó?**

| Síntoma | Causa probable | Cómo comprobarlo | Solución |
|---|---|---|---|
| `AccessDenied` al asumir (`not authorized to perform: sts:AssumeRole`) | Falta permiso en el origen **o** confianza en el destino | Ambas políticas | Añadir las dos mitades |
| `AccessDenied` con ExternalId | No coincide o falta | Condición `sts:ExternalId` en la confianza | Enviar el valor correcto |
| `ExpiredToken` / `The security token included in the request is expired` | Sesión caducada | `Expiration` | Renovar; refresco automático |
| `ValidationError` en `RoleSessionName` | Caracteres no permitidos o longitud | Nombre de sesión | Solo `[\w+=,.@-]`, 2–64 |
| `DurationSeconds exceeds the MaxSessionDuration` | Pedí más que el máximo del rol | Máximo del rol | Subir el máximo o pedir menos |
| `Role chaining limited to 1 hour` | Cadena de roles | Origen de las credenciales | ≤ 3600 s |
| `Rate exceeded` en STS | Demasiadas llamadas | Métricas | Caché de credenciales |
| Funciona en la CLI y no en Java | Perfil/cadena de proveedores distinta | Orden del proveedor | Fijar el proveedor explícito |
| `InvalidIdentityToken` (web identity) | Token/OIDC mal configurado | Emisor, audiencia, expiración | Ver capítulo IRSA / OIDC |
| El mensaje es ilegible (`Encoded authorization failure message`) | Mensaje cifrado | — | `aws sts decode-authorization-message` |
| Región: `The security token ... is not valid for this region` | Credenciales de endpoint global en regiones opt-in | Endpoint de STS | Usar STS regional |
| Las acciones aparecen con el nombre de sesión equivocado | Cadena sin nombre propio | CloudTrail | Nombre de sesión explícito |
