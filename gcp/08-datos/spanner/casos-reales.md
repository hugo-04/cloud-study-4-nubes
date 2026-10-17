# Google Cloud · Datos · Spanner · Casos reales

## 1. La clave creciente
**Qué pasó:** ModaLima migró Pedidos con PK = timestamp y la latencia de escritura se disparó.
**Causa:** todas las escrituras iban a la última división (hotspot).
**Arreglo:** PK UUIDv4 e índice secundario por fecha.
**Lección:** la clave define la distribución.

## 2. La sobreventa evitada
**Qué pasó:** en preventa, 3 000 personas compraban 500 zapatillas.
**Causa:** (sin incidente) transacción RW leía y actualizaba stock.
**Arreglo:** el aborto por conflicto se reintenta solo; ninguna venta de más.
**Lección:** la consistencia fuerte vale aquí.

## 3. La transacción eterna
**Qué pasó:** las reservas de Café Andino daban `ABORTED` en cadena.
**Causa:** llamada a la pasarela de pagos dentro de la transacción.
**Arreglo:** pagar fuera y confirmar después.
**Lección:** transacciones cortas, sin red externa.

## 4. La factura inflada
**Qué pasó:** el entorno de pruebas costaba como producción.
**Causa:** 3 nodos multirregión en pruebas.
**Arreglo:** 100 PU regionales en pruebas.
**Lección:** dimensiona por entorno.

## Resumen
| # | Síntoma | Causa | Arreglo |
|---|---|---|---|
| 1 | Latencia | Hotspot | UUID |
| 2 | — | Concurrencia | Transacción RW |
| 3 | ABORTED | Red en transacción | Sacar llamadas |
| 4 | Costo | Sobredimensión | PU por entorno |
