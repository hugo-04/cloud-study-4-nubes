# AWS · Caso integrado · Landing zone · Troubleshooting

## Lista ordenada
1. **¿Quién ejecuta?** Cuenta de administración con permisos de Organizations.
2. **¿La cuenta se está creando?** `describe-create-account-status`: `IN_PROGRESS`, `SUCCEEDED` o `FAILED` con `FailureReason`.
3. **¿Está en la OU esperada?** `list-parents`.
4. **¿Qué SCP la afectan?** `list-policies-for-target` en la cuenta, la OU y la raíz.
5. **¿El verificador puede entrar?** `sts:AssumeRole` al rol `modalima-auditor`.
6. **¿El trail registra?** `get-trail-status`: `IsLogging` y `LatestDeliveryError`.
7. **¿Presupuesto y etiquetas?** Budgets filtrado por `LinkedAccount`; etiquetas en la cuenta.

## Síntoma → causa
| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| `EMAIL_ALREADY_EXISTS` | Correo ya usado | Usar otro alias único |
| `ACCOUNT_LIMIT_EXCEEDED` | Cuota de cuentas | Solicitar aumento |
| `CreateAccount` tarda | Es asíncrono | Consultar estado, no reintentar a ciegas |
| `AccessDenied` al operar en la cuenta nueva | SCP o rol de acceso inicial | Revisar SCP y `OrganizationAccountAccessRole` |
| El verificador reporta «no se pudo verificar» | Falta el rol `modalima-auditor` o su confianza | Desplegar la línea base de roles |
| Plan intenta destruir una cuenta | Se quitó la entrada del mapa | Cancelar; `prevent_destroy` lo bloquea |
| Dos cuentas con el mismo CIDR | Asignación manual | Reasignar con el asignador antes de crear la VPC |
| Alerta de presupuesto no llega | Suscriptor sin confirmar | Confirmar el correo; revisar umbrales |
