# Oracle OCI · Ingress y API · WAF · Repaso

## Preguntas
1. ¿A qué recurso se adjunta el WAF regional?
2. ¿Qué tres módulos de petición tiene una política?
3. ¿Qué hace la acción `CHECK`?
4. ¿Qué es un falso positivo?
5. ¿Qué es una exclusión?
6. ¿En qué lenguaje se escriben las condiciones?
7. ¿Por qué empezar sin bloquear?
8. ¿Cómo se esquiva un WAF?
9. ¿El WAF autentica usuarios?
10. ¿Qué problema trae limitar por IP?

## Respuestas
1. Al Load Balancer de capa 7.
2. Control de acceso, límite de tasa y protecciones.
3. Registra la coincidencia sin bloquear.
4. Una petición legítima bloqueada.
5. Ignorar un argumento o cookie concreto en una protección.
6. JMESPATH.
7. Para descubrir falsos positivos sin afectar clientes.
8. Llegando al backend sin pasar por el LB.
9. No.
10. Muchas personas pueden compartir una IP (NAT).

## Ejercicios
1. Diseña las reglas de tasa de login, búsqueda y checkout de ModaLima.
2. Escribe una exclusión para el campo `comentario` de `/v1/resenas`.
3. Planifica el paso de `CHECK` a bloqueo con criterios de salida.
