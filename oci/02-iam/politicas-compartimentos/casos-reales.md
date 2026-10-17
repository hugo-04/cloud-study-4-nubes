# Oracle OCI · IAM · Compartimentos, grupos y políticas · Casos reales

## 1. El `manage all-resources` de la prisa
**Qué pasó:** un practicante borró una VCN de producción.
**Causa:** el grupo de desarrollo tenía `manage all-resources in tenancy` «para avanzar».
**Arreglo:** políticas por compartimento con `use`/`read` en prod.
**Lección:** lo temporal se queda.

## 2. `any-user` sin condición
**Qué pasó:** una función de otro compartimento leía secretos.
**Causa:** `Allow any-user to read secret-family in compartment seguridad`.
**Arreglo:** grupo dinámico específico o condición `request.principal.type`.
**Lección:** `any-user` exige `where`.

## 3. La política en el lugar equivocado
**Qué pasó:** «NotAuthorizedOrNotFound» aunque la política existía.
**Causa:** adjunta a un compartimento hermano; no se hereda hacia los lados.
**Arreglo:** moverla al padre común.
**Lección:** herencia hacia abajo, no hacia los lados.

## 4. El 404 que era un 403
**Qué pasó:** «not found» al consultar un recurso que existía.
**Causa:** OCI devuelve `NotAuthorizedOrNotFound` para no filtrar la existencia.
**Arreglo:** revisar políticas antes que el recurso.
**Lección:** ese error significa permisos primero.

## Resumen
| # | Síntoma | Causa | Arreglo |
|---|---|---|---|
| 1 | Borrado accidental | `manage` amplio | Mínimo privilegio |
| 2 | Lectura no esperada | `any-user` abierto | Condición |
| 3 | Política sin efecto | Compartimento hermano | Padre común |
| 4 | «Not found» | Falta permiso | Revisar políticas |
