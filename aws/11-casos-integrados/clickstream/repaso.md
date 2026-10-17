# AWS · Caso integrado · Clickstream · Repaso

## Preguntas
1. ¿Qué hace una clave de partición y por qué importa elegirla bien?
2. ¿Qué es una clave caliente y cómo se detecta?
3. ¿Por qué `PutRecords` puede devolver 200 con fallos?
4. ¿Qué diferencia hay entre hora del evento y hora de llegada?
5. ¿Qué es una marca de agua?
6. ¿Por qué el checkpoint debe ir «hasta el punto seguro»?
7. ¿Por qué `PutItem` y no `ADD` para las métricas?
8. ¿Por qué un agregador por shard?
9. ¿Cuándo bajo demanda y cuándo provisionado?
10. ¿Cómo se maneja un registro inválido?

## Respuestas
1. Decide el shard (MD5 de la clave); un mal reparto satura carriles.
2. Una clave que concentra tráfico; se ve como estrangulamiento en un shard con el total bajo.
3. La respuesta trae un resultado por registro; hay que reintentar solo los fallidos.
4. Cuándo ocurrió vs cuándo se recibió; se agrega por la primera.
5. Umbral que dice «ya no espero eventos más viejos»; cierra ventanas.
6. Porque las ventanas abiertas viven en memoria; si se cae el proceso hay que releer desde su inicio.
7. Reprocesar con `ADD` duplica; `PutItem` por clave deja el mismo resultado.
8. Mantiene el estado simple y las sesiones únicas se suman sin doble conteo (una sesión vive en un shard).
9. Bajo demanda para carga irregular o desconocida; provisionado para carga estable y medida.
10. Se cuenta, se salta y se guarda una muestra; nunca detiene el shard.

## Ejercicios
1. Con 1200 clics/s de 600 bytes, 3 consumidores compartiendo lectura: ¿cuántos shards?
2. Simula el reparto con clave `pagina` vs `idSesion` (20 páginas, 5000 sesiones).
3. Cambia la ventana a 5 minutos y la latencia permitida a 10: ¿qué cambia en el punto seguro?
4. Escribe la consulta de Athena que corrige las métricas de ayer.

## Autoevaluación
- [ ] Sé elegir una clave de partición y justificarla.
- [ ] Puedo explicar punto seguro de checkpoint.
- [ ] Diagnostico atraso, estrangulamiento y lotes repetidos.
