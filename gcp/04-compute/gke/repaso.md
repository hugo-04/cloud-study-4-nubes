# Google Cloud · Compute · GKE · Repaso

## Preguntas
1. ¿Diferencia entre Autopilot y Standard?
2. ¿Qué es un canal de lanzamiento?
3. ¿Para qué un PDB?
4. ¿Qué es un clúster privado?
5. ¿Qué es VPC nativo?
6. ¿Qué hace Dataplane V2?
7. ¿Cómo obtienen permisos los pods?
8. ¿Qué es Binary Authorization?
9. ¿Por qué regional?
10. ¿Cuándo preferir Cloud Run?

## Respuestas
1. En Autopilot Google administra nodos y cobras por pods; en Standard administras node pools.
2. La cadencia de versiones y actualizaciones automáticas.
3. Limitar cuántas réplicas pueden faltar en mantenimientos.
4. Nodos sin IP externa y plano de control con acceso restringido.
5. Pods y servicios con IPs de rangos secundarios de la VPC.
6. Red eBPF con NetworkPolicy integrada.
7. Con Workload Identity.
8. Permitir solo imágenes firmadas o aprobadas.
9. Para tolerar la caída de una zona.
10. Con pocas APIs HTTP sin estado.

## Ejercicios
1. Diseña el clúster de ModaLima (modo, canal, red, seguridad).
2. Escribe PDB y HPA del servicio de pedidos.
3. Planifica la prueba de versiones en no-prod.
