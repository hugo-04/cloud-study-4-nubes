# KQL · Identidades de Terraform y pipelines

Requieren que los registros de inicio de sesión de Entra ID y el registro de actividad lleguen a Log Analytics (configuración de diagnóstico del tenant y de la suscripción). Los nombres de tablas y de columnas pueden variar con tu configuración: **verifica con un evento real**.

## 1. ¿Qué identidades de pipelines iniciaron sesión y cuáles fallaron?
```kusto
union AADManagedIdentitySignInLogs, AADServicePrincipalSignInLogs
| where TimeGenerated > ago(7d)
| where ServicePrincipalName startswith "id-tf-" or ServicePrincipalName has "terraform"
| summarize intentos = count(), fallos = countif(ResultType != "0"), ultimo = max(TimeGenerated)
    by ServicePrincipalName, ResultType, ResultDescription
| order by fallos desc
```

## 2. Fallos de federación (subject, issuer o audiencia mal escritos)
```kusto
union AADManagedIdentitySignInLogs, AADServicePrincipalSignInLogs
| where TimeGenerated > ago(3d) and ResultType in ("70021", "700211", "700212", "70025")
| project TimeGenerated, ServicePrincipalName, ResultType, ResultDescription, IPAddress
| order by TimeGenerated desc
```

## 3. Cambios hechos por las identidades de apply (registro de actividad)
```kusto
AzureActivity
| where TimeGenerated > ago(1d)
| where Caller has "id-tf-" or Caller == "<client-id-de-la-identidad-apply>"
| where ActivityStatusValue == "Success"
| summarize operaciones = count() by Caller, OperationNameValue, ResourceGroup
| order by operaciones desc
```

## 4. Asignaciones de roles creadas o borradas (¿quién dio permisos?)
```kusto
AzureActivity
| where TimeGenerated > ago(7d)
| where OperationNameValue in~ ("MICROSOFT.AUTHORIZATION/ROLEASSIGNMENTS/WRITE", "MICROSOFT.AUTHORIZATION/ROLEASSIGNMENTS/DELETE")
| project TimeGenerated, Caller, OperationNameValue, ActivityStatusValue, _ResourceId, CallerIpAddress
| order by TimeGenerated desc
```

## 5. Operaciones denegadas a la identidad de apply (le falta un rol)
```kusto
AzureActivity
| where TimeGenerated > ago(7d)
| where Caller has "id-tf-" and ActivityStatusValue == "Failure"
| where Properties has "AuthorizationFailed" or Properties has "RequestDisallowedByPolicy"
| project TimeGenerated, Caller, OperationNameValue, ResourceGroup, SubStatusValue
| order by TimeGenerated desc
```

## 6. Inicios de sesión de pipelines desde IP inesperadas
```kusto
union AADManagedIdentitySignInLogs, AADServicePrincipalSignInLogs
| where TimeGenerated > ago(14d) and ServicePrincipalName startswith "id-tf-" and ResultType == "0"
| summarize dias = dcount(bin(TimeGenerated, 1d)), ultimo = max(TimeGenerated) by ServicePrincipalName, IPAddress
| order by dias asc
// Las IP vistas solo uno o dos días merecen una mirada (o son runners nuevos, o es otra cosa)
```
