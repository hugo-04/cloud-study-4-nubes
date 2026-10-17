# Consultas KQL · Subidas

Requieren registros de diagnóstico de la cuenta de almacenamiento (`StorageBlobLogs`) y trazas de la aplicación (`AppTraces`) en Log Analytics. Las consultas 4 y 5 suponen que la aplicación registra `subidaId`, `hacia` y `motivo` como campos estructurados (propiedades personalizadas); si solo escribes texto, usa `parse Message with *`.

**1. Subidas directas que fallaron (por código)**
```kusto
StorageBlobLogs
| where TimeGenerated > ago(1h) and OperationName in ("PutBlob", "PutBlock", "PutBlockList")
| where StatusCode >= 400
| summarize intentos = count() by StatusCode, StatusText, CallerIpAddress = tostring(CallerIpAddress)
| order by intentos desc
```

**2. Rechazos por SAS vencida o firma inválida (403)**
```kusto
StorageBlobLogs
| where TimeGenerated > ago(24h) and StatusCode == 403
| summarize n = count() by AuthenticationType, StatusText, bin(TimeGenerated, 1h)
| order by TimeGenerated desc
```

**3. Tamaño de lo que se sube (para ajustar topes)**
```kusto
StorageBlobLogs
| where TimeGenerated > ago(7d) and OperationName == "PutBlob" and StatusCode < 300
| summarize p50 = percentile(RequestBodySize, 50), p95 = percentile(RequestBodySize, 95), maximo = max(RequestBodySize) by bin(TimeGenerated, 1d)
```

**4. Tiempo entre «subida» y «validada» (traza de aplicación)**
```kusto
AppTraces
| where TimeGenerated > ago(24h) and Message startswith "subida.transicion"
| extend id = tostring(Properties.subidaId), a = tostring(Properties.hacia)
| summarize subida = minif(TimeGenerated, a == "SUBIDA"), validada = minif(TimeGenerated, a == "VALIDADA") by id
| extend segundos = datetime_diff('second', validada, subida)
| summarize p50 = percentile(segundos, 50), p95 = percentile(segundos, 95)
```

**5. Motivos de rechazo más frecuentes**
```kusto
AppTraces
| where TimeGenerated > ago(7d) and Message startswith "subida.rechazada"
| summarize n = count() by motivo = tostring(Properties.motivo)
| order by n desc
```

**6. Blobs borrados por la política de limpieza (señal de subidas abandonadas)**
```kusto
StorageBlobLogs
| where TimeGenerated > ago(7d) and OperationName == "DeleteBlob" and tostring(split(Uri, "/")[3]) == "cuarentena"
| summarize borrados = count() by bin(TimeGenerated, 1d), CallerIpAddress = tostring(CallerIpAddress)
```
