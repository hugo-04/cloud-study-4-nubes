-- Data Exports (CUR 2.0) en S3, formato Parquet, consultado con Athena.
-- Los nombres de columna pueden variar según la configuración de la exportación (verifica con DESCRIBE).
-- Regla de oro: filtra SIEMPRE por la partición del período; una consulta sin filtro escanea todo el historial.

-- 1) Costo por equipo del mes (etiqueta definida por el usuario).
SELECT
  coalesce(nullif(resource_tags['user_equipo'], ''), '(sin etiqueta)') AS equipo,
  round(sum(line_item_unblended_cost), 2)                              AS costo_usd
FROM costos.cur2
WHERE billing_period = '2026-03'
GROUP BY 1
ORDER BY costo_usd DESC;

-- 2) Los 10 tipos de uso más caros (aquí aparece el NAT Gateway silencioso).
SELECT
  line_item_product_code AS servicio,
  line_item_usage_type   AS tipo_de_uso,
  round(sum(line_item_unblended_cost), 2) AS costo_usd
FROM costos.cur2
WHERE billing_period = '2026-03'
GROUP BY 1, 2
ORDER BY costo_usd DESC
LIMIT 10;

-- 3) Costo diario de un servicio, para ver cuándo empezó el aumento.
SELECT
  date(line_item_usage_start_date) AS dia,
  round(sum(line_item_unblended_cost), 2) AS costo_usd
FROM costos.cur2
WHERE billing_period = '2026-03'
  AND line_item_product_code = 'AmazonEC2'
GROUP BY 1
ORDER BY 1;

-- 4) Recursos más caros sin la etiqueta equipo (a quién pedirle que etiquete).
SELECT
  line_item_resource_id AS recurso,
  round(sum(line_item_unblended_cost), 2) AS costo_usd
FROM costos.cur2
WHERE billing_period = '2026-03'
  AND coalesce(resource_tags['user_equipo'], '') = ''
  AND line_item_resource_id <> ''
GROUP BY 1
ORDER BY costo_usd DESC
LIMIT 20;
