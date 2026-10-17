# AWS · ALB y NLB · Repaso

## Preguntas
1. ¿Diferencia principal entre ALB y NLB?
   - *ALB enruta HTTP por contenido (capa 7); NLB reenvía TCP/UDP (capa 4) con IP estable.*
2. ¿Qué es un target group?
   - *El conjunto de destinos y la forma de comprobar su salud.*
3. ¿Por qué el keep-alive de la app debe ser mayor que el idle timeout del ALB?
   - *Para que el balanceador nunca reutilice una conexión que la app ya cerró (502).*
4. ¿Qué hace el deregistration delay?
   - *Da tiempo a terminar peticiones antes de retirar el destino.*
5. ¿Cómo obtienes la IP real del cliente detrás de un ALB?
   - *De `X-Forwarded-For`, confiando solo en el balanceador.*
6. ¿Para qué sirve SNI?
   - *Servir varios certificados en el mismo listener.*
7. ¿Cuándo elegir NLB?
   - *IP fija, TCP/UDP, PrivateLink o rendimiento extremo.*
8. ¿Qué es un 502 frente a un 503 y un 504?
   - *Respuesta inválida/conexión cerrada; sin destinos sanos; tiempo agotado.*
9. ¿Por qué un ALB compartido?
   - *Reduce costo fijo; las reglas separan servicios.*
10. ¿Cómo haces un despliegue gradual con el ALB?
    - *Pesos entre dos target groups.*

## Ejercicios
1. Diseña las reglas de un ALB para tres microservicios en un dominio.
2. Calcula timeouts coherentes: keep-alive, idle timeout, deregistration delay, stopTimeout.
3. Escribe el health check de un servicio con base de datos.
4. Plantea una migración 90/10 → 50/50 → 0/100 con pesos.

## Autoevaluación
- [ ] Sé elegir entre ALB y NLB.
- [ ] Sé diagnosticar 502/503/504.
- [ ] Sé alinear timeouts y apagado.
- [ ] Sé obtener la IP real del cliente de forma segura.
