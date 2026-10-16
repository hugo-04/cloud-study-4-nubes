# Azure · Workload Identity · Repaso

## Preguntas de repaso
1. ¿Qué es una credencial federada?
   - *Una regla que dice: confío en este emisor y este subject para actuar como esta identidad.*
2. ¿Qué tres valores debe coincidir entre el token y la credencial federada?
   - *Issuer, subject y audience.*
3. ¿Cómo es el subject de un ServiceAccount?
   - *`system:serviceaccount:<namespace>:<nombre>`.*
4. ¿Dónde va la etiqueta `azure.workload.identity/use: "true"`?
   - *En la plantilla del pod (`spec.template.metadata.labels`).*
5. ¿Qué cambia en tu código Java?
   - *Nada; `DefaultAzureCredential` reconoce las variables.*
6. ¿Por qué evitar `AZURE_CLIENT_SECRET` en el pod?
   - *`DefaultAzureCredential` lo prueba primero y anula la federación.*
7. ¿Cuándo usas Managed Identity directa y cuándo Workload Identity?
   - *Managed Identity en servicios de Azure (App Service, VM, Container Apps); Workload Identity para pods de AKS y emisores externos.*
8. ¿Qué pasa si recreas el clúster?
   - *El issuer cambia; hay que actualizar la credencial federada.*

## Entrevista
- Explica el flujo completo de un pod de AKS que lee un secreto de Key Vault.
- Un pipeline de GitHub debe desplegar solo desde `main` a producción: ¿cómo configuras el subject?
- ¿Cómo migras de `aad-pod-identity` a workload identity?
