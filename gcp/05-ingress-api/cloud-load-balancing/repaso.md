# Google Cloud · Ingress y API · Cloud Load Balancing · Repaso

## Preguntas
1. ¿Qué tipos de balanceador hay?
2. ¿Qué hace el URL map?
3. ¿Qué es un backend service?
4. ¿Qué es un NEG sin servidor?
5. ¿Desde qué rangos llegan los chequeos?
6. ¿Qué ventaja tiene la IP anycast?
7. ¿Dónde se adjunta Cloud Armor?
8. ¿Cómo se renuevan los certificados?
9. ¿Qué ingress debe tener un Cloud Run detrás del balanceador?
10. ¿Cuándo usar uno de red de paso?

## Respuestas
1. Aplicación (externo global/regional, interno), red de proxy y red de paso.
2. Decide el backend según host y ruta.
3. Grupo de backends con salud, timeout, CDN y seguridad.
4. Un grupo que apunta a Cloud Run/Functions.
5. `130.211.0.0/22` y `35.191.0.0/16` *(verifica)*.
6. Atiende desde el borde más cercano con una sola IP.
7. Al backend service.
8. Con certificados administrados.
9. `internal-and-cloud-load-balancing`.
10. Para UDP o cuando necesitas la IP del cliente intacta.

## Ejercicios
1. Diseña el URL map de la tienda (web, API, estáticos).
2. Escribe las pruebas del URL map para 5 rutas críticas.
3. Elige timeouts por backend.
