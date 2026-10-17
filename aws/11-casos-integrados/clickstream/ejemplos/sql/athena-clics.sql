-- Athena sobre el lago que llena Firehose (JSON en gzip, particionado por fecha).
-- Con "partition projection" no hace falta ejecutar MSCK REPAIR TABLE cada día.
CREATE EXTERNAL TABLE IF NOT EXISTS clics (
    idEvento  string,
    idSesion  string,
    pagina    string,
    tipo      string,
    instante  string
)
PARTITIONED BY (anio string, mes string, dia string)
ROW FORMAT SERDE 'org.openx.data.jsonserde.JsonSerDe'
LOCATION 's3://modalima-lago-prod-111122223333/clics/'
TBLPROPERTIES (
    'projection.enabled'        = 'true',
    'projection.anio.type'      = 'integer', 'projection.anio.range' = '2026,2030',
    'projection.mes.type'       = 'integer', 'projection.mes.range'  = '1,12',  'projection.mes.digits' = '2',
    'projection.dia.type'       = 'integer', 'projection.dia.range'  = '1,31',  'projection.dia.digits' = '2',
    'storage.location.template' = 's3://modalima-lago-prod-111122223333/clics/anio=${anio}/mes=${mes}/dia=${dia}/'
);

-- Corrección diaria de lo que el tiempo real dejó fuera (eventos tardíos):
-- siempre filtra por partición para no leer todo el lago.
SELECT pagina, tipo, date_trunc('minute', from_iso8601_timestamp(instante)) AS ventana,
       count(DISTINCT idEvento) AS clics, count(DISTINCT idSesion) AS sesiones
FROM clics
WHERE anio = '2026' AND mes = '03' AND dia = '10'
GROUP BY 1, 2, 3
ORDER BY ventana, pagina;
