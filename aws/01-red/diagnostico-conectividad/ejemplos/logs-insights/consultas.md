# Consultas de diagnóstico · Flow Logs (CloudWatch Logs Insights)

Supone el formato predeterminado de campos (`srcAddr`, `dstAddr`, `srcPort`, `dstPort`, `action`, `bytes`…). Con formato personalizado puedes añadir `pkt_srcaddr`, `flow_direction`, `az_id`.

**1. ¿Qué rechaza la red hacia un destino concreto?**
```
filter dstAddr = "10.20.100.37" and action = "REJECT"
| stats count(*) as rechazos by srcAddr, dstPort
| sort rechazos desc
| limit 20
```

**2. Flujo en ambos sentidos entre dos IP (¿vuelve la respuesta?)**
```
filter (srcAddr = "10.20.16.15" and dstAddr = "10.20.100.37") or (srcAddr = "10.20.100.37" and dstAddr = "10.20.16.15")
| fields @timestamp, srcAddr, dstAddr, srcPort, dstPort, action
| sort @timestamp asc
| limit 50
```
Si ves ida `ACCEPT` y vuelta `REJECT`, sospecha de la **NACL** (retorno) o de rutas asimétricas.

**3. ¿Qué IP externas golpean mi VPC y son rechazadas? (ruido/escaneo)**
```
filter action = "REJECT" and not (srcAddr like /^10\./)
| stats count(*) as intentos by srcAddr, dstPort
| sort intentos desc
| limit 20
```

**4. Salida a internet por destino (candidatos a endpoint)**
```
filter action = "ACCEPT" and srcAddr like /^10\./ and not (dstAddr like /^10\./)
| stats sum(bytes) as bytes by dstAddr
| sort bytes desc
| limit 20
```
