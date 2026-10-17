# Oracle OCI · Red · Diagnóstico de conectividad · Repaso

## Preguntas
1. ¿Cuáles son los seis escalones y en qué orden?
2. ¿Qué indica un *timeout* frente a una conexión rechazada?
3. ¿Qué indica un 403?
4. ¿Para qué sirve Network Path Analyzer?
5. ¿Qué muestran los registros de flujo?
6. ¿Por qué probar desde el mismo lugar que falla?
7. ¿Qué es la ruta de vuelta?
8. ¿Qué causa fallos intermitentes frecuentes?
9. ¿Qué es Bastion?
10. ¿Qué haces después de resolver?

## Respuestas
1. DNS, ruta, seguridad, servicio/puerto, TLS, identidad.
2. *Timeout*: se descarta (ruta o seguridad); rechazo: llega y nadie escucha.
3. Problema de identidad o permisos, no de red.
4. Calcular el camino origen→destino sin enviar tráfico y ver dónde se corta.
5. Conexiones aceptadas o rechazadas por subred/VNIC.
6. Porque DNS, ruta e identidad dependen del origen.
7. El camino que debe tener la respuesta desde el destino.
8. Agotamiento de puertos de NAT, DNS, saturación y reintentos.
9. Servicio de sesiones temporales hacia recursos privados.
10. Documentar y actualizar el runbook.

## Ejercicios
1. Clasifica 6 síntomas dados en su escalón.
2. Escribe un runbook de 6 pasos para «no conecta a la base».
3. Habilita registros de flujo en una subred y busca un rechazo.
