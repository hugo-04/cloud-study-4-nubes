# Oracle OCI · IAM · Workload Identity en OKE · Casos reales

## 1. Todos los pods con los permisos del nodo
**Qué pasó:** un pod de pruebas leyó el bucket de facturación.
**Causa:** grupo dinámico por instancia: todos los pods del nodo heredaban el acceso.
**Arreglo:** workload identity por ServiceAccount.
**Lección:** la identidad debe ser por aplicación, no por nodo.

## 2. El ServiceAccount `default`
**Qué pasó:** un despliegue nuevo obtuvo permisos sin pedirlos.
**Causa:** la política citaba `default` y el despliegue lo usaba por omisión.
**Arreglo:** ServiceAccount con nombre y `automountServiceAccountToken` explícito.
**Lección:** nunca des permisos a `default`.

## 3. Política sin `cluster_id`
**Qué pasó:** un clúster de pruebas con el mismo namespace y cuenta accedió a producción.
**Causa:** la condición no incluía el clúster.
**Arreglo:** añadir `request.principal.cluster_id`.
**Lección:** namespace y cuenta no son únicos entre clústeres.

## 4. Clúster básico
**Qué pasó:** el proveedor `oke` fallaba al arrancar.
**Causa:** el clúster no era *enhanced*.
**Arreglo:** migrar o planificar otra opción.
**Lección:** verifica requisitos antes de diseñar.

## Resumen
| # | Síntoma | Causa | Arreglo |
|---|---|---|---|
| 1 | Acceso entre apps | Identidad del nodo | Workload identity |
| 2 | Permisos no pedidos | Cuenta `default` | Cuenta propia |
| 3 | Acceso entre clústeres | Falta `cluster_id` | Añadirlo |
| 4 | Falla al iniciar | Clúster básico | Enhanced |
