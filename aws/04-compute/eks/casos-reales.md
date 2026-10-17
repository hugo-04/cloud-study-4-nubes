# AWS · EKS · Casos reales

Historias de ModaLima y Café Andino (ficticias).

## 1. Las IPs que se acabaron
**Qué pasó:** con 400 pods, los nuevos quedaban `Pending` por falta de IP en las subredes `/24`. **Solución:** subredes mayores para pods y *prefix delegation* del CNI. **Lección:** en EKS cada pod usa una IP de la VPC; el plan de direcciones se calcula antes.

## 2. El upgrade que se fue posponiendo
**Qué pasó:** el clúster siguió dos versiones atrás y entró en soporte extendido (con cargo). Actualizar de golpe rompió APIs obsoletas. **Solución:** calendario trimestral de una versión menor, con herramienta de detección de APIs obsoletas en CI. **Lección:** actualizar poco y seguido es más barato que una vez y a la fuerza.

## 3. El pod que no podía leer su secreto
**Qué pasó:** `AccessDenied` aunque el rol existía: el ServiceAccount no estaba asociado al rol. **Solución:** `pod_identity_association` por servicio y SDK reciente. **Lección:** permiso AWS = rol + asociación + SDK que sepa usarlo.

## 4. OOMKilled cada pocas horas
**Qué pasó:** `limits.memory` igual al heap de Java; el contenedor moría. **Solución:** `MaxRAMPercentage=75`, `requests = limits` en memoria. **Lección:** la memoria del contenedor incluye metaspace, hilos y buffers, no solo el heap.

## 5. Spot sin red de seguridad
**Qué pasó:** una interrupción simultánea dejó un servicio sin réplicas. **Solución:** `PodDisruptionBudget`, `topologySpreadConstraints` entre zonas y nodos base On-Demand. **Lección:** Spot es para lo tolerante, con repartición y presupuesto de disrupción.

## 6. Nadie podía entrar al clúster
**Qué pasó:** un cambio en el `ConfigMap aws-auth` dejó sin acceso a todos. **Solución:** *access entries* gestionadas con Terraform y un rol de emergencia. **Lección:** el acceso al clúster es infraestructura versionada, no un ConfigMap editado a mano.

| Problema | Solución |
|---|---|
| Pods Pending por IPs | Prefix delegation / subredes amplias |
| Versión vencida | Calendario de upgrades |
| AccessDenied en pods | Pod Identity + asociación |
| OOMKilled | MaxRAMPercentage + requests=limits |
| Spot tumba servicio | PDB + spread + base On-Demand |
| Sin acceso | Access entries como código |
