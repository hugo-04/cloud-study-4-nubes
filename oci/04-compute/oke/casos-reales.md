# Oracle OCI · Compute · OKE · Casos reales

## 1. El clúster que se quedó en una versión retirada
**Qué pasó:** no se podía crear un node pool nuevo.
**Causa:** el plano de control quedó en una versión sin soporte.
**Arreglo:** actualizar el plano y luego los pools.
**Lección:** las versiones de Kubernetes caducan; ponlo en el calendario.

## 2. IP agotadas en la subred de pods
**Qué pasó:** los pods no arrancaban (`Pending`).
**Causa:** subred de pods /24 con CNI nativo.
**Arreglo:** subred de pods más amplia.
**Lección:** con CNI nativo cada pod gasta una IP: dimensiona.

## 3. Todos los pods con la identidad del nodo
**Qué pasó:** un pod leía buckets ajenos.
**Causa:** grupo dinámico por instancia.
**Arreglo:** workload identity.
**Lección:** identidad por aplicación.

## 4. Sin límites, nodos caídos
**Qué pasó:** un servicio consumió toda la memoria del nodo.
**Causa:** pods sin `limits`.
**Arreglo:** `requests`/`limits` y `LimitRange` por namespace.
**Lección:** un pod sin límite es un vecino ruidoso.

## Resumen
| # | Síntoma | Causa | Arreglo |
|---|---|---|---|
| 1 | No crea pools | Versión retirada | Actualizar |
| 2 | Pods `Pending` | Pocas IP | Subred amplia |
| 3 | Acceso excesivo | Identidad del nodo | Workload identity |
| 4 | Nodo agotado | Sin límites | Requests/limits |
