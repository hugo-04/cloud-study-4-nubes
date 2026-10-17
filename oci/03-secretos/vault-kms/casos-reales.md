# Oracle OCI · Secretos · Vault: llaves (KMS) · Casos reales

## 1. La llave borrada de verdad
**Qué pasó:** se programó el borrado de una llave «sin uso» y semanas después falló un respaldo.
**Causa:** el respaldo estaba cifrado con ella; nadie lo sabía.
**Arreglo:** cancelar el borrado dentro de la ventana.
**Lección:** antes de borrar, busca qué depende de la llave.

## 2. `Encrypt` para un PDF
**Qué pasó:** error al cifrar comprobantes de MB.
**Causa:** `Encrypt` directo tiene límite pequeño.
**Arreglo:** cifrado de sobre con AES-GCM local.
**Lección:** Vault cifra llaves; los datos los cifras tú.

## 3. Datos copiados entre filas
**Qué pasó:** alguien copió el campo cifrado de un cliente a otro y la app lo descifró.
**Causa:** sin AAD.
**Arreglo:** AAD con el id del registro.
**Lección:** ata el cifrado a su contexto.

## 4. Rotación sin miedo
**Qué pasó:** se rotó la llave y nada se rompió.
**Causa del éxito:** la llave envuelta guarda su versión y las anteriores siguen vigentes.
**Lección:** rotar es seguro; borrar versiones no.

## Resumen
| # | Síntoma | Causa | Arreglo |
|---|---|---|---|
| 1 | Respaldo ilegible | Borrado de llave en uso | Cancelar y auditar |
| 2 | Error de tamaño | `Encrypt` directo | Sobre |
| 3 | Dato intercambiable | Sin AAD | AAD por registro |
| 4 | Sin impacto | Versiones | Rotar periódicamente |
