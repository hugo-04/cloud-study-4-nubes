-- Costo neto del mes por label "equipo" (exportación detallada). Ajusta proyecto, dataset y sufijo.
SELECT
  IFNULL((SELECT value FROM UNNEST(labels) WHERE key = 'equipo'), 'sin-equipo') AS equipo,
  service.description AS servicio,
  ROUND(SUM(cost) + SUM(IFNULL((SELECT SUM(c.amount) FROM UNNEST(credits) c), 0)), 2) AS costo_neto,
  currency
FROM `modalima-finanzas.facturacion.gcp_billing_export_resource_v1_XXXXXX`
WHERE invoice.month = FORMAT_DATE('%Y%m', CURRENT_DATE())
GROUP BY equipo, servicio, currency
ORDER BY costo_neto DESC
LIMIT 50;
