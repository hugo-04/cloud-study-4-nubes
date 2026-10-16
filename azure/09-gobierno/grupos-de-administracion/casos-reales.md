# Azure · Grupos de administración · Casos reales

(ModaLima y Café Andino son empresas inventadas para estudiar. Cada caso: problema → causa → solución → lección.)

## Caso 1 · Quince suscripciones colgando de la raíz
- **Problema:** ModaLima creció a 15 suscripciones sin estructura. Cada equipo tenía sus propias asignaciones de política, copiadas a mano, y cada una había cambiado un poco.
- **Causa:** nunca se creó una jerarquía; todas las suscripciones colgaban de la raíz del tenant.
- **Solución:** una raíz intermedia (`mg-modalima`) con Plataforma, Landing zones (Corp y Online), Sandbox y Desmantelado; las políticas comunes pasaron a la raíz intermedia y las específicas a Corp/Online; las copias manuales se retiraron tras ensayarlas en `DoNotEnforce`.
- **Lección:** una regla que vale para todos se escribe **una vez**, arriba. Cuantas más copias haya, más versiones distintas habrá.

## Caso 2 · El organigrama convertido en jerarquía
- **Problema:** se creó un grupo por gerencia, con subgrupos por equipo y por país: seis niveles. Cada reorganización de la empresa exigía mover media docena de grupos.
- **Causa:** se copió el organigrama en lugar de agrupar por **necesidad de gobierno** (cargas internas, expuestas, de laboratorio).
- **Solución:** rediseño a tres niveles por tipo de carga. El equipo y el centro de costo pasaron a **etiquetas**.
- **Lección:** los grupos describen **qué reglas necesita una carga**, no quién es su jefe.

## Caso 3 · Un grupo por entorno
- **Problema:** había grupos "Producción", "Pruebas" y "Desarrollo", y cada aplicación tenía suscripciones repartidas entre los tres. Las políticas de red eran casi iguales en los tres, pero había que mantenerlas por triplicado.
- **Solución:** los entornos se separaron en **suscripciones** (`sub-tienda-prod`, `sub-tienda-dev`) dentro del **mismo** grupo (Corp). Las diferencias entre entornos (por ejemplo, `Deny` en producción y `Audit` en desarrollo) se resuelven con **parámetros de la asignación** o con asignaciones a suscripciones concretas.
- **Lección:** el entorno es un atributo de la **suscripción**, no del árbol.

## Caso 4 · Treinta políticas en la raíz del tenant
- **Problema:** cuando un equipo de otra unidad de la empresa (otro grupo bajo la misma raíz) no podía desplegar, nadie sabía qué política lo bloqueaba.
- **Causa:** se habían asignado decenas de políticas en la raíz del tenant, que aplican a **todo**, incluidos los que no tenían nada que ver con ModaLima.
- **Solución:** raíz del tenant casi vacía; todo lo de la empresa en `mg-modalima`; documentación de qué política está en qué nivel (el [catálogo NET](../azure-policy/catalogo-net-01-12.md) incluye el mapa).
- **Lección:** cuanto más arriba, más difícil depurar. Asigna **lo más bajo posible** que cubra el caso.

## Caso 5 · Mover una suscripción cambió el cumplimiento de golpe
- **Problema:** al mover `sub-pagos-prod` de Online a Corp, aparecieron 60 recursos no conformes por la política "sin IP pública" y, una hora después, comenzaron a fallar despliegues.
- **Causa:** la suscripción heredó de golpe las políticas de Corp (`Deny`), incluidas reglas que antes no aplicaban.
- **Solución:** antes de mover una suscripción importante, asignar temporalmente las políticas del grupo destino en `DoNotEnforce` a esa suscripción (o consultar el cumplimiento simulado), arreglar y recién entonces mover. Los movimientos pasaron a hacerse con un cambio revisado.
- **Lección:** mover una suscripción es **cambiarle el reglamento**. Ensaya antes.

## Caso 6 · La suscripción nueva que nació sin reglas
- **Problema:** un equipo creó una suscripción por su cuenta; durante tres semanas estuvo bajo la raíz, sin políticas, con IP públicas y sin etiquetas.
- **Causa:** por defecto las suscripciones nuevas caen en la raíz del tenant.
- **Solución:** **grupo predeterminado** = `mg-modalima-sandbox` (el más restrictivo en costo y con políticas de ensayo) y un control semanal con la consulta de suscripciones bajo la raíz ([B1](ejemplos/kql/kql-grupos.md)). Las suscripciones oficiales se crean con el proceso de alta automatizada, que las coloca en el grupo correcto.
- **Lección:** el destino por defecto de una suscripción nueva debe ser **restrictivo**, no "libre".

## Caso 7 · Grupos "Prueba1" y "Final-final"
- **Problema:** la jerarquía se llenó de grupos con nombres sin sentido creados por usuarios curiosos.
- **Causa:** por defecto, **cualquier usuario puede crear grupos** bajo la raíz.
- **Solución:** activar `requireAuthorizationForGroupCreation` en la raíz, limpiar los grupos vacíos (consulta [B3](ejemplos/kql/kql-grupos.md)) y dejar la creación a la identidad del *pipeline* de gobierno.
- **Lección:** la jerarquía es infraestructura crítica: se cambia por código y revisión.

## Caso 8 · Un desarrollador veía los pagos
- **Problema:** un desarrollador de la tienda pudo leer recursos de la suscripción de pagos.
- **Causa:** por comodidad se le había asignado *Contributor* en el grupo **Corp**, y la herencia lo extendió a todas las suscripciones de Corp, pagos incluida.
- **Solución:** quitar el rol del grupo, asignarlo solo en su suscripción y dejar el RBAC de los grupos para plataforma y seguridad (con PIM). El alta automatizada de suscripciones asigna los roles del equipo en **su** suscripción.
- **Lección:** la herencia amplifica un permiso. RBAC de equipos: **abajo**.

## Caso 9 · El rol personalizado con un grupo que no existía
- **Problema:** se creó un rol personalizado con alcance asignable `/providers/Microsoft.Management/managementgroups/mg-modalima-corpp` (con doble "p"); la creación funcionó, pero el rol no aparecía al asignarlo en Corp.
- **Causa:** ARM **no valida** que el grupo del alcance asignable exista. El rol se creó "en un lugar que no existe".
- **Solución:** crear los roles personalizados como código y verificar el ID con `az account management-group show`; añadir una prueba en el *pipeline* que falla si el alcance no existe.
- **Lección:** donde ARM no valida, valida tú.

## Caso 10 · Elevar acceso para recuperar la raíz
- **Problema:** la persona que administraba la raíz dejó la empresa; nadie más tenía acceso para cambiar los ajustes de la jerarquía.
- **Causa:** por defecto **nadie** tiene acceso a la raíz; el acceso se había dado a una cuenta personal.
- **Solución:** un administrador global de Entra **elevó su acceso** (*User Access Administrator* en la raíz) con ticket y testigo, asignó el rol *Hierarchy Settings Administrator* a un **grupo de seguridad** con PIM y retiró la elevación. Se agregó una alerta para cada elevación futura.
- **Lección:** los permisos de la raíz van a **grupos**, no a personas, y la elevación se trata como un incidente planificado.

## Caso 11 · "Ya moví la suscripción, pero la política vieja sigue"
- **Problema:** tras mover una suscripción, el portal seguía mostrando las políticas del grupo anterior.
- **Causa:** ARM **cachea la jerarquía hasta 30 minutos**; además, la evaluación de cumplimiento tiene sus propios ciclos.
- **Solución:** esperar el tiempo de caché antes de diagnosticar, lanzar una evaluación bajo demanda y no encadenar movimientos sin comprobar el estado.
- **Lección:** no todo es instantáneo; conoce las ventanas de propagación.

## Caso 12 · Alta de suscripciones en 20 minutos
- **Problema:** crear una suscripción para un equipo nuevo tomaba tres semanas y cuatro tickets (facturación, red, permisos, políticas).
- **Solución:** *subscription vending* con Terraform: se crea la suscripción, se asocia al grupo (Corp u Online), se asignan roles al equipo **en su suscripción**, se crea el presupuesto y se despliega la red de acceso al *hub*. El equipo solo completa un formulario con nombre, tipo de carga y centro de costo.
- **Lección:** la jerarquía sirve de verdad cuando el **alta** de suscripciones la usa.

## Caso 13 · Dar de baja sin perder la auditoría
- **Problema:** al cerrar un proyecto, la suscripción se canceló y los datos de auditoría desaparecieron sin que nadie los exportara.
- **Solución:** flujo de baja: mover a `mg-modalima-desmantelado` (políticas de solo lectura), exportar registros y datos que deban conservarse, cancelar y dejar que Azure la elimine tras su periodo de retención.
- **Lección:** el grupo *Desmantelado* es una **sala de espera con reglas**, no una papelera.

---

## Patrones que se repiten
| Patrón | Casos |
|---|---|
| Una regla, escrita una vez y arriba | 1, 4 |
| Agrupar por necesidad de gobierno, no por organigrama ni entorno | 2, 3 |
| La herencia amplifica (permisos y políticas): ensaya y limita | 5, 8, 9 |
| Valores por defecto restrictivos (grupo predeterminado, autorización de creación) | 6, 7 |
| Permisos de la raíz a grupos de seguridad con PIM | 8, 10 |
| Propagación y caché | 5, 11 |
| Automatizar alta y baja de suscripciones | 12, 13 |
