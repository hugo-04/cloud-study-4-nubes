# AWS · STS y asumir roles · Repaso

## Preguntas
1. ¿Qué recibes al asumir un rol?
   - *Clave de acceso, clave secreta, token de sesión y fecha de caducidad.*
2. ¿Qué dos políticas hacen falta entre cuentas?
   - *Permiso `sts:AssumeRole` en el origen y confianza en el destino.*
3. ¿Qué problema resuelve el ExternalId?
   - *El delegado confundido en escenarios con terceros.*
4. ¿Cuánto dura una sesión encadenada?
   - *Máximo 1 hora.*
5. ¿Por qué darle un nombre útil a la sesión?
   - *Aparece en CloudTrail y permite auditar.*
6. ¿Cómo evitas llamar a STS en cada petición?
   - *Proveedor de credenciales con caché y refresco.*
7. ¿Cómo «revocas» una sesión ya emitida?
   - *Denegando por `aws:TokenIssueTime` y esperando a que caduque.*
8. ¿Qué operación te dice quién eres?
   - *`GetCallerIdentity`.*
9. ¿Cuándo NO debes asumir un rol manualmente?
   - *Cuando tu servicio ya tiene un rol de tarea/IRSA.*
10. ¿Qué hace `DecodeAuthorizationMessage`?
    - *Descifra el motivo detallado de un AccessDenied.*

## Ejercicios
1. Crea un rol de lectura en una cuenta B que confíe en un rol concreto de A.
2. Configura un perfil de CLI con `role_arn` y `source_profile`.
3. Escribe la confianza de un rol para un tercero con ExternalId.
4. Calcula cuántas llamadas a STS ahorras con un proveedor con caché a 1000 req/s.

## Autoevaluación
- [ ] Sé las dos mitades de una asunción entre cuentas.
- [ ] Sé cuándo usar ExternalId.
- [ ] Sé que las credenciales se refrescan solas.
- [ ] Sé depurar un `AccessDenied` de STS.
