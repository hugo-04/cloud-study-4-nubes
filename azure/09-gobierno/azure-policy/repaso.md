# Azure · Azure Policy · Repaso

## Preguntas de repaso
1. ¿Qué diferencia hay entre RBAC y Azure Policy?
   - *RBAC dice quién puede hacer qué; Policy dice qué configuración de recursos está permitida, aunque tengas permiso.*
2. ¿Qué es una definición, una iniciativa y una asignación?
   - *Definición = la regla; iniciativa = paquete de reglas con parámetros; asignación = ponerlas a trabajar en un alcance.*
3. ¿Qué hacen `Audit`, `Deny`, `Modify` y `DeployIfNotExists`?
   - *Audit marca; Deny rechaza; Modify cambia propiedades; DeployIfNotExists despliega un recurso relacionado si falta.*
4. ¿Cuándo se usa `AuditIfNotExists`?
   - *Cuando la regla trata de un recurso relacionado que debe existir (por ejemplo, la configuración de diagnóstico).*
5. ¿Qué hace `DenyAction`?
   - *Impide una acción concreta (hoy, `delete`) y devuelve 403; sirve para proteger recursos de borrados.*
6. ¿En qué orden se evalúan los efectos?
   - *Disabled, luego Append/Modify, Deny, Audit, Manual, AuditIfNotExists y DenyAction; DINE/AuditIfNotExists después de la respuesta del proveedor.*
7. ¿Cuándo se evalúa una política?
   - *Al crear/modificar un recurso (en la solicitud), tras crear o cambiar una asignación (minutos), y en un ciclo estándar cada 24 horas; también bajo demanda.*
8. ¿Qué es `DoNotEnforce` y para qué sirve?
   - *Un modo de la asignación que evalúa e informa sin bloquear: permite ver el impacto de un `Deny` antes de activarlo.*
9. ¿Qué diferencia hay entre una exención y `notScopes`?
   - *`notScopes` excluye por completo (no se evalúa); la exención sí se evalúa y aparece como *Exempt*, con categoría y fecha de caducidad.*
10. ¿Por qué asignar políticas en un grupo de administración?
    - *Heredan hacia abajo y un dueño de suscripción no puede quitarlas; evitas duplicar reglas por proyecto.*
11. ¿Qué es un alias y por qué hay que validarlo?
    - *Nombre estable de una propiedad de un tipo de recurso; si está mal, la regla nunca coincide y el cumplimiento sale falsamente al 100 %.*
12. ¿Qué diferencia hay entre los modos `All` e `Indexed`?
    - *`All` evalúa todos los tipos, grupos de recursos y suscripciones; `Indexed` solo los que admiten etiquetas y ubicación.*
13. ¿Qué necesita una asignación con `Modify` o DINE?
    - *Una identidad administrada con los roles de `roleDefinitionIds`; con Terraform/CLI/SDK los roles se conceden a mano.*
14. ¿Cómo se corrige lo que ya existía antes de la política?
    - *Con una tarea de remediación (solo `Modify`/DINE); `Deny` no remedia.*
15. ¿Qué permisos hacen falta para crear una exención?
    - *Escribir la exención en el alcance y la acción `exempt` sobre la asignación.*
16. ¿Qué hace Azure Policy para Kubernetes?
    - *Instala Gatekeeper v3 en AKS y evalúa los objetos al admitirlos (privilegiados, límites, imágenes permitidas…).*
17. ¿Cuál es el ciclo de adopción recomendado?
    - *Audit/DoNotEnforce → medir y comunicar → Deny (Sandbox/Dev, luego Prod) → Modify/DINE + remediación para lo existente.*
18. ¿Qué pasa con Azure Blueprints?
    - *Se retira el 31 de enero de 2027; se sustituye por Deployment Stacks, template specs y políticas como código (verifica la fecha vigente).*
19. ¿Cuánto cuesta Azure Policy?
    - *No tiene cargo propio; sí los recursos que despliegan las políticas DINE y servicios relacionados.*
20. ¿Cómo lees un rechazo desde Java?
    - *Capturas `ManagementException`, buscas `RequestDisallowedByPolicy` (también anidado) y lees `additionalInfo` de tipo `PolicyViolation`.*

## Mini-ejercicios
1. Escribe (en JSON) una política que audite las cuentas de almacenamiento sin `minimumTlsVersion = TLS1_2` y conviértela en `Modify`. ¿Qué rol necesita la identidad?
2. Diseña dónde asignarías: regiones permitidas, etiquetas, sin IP pública, PaaS sin acceso público y un sandbox con presupuesto.
3. Un equipo dice "la política me bloquea". Escribe los 5 pasos para diagnosticarlo.
4. Una consulta de Resource Graph encuentra 40 Storage con acceso público aunque hay un `Deny` asignado. Lista 5 causas posibles.
5. Define una regla para las exenciones (quién las pide, quién las aprueba, máximo de días, revisión).

## Frases para recordar
- **IAM = la llave; Policy = el reglamento.**
- **Audit antes de Deny; Deny para lo nuevo; remediación para lo existente.**
- **Asigna arriba y excepciona con fecha.**
- **Prueba que la política bloquea lo que debe: un 100 % puede ser una regla rota.**
- **Modify y DINE necesitan identidad, rol y tarea.**
