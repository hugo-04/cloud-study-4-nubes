# Azure · Caso integrado · Runbook de diagnóstico · Repaso

## Preguntas
1. ¿Qué es un runbook y por qué se escribe antes del incidente?
   - *Un procedimiento probado; en pleno incidente no se improvisa.*
2. ¿Por qué «mitigar primero, investigar después»?
   - *Cada minuto cuesta ventas; el rollback o escalar reducen el daño ya.*
3. ¿Cuál es la primera pregunta en un incidente?
   - *«¿Qué cambió?» (despliegues, reglas, certificados, secretos, tráfico).*
4. ¿Qué roles hay y por qué separarlos?
   - *Comandante, operador, comunicación y escriba; evita que todos hagan todo.*
5. ¿Cómo sirve la escalera RPDSI?
   - *Convierte un «no conecta» en un escalón concreto: DNS, ruta/puerto, TLS, identidad.*
6. ¿Qué diferencia hay entre un `403` y un `timeout`?
   - *El `403` ya llegó (identidad o permiso); el `timeout` ni siquiera llegó (ruta o firewall).*
7. ¿Qué aporta la sonda sintética que una consulta no da?
   - *Lo que ve la aplicación desde su pod, con su red e identidad.*
8. ¿Por qué se alerta por síntoma y no por causa?
   - *El síntoma es lo que siente el cliente y no depende de adivinar la causa.*
9. ¿Qué hacer con la cola de mensajes fallidos?
   - *Alertar, leer el motivo, corregir y reprocesar con procedimiento.*
10. ¿Qué es un acceso de emergencia y cómo se controla?
    - *Permisos elevados con aprobación, motivo y caducidad automática.*
11. ¿Qué debe tener un buen postmortem?
    - *Línea de tiempo, causa y factores, qué salió bien/mal y acciones con responsable y fecha, sin culpables.*
12. ¿Por qué ensayar el runbook?
    - *Para descubrir pasos rotos y medir tiempos antes del incidente real.*

## Ejercicios
1. Escribe el runbook de «el login con Entra ID falla» siguiendo el formato de la sección 2.4.
2. Define tres alertas por síntoma para tu servicio y su umbral.
3. Diseña un simulacro: ¿qué rompes, qué esperas que pase y qué mides?
4. Añade a la sonda una dependencia nueva (Redis) y decide su expectativa de red.
5. Redacta el primer aviso a clientes (3 líneas, sin especular).

## Autoevaluación
- [ ] Recito los primeros cinco minutos.
- [ ] Sé leer un síntoma y ubicar el escalón.
- [ ] Sé qué mitigaciones existen y su riesgo.
- [ ] Sé qué contiene un postmortem útil.
