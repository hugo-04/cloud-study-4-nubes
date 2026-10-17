# AWS · Módulos y entornos · Repaso

## Preguntas
1. ¿Qué es el contrato de un módulo?
   - *Variables con tipo y validación (entrada) y salidas documentadas (salida).*
2. ¿Por qué fijar la versión del módulo?
   - *Para que un cambio del módulo no llegue a producción sin que alguien lo decida.*
3. ¿Por qué `for_each` con mapa y no `count` con lista?
   - *Las claves son estables; con `count` el orden cambia las direcciones y provoca reemplazos.*
4. ¿Por qué carpetas por entorno y no workspaces?
   - *El entorno queda visible en la ruta, con backend, variables y rol propios.*
5. ¿Para qué sirve `moved`?
   - *Para cambiar la dirección de un recurso o módulo sin destruirlo.*
6. ¿Qué hace `terraform test` con `mock_provider`?
   - *Ejecuta aserciones sin crear nada en AWS.*
7. ¿Qué no debes exponer como variable?
   - *Lo que no quieres que se apague: cifrado, límite de permisos, retención mínima.*
8. ¿Por qué no pasar secretos como variables?
   - *Terminan en el estado y en los planes; pasa referencias (ARN).*
9. ¿Por qué subir `.terraform.lock.hcl`?
   - *Para que todos usen las mismas versiones del proveedor.*
10. ¿Cómo se sube de versión un módulo con seguridad?
    - *Primero en `dev`, con plan revisado y «0 to destroy», luego en los demás entornos.*

## Ejercicios
1. Añade una variable con `validation` al módulo y una prueba que la rechace con `expect_failures`.
2. Convierte un `count` sobre una lista en `for_each` con mapa usando `moved`.
3. Crea un entorno `stg` copiando `dev` con su `backend.stg.hcl`.
4. Genera con el código Java un `tfvars.json` y pásalo por `terraform test` como prueba de contrato.
5. Publica una versión `v1.1.0` del módulo y actualiza `dev`.

## Autoevaluación
- [ ] Mis módulos tienen contrato, pruebas y versión.
- [ ] Mis entornos son carpetas con estado y rol propios.
- [ ] Uso `for_each` con mapas estables.
- [ ] Refactorizo con `moved` y verifico «0 to destroy».
- [ ] No expongo variables que desactiven la seguridad.
