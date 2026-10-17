# Oracle OCI · Datos · NoSQL · Troubleshooting

## Lista ordenada
1. **¿Tabla `ACTIVE`?** Cambios de capacidad o esquema la ponen en `UPDATING`.
2. **¿Política?** `use nosql-rows` en el compartimento/tabla.
3. **¿Clave completa?** `getRow` necesita todas las columnas de la clave primaria.
4. **¿Throttling?** Métricas de unidades consumidas vs provisionadas.
5. **¿Escritura condicional fallida?** La versión cambió: relee.
6. **¿Fila demasiado grande?** Límite de tamaño de fila.

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| 404 de tabla | Nombre/compartimento | Usa OCID o compartimento correcto |
| `IllegalArgument` en clave | Clave incompleta | Todas las columnas de la PK |
| 429 / *throttling* | Capacidad o consultas | Sube unidades / quita escaneos |
| Escritura no aplicada | Versión distinta | Releer y reintentar |
| Filas que desaparecen | TTL | Renueva TTL al escribir |
