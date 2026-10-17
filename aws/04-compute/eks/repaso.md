# AWS · EKS · Repaso

## Preguntas
1. ¿Qué administra AWS y qué administras tú en EKS?
   - *AWS el plano de control; tú el plano de datos (salvo Auto Mode).*
2. ¿Cuatro formas de ejecutar pods?
   - *Grupos gestionados, Karpenter, Fargate y Auto Mode.*
3. ¿Por qué EKS consume tantas IPs?
   - *El CNI da a cada pod una IP real de la VPC.*
4. ¿Qué son las access entries?
   - *El modo moderno de dar acceso de IAM al clúster, con políticas de EKS.*
5. ¿Pod Identity vs IRSA?
   - *Dos formas de dar un rol de IAM a un ServiceAccount; Pod Identity es más simple.*
6. ¿En qué orden se actualiza?
   - *Plano de control, add-ons, nodos; una versión menor cada vez.*
7. ¿Para qué un PDB?
   - *Garantizar un mínimo de pods durante interrupciones voluntarias.*
8. ¿Diferencia entre liveness y readiness?
   - *Reiniciar un pod colgado vs. sacarlo del balanceo mientras no esté listo.*
9. ¿Por qué no poner permisos AWS en el rol del nodo?
   - *Todos los pods del nodo los heredarían.*
10. ¿Cuándo preferir ECS a EKS?
    - *Cuando no necesitas el ecosistema Kubernetes y quieres menos operación.*

## Ejercicios
1. Calcula IPs necesarias para 600 pods y define el tamaño de subredes.
2. Escribe un PDB y un `topologySpreadConstraints` para 6 réplicas en 3 zonas.
3. Define `requests/limits` y `MaxRAMPercentage` para una app con 1 GB de heap.
4. Diseña el calendario de upgrades de un año.

## Autoevaluación
- [ ] Sé qué opera AWS y qué opero yo.
- [ ] Sé dar acceso al clúster y permisos AWS a un pod.
- [ ] Sé diagnosticar un pod Pending / CrashLoop / OOMKilled.
- [ ] Sé planear un upgrade.
