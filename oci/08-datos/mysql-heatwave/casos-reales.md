# Oracle OCI · Datos · MySQL HeatWave · Casos reales

## 1. «Too many connections» al escalar
**Qué pasó:** al pasar de 4 a 12 réplicas del catálogo, todo ModaLima perdió la base.
**Causa:** cada réplica abría un pool de 50; el total superó `max_connections`.
**Arreglo:** pools calculados por servicio y réplica, con reserva para administración.
**Lección:** el pool se dimensiona contra el total global, no por réplica.

## 2. El reporte que frenaba las ventas
**Qué pasó:** el reporte diario de ventas bloqueaba el checkout 10 minutos.
**Causa:** consulta analítica sobre la base transaccional.
**Arreglo:** HeatWave: la consulta se descarga al clúster en memoria.
**Lección:** lo analítico no debe competir con lo transaccional.

## 3. El saldo que «volvió atrás»
**Qué pasó:** Café Andino mostraba puntos de fidelidad viejos tras canjearlos.
**Causa:** la pantalla leía del endpoint de lectura con retraso de réplica.
**Arreglo:** lecturas posteriores a una escritura van al primario.
**Lección:** consistencia de «leer lo que escribí» requiere el primario.

## 4. El borrado accidental
**Qué pasó:** un `terraform destroy` en el directorio equivocado borró la base de pruebas con datos de una demo.
**Causa:** sin protección contra borrado.
**Arreglo:** `deletion_policy` con `is_delete_protected` y respaldo final.
**Lección:** protege lo que no se puede recrear.

## Resumen
| # | Síntoma | Causa | Arreglo |
|---|---|---|---|
| 1 | Sin conexiones | Pools grandes | Reparto global |
| 2 | Checkout lento | Analítica en OLTP | HeatWave |
| 3 | Datos viejos | Réplica atrasada | Primario tras escribir |
| 4 | Base borrada | Sin protección | `deletion_policy` |
