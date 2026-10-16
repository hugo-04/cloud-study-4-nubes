# Azure · RBAC · Repaso

## Preguntas de repaso
1. ¿Cuáles son las tres partes de una asignación de rol?
   - *Principal, definición de rol y alcance.*
2. ¿Qué diferencia hay entre `Actions` y `DataActions`?
   - *Control (administrar el recurso) frente a datos (usar su contenido).*
3. ¿Por qué un Contributor puede no poder leer blobs?
   - *Contributor es del plano de control; leer datos requiere un rol de datos.*
4. ¿Cómo se heredan los roles?
   - *De Management Group a suscripción a RG a recurso, hacia abajo.*
5. ¿RBAC sirve para prohibir cosas?
   - *No; para prohibir se usa Azure Policy.*
6. ¿Qué es un rol elegible en PIM?
   - *Un rol disponible que la persona activa por tiempo limitado.*
7. ¿Qué pasa si se asignan permisos y falla de inmediato?
   - *Hay propagación; esperar y renovar el token.*
8. ¿Cuándo creas un rol personalizado?
   - *Cuando ningún rol integrado ofrece los permisos justos; debe ser pequeño y revisado.*

## Entrevista
- Diseña los roles para: desarrolladores (dev), líderes (qa) y el pipeline (prod).
- ¿Cómo delegas la asignación de roles de datos sin dar Owner?
- Explica cómo auditarías quién tiene Owner en toda la empresa.
