# AWS · STS y asumir roles · Casos reales

Historias de ModaLima y Café Andino (ficticias).

## 1. El SaaS y el delegado confundido
**Qué pasó:** una plataforma de analítica de Café Andino asumía roles en las cuentas de sus clientes. Un cliente descubrió que podía registrar el ARN del rol de otro cliente y ver sus datos. **Solución:** ExternalId único por cliente, generado por la plataforma. **Lección:** quien elige el ExternalId es el proveedor, no el cliente.

## 2. Llamar a `AssumeRole` en cada petición
**Qué pasó:** latencia de 300 ms extra y errores `Rate exceeded` en campañas. **Solución:** un proveedor de credenciales con caché y refresco asíncrono por rol. **Lección:** asume una vez, reutiliza hasta casi caducar.

## 3. La cadena de roles de 1 hora
**Qué pasó:** un proceso de larga duración falló a la hora exacta: asumía un rol desde un rol asumido y pidió 6 horas. **Solución:** refresco automático y duración ≤ 1 h en cadenas. **Lección:** el encadenamiento tiene su propio techo.

## 4. «¿Quién borró eso?»
**Qué pasó:** CloudTrail mostraba `session1` en todas las acciones. **Solución:** nombre de sesión con tenant y persona, e identidad de origen. **Lección:** el nombre de sesión es tu rastro de auditoría.

## 5. Confianza a `:root`
**Qué pasó:** el rol de lectura confiaba en toda la cuenta A; cualquier rol con `sts:AssumeRole` podía usarlo. **Solución:** confianza en un rol concreto y condición `aws:SourceAccount`. **Lección:** acota el principal.

## 6. El mensaje cifrado
**Qué pasó:** un `AccessDenied` con «Encoded authorization failure message» que nadie entendía. **Solución:** `aws sts decode-authorization-message` (con el permiso adecuado) mostró la política y la condición que fallaron. **Lección:** hay herramienta para leerlo.

| Problema | Solución |
|---|---|
| Delegado confundido | ExternalId único |
| Sobrecarga de STS | Proveedor con caché |
| Techo de cadena | Duración ≤ 1 h |
| Auditoría pobre | Nombre de sesión útil |
| Confianza amplia | Rol concreto |
| Error cifrado | `decode-authorization-message` |
