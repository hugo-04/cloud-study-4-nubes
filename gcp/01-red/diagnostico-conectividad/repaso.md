# Google Cloud · Red · Diagnóstico de conectividad · Repaso

## Preguntas
1. ¿Qué hace Connectivity Tests?
2. ¿Qué registran los flow logs?
3. ¿Qué es una regla sombra?
4. ¿Qué diferencia hay entre timeout y rechazo?
5. ¿Cuál es el orden del método?
6. ¿Un 403 es un problema de red?
7. ¿Qué muestra Firewall Insights?
8. ¿Por qué muestrear flow logs?
9. ¿Qué permiso crea pruebas de conectividad?
10. ¿Dónde se ven los logs de firewall?

## Respuestas
1. Simula el camino del paquete y dice dónde se detiene.
2. Muestras de flujos con origen, destino, puertos y bytes.
3. Una regla tapada por otra de mayor prioridad.
4. Timeout suele ser firewall/ruta; rechazo, nada escucha.
5. DNS, ruta, firewall, intermedios, destino, TLS/IAM.
6. No; es IAM.
7. Reglas sin uso, sombra o demasiado amplias.
8. Por costo.
9. `roles/networkmanagement.admin`.
10. En Cloud Logging.

## Ejercicios
1. Escribe la prueba de conectividad de pedidos a Cloud SQL.
2. Diseña la consulta de flow logs para ver quién habla con el puerto 5432.
3. Arma el checklist de «no conecta» de ModaLima.
