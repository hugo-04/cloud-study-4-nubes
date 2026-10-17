# Oracle OCI · IAM · Identity Domains · Troubleshooting

## Lista ordenada
1. **¿Qué dominio?** Cada uno tiene su URL y su lista de usuarios y grupos.
2. **¿El usuario está activo** y pertenece al grupo esperado?
3. **¿El grupo se nombra con su dominio** en la política?
4. **¿SSO falla?** Revisa el mapeo de atributos y la hora de los servidores (SAML es sensible al reloj).
5. **¿MFA bloquea?** Registro del segundo factor pendiente o dispositivo perdido.
6. **¿La API SCIM responde 401/403?** El principal necesita permisos de lectura sobre el dominio.

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| Usuario entra y no puede nada | Sin grupo o sin política | Añádelo a un grupo con política |
| Política no aplica al grupo | Falta `'Dominio'/'Grupo'` | Corrige la frase |
| SSO: «assertion invalid» | Reloj o certificado del IdP | Sincroniza hora, renueva certificado |
| Lista de usuarios vacía | Endpoint de otro dominio | Usa la URL correcta |
| No llega el correo de activación | Dirección errónea o filtro | Reenvía y revisa spam |
