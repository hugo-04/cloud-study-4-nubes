# Azure · Caso integrado · Landing zone · Repaso

## Preguntas
1. ¿Qué es una landing zone y qué problema resuelve?
   - *Una suscripción preparada con red, identidad, políticas y presupuesto estándar; evita que cada equipo improvise.*
2. ¿Qué es el *subscription vending*?
   - *El proceso automático que entrega suscripciones nuevas ya configuradas.*
3. ¿Por qué las políticas no están en el módulo?
   - *Se asignan una vez en el grupo de administración y se heredan; así una norma nueva alcanza a todos.*
4. ¿Por qué el bloque de red lo asigna un servicio?
   - *Para que no haya solapamientos; la clave primaria evita que dos solicitudes reciban el mismo.*
5. ¿Por qué es idempotente la solicitud?
   - *Repetirla devuelve el mismo bloque; no consume otro.*
6. ¿Qué dos recursos forman un peering?
   - *Uno en cada red (spoke→hub y hub→spoke), cada uno en su suscripción.*
7. ¿Por qué hay un bloque `provider` por suscripción?
   - *Terraform no admite proveedores dinámicos; cada alias apunta a una suscripción.*
8. ¿Qué permisos recibe el equipo y por qué?
   - *`Contributor` en su grupo de recursos y `Reader` en la suscripción: mínimo necesario, a un grupo.*
9. ¿Qué diferencia hay entre el hub y un spoke?
   - *El hub concentra servicios comunes; el spoke es la red de un equipo.*
10. ¿Qué verifica el checklist y por qué se ejecuta de forma programada?
    - *Que la zona siga cumpliendo (etiquetas, presupuesto, bloqueo, peering…); detecta la deriva.*
11. ¿Por qué el portal de solicitudes no tiene permisos de Azure?
    - *Para que un fallo o abuso del portal no pueda cambiar la infraestructura; solo genera cambios revisables.*
12. ¿Para qué sirve el Sandbox?
    - *Experimentar con presupuesto bajo, SKU limitado y freno, sin tocar producción.*

## Ejercicios
1. Calcula el prefijo para 300 hosts y 3 subredes.
2. Dibuja la jerarquía de tu empresa en 5 grupos y justifica cada uno.
3. Añade al módulo un Key Vault base con Private Endpoint: ¿qué variable nueva hace falta?
4. Escribe la regla del checklist que detecta suscripciones sin etiqueta `costcenter`.
5. Diseña el procedimiento para retirar un equipo (desmantelado) sin romper el peering.

## Autoevaluación
- [ ] Explico el proceso de punta a punta en diez frases.
- [ ] Sé qué se hereda y qué se crea por equipo.
- [ ] Sé evitar solapamientos de red.
- [ ] Sé detectar la deriva.
