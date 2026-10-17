# Azure · Caso integrado · Runbook de diagnóstico · Troubleshooting de las propias herramientas

Qué hacer cuando **falla la herramienta que debería ayudarte** en el incidente.

| Síntoma | Causa probable | Cómo comprobarlo | Solución |
|---|---|---|---|
| La alerta no se dispara | La consulta no devuelve filas o la ventana es corta | Ejecutar la consulta en Log Analytics con el mismo intervalo | Ajustar umbral/ventana; verificar que la tabla recibe datos |
| La alerta llega tarde | Latencia de ingesta + frecuencia de evaluación | Hora del evento vs hora de la alerta | Usar métricas para lo urgente; reducir la frecuencia |
| Tormenta de alertas | Una alerta por causa y por recurso | Cantidad de alertas simultáneas | Agrupar por síntoma; supresión durante incidentes declarados |
| Nadie recibe el aviso | Grupo de acciones sin receptores o filtrado por el correo | Probar el grupo de acciones | Receptores válidos y un segundo canal (SMS/llamada) |
| La sonda dice `DNS_PUBLICA` pero todo funciona | `esperaPrivada` en una dependencia que no usa Private Endpoint | Configuración de la dependencia | Ajustar la expectativa por entorno |
| La sonda da `TOKEN_FALLIDO` en un pod nuevo | Cuenta de servicio sin federación o sin la etiqueta del pod | Credencial federada y etiqueta `azure.workload.identity/use` | Corregir la federación ([IAM](../../02-iam/workload-identity/README.md)) |
| La sonda da `TIMEOUT` en todo | Salida bloqueada o DNS del clúster caído | Probar desde otro pod/nodo | Revisar la red del clúster antes que las dependencias |
| `kubectl` no conecta durante el incidente | Credenciales vencidas o API privada sin acceso | `kubectl cluster-info` | Acceso desde la red autorizada; credenciales previas por Entra ID |
| `triage.sh` no muestra nada del bus | Falta rol de lectura en el espacio de nombres | Mensajes de error | Asignar rol de lector de recursos al grupo de guardia |
| Consultas KQL sin datos | Registros de diagnóstico no habilitados | Configuración de diagnóstico del recurso | Habilitar categorías; política que lo exija |
| El endpoint `/diagnostico` responde 403 | Falta el alcance/rol de operaciones | Token y reclamaciones | Asignar el rol a la guardia (no abrir el endpoint) |
| El informe incluye datos sensibles | Mensajes de error con valores | Revisar el campo `detalle` | Mantener solo categorías y enmascarar |
| El runbook tiene comandos obsoletos | Nadie lo ensayó | Simulacro | Revisión trimestral con el equipo |
