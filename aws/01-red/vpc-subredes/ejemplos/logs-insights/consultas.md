# Consultas · Flow Logs de la VPC

Con los registros en **CloudWatch Logs** se usa **Logs Insights**; con **S3** se consultan con **Athena** (verifica el formato de registro que elegiste). Las primeras usan el formato predeterminado.

**1. Tráfico rechazado por destino y puerto (¿quién choca contra qué?)**
```
fields @timestamp, srcAddr, dstAddr, dstPort, protocol
| filter action = "REJECT"
| stats count(*) as rechazos by dstAddr, dstPort
| sort rechazos desc
| limit 20
```

**2. Mayores consumidores de ancho de banda**
```
stats sum(bytes) as total by srcAddr, dstAddr
| sort total desc
| limit 20
```

**3. ¿Llega tráfico a la base? (puerto 5432) y quién**
```
filter dstPort = 5432 and action = "ACCEPT"
| stats count(*) as conexiones by srcAddr
| sort conexiones desc
```

**4. Tráfico que sale hacia internet desde subredes privadas (candidato a endpoint)**
```
filter action = "ACCEPT" and not (dstAddr like /^10\./)
| stats sum(bytes) as bytes by dstAddr
| sort bytes desc
| limit 20
```

**5. Athena (si los registros están en S3): rechazados en la última hora**
```sql
SELECT srcaddr, dstaddr, dstport, count(*) AS rechazos
FROM vpc_flow_logs
WHERE action = 'REJECT' AND from_unixtime(start) > current_timestamp - interval '1' hour
GROUP BY srcaddr, dstaddr, dstport
ORDER BY rechazos DESC
LIMIT 20;
```
