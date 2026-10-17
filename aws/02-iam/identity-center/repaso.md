# AWS · IAM Identity Center · Repaso

## Preguntas
1. ¿Para quién es Identity Center: personas o aplicaciones?
   - *Personas (la fuerza laboral).*
2. ¿Qué es un conjunto de permisos?
   - *Plantilla de permisos que se aprovisiona como rol en cada cuenta asignada.*
3. ¿Qué compone una asignación?
   - *Principal (grupo/usuario) + conjunto de permisos + cuenta.*
4. ¿Qué hace SCIM?
   - *Sincroniza usuarios y grupos del directorio al servicio.*
5. ¿Qué pasa con el acceso al darte de baja en el directorio?
   - *Desaparece y las sesiones caducan.*
6. ¿Se puede cambiar la región de origen?
   - *No; planifícala.*
7. ¿Por qué asignar a grupos y no a usuarios?
   - *Escala, auditoría y bajas automáticas.*
8. ¿Cómo entra una persona por CLI?
   - *`aws sso login` con un perfil `sso_session`.*
9. ¿Qué necesita el SDK de Java para usar un perfil SSO?
   - *Los módulos `sso` y `ssooidc`.*
10. ¿Qué es la cuenta de emergencia?
    - *Acceso fuera del proveedor de identidad, con MFA físico y alarma.*

## Ejercicios
1. Diseña cuatro grupos, tres conjuntos de permisos y la matriz de asignaciones para cinco cuentas.
2. Configura un perfil SSO y lista tus cuentas con la CLI.
3. Define la duración de sesión de cada conjunto y justifícala.
4. Escribe el procedimiento de la cuenta de emergencia.

## Autoevaluación
- [ ] Sé explicar el flujo SAML + SCIM + asignación.
- [ ] Asigno por grupos.
- [ ] Sé cómo llega una credencial a la CLI y al SDK.
- [ ] Tengo un plan para cuando el proveedor falle.
