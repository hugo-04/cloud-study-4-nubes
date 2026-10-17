# Oracle OCI · Datos · Autonomous Database · Casos reales

## 1. El checkout que se quedaba sin sesiones
**Qué pasó:** en una venta flash, el checkout de ModaLima devolvía «máximo de sesiones alcanzado».
**Causa:** la app usaba el servicio `high`, pensado para pocas consultas paralelas.
**Arreglo:** servicio `tp` y pool de 20 conexiones por réplica.
**Lección:** el servicio de conexión es una decisión de diseño.

## 2. La wallet vencida
**Qué pasó:** un lunes ninguna réplica podía conectarse.
**Causa:** la wallet de TLS mutuo se rotó y la imagen tenía la vieja.
**Arreglo:** TLS one-way con endpoint privado; sin archivos que rotar.
**Lección:** cuantos menos secretos en disco, mejor.

## 3. Datos reales en desarrollo
**Qué pasó:** un clon de producción con datos de clientes quedó accesible para todo el equipo.
**Causa:** clonado sin enmascarar.
**Arreglo:** clones solo a través de un proceso con enmascaramiento de Data Safe.
**Lección:** un clon es una copia de tu riesgo.

## 4. La factura del autoescalado
**Qué pasó:** Café Andino pagó el triple un mes.
**Causa:** un reporte mal escrito mantenía la base escalada al máximo.
**Arreglo:** reportes con el servicio `low`, alarma de ECPU y revisión de planes.
**Lección:** el autoescalado amplifica las consultas malas.

## Resumen
| # | Síntoma | Causa | Arreglo |
|---|---|---|---|
| 1 | Sin sesiones | Servicio `high` | `tp` + pool |
| 2 | No conecta | Wallet rotada | TLS one-way privado |
| 3 | Fuga en dev | Clon sin enmascarar | Data Safe |
| 4 | Costo triple | Consulta mala + autoescalado | `low` + alarma |
