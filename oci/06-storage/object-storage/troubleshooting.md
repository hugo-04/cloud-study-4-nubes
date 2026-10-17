# Oracle OCI · Storage · Object Storage · Troubleshooting

## Lista ordenada
1. **¿Namespace, bucket y región correctos?** El 404 más común es la región equivocada en el cliente.
2. **¿Política?** `manage objects` / `read objects` con la condición de bucket correcta.
3. **¿Red?** Desde subred privada: ruta a la puerta de servicios ("All services in Oracle Services Network").
4. **¿CMK?** Si el bucket usa tu llave, el servicio necesita `use keys` y la llave debe estar habilitada.
5. **¿`412 Precondition Failed`?** Tu `If-Match`/`If-None-Match` hizo su trabajo.
6. **¿Objeto en `Archive`?** Hay que restaurarlo antes de leerlo.
7. **¿Retención activa?** Impide borrar o sobrescribir.

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| 404 `BucketNotFound` | Región o namespace errados, o sin permiso | Revisa región; política |
| 409 al borrar bucket | Tiene objetos o PAR | Vacía primero |
| 412 | Condición no cumplida | Esperado: ya existe |
| 400 al leer | Objeto archivado | `RestoreObjects` |
| Timeout desde la VM | Sin ruta | Puerta de servicios / NAT |
| `KmsKeyDisabled` | Llave deshabilitada | Habilita la llave |
