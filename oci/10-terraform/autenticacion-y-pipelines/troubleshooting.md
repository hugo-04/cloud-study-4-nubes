# Oracle OCI · Terraform · Autenticación y pipelines · Troubleshooting

## Lista ordenada
1. **¿Qué identidad usa el provider?** Revisa `auth` y el perfil; `oci iam region list` con la misma configuración.
2. **¿Huella correcta?** La del archivo de configuración debe coincidir con la llave cargada.
3. **¿Reloj?** Desfase de hora rompe la firma de peticiones.
4. **¿Grupo dinámico?** La regla debe incluir la instancia/recurso del runner.
5. **¿Política?** El 404 «NotAuthorizedOrNotFound» suele ser falta de permiso.
6. **¿Región?** El provider apunta a la región correcta; IAM se modifica en la región *home*.

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| `401 NotAuthenticated` | Huella/llave/usuario | Revisa config y llave |
| `401` intermitente | Reloj desfasado | NTP |
| `404 NotAuthorizedOrNotFound` | Sin política | Política para la identidad |
| Instance principal falla | Instancia fuera del grupo dinámico | Regla del grupo |
| Error al cambiar IAM | Región no *home* | Usa la región *home* |
