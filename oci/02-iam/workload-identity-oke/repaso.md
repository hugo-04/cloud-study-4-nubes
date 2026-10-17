# Oracle OCI · IAM · Workload Identity en OKE · Repaso

## Preguntas
1. ¿Qué problema resuelve workload identity?
2. ¿Qué atributos describen al principal de un pod?
3. ¿Por qué es mejor que el grupo dinámico de los nodos?
4. ¿Por qué no usar el ServiceAccount `default`?
5. ¿Por qué incluir `cluster_id`?
6. ¿Qué proveedor del SDK se usa?
7. ¿Quién puede usar un ServiceAccount?
8. ¿Qué requisito tiene el clúster?
9. ¿Cómo pruebas sin riesgo?
10. ¿Qué haces si el proveedor falla al arrancar?

## Respuestas
1. Dar identidad y permisos propios a cada pod sin guardar llaves.
2. Tipo, clúster, namespace y ServiceAccount.
3. La identidad es por aplicación y no por nodo.
4. Se usa por omisión y daría permisos a despliegues no previstos.
5. Evita que otro clúster con el mismo namespace y cuenta acceda.
6. `OkeWorkloadIdentityAuthenticationDetailsProvider`.
7. Quien pueda crear pods en ese namespace (RBAC).
8. Debe ser *enhanced*.
9. Con un pod efímero y una política mínima.
10. Verificar tipo de clúster y entorno del pod.

## Ejercicios
1. Escribe la política para que `app-tienda` (namespace `tienda`) lea solo el bucket `comprobantes`.
2. Escribe el YAML del ServiceAccount y del Deployment que lo use.
3. Diseña los ServiceAccounts de tres servicios con permisos distintos.
