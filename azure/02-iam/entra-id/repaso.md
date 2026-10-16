# Azure · Entra ID · Repaso

## Preguntas de repaso
1. ¿Qué diferencia hay entre autenticación y autorización?
   - *Autenticación: probar quién eres. Autorización: decidir qué puedes hacer.*
2. ¿Qué diferencia hay entre una app registration y un service principal?
   - *La primera es la definición de la app; el segundo es su instancia con permisos en un tenant.*
3. ¿Qué flujo OAuth usa un microservicio que llama a otro sin usuario?
   - *Client credentials (o managed identity).*
4. ¿Qué claim valida que el token sea para tu API?
   - *`aud` (audiencia).*
5. ¿Cuándo usas scopes (`scp`) y cuándo app roles (`roles`)?
   - *Scopes para tokens delegados con usuario; app roles para permisos de la aplicación.*
6. ¿Qué es el consentimiento de administrador?
   - *Aprobación del admin para que una app use permisos sensibles en nombre de todos o por sí misma.*
7. ¿Ser Global Administrator te da acceso a las suscripciones?
   - *No; los roles de Entra y de Azure RBAC son mundos distintos.*
8. ¿Por qué evitar el flujo de contraseña (ROPC)?
   - *Expone credenciales a la app y no soporta MFA ni acceso condicional.*

## Entrevista
- Diseña la autenticación entre tres microservicios y un frontend con Entra ID.
- Un token válido da 401 en tu API: ¿qué claims revisas?
- ¿Cómo evitas secretos que vencen y rompen producción?
