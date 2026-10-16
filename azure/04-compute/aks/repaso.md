# Azure · AKS · Repaso

## Preguntas de repaso
1. ¿Qué administra Azure y qué administras tú en AKS?
   - *Azure: plano de control. Tú: nodos (pools), manifiestos, red, identidad, seguridad y observabilidad.*
2. ¿Diferencia entre `requests` y `limits`?
   - *Requests: reserva para planificar. Limits: tope; superar el de memoria mata el contenedor (OOMKilled), el de CPU lo frena (throttling).*
3. ¿Por qué no deberías poner la base de datos en la *liveness probe*?
   - *Si cae la base, Kubernetes reinicia todos los pods y empeora el incidente. La liveness es solo estado interno.*
4. ¿Qué hace cada sonda: startup, readiness, liveness?
   - *Startup: ¿arrancó? Readiness: ¿puede recibir tráfico? Liveness: ¿está colgado?*
5. ¿Qué es un PDB y cuándo bloquea una actualización?
   - *Mínimo de pods disponibles durante interrupciones voluntarias; bloquea si exige más réplicas de las que se pueden mantener.*
6. ¿Qué ventaja tiene Azure CNI Overlay frente a Azure CNI con IP de la VNet?
   - *Los pods no consumen IP de tu subred; escala sin agotar direcciones.*
7. ¿Qué tres rangos no deben solaparse con tus redes?
   - *`service-cidr`, `pod-cidr` (overlay) y la VNet/redes emparejadas/on-premises.*
8. ¿Cómo accede un pod a Azure sin secretos?
   - *Workload Identity: OIDC issuer + credencial federada + ServiceAccount anotado + etiqueta en el pod.*
9. ¿Cómo hace la imagen su camino desde ACR a un nodo?
   - *La identidad del kubelet tiene `AcrPull` sobre el ACR (`--attach-acr`).*
10. ¿Cuál es la cadena de escalado completa?
    - *HPA/KEDA sube pods → no caben → Cluster Autoscaler añade nodos → los pods se programan.*
11. ¿Por qué una JVM puede elegir SerialGC en un contenedor?
    - *Con menos de 2 CPU o ~1.8 GB la JVM no se considera "servidor" y usa SerialGC.*
12. ¿Cómo evitas 502 durante un despliegue?
    - *Readiness real, `preStop: sleep`, `terminationGracePeriodSeconds` mayor, apagado ordenado, `maxUnavailable: 0`.*
13. ¿Cuándo no usarías AKS?
    - *Pocas apps simples, equipo sin operación de Kubernetes, solo eventos cortos o HTTP con escala a cero (App Service, Functions, Container Apps).*
14. ¿Por qué usar un CronJob y no `@Scheduled` en un Deployment?
    - *`@Scheduled` corre en cada réplica; el CronJob lanza un único pod por ejecución.*

## Entrevista
- Una API Java en AKS responde lento solo en picos. ¿Qué revisas y en qué orden?
- ¿Cómo haces un despliegue sin caída y cómo revertirías?
- Diseña la seguridad de un clúster de producción (acceso, red, pods, imágenes, secretos).
- Tu upgrade lleva horas atascado: ¿qué sospechas?
- ¿Cómo escalarías consumidores de una cola a cero y qué identidad usarías?
- ¿Qué decides: un clúster compartido o uno por entorno? ¿Por qué?

## Ejercicio práctico
1. Crea el clúster de estudio y despliega `10-deployment.yaml` con una imagen de ejemplo.
2. Aplica `30-networkpolicy.yaml`, comprueba que se corta lo no permitido y ábrelo con una regla.
3. Provoca un `OOMKilled` bajando el límite de memoria y localízalo con `describe pod`.
4. Haz un *rollout* con `maxUnavailable: 0` y revierte con `rollout undo`.
5. Configura un `ScaledObject` sobre una cola y observa el escalado de 0 a N.
