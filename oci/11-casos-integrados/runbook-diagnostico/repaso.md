# Oracle OCI · Caso integrado · Runbook de diagnóstico · Repaso

## Preguntas
1. ¿Qué roles hay en un incidente?
2. ¿Qué se hace en los primeros cinco minutos?
3. ¿Cuál es el orden de la cadena de capas?
4. ¿Qué es una alarma por síntoma?
5. ¿Para qué una sonda sintética?
6. ¿Cuál es la mitigación de menor riesgo?
7. ¿Por qué mitigar antes de la causa raíz?
8. ¿Qué es un postmortem sin culpables?
9. ¿Qué métricas del LB miras primero?
10. ¿Qué significa «no se pudo comprobar» en el triage?

## Respuestas
1. Coordinador, comunicación, operadores y escriba.
2. Declarar, confirmar impacto, preguntar qué cambió, triage y mitigar.
3. DNS/WAF, LB, Ingress/pods, dependencias, cambios.
4. Una alerta sobre lo que percibe el cliente.
5. Detectar fallos aunque no haya tráfico real o métricas engañen.
6. Revertir el último despliegue.
7. Porque el impacto al cliente importa más que entender todo de inmediato.
8. Un análisis del sistema que produce acciones, sin culpar personas.
9. Tasa de 5xx, latencia y salud de backends.
10. Que falta información: se trata como hallazgo.

## Ejercicios
1. Escribe la alarma de tasa de 5xx > 2 % en 5 minutos.
2. Diseña la sonda sintética del checkout.
3. Escribe la plantilla de postmortem de ModaLima.
