# AWS · KMS · Casos reales

Historias de ModaLima y Café Andino (ficticias).

## 1. La clave borrada «por limpieza»
**Qué pasó:** alguien programó el borrado de una clave que «nadie usaba»; 30 días después, un bucket de archivo histórico dejó de poder descifrarse. **Solución:** restaurar desde un respaldo en otra cuenta; desde entonces, `DisableKey` primero, alarma ante `ScheduleKeyDeletion` y revisión de uso (CloudTrail) antes de borrar. **Lección:** borrar una clave borra los datos.

## 2. Throttling en la campaña
**Qué pasó:** una campaña subió 10 000 objetos por segundo a S3 con SSE-KMS y KMS devolvió `ThrottlingException`. **Solución:** **S3 Bucket Keys** (reducen las llamadas a KMS hasta en ~99 %). **Lección:** las cuotas de KMS son compartidas por región.

## 3. El cifrado sin contexto
**Qué pasó:** un campo cifrado de un cliente se pudo descifrar al pegarlo en la fila de otro cliente. **Solución:** contexto de cifrado `{tenant, tabla, id}` en cada operación: el descifrado falla si cambia. **Lección:** el contexto ata el dato a su dueño.

## 4. La clave que no se podía compartir
**Qué pasó:** se cifraron datos con `aws/s3` y la cuenta de analítica no podía leerlos. **Solución:** CMK propia con política que permite a esa cuenta, y re-cifrado de los objetos. **Lección:** para compartir, CMK desde el día uno.

## 5. Administrador que también descifraba
**Qué pasó:** un rol con `kms:*` administraba y usaba una clave de datos de clientes. **Solución:** separar administradores (sin `Decrypt`) de usuarios (solo `Decrypt` con `kms:ViaService`). **Lección:** separación de funciones.

## 6. Recuperación ante desastres con multi-región
**Qué pasó:** en una prueba de DR, los datos replicados a otra región no podían descifrarse (clave distinta). **Solución:** claves **multi-región** para los datos replicados. **Lección:** diseña el cifrado junto con la replicación.

| Problema | Solución |
|---|---|
| Datos perdidos por borrado | Deshabilitar antes + alarma |
| Throttling | Bucket Keys / caché de claves de datos |
| Dato movido de dueño | Contexto de cifrado |
| Compartir entre cuentas | CMK propia |
| Poder excesivo | Separar administración y uso |
| DR sin clave | Multi-región |
