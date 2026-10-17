# AWS · Autenticación y pipelines · Repaso

## Preguntas
1. ¿Qué problema resuelve OIDC en un pipeline?
   - *Elimina las claves de larga vida: el pipeline obtiene credenciales temporales demostrando su identidad.*
2. ¿Qué es el `sub` y por qué es crítico?
   - *Identifica repositorio y entorno/rama; un `sub` amplio deja que otros asuman el rol.*
3. ¿Por qué dos roles, `plan` y `apply`?
   - *Para que lo que cualquiera ejecuta (PR) solo pueda leer, y el cambio exija entorno protegido.*
4. ¿Qué hace el límite de permisos?
   - *Pone un techo a los roles que crea el pipeline: no puede otorgarse más de lo permitido.*
5. ¿Por qué aplicar el mismo plan que se aprobó?
   - *Porque si se vuelve a planificar, el resultado puede diferir de lo que se revisó.*
6. ¿Por qué `StringEquals` con `*` no funciona?
   - *Porque toma el comodín como texto literal; los patrones requieren `StringLike`.*
7. ¿Por qué no cancelar un `apply` en curso?
   - *Deja el candado y un estado parcial.*
8. ¿Qué detecta la puerta de seguridad?
   - *Destrucción de datos, permisos amplios, puertos abiertos al mundo y accesos públicos.*
9. ¿Para qué sirve la deriva nocturna?
   - *Para detectar y avisar de cambios hechos fuera de Terraform.*
10. ¿Qué pasa con los PR de forks?
    - *No reciben permisos de escritura/OIDC: es una protección, no un fallo.*

## Ejercicios
1. Crea el proveedor OIDC y los roles con el código de ejemplo y ejecuta un `plan` desde un PR.
2. Cambia el `sub` a un comodín y comprueba que el validador lo marca como error.
3. Intenta asumir el rol de `apply` desde una rama sin entorno y observa el rechazo.
4. Genera `plan.json` con un cambio que reemplace una base de datos y comprueba que la puerta lo bloquea.
5. Programa la deriva nocturna y provoca un cambio manual.

## Autoevaluación
- [ ] Mi pipeline no tiene claves de larga vida.
- [ ] El `sub` del rol de `apply` incluye el entorno protegido.
- [ ] `plan` y `apply` usan roles distintos.
- [ ] Aplico el plan aprobado y no cancelo ejecuciones en curso.
- [ ] Hay puerta de seguridad y deriva nocturna.
