# Oracle OCI · Caso integrado · Runbook de diagnóstico · Casos reales

## 1. El Cyber de las 21:07
**Qué pasó:** errores 502 del 12 % en checkout.
**Causa:** un despliegue de las 20:55 cambió la ruta del chequeo de salud; la mitad de los pods quedó fuera del LB.
**Arreglo:** revertir el despliegue (mitigación 1) en 4 minutos; luego corregir la ruta.
**Lección:** «¿qué cambió?» resuelve la mayoría de incidentes.

## 2. La alarma que no sonó
**Qué pasó:** clientes reportaron errores 40 minutos antes que la guardia.
**Causa:** alarma sobre CPU, no sobre errores; la CPU estaba normal.
**Arreglo:** alarmas sobre tasa de 5xx y latencia del LB, y sonda sintética.
**Lección:** alarma lo que sufre el cliente.

## 3. Todos tecleando a la vez
**Qué pasó:** tres ingenieros reiniciaban servicios distintos sin coordinarse.
**Causa:** sin roles.
**Arreglo:** coordinador que asigna; un cambio a la vez, anunciado en el canal.
**Lección:** en un incidente, el orden vale más que la velocidad.

## 4. El postmortem que buscaba culpables
**Qué pasó:** tras un incidente en Café Andino, nadie quería admitir errores y se repitió el problema.
**Causa:** postmortem centrado en personas.
**Arreglo:** formato sin culpables con acciones del sistema (pruebas, alarmas, guardarraíles).
**Lección:** se corrige el sistema, no la persona.

## Resumen
| # | Síntoma | Causa | Arreglo |
|---|---|---|---|
| 1 | 502 masivos | Despliegue | Revertir primero |
| 2 | Aviso tardío | Alarma por CPU | Alarma por síntoma + sonda |
| 3 | Caos | Sin roles | Coordinador |
| 4 | Repetición | Culpa | Postmortem sin culpables |
