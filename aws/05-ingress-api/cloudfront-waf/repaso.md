# AWS · CloudFront y WAF · Repaso

## Preguntas
1. ¿Qué es la clave de caché y por qué importa?
   - *Lo que distingue una copia de otra; si incluye datos variables, nunca hay aciertos.*
2. ¿Qué hace OAC?
   - *Permite que solo CloudFront lea un bucket S3 privado.*
3. ¿Dónde debe estar el certificado de CloudFront?
   - *En ACM, región `us-east-1`.*
4. ¿Qué diferencia hay entre invalidar y versionar archivos?
   - *Invalidar borra copias; versionar (hash en el nombre) evita necesitar la invalidación.*
5. ¿Para qué sirve el modo Count de WAF?
   - *Probar reglas sin bloquear y medir falsos positivos.*
6. ¿Qué es una regla por tasa?
   - *Limita peticiones por IP en una ventana de tiempo.*
7. ¿Cómo proteges el origen?
   - *Prefix list de CloudFront en el SG, cabecera secreta y OAC en S3.*
8. ¿Qué es una URL firmada?
   - *Un enlace temporal con firma que da acceso a contenido privado.*
9. ¿Qué no se debe cachear?
   - *Respuestas personalizadas o privadas.*
10. ¿Cuándo usar WAF regional en vez de CloudFront?
    - *Cuando solo quieres proteger un ALB/API sin CDN.*

## Ejercicios
1. Define comportamientos para un SPA con API: rutas, políticas y TTL.
2. Diseña la regla por tasa para `/login` y la de reputación de IP, con plan de paso a Block.
3. Escribe la política del bucket para OAC.
4. Plantea la estrategia de caché y nombres para un frontend con despliegues diarios.

## Autoevaluación
- [ ] Sé construir una clave de caché mínima.
- [ ] Sé proteger el origen.
- [ ] Sé desplegar WAF sin romper tráfico legítimo.
- [ ] Sé emitir URLs firmadas seguras.
