# Oracle OCI · Storage · Claim check · Troubleshooting

## Lista ordenada
1. **¿El objeto existe?** `oci os object head` con el nombre del ticket.
2. **¿Huella distinta?** El objeto cambió o se leyó incompleto.
3. **¿Permisos del consumidor?** `read objects` en el bucket de cargas.
4. **¿Ciclo de vida demasiado corto?** Más corto que el tiempo máximo de reintento de la cola.
5. **¿Mensaje demasiado grande aun como ticket?** Revisa qué metadatos agregas.
6. **¿Huérfanos acumulados?** Productores que fallan tras subir: el ciclo de vida debe limpiarlos.

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| 404 al canjear | Orden invertido o ciclo de vida corto | Orden correcto; alarga retención |
| Huella no coincide | Objeto modificado | Investiga quién escribe; retención |
| 403/404 por permisos | Falta política | `read objects` |
| Mensaje rechazado | Tamaño | Umbral del sobre más bajo |
| Costo creciente | Huérfanos sin limpiar | Regla de ciclo de vida |
