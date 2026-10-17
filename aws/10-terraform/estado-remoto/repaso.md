# AWS · Estado remoto · Repaso

## Preguntas
1. ¿Qué guarda el estado y por qué importa?
   - *La relación entre el código y los recursos reales; sin él, Terraform no sabe qué existe.*
2. ¿Por qué un backend remoto y no un archivo local?
   - *Para compartirlo, bloquearlo, cifrarlo, versionarlo y recuperarlo.*
3. ¿Qué hace `use_lockfile`?
   - *Crea un objeto `.tflock` con escritura condicional para que solo un `apply` escriba a la vez.*
4. ¿Por qué el estado es sensible?
   - *Contiene atributos de los recursos, incluidos secretos, en texto claro.*
5. ¿Por qué un estado por entorno y componente?
   - *Limita el radio de explosión, acelera los planes y permite permisos por prefijo.*
6. ¿Cómo se recupera un estado borrado?
   - *Con el versionado: copiar la versión anterior como la actual y verificar con un plan.*
7. ¿Para qué sirve `moved`?
   - *Para renombrar o reubicar sin destruir y recrear.*
8. ¿Cuándo es seguro `force-unlock`?
   - *Solo cuando confirmas que ningún proceso está aplicando.*
9. ¿Por qué el bloque `backend` no usa variables?
   - *Se evalúa antes que el resto; se pasan valores con `-backend-config`.*
10. ¿Qué compartes entre componentes?
    - *Solo salidas mínimas, en solo lectura; el resto con Parameter Store.*

## Ejercicios
1. Crea el bucket del estado con el código de ejemplo y migra un componente local con `init -migrate-state`.
2. Provoca un candado (dos terminales) y resuélvelo sin `force-unlock`.
3. Borra el objeto del estado en un entorno de pruebas y recupéralo desde su versión anterior.
4. Renombra un recurso con `moved` y comprueba «0 to destroy».
5. Ejecuta el auditor de Java contra el bucket y corrige los hallazgos.

## Autoevaluación
- [ ] Sé qué contiene el estado y por qué lo protejo.
- [ ] Mi bucket es privado, versionado, cifrado con KMS y con candado.
- [ ] Tengo un estado por entorno y componente, con permisos por prefijo.
- [ ] Sé renombrar (`moved`), adoptar (`import`) y soltar (`removed`).
- [ ] He probado la recuperación.
