# Oracle OCI · IAM · Grupos dinámicos y principales · Troubleshooting

## Lista ordenada
1. **¿Qué principal estás usando?** Config de usuario, instancia, recurso o workload.
2. **¿La regla coincide?** Compara `instance.compartment.id` y etiquetas con la VM real.
3. **¿Existe una política que cite el grupo?** `Allow dynamic-group <nombre> to …`.
4. **¿El grupo se nombra con su dominio** si no es `Default`?
5. **¿Llegas al servicio de metadatos?** `curl http://169.254.169.254/opc/v2/instance/` desde la VM (cabecera `Authorization: Bearer Oracle`).
6. **¿Cambio reciente?** Espera unos segundos.

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| `NotAuthenticated` | VM fuera de la regla o IAM aún propagando | Revisa regla; reintenta |
| 404 `NotAuthorizedOrNotFound` | Falta política para el grupo | Añade la frase mínima |
| Funciona en una VM y no en otra | Otro compartimento o sin etiqueta | Compara atributos |
| Error al contactar metadatos | Reglas de red del host o proxy | Excluye 169.254.169.254 del proxy |
| Permisos de más | Regla `ANY` o etiqueta libre | Acota y restringe etiquetado |
