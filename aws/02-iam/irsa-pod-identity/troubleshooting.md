# AWS · IRSA y Pod Identity · Troubleshooting

Orden: **¿qué identidad usa el pod (`GetCallerIdentity`)? → ¿variables inyectadas? → ¿confianza correcta (`sub`, `aud` / `pods.eks.amazonaws.com`)? → ¿SDK compatible? → ¿permisos del rol?**

| Síntoma | Causa probable | Cómo comprobarlo | Solución |
|---|---|---|---|
| El pod usa el rol del **nodo** (`assumed-role/…-node-…`) | Sin anotación/asociación o SDK antiguo | `GetCallerIdentity` desde el pod | Crear asociación/anotación; actualizar el SDK |
| No hay `AWS_ROLE_ARN` ni `AWS_WEB_IDENTITY_TOKEN_FILE` (IRSA) | ServiceAccount sin anotación o pod creado antes | `kubectl describe pod` | Anotar y recrear el pod |
| No hay `AWS_CONTAINER_CREDENTIALS_FULL_URI` (Pod Identity) | Sin asociación o sin agente | Complemento y asociaciones | Instalar agente; crear asociación; recrear pod |
| `AccessDenied` en `AssumeRoleWithWebIdentity` | `sub`/`aud` no coinciden o proveedor mal registrado | Condiciones de la confianza | Corregir `sub` (namespace:serviceaccount) y `aud` |
| `InvalidIdentityToken: No OpenIDConnect provider found` | Proveedor OIDC del clúster sin crear | `list-open-id-connect-providers` | Registrar el emisor del clúster |
| `AccessDenied` en `sts:TagSession` (Pod Identity) | Confianza sin `sts:TagSession` | Confianza | Añadir `sts:AssumeRole` y `sts:TagSession` |
| Funciona en EC2 y no en Fargate (Pod Identity) | No compatible con Fargate | Tipo de cómputo | Usar IRSA |
| Funciona unos minutos y deja de funcionar | Token/credencial no se refresca (cliente creado una vez con credenciales estáticas) | Cómo se creó el cliente | Usar la cadena por defecto, no credenciales fijas |
| Cambié el rol y el pod sigue con el viejo | Credenciales en caché del pod | — | Reiniciar el pod |
| El pod llega al IMDS | IMDS con salto > 1 o IMDSv1 | Opciones de metadatos del nodo | IMDSv2 obligatorio, salto 1 |
| `The security token included in the request is invalid` | Región/endpoint de STS equivocado | Variables `AWS_REGION`, `AWS_STS_REGIONAL_ENDPOINTS` | STS regional |
