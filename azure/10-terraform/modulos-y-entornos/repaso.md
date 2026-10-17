# Azure · Terraform · Módulos y entornos · Repaso

## Preguntas de repaso
1. ¿Qué es un módulo y qué es el módulo raíz?
   - *Una carpeta con `.tf` que se puede llamar; el raíz es donde ejecutas Terraform.*
2. ¿Qué lleva un buen módulo además de recursos?
   - *Variables con tipo y validación, salidas, `versions.tf`, pruebas y `README.md`.*
3. ¿Por qué un módulo no debe configurar proveedores?
   - *Impide `for_each`, `count`, alias y el borrado limpio; los configura quien lo llama.*
4. ¿Cuál es la diferencia entre `count` y `for_each` en el estado?
   - *`count` identifica por posición; `for_each` por clave estable.*
5. ¿Qué pasa si una dirección cambia por un refactor?
   - *Terraform cree que es otro recurso y propone destruir y crear; se evita con `moved`.*
6. ¿Para qué sirven `moved`, `import` y `removed`?
   - *Renombrar sin destruir, traer lo existente y dejar de administrar sin borrar.*
7. ¿Qué es `-generate-config-out`?
   - *Escribe un borrador del código de los recursos que importas; hay que revisarlo.*
8. ¿Cuándo `azapi` en vez de `azurerm`?
   - *Cuando `azurerm` todavía no cubre un recurso o propiedad; llama a la API de ARM directamente.*
9. ¿Cómo se usan dos suscripciones en la misma configuración?
   - *Proveedores con `alias` y `providers = { azurerm = azurerm.plataforma }`.*
10. ¿Qué diferencia hay entre `validation`, `precondition` y `check`?
    - *`validation` revisa un valor de entrada; `precondition` una relación antes de crear; `check` avisa sin detener.*
11. ¿Qué hace `postcondition`?
    - *Comprueba el resultado tras aplicar (por ejemplo TLS 1.2) y falla si no se cumple.*
12. ¿Qué prueba `terraform test` con `mock_provider`?
    - *El contrato del módulo (nombres, seguridad, validaciones) sin Azure ni credenciales.*
13. ¿Para qué `expect_failures`?
    - *Para comprobar que una validación rechaza un valor malo.*
14. ¿Por qué fijar la versión del módulo con `?ref=`?
    - *Para que un `init` no traiga cambios inesperados; se actualiza deliberadamente por entorno.*
15. ¿Qué es el archivo `.terraform.lock.hcl` y se versiona?
    - *Versiones exactas de los proveedores; sí, va en Git.*
16. ¿Por qué un directorio por entorno y no workspaces?
    - *Estado, permisos y ritmo de cambio distintos; los workspaces comparten backend y credenciales.*
17. ¿Qué significa "seguro por defecto" en un módulo?
    - *Sale sin claves, con TLS 1.2 y sin acceso público; abrir algo exige pedirlo explícitamente.*
18. ¿Por qué un módulo no debe recibir ni devolver secretos?
    - *Terminan en el estado, el plan y los registros; mejor leerlos de Key Vault con identidad.*
19. ¿Cuándo es mala idea un módulo?
    - *Cuando se usa una sola vez, solo renombra argumentos o es una navaja suiza con decenas de variables.*
20. ¿Qué debe decir el plan tras un refactor correcto?
    - *"0 to destroy" (y normalmente cero cambios).*

## Mini-ejercicios
1. Convierte un `count` sobre una lista de tres bases de datos a `for_each` con `moved` para no recrearlas.
2. Escribe una `precondition` que verifique que `st${app}${entorno}${sufijo}` cabe en 24 caracteres.
3. Escribe un `run` de `terraform test` que compruebe que el módulo crea la cuenta sin claves.
4. Diseña la estructura de carpetas para tres aplicaciones y tres entornos, con sus claves de estado.
5. Planifica la actualización del módulo de `v1.3.0` a `v2.0.0` (cambio que rompe) en dev, qa y prod.
6. Importa un grupo de recursos existente: pasos y cómo verificas que el plan queda sin cambios.

## Frases para recordar
- **Un módulo es un contrato: pocas entradas, buenas validaciones, seguro por defecto.**
- **Versiona los módulos y adóptalos entorno por entorno.**
- **`for_each` por nombre; `moved` al reorganizar; "0 to destroy" antes de aplicar.**
- **Los entornos se diferencian por variables y estado, no por código copiado.**
- **Prueba el contrato con proveedores simulados antes de tocar Azure.**
