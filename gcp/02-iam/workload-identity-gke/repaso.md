# Google Cloud · IAM · Workload Identity en GKE · Repaso

## Preguntas
1. ¿Qué es el workload pool?
2. ¿Cómo se escribe el principal directo de una KSA?
3. ¿Qué diferencia hay con el modo suplantación?
4. ¿Qué configura el node pool?
5. ¿Qué es la igualdad de identidad?
6. ¿Por qué no dar roles a la KSA `default`?
7. ¿Qué rol necesita la KSA en modo suplantación?
8. ¿Cómo ves la identidad desde el pod?
9. ¿Qué código Java hace falta?
10. ¿Qué roles debe tener la cuenta del nodo?

## Respuestas
1. `<PROYECTO>.svc.id.goog`, el pool de identidades del clúster.
2. `principal://iam.googleapis.com/projects/<NÚMERO>/locations/global/workloadIdentityPools/<PROYECTO>.svc.id.goog/subject/ns/<ns>/sa/<ksa>`.
3. En directo, IAM otorga roles a la KSA; en suplantación, la KSA actúa como una cuenta de IAM.
4. `workload_metadata_config` con modo `GKE_METADATA`.
5. Misma combinación de pool, namespace y KSA comparte permisos entre clústeres.
6. Porque cualquier pod sin KSA explícita los heredaría.
7. `roles/iam.workloadIdentityUser` sobre la cuenta de IAM.
8. Consultando el servidor de metadatos.
9. Ninguno especial: ADC.
10. Solo logging, monitoring y lectura de imágenes.

## Ejercicios
1. Escribe los principales y roles de pedidos, pagos y catálogo de ModaLima.
2. Diseña la separación de proyectos para clústeres de prueba.
3. Escribe la prueba de humo que valida la identidad al desplegar.
