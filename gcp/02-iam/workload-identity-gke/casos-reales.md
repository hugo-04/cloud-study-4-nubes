# Google Cloud · IAM · Workload Identity en GKE · Casos reales

## 1. El secreto con la llave
**Qué pasó:** ModaLima montaba una llave JSON como secreto de Kubernetes en cada pod.
**Causa:** costumbre heredada.
**Arreglo:** Workload Identity con roles directos a cada KSA; llaves revocadas.
**Lección:** en GKE no hacen falta llaves.

## 2. La KSA default con poderes
**Qué pasó:** cualquier pod nuevo del namespace podía escribir en buckets.
**Causa:** roles otorgados a la KSA `default`.
**Arreglo:** una KSA por app y nada a `default`.
**Lección:** la identidad por defecto debe ser inútil.

## 3. El clúster de pruebas con permisos de prod
**Qué pasó:** un clúster de pruebas en el mismo proyecto leía secretos de producción.
**Causa:** mismo pool, mismo namespace y KSA.
**Arreglo:** clústeres de prueba en otro proyecto.
**Lección:** la identidad depende del pool, namespace y nombre.

## 4. Pods que usaban la cuenta del nodo
**Qué pasó:** un pod sin KSA configurada llamaba APIs con la cuenta del nodo de Café Andino.
**Causa:** node pool sin `GKE_METADATA`.
**Arreglo:** recrear el node pool con el metadata server de GKE.
**Lección:** sin el metadata server de GKE, los pods ven el de la VM.

## Resumen
| # | Síntoma | Causa | Arreglo |
|---|---|---|---|
| 1 | Llaves en pods | Hábito | Workload Identity |
| 2 | Permisos amplios | KSA `default` | KSA por app |
| 3 | Acceso cruzado | Mismo pool | Proyecto aparte |
| 4 | Identidad del nodo | Sin `GKE_METADATA` | Node pool correcto |
