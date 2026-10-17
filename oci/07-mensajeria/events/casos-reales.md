# Oracle OCI · Mensajería · Events · Casos reales

## 1. La política que nadie vio cambiar
**Qué pasó:** alguien amplió una política de ModaLima a `manage all-resources` y se supo un mes después.
**Causa:** no había vigilancia de cambios de IAM.
**Arreglo:** regla para `com.oraclecloud.identitycontrolplane.updatepolicy` y `createpolicy` → tema de seguridad.
**Lección:** los cambios sensibles deben avisar en minutos.

## 2. El DNS de máquinas fantasma
**Qué pasó:** registros DNS apuntaban a IPs de instancias ya terminadas, reutilizadas por otras.
**Causa:** la limpieza era manual.
**Arreglo:** regla de `terminateinstance.end` → función que borra el registro.
**Lección:** automatiza la limpieza al ritmo del cambio.

## 3. La bandeja inundada
**Qué pasó:** el equipo de Café Andino dejó de leer las alertas.
**Causa:** una regla mandaba cada evento de Compute a correo.
**Arreglo:** solo eventos críticos a correo; el resto a Streaming para análisis.
**Lección:** filtra por importancia, no por servicio.

## 4. La regla del compartimento equivocado
**Qué pasó:** la regla de seguridad no disparaba para producción.
**Causa:** estaba en un compartimento hermano, no en el padre.
**Arreglo:** reglas de seguridad en el compartimento raíz de la jerarquía de producción.
**Lección:** una regla ve su compartimento y los hijos.

## Resumen
| # | Síntoma | Causa | Arreglo |
|---|---|---|---|
| 1 | Cambio IAM sin aviso | Sin regla | Regla de IAM → tema |
| 2 | DNS obsoleto | Limpieza manual | Regla → función |
| 3 | Alertas ignoradas | Regla demasiado amplia | Filtrar |
| 4 | No dispara | Compartimento errado | Regla en el padre |
