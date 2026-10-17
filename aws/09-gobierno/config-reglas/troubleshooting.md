# AWS · Config · Troubleshooting

Orden: **¿el registrador está encendido y grabando? → ¿el bucket/rol permiten entregar? → ¿la regla tiene el alcance y el disparo correctos? → ¿la regla personalizada responde (permisos, token, errores)? → ¿la remediación tiene rol y parámetros? → ¿hay retraso normal?**

| Síntoma | Causa probable | Cómo comprobarlo | Solución |
|---|---|---|---|
| No aparecen recursos | Registrador apagado o tipos no incluidos | `describe-configuration-recorder-status` | Iniciar el registrador; revisar `recording_group` |
| Falla la entrega al bucket | Política del bucket o permisos del rol | `describe-delivery-channel-status` | Permitir `config.amazonaws.com` (`GetBucketAcl`, `ListBucket`, `PutObject`) |
| Regla en `INSUFFICIENT_DATA` | Aún no evaluó, o la Lambda no reporta | `get-compliance-details-by-config-rule` | Esperar la primera evaluación; revisar la Lambda |
| La Lambda de la regla no se invoca | Falta permiso de Config para invocarla | `get-policy` de la función | `lambda:InvokeFunction` para `config.amazonaws.com` con `aws:SourceAccount` |
| `PutEvaluations` falla con `InvalidResultTokenException` | Token vencido o reutilizado | Registro de la Lambda | Usar el `resultToken` recibido una vez, dentro de su vigencia |
| `PutEvaluations` devuelve evaluaciones fallidas | Más de 100 por llamada o datos inválidos | `FailedEvaluations` en la respuesta | Partir en lotes de 100; reintentar las fallidas |
| Recurso eliminado sigue como `NON_COMPLIANT` | La regla no reportó `NOT_APPLICABLE` | Estado del elemento (`ResourceDeleted`) | Manejar el estado eliminado |
| Elemento «demasiado grande» | Notificación `OversizedConfigurationItemChangeNotification` | `messageType` | Obtener el elemento con `GetResourceConfigHistory` |
| La remediación no actúa | Falta rol o parámetro del recurso | `describe-remediation-execution-status` | Rol de Automation, parámetro `ResourceId` |
| Remediación en bucle | La corrección no resuelve la causa | Historial de ejecuciones | Limitar reintentos; corregir la causa |
| Cumplimiento tarda en reflejarse | Retraso normal de evaluación | Hora de captura del elemento | Esperar; forzar con `start-config-rules-evaluation` |
| Costo inesperado | Grabación continua de tipos ruidosos | Costos por tipo | Registro selectivo; frecuencia diaria |
| Agregador sin datos | Autorización de agregación pendiente | `describe-aggregation-authorizations` | Autorizar o usar la organización |
