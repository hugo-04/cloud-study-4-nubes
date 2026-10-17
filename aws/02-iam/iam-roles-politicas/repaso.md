# AWS · IAM · Roles y políticas · Repaso

## Preguntas
1. ¿Qué gana: un Allow o un Deny explícito?
   - *El Deny, siempre.*
2. ¿Qué es un rol y por qué es mejor que una clave?
   - *Identidad temporal que se asume; las credenciales caducan.*
3. ¿Diferencia entre política de permisos y de confianza?
   - *Permisos: qué puede hacer; confianza: quién puede asumir el rol.*
4. ¿Qué hace un límite de permisos?
   - *Fija el máximo que un rol puede llegar a tener.*
5. ¿Qué necesitas para acceso entre cuentas?
   - *Que lo permitan la identidad y la política del recurso.*
6. ¿Por qué `iam:PassRole` es peligroso?
   - *Permite usar roles poderosos desde servicios; equivale a escalar.*
7. ¿Qué es ABAC?
   - *Control de acceso por etiquetas comparando principal y recurso.*
8. ¿Qué condición exige que el tráfico venga de tu endpoint?
   - *`aws:SourceVpce`.*
9. ¿Qué hace Access Analyzer?
   - *Detecta acceso externo y permisos no usados; valida políticas.*
10. ¿Qué haces si encuentras una clave filtrada?
    - *Desactivar y rotar, revisar CloudTrail, eliminar claves de larga duración.*

## Ejercicios
1. Escribe la política mínima de una app que lee una cola y escribe en un prefijo de S3.
2. Añade la condición para que solo funcione desde tu endpoint.
3. Diseña un límite de permisos para equipos que crean roles.
4. Usa el simulador para probar `s3:DeleteObject` con el rol anterior.

## Autoevaluación
- [ ] Sé explicar el orden de evaluación.
- [ ] Sé distinguir los seis tipos de política.
- [ ] Escribo políticas sin comodines.
- [ ] Sé qué acciones permiten escalar privilegios.
