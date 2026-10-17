# Oracle OCI · Storage · Eventos de Object Storage · Troubleshooting

## Lista ordenada
1. **¿Eventos activos en el bucket?** `oci os bucket get --query 'data."object-events-enabled"'`.
2. **¿Regla activa y condición correcta?** Tipo exacto (`com.oraclecloud.objectstorage.createobject`) y `bucketName`.
3. **¿Compartimento?** La regla vive en un compartimento y ve eventos de ese y sus hijos.
4. **¿Política del servicio Events hacia el destino?** (`fn-invocation`, `ons-topics`, `stream-push`).
5. **¿El destino recibió y falló?** Registros de la función o del tema.
6. **¿Duplicados?** Normal: deduplica.
7. **¿Ciclo?** Revisa si el consumidor escribe en el origen.

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| Nada llega | Eventos del bucket apagados o condición errónea | Activa / corrige JSON |
| Llega a Notifications pero no a la función | Falta política de servicio | `use fn-invocation` |
| Procesamiento doble | Reentrega | Idempotencia |
| Invocaciones descontroladas | Ciclo de eventos | Destino distinto |
| 404 al leer el objeto | Borrado antes de procesar | `HEAD` y descartar |
