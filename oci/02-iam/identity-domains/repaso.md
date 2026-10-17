# Oracle OCI · IAM · Identity Domains · Repaso

## Preguntas
1. ¿Qué guarda un identity domain?
2. ¿Qué diferencia hay entre decidir «quién eres» y «qué puedes hacer»?
3. ¿Cómo se nombra un grupo de un dominio no `Default` en una política?
4. ¿Qué es SCIM?
5. ¿Por qué cada dominio tiene su propia URL?
6. ¿Qué es la federación?
7. ¿Para qué sirven los grupos en lugar de permisos por persona?
8. ¿Cuándo NO uses usuarios para una aplicación?
9. ¿Qué haces con un exempleado?
10. ¿Qué auditarías cada mes?

## Respuestas
1. Usuarios, grupos, credenciales, MFA y federación.
2. El dominio autentica (quién); las políticas autorizan (qué).
3. `'Dominio'/'Grupo'`.
4. Un estándar de API para gestionar usuarios y grupos.
5. Es un directorio aislado con su propio endpoint.
6. Confianza entre el dominio y tu proveedor de identidad para SSO.
7. Cambian menos y se revisan mejor.
8. Siempre que pueda usar principales de instancia o workload.
9. Desactivarlo en el IdP y verificar que se propague.
10. Inactivos, sin grupo, administradores de más.

## Ejercicios
1. Escribe la frase de política para el grupo `Desarrollo` del dominio `Socios`.
2. Lista tres señales de un usuario que conviene revisar.
3. Diseña la estrategia de dominios para dev, prod y un socio externo.
