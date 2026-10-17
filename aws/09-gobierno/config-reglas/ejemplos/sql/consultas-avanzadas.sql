-- Consultas avanzadas de AWS Config (aws configservice select-resource-config --expression "...")

-- Volúmenes sin cifrar
SELECT resourceId, resourceType, configuration.encrypted
WHERE resourceType = 'AWS::EC2::Volume' AND configuration.encrypted = false

-- Instancias EC2 sin la etiqueta centro-costo
SELECT resourceId, tags
WHERE resourceType = 'AWS::EC2::Instance' AND tags.tag NOT LIKE 'centro-costo%'

-- Buckets de S3 por región
SELECT awsRegion, COUNT(*)
WHERE resourceType = 'AWS::S3::Bucket'
GROUP BY awsRegion

-- Bases RDS públicas
SELECT resourceId, configuration.publiclyAccessible
WHERE resourceType = 'AWS::RDS::DBInstance' AND configuration.publiclyAccessible = true
