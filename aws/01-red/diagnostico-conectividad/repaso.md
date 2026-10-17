# AWS · Diagnóstico de conectividad · Repaso

## Preguntas
1. ¿Reachability Analyzer envía paquetes?
   - *No; analiza la configuración.*
2. ¿Qué te dice un Flow Log `REJECT`?
   - *Que un SG o una NACL descartó ese tráfico.*
3. ¿Qué diferencia hay entre timeout y connection refused?
   - *Timeout: se descarta en silencio; refused: llegó y nadie escucha.*
4. ¿Cuál es el primer paso de cualquier diagnóstico?
   - *Resolver el nombre y comprobar a qué IP apunta.*
5. ¿Por qué los Flow Logs no explican todo?
   - *Tienen retraso, no capturan algunos tráficos y no guardan el contenido.*
6. ¿Qué métrica del NAT delata puertos agotados?
   - *`ErrorPortAllocation`.*
7. ¿Cómo entras a una tarea de Fargate sin abrir puertos?
   - *Con ECS Exec (SSM).*
8. ¿Para qué sirve Network Access Analyzer?
   - *Para encontrar caminos de acceso no deseados (p. ej., internet → bases).*
9. ¿Qué haces con un problema intermitente?
   - *Métricas (NAT, balanceador, pool); Reachability no lo ve.*
10. ¿Qué campos extra son útiles en un registro de flujo personalizado?
    - *`pkt-srcaddr`, `pkt-dstaddr`, `flow-direction`, `az-id`, `tcp-flags`.*

## Ejercicios
1. Crea un análisis «app → base:5432» y simula un fallo quitando una regla del SG.
2. Escribe una consulta de Logs Insights que muestre los `REJECT` hacia un destino.
3. Ejecuta `ConnCheck` contra un puerto abierto y otro cerrado y explica la diferencia.
4. Escribe tu runbook de 6 pasos para tu servicio.

## Autoevaluación
- [ ] Puedo recorrer la escalera de 6 peldaños.
- [ ] Sé qué ve cada herramienta y qué no.
- [ ] Sé entrar a probar sin abrir puertos.
- [ ] Tengo un análisis guardado para mi ruta más crítica.
