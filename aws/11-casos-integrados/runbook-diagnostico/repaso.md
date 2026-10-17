# AWS · Caso integrado · Runbook de diagnóstico · Repaso

## Preguntas
1. ¿Por qué se mitiga antes de buscar la causa raíz?
2. ¿Qué cuatro roles tiene un incidente y qué no hace cada uno?
3. ¿Por qué «¿qué cambió?» es la primera pregunta técnica?
4. ¿Por qué el silencio (cero peticiones) es una alarma y no «todo bien»?
5. ¿Qué diferencia hay entre `ELB_5XX` y `Target_5XX`?
6. ¿Para qué sirve una alarma compuesta?
7. ¿Por qué ignorar el minuto en curso al calcular la tasa de errores?
8. ¿Qué limitaciones tiene CloudTrail `LookupEvents` para un incidente?
9. ¿Por qué la sonda corre con la identidad de la aplicación?
10. ¿Qué lleva un postmortem sin culpables?

## Respuestas
1. Porque cada minuto cuesta dinero y confianza; revertir o escalar reduce el daño ya, y el análisis puede esperar.
2. Comandante (decide, no teclea), operador (ejecuta, no decide riesgos solo), comunicación (informa, no especula), escriba (anota, no diagnostica).
3. Porque la mayoría de los incidentes siguen a un cambio, y revertirlo es la mitigación más segura.
4. Porque un fallo antes del balanceador (DNS, CDN, WAF) produce cero errores y cero tráfico; solo la ausencia lo delata.
5. `ELB_5XX` los genera el balanceador (sin destinos, saturado); `Target_5XX` los devuelve la aplicación.
6. Para recibir **una** página por incidente en vez de una por alarma, y expresar «la tienda no vende» como una condición.
7. Está incompleto: unos pocos eventos con muchos errores parecen una caída y generan falsas alarmas.
8. Retraso de hasta ~15 min, pocas llamadas por segundo y solo eventos de gestión de los últimos 90 días.
9. Para que la sonda vea lo mismo que la aplicación; con una identidad más poderosa la prueba mentiría.
10. Resumen, impacto, línea de tiempo, causas y factores, qué salió bien/mal, suerte, acciones con responsable y fecha, y cambios al runbook.

## Ejercicios
1. Configura la tasa de errores con umbral 2 % y simula 100 peticiones/min con 3 errores: ¿qué severidad da el triage? ¿y con 25 errores?
2. Escribe el patrón de filtro de métrica para contar las líneas `sonda.dependencia … ok=false`.
3. Redacta el mensaje de comunicación de los primeros 15 minutos de un incidente de severidad 1.
4. Diseña un simulacro: rompe el DNS privado de un endpoint en un entorno de prueba y mide cuánto tarda la guardia en llegar a la causa.

## Autoevaluación
- [ ] Puedo recitar los cinco primeros minutos sin mirar.
- [ ] Sé qué alarma salta con cero tráfico y con 5xx.
- [ ] Sé cuándo CloudTrail no me ayuda aún.
- [ ] Mi equipo tiene roles y un simulacro programado.
