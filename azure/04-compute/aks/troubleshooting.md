# Azure · AKS · Troubleshooting

Método: **de afuera hacia adentro y de arriba hacia abajo.** Primero el estado del objeto (`get`), luego su historia (`describe` + eventos), luego los logs (`logs`), y solo después la red y el nodo.

```
¿El pod existe?        → kubectl get pods
¿Por qué no está Ready? → kubectl describe pod  (sección Events y Last State)
¿Qué dice la app?       → kubectl logs <pod> [--previous]
¿Llega el tráfico?      → Service → Endpoints → Ingress
¿Llega a la dependencia?→ Identidad → Permiso → Red → DNS → Servicio (RPDSI)
```

## 1. Estados de pod

| Síntoma | Causa probable | Cómo comprobarlo | Solución |
|---|---|---|---|
| `Pending` | Sin recursos, *taint* sin toleration, `nodeSelector` imposible, PVC sin volumen, cuota de namespace | `kubectl describe pod` → Events (`FailedScheduling`, `Insufficient cpu`) | Ajustar `requests`; esperar al autoscaler; revisar taints/selectores/cuota |
| `ContainerCreating` mucho tiempo | Montaje de volumen/CSI fallido, imagen grande, red del CNI | `describe pod` → Events (`FailedMount`, `FailedCreatePodSandBox`) | Revisar identidad/permiso del CSI, SecretProviderClass, IPs disponibles |
| `ImagePullBackOff` / `ErrImagePull` | Etiqueta inexistente, ACR sin `AcrPull`, DNS/red al ACR, ACR privado sin ruta | `describe pod` → mensaje (`unauthorized`, `not found`, `i/o timeout`) | `az aks update --attach-acr`; revisar etiqueta; Private Link y DNS del ACR |
| `CrashLoopBackOff` | La app falla al arrancar o la *liveness* la mata | `kubectl logs <pod> --previous`; `describe pod` → *Last State: Exit Code* | Corregir la excepción; subir `startupProbe`; revisar la configuración |
| `OOMKilled` (exit 137) | Memoria del proceso > `limits.memory` | `describe pod` → *Reason: OOMKilled* | `MaxRAMPercentage`; subir límite; revisar fugas y buffers |
| Exit code 143 / reinicios al desplegar | `SIGTERM` normal tras *rollout* | — | Esperado; verifica apagado ordenado |
| `Evicted` | Presión de disco/memoria del nodo | `kubectl describe node` → Conditions | Definir `requests`; limpiar; ampliar nodos o disco |
| `Running` pero `0/1 Ready` | La *readiness* falla | `describe pod` → Events (`Readiness probe failed`) | Probar la ruta con `curl` desde otro pod; revisar dependencias |
| `Terminating` eterno | *Finalizers* o nodo caído | `kubectl get pod -o yaml` | Esperar `terminationGracePeriodSeconds`; como último recurso `--force --grace-period=0` |
| `CreateContainerConfigError` | ConfigMap/Secret inexistente o clave faltante | `describe pod` → Events | Crear el objeto o corregir la referencia |
| `RunContainerError` con `runAsNonRoot` | La imagen corre como root o usuario no numérico | Events | `runAsUser` numérico; imagen sin root |

## 2. Red y servicios

| Síntoma | Causa probable | Cómo comprobarlo | Solución |
|---|---|---|---|
| El Service no encuentra pods | Etiquetas del `selector` no coinciden | `kubectl get endpoints <svc>` (vacío) | Alinear etiquetas |
| Endpoints correctos pero 502/504 del ingress | Puerto/protocolo erróneo, readiness, timeouts | Logs del controlador de entrada; `curl` interno al Service | Puerto correcto; ajustar timeouts; ver [Ingress en AKS](../../05-ingress-api/ingress-aks/README.md) |
| 502 solo durante los despliegues | Sin `preStop` ni apagado ordenado | Coincide con *rollouts* | `preStop: sleep`, readiness, graceful shutdown |
| `nslookup` falla dentro del pod | CoreDNS caído, NetworkPolicy bloquea DNS, `dnsPolicy` | `kubectl -n kube-system get pods -l k8s-app=kube-dns`; `kubectl exec ... nslookup` | Permitir UDP/TCP 53 hacia kube-dns; escalar CoreDNS |
| Resolución lenta de dominios externos | `ndots:5` + CoreDNS saturado | `cat /etc/resolv.conf` en el pod | FQDN con punto final; `dnsConfig.ndots`; NodeLocal DNSCache |
| Un host de PaaS resuelve a IP pública | Zona privatelink sin enlace a la VNet del clúster | `nslookup` desde el pod | Enlazar la zona; DNS del clúster hacia el resolvedor correcto ([Private Endpoint y DNS](../../01-red/private-endpoint-dns/README.md)) |
| Sin salida a Internet | NSG/UDR/Firewall, `outboundType`, NetworkPolicy de egress | `kubectl run -it --rm dbg --image=curlimages/curl -- curl -v https://...` | Permitir egress; revisar rutas efectivas de la subred |
| Errores intermitentes de salida en horas pico | Agotamiento de puertos SNAT | Métricas del balanceador (*SNAT Connection Count*, puertos fallidos) | NAT Gateway; reutilizar conexiones |
| Los pods no se comunican | NetworkPolicy *deny-all* sin regla | `kubectl get networkpolicy -n <ns>` | Añadir la regla de entrada/salida |
| `LoadBalancer` en `<pending>` | Cuota de IP, permisos de red del clúster, anotación errónea | `describe svc` → Events | Rol *Network Contributor* de la identidad del clúster en la subred; IP/cuota |
| IP agotadas (`failed to allocate for range`) | Azure CNI (VNet) con subred pequeña | `describe pod` → Events; IPs libres | Migrar a CNI Overlay o ampliar subred |
| Servicios solapan con la VNet | `service-cidr` o `pod-cidr` duplican otra red | Rutas inesperadas | Recrear con rangos disjuntos (se define al crear) |

## 3. Identidad y acceso

| Síntoma | Causa probable | Cómo comprobarlo | Solución |
|---|---|---|---|
| `kubectl`: `Unauthorized` / pide login interactivo | Falta `kubelogin` o token vencido | `kubectl get nodes` | `kubelogin convert-kubeconfig -l azurecli`; `az login` |
| `Forbidden` dentro del namespace | Falta rol de AKS RBAC | `kubectl auth can-i ...` | Asignar *AKS RBAC Reader/Writer* en el scope del namespace |
| `az aks get-credentials` falla | Falta *Cluster User Role* | Mensaje 403 | Asignar el rol |
| Pod sin acceso a Azure (`AADSTS70021`) | Credencial federada o subject incorrectos | Ver [Workload Identity · troubleshooting](../../02-iam/workload-identity/troubleshooting.md) | Alinear issuer/subject/audience |
| Pod no tiene `AZURE_FEDERATED_TOKEN_FILE` | Etiqueta ausente en el **pod** o SA sin anotación | `describe pod` | Etiqueta `azure.workload.identity/use: "true"` en la plantilla |
| Secretos CSI no montan | Identidad sin rol en Key Vault, red del vault cerrada | Events del pod; logs del proveedor CSI | Ver [Key Vault · troubleshooting](../../03-secretos/key-vault/troubleshooting.md) |

## 4. Escalado y actualizaciones

| Síntoma | Causa probable | Cómo comprobarlo | Solución |
|---|---|---|---|
| El HPA no escala (`<unknown>/70%`) | Sin `requests`, metrics-server falla | `kubectl describe hpa`; `kubectl top pods` | Definir `requests`; revisar metrics-server |
| El HPA escala pero los pods quedan `Pending` | No hay nodos | Events `FailedScheduling`; estado del autoscaler | Subir `max-count` del pool; cuota de vCPU de la suscripción |
| El Cluster Autoscaler no añade nodos | Cuota agotada, tamaño no disponible en la zona, `max-count` alcanzado | `kubectl -n kube-system get configmap cluster-autoscaler-status -o yaml` | Cuota; otra SKU; subir máximo |
| KEDA no escala | Autenticación del escalador fallida | `kubectl describe scaledobject`; logs de `keda-operator` | Rol de datos de la identidad de KEDA; nombre del namespace/cola |
| El upgrade se atasca | PDB imposible (`minAvailable` = réplicas), pods sin controlador, `Pending` por falta de capacidad | `kubectl get pdb -A`; estado del drenado | Ajustar PDB; subir `max-surge`; liberar cuota |
| Error de upgrade por versión | Salto de más de una menor o API retirada | `az aks get-upgrades` | Actualizar de menor en menor; migrar manifiestos a APIs vigentes |
| Nodo `NotReady` | Presión de recursos, kubelet caído, red | `kubectl describe node` | Reiniciar/reemplazar el nodo (`az aks nodepool upgrade --node-image-only` o reciclar) |

## 5. Comandos de diagnóstico

```bash
# Estado general
kubectl get nodes -o wide
kubectl get pods -A -o wide | grep -v Running
kubectl get events -A --sort-by=.lastTimestamp | tail -30

# Un pod en problemas
kubectl -n modalima describe pod <pod>
kubectl -n modalima logs <pod> --previous --tail=200
kubectl -n modalima get pod <pod> -o jsonpath='{.status.containerStatuses[*].lastState}'

# Despliegues
kubectl -n modalima rollout status deployment/api-pedidos
kubectl -n modalima rollout history deployment/api-pedidos
kubectl -n modalima rollout undo deployment/api-pedidos

# Recursos
kubectl top nodes
kubectl top pods -n modalima --containers

# Red desde dentro del clúster
kubectl -n modalima run dbg --rm -it --image=nicolaka/netshoot -- bash
#   nslookup svc-pedidos.modalima.svc.cluster.local
#   curl -v http://svc-pedidos.modalima.svc.cluster.local/actuator/health
#   curl -v https://<vault>.vault.azure.net     (¿IP privada?)

# Lado Azure
az aks show -g <rg> -n <aks> --query "{estado:powerState.code, version:kubernetesVersion, red:networkProfile, salida:networkProfile.outboundType}" -o json
az aks nodepool list -g <rg> --cluster-name <aks> -o table
az aks get-upgrades -g <rg> -n <aks> -o table
```

## 6. Pod de depuración efímero (sin tocar el pod de producción)
```bash
kubectl -n modalima debug -it <pod> --image=nicolaka/netshoot --target=api
```
Comparte el espacio de nombres de procesos con el contenedor `api`, sin modificar la imagen.

## 7. Consulta KQL (Container Insights)
```kusto
KubePodInventory
| where TimeGenerated > ago(1h) and Namespace == "modalima"
| summarize reinicios = sum(ContainerRestartCount) by Name
| order by reinicios desc

ContainerLogV2
| where TimeGenerated > ago(30m) and PodNamespace == "modalima"
| where LogMessage has_any ("Exception", "ERROR")
| project TimeGenerated, PodName, LogMessage
```
