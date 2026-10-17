# AWS · Budgets y Cost Explorer · Troubleshooting

Orden: **¿tienes permiso de Facturación/Cost Explorer? → ¿el dato ya existe (retraso de horas)? → ¿la etiqueta está activada en Facturación? → ¿el filtro/tipo de costo es el correcto (créditos, impuestos, amortizado)? → ¿llegó el aviso (SNS/correo confirmado)? → ¿estás llamando al endpoint global (`us-east-1`)?**

| Síntoma | Causa probable | Cómo comprobarlo | Solución |
|---|---|---|---|
| `AccessDeniedException` en `ce:` desde una cuenta miembro | Cost Explorer deshabilitado para miembros o falta política IAM | Preferencias de facturación de la cuenta de administración | Habilitar el acceso y conceder `ce:Get*` |
| Cost Explorer vacío en cuenta nueva | Aún no se habilitó o no hay datos (hasta 24 h) | Consola de Cost Explorer | Habilitar y esperar |
| Todo aparece «sin etiqueta» | Etiqueta no activada en Facturación o recursos sin etiquetar | Etiquetas de asignación de costos (estado) | Activar; etiquetar; política de etiquetas |
| El costo por etiqueta no incluye el pasado | La activación no es retroactiva (o el relleno no se pidió) | Fecha de activación | Pedir relleno *(verifica)* o aceptar el corte |
| Valores duplicados `Pagos`/`pagos` | Las etiquetas distinguen mayúsculas | Valores devueltos por `GetTags` | Normalizar en origen y en el informe |
| El presupuesto no avisa | Correo sin confirmar, tópico SNS sin política o suscripción pendiente | Estado de la suscripción; política del tópico | Confirmar; permitir `budgets.amazonaws.com` |
| El aviso llegó pero tarde | Solo había aviso real al 100 % | Avisos del presupuesto | Añadir pronosticado al 80/100 % |
| Sin pronóstico en un presupuesto nuevo | Falta de historial | Detalle del presupuesto | Esperar semanas de uso *(verifica)* |
| La acción de presupuesto no se ejecuta | Rol de ejecución sin permisos, aprobación manual pendiente o aún no se cruzó el umbral | Historial de la acción | Revisar rol, aprobar, comprobar el umbral y el retraso |
| `ThrottlingException` / `LimitExceededException` en `ce:` | Demasiadas solicitudes | Frecuencia | Caché, reintentos con espera |
| La API de Cost Explorer genera cargos | Llamadas por cada petición web | Facturación por tipo de uso | Caché de minutos y consultas por mes |
| `DataUnavailableException` | Rango anterior al historial o a la activación | Fechas de la consulta | Ajustar el período |
| `GetCostForecast` falla con fechas pasadas | El inicio debe ser hoy o futuro | Parámetros | Usar fecha de inicio de hoy en adelante |
| El total no coincide con la factura | Créditos, impuestos, soporte o tipo de costo distinto | Tipo de costo (sin mezclar / amortizado) y filtros | Alinear parámetros; documentar la definición |
| Anomalía sin aviso | Suscripción inmediata con correo (no admitido) o umbral alto | Tipo de suscriptor | Usar SNS para inmediata; bajar el umbral |
