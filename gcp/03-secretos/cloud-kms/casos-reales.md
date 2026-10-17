# Google Cloud · Secretos · Cloud KMS · Casos reales

## 1. El límite de operaciones
**Qué pasó:** la exportación nocturna de ModaLima fallaba con errores de cuota de KMS.
**Causa:** se llamaba a `Encrypt` por cada fila.
**Arreglo:** cifrado de sobre: una DEK por lote, una llamada a KMS por lote.
**Lección:** KMS cifra llaves, tú cifras datos.

## 2. El bucket que dejó de leerse
**Qué pasó:** tras un cambio de permisos, Cloud Storage no podía leer objetos CMEK.
**Causa:** se quitó el rol al agente de servicio de Cloud Storage sobre la llave.
**Arreglo:** restaurar `cryptoKeyEncrypterDecrypter` al agente y gestionar ese binding en Terraform.
**Lección:** CMEK depende de un permiso que no es de tu app.

## 3. Datos cifrados intercambiables
**Qué pasó:** un atacante copió el documento cifrado de un cliente al registro de otro y se descifró sin error.
**Causa:** sin AAD.
**Arreglo:** AAD con el id del cliente.
**Lección:** ata el cifrado a su contexto.

## 4. La destrucción que borró el historial
**Qué pasó:** Café Andino destruyó una versión «vieja» y perdió facturas de hace dos años.
**Causa:** las facturas seguían cifradas con esa versión.
**Arreglo:** re-cifrado periódico antes de retirar versiones; destrucción programada con revisión.
**Lección:** las versiones viejas descifran lo viejo.

## Resumen
| # | Síntoma | Causa | Arreglo |
|---|---|---|---|
| 1 | Cuota agotada | `Encrypt` por fila | Sobre |
| 2 | Bucket ilegible | Agente sin rol | Restaurar binding |
| 3 | Sustitución | Sin AAD | AAD |
| 4 | Datos perdidos | Versión destruida | Re-cifrar antes |
