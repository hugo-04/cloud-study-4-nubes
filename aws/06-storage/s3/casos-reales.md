# AWS · S3 · Casos reales

Historias de ModaLima y Café Andino (ficticias).

## 1. El bucket público de los comprobantes
**Qué pasó:** un desarrollador abrió un bucket de comprobantes con una política `Principal: "*"` para que «el frontend los viera». Un buscador de buckets los indexó. **Solución:** Block Public Access en la cuenta, URLs prefirmadas de 5 minutos y alerta de configuración ([Config](../../09-gobierno/README.md)). **Lección:** público es una decisión de arquitectura, no un atajo.

## 2. La factura de las versiones
**Qué pasó:** el versionado estaba activo desde hacía un año y un job reescribía un CSV de 2 GB cada hora; las versiones viejas pesaban terabytes. **Solución:** regla que expira versiones no actuales a los 30 días y mueve a IA lo que se consulta poco. **Lección:** versionado sin ciclo de vida es una fuga de dinero.

## 3. Cien mil objetos pequeños, millones de solicitudes
**Qué pasó:** se subían cientos de miles de JSON de 2 KB; el costo era sobre todo en solicitudes y en llamadas a KMS. **Solución:** agrupar en archivos por lote (JSON Lines comprimido) y activar Bucket Key. **Lección:** en S3 se paga por solicitud tanto como por GB.

## 4. Dos instancias pisándose el mismo reporte
**Qué pasó:** dos réplicas generaron `reporte-diario.csv` a la vez y la última ganó con datos incompletos. **Solución:** clave única por ejecución y escritura condicional `If-None-Match: *`. **Lección:** S3 no tiene bloqueos; usa escrituras condicionales.

## 5. AccessDenied con SSE-KMS
**Qué pasó:** el rol tenía `s3:PutObject` pero el bucket usaba una clave KMS; las subidas fallaban. **Solución:** `kms:GenerateDataKey` y `kms:Decrypt` en el rol y en la política de la clave. **Lección:** con SSE-KMS hay dos autorizaciones.

## 6. Un borrado accidental recuperado
**Qué pasó:** un script borró un prefijo entero de catálogos. Con versionado, bastó eliminar los marcadores de borrado. **Solución:** procedimiento de recuperación ensayado y MFA Delete / Object Lock en datos regulados. **Lección:** el versionado es el botón de deshacer.

| Problema | Solución |
|---|---|
| Datos públicos | Block Public Access + URLs prefirmadas |
| Costo por versiones | Ciclo de vida de versiones no actuales |
| Costo por solicitudes | Agrupar objetos + Bucket Key |
| Escrituras concurrentes | Claves únicas + escrituras condicionales |
| AccessDenied con KMS | Permisos en rol **y** clave |
| Borrado accidental | Versionado + recuperación ensayada |
