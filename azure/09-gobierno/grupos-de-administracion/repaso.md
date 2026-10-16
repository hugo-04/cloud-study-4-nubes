# Azure · Grupos de administración · Repaso

## Preguntas de repaso
1. ¿Qué es un grupo de administración y para qué sirve?
   - *Un contenedor de suscripciones y de otros grupos para aplicar políticas y permisos una vez y que se hereden hacia abajo.*
2. ¿Qué límites tiene la jerarquía?
   - *Hasta 10 000 grupos por directorio, seis niveles de profundidad (sin contar la raíz ni la suscripción) y un solo padre por elemento (verifica los vigentes).*
3. ¿Qué es el *Tenant Root Group* y qué no se puede hacer con él?
   - *La raíz del directorio, con el ID del tenant; no se puede mover ni borrar, y por defecto nadie tiene acceso a administrarla.*
4. ¿Cómo se obtiene acceso a la raíz si nadie lo tiene?
   - *Un administrador global de Entra eleva su acceso (User Access Administrator), asigna roles a un grupo y revierte la elevación.*
5. ¿Qué se hereda por el árbol?
   - *Azure RBAC, asignaciones y definiciones de Azure Policy; las etiquetas no.*
6. ¿Por qué asignar políticas en un grupo y no en cada suscripción?
   - *Se escriben una vez y los dueños de las suscripciones no pueden quitarlas.*
7. ¿Qué permisos hacen falta para mover una suscripción?
   - *Escritura en la suscripción (grupo, asignaciones de roles, registro), y `managementGroups/write` en los grupos de origen y destino; no se exigen si uno es la raíz.*
8. ¿Cuánto tarda en reflejarse un movimiento?
   - *ARM cachea la jerarquía hasta 30 minutos; la evaluación de políticas tiene además sus propios ciclos.*
9. ¿Qué es el grupo predeterminado?
   - *El grupo donde caen las nuevas suscripciones; por defecto es la raíz, y conviene apuntarlo a uno restrictivo (p. ej., Sandbox).*
10. ¿Qué hace `requireAuthorizationForGroupCreation`?
    - *Exige permiso explícito para crear grupos bajo la raíz; por defecto cualquiera puede.*
11. ¿Qué rol permite administrar esos ajustes?
    - *Hierarchy Settings Administrator (permisos `settings/read` y `settings/write` sobre la raíz).*
12. ¿Se puede cambiar el ID de un grupo?
    - *No; el nombre visible sí. Elige un ID con prefijo de la empresa.*
13. ¿Qué diseño recomienda la guía de zonas de aterrizaje?
    - *Raíz intermedia → Plataforma (identidad, conectividad, gestión) / Landing zones (Corp, Online) / Sandboxes / Decommissioned, en tres o cuatro niveles.*
14. ¿Por qué no crear un grupo por entorno?
    - *Los entornos se separan en suscripciones dentro del mismo grupo; así se mantiene una sola regla y la diferencia se resuelve con parámetros.*
15. ¿Por qué no dar RBAC de equipos en un grupo de administración?
    - *La herencia lo extiende a todas las suscripciones de abajo (sobre-permisos).*
16. ¿Qué limitaciones tienen los roles personalizados en un grupo?
    - *Un solo grupo en los alcances asignables, sin acciones de datos, y ARM no valida que el grupo exista.*
17. ¿Se puede poner un bloqueo de recursos en un grupo de administración?
    - *No; para proteger se usan políticas y permisos.*
18. ¿Cómo se gestionan los grupos con Terraform?
    - *`azurerm_management_group` con `parent_management_group_id`, `azurerm_management_group_subscription_association` y AzAPI para los ajustes de la raíz.*
19. ¿Qué opciones hay en Java?
    - *El SDK de grupos está en beta: se lee con Resource Graph y se escribe con REST sobre el pipeline de azure-core.*
20. ¿Cuánto cuestan los grupos de administración?
    - *Nada.*

## Mini-ejercicios
1. Diseña la jerarquía de una empresa con 20 suscripciones (10 aplicaciones internas, 3 públicas, 4 de plataforma, 3 de laboratorio). Dibuja el árbol y di dónde pones cada política de región, red privada y etiquetas.
2. Escribe los pasos para mover `sub-pagos-prod` de Online a Corp sin romper nada.
3. Redacta la política de acceso a la raíz: quién, con qué rol, con PIM, con qué alertas.
4. Un equipo pide *Contributor* "en toda la empresa" para encontrar recursos. ¿Qué le ofreces en su lugar?
5. Escribe la consulta de Resource Graph para encontrar las suscripciones que cuelgan directamente de la raíz.

## Frases para recordar
- **Los grupos dicen qué reglas necesita una carga, no quién es su jefe.**
- **Políticas arriba; permisos de equipos abajo.**
- **Entorno = suscripción, no un nivel del árbol.**
- **Grupo predeterminado restrictivo y creación de grupos con autorización.**
- **Mover una suscripción es cambiarle el reglamento: ensaya antes.**
