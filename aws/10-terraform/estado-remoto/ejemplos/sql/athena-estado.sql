-- ¿Quién leyó o escribió el estado? Requiere eventos de datos de CloudTrail sobre el bucket del estado
-- y la tabla de Athena del capítulo de CloudTrail (cloudtrail_logs). Filtra siempre por partición.

SELECT
  eventtime,
  useridentity.arn                         AS principal,
  eventname,
  json_extract_scalar(requestparameters, '$.key') AS clave,
  sourceipaddress,
  errorcode
FROM cloudtrail_logs
WHERE day BETWEEN '2026/03/01' AND '2026/03/07'
  AND eventsource = 's3.amazonaws.com'
  AND json_extract_scalar(requestparameters, '$.bucketName') = 'modalima-tfstate-111122223333'
  AND eventname IN ('PutObject', 'DeleteObject', 'DeleteObjectVersion', 'GetObject')
ORDER BY eventtime DESC
LIMIT 200;

-- Cualquier borrado de versiones (solo debería hacerlo el rol administrador).
SELECT eventtime, useridentity.arn AS principal, eventname, json_extract_scalar(requestparameters, '$.key') AS clave
FROM cloudtrail_logs
WHERE day BETWEEN '2026/03/01' AND '2026/03/31'
  AND eventsource = 's3.amazonaws.com'
  AND eventname = 'DeleteObjectVersion'
  AND json_extract_scalar(requestparameters, '$.bucketName') = 'modalima-tfstate-111122223333';
