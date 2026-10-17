-- Tabla de Athena sobre el bucket de la traza, con proyección de particiones (sin MSCK REPAIR).
-- Ajusta el bucket, la cuenta y la fecha de inicio. Verifica el DDL vigente en la documentación.
CREATE EXTERNAL TABLE cloudtrail_logs (
  eventVersion string,
  userIdentity struct<type:string, principalId:string, arn:string, accountId:string, invokedBy:string, accessKeyId:string, userName:string,
    sessionContext:struct<attributes:struct<mfaAuthenticated:string, creationDate:string>,
      sessionIssuer:struct<type:string, principalId:string, arn:string, accountId:string, userName:string>>>,
  eventTime string,
  eventSource string,
  eventName string,
  awsRegion string,
  sourceIpAddress string,
  userAgent string,
  errorCode string,
  errorMessage string,
  requestParameters string,
  responseElements string,
  additionalEventData string,
  requestId string,
  eventId string,
  readOnly string,
  eventType string,
  recipientAccountId string
)
PARTITIONED BY (region string, fecha string)
ROW FORMAT SERDE 'org.apache.hive.hcatalog.data.JsonSerDe'
STORED AS INPUTFORMAT 'com.amazon.emr.cloudtrail.CloudTrailInputFormat'
OUTPUTFORMAT 'org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat'
LOCATION 's3://prod-auditoria-111122223333/AWSLogs/111122223333/CloudTrail/'
TBLPROPERTIES (
  'projection.enabled' = 'true',
  'projection.region.type' = 'enum',
  'projection.region.values' = 'us-east-1,sa-east-1',
  'projection.fecha.type' = 'date',
  'projection.fecha.range' = '2026/01/01,NOW',
  'projection.fecha.format' = 'yyyy/MM/dd',
  'projection.fecha.interval' = '1',
  'projection.fecha.interval.unit' = 'DAYS',
  'storage.location.template' = 's3://prod-auditoria-111122223333/AWSLogs/111122223333/CloudTrail/${region}/${fecha}'
);

-- ¿Quién borró una tabla de DynamoDB ayer?
SELECT eventTime, userIdentity.arn, sourceIpAddress, requestParameters
FROM cloudtrail_logs
WHERE fecha = '2026/10/16' AND eventName = 'DeleteTable'
ORDER BY eventTime;

-- Rechazos por rol en un día (ráfagas)
SELECT userIdentity.arn AS principal, count(*) AS rechazos, array_agg(DISTINCT eventSource) AS servicios
FROM cloudtrail_logs
WHERE fecha = '2026/10/16' AND (errorCode LIKE '%Unauthorized%' OR errorCode LIKE 'AccessDenied%')
GROUP BY userIdentity.arn
HAVING count(*) >= 20
ORDER BY rechazos DESC;

-- Uso del usuario raíz
SELECT eventTime, eventName, sourceIpAddress
FROM cloudtrail_logs
WHERE userIdentity.type = 'Root' AND userIdentity.invokedBy IS NULL AND eventType <> 'AwsServiceEvent'
  AND fecha >= '2026/10/01';
