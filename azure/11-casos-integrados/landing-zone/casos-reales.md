# Azure · Caso integrado · Landing zone · Casos reales

Historias de ModaLima (ficticia).

## 1. Dos equipos, la misma red
**Qué pasó:** Pedidos y Catálogo usaron `10.0.0.0/16` sin consultarse; al conectar ambos al hub, el tráfico se enrutaba al lugar equivocado.
**Solución:** servicio de direcciones con tabla (clave primaria) y reserva `10.40.0.0/16` para cargas; rediseño de una de las redes.
**Lección:** las direcciones IP son un recurso global de la empresa, no de cada equipo.

## 2. El Owner «temporal»
**Qué pasó:** un líder de proyecto recibió `Owner` «por una semana» y creó una cuenta de almacenamiento pública con datos de clientes.
**Solución:** equipos con `Contributor` solo en su grupo de recursos; política que audita asignaciones privilegiadas; accesos de emergencia con aprobación y caducidad.
**Lección:** lo temporal que no caduca solo es permanente.

## 3. Tres semanas para una suscripción
**Qué pasó:** cada equipo esperaba semanas: pedidos por correo, configuración manual, olvidos.
**Solución:** *vending*: solicitud estructurada → PR → módulo → verificación; la entrega bajó a un día.
**Lección:** automatizar el camino feliz reduce también los errores.

## 4. El peering a medias
**Qué pasó:** una nueva red no llegaba al hub; el peering estaba «Initiated» y no «Connected».
**Causa:** el módulo solo creó el lado del spoke; faltaba el lado del hub (otra suscripción).
**Solución:** el módulo crea **ambos** lados con el alias del proveedor de plataforma; el verificador revisa el estado.
**Lección:** un peering son dos recursos en dos suscripciones.

## 5. Presupuesto sin destinatarios
**Qué pasó:** un laboratorio gastó 4 000 USD en un fin de semana sin que nadie se enterara.
**Causa:** presupuesto creado a mano sin correos.
**Solución:** correos obligatorios en la validación de la solicitud, alerta pronosticada y freno en sandbox.
**Lección:** un presupuesto sin destinatarios es decoración.

## 6. La política que bloqueó a la plataforma
**Qué pasó:** una política `Deny` de acceso público también bloqueó el despliegue del propio hub.
**Solución:** exenciones con fecha para la plataforma, y ensayo en `Audit` durante un ciclo antes de `Deny`.
**Lección:** prueba cada norma contra los despliegues legítimos antes de aplicarla.

## 7. Deriva silenciosa
**Qué pasó:** alguien quitó el bloqueo de la red de producción «para arreglar algo» y se olvidó de ponerlo.
**Solución:** el checklist programado detecta `PROD_SIN_BLOQUEO` y abre un ticket; el registro de actividad alerta cambios de bloqueos.
**Lección:** lo que no se verifica se erosiona.

| Problema | Solución |
|---|---|
| Direcciones duplicadas | Asignación central |
| Permisos excesivos | Grupos, alcance mínimo, sin Owner |
| Entrega lenta | Vending automatizado |
| Peering incompleto | Ambos lados + verificación |
| Gasto invisible | Presupuesto con destinatarios |
| Deriva | Checklist y alertas |
