# Azure · Red · Comunicación privada y diagnóstico de conectividad

Este documento responde dos preguntas:
1. **¿Cómo hago que mis servicios hablen entre sí sin salir a internet?** (la política)
2. **¿Qué reviso, y en qué orden, cuando algo no conecta?** (el método)

Los casos específicos de **AKS** y **APIM** están en sus carpetas:
[AKS · troubleshooting](../../04-compute/aks/troubleshooting.md) y [APIM · troubleshooting](../../05-ingress-api/apim/troubleshooting.md).

---

## 1. La idea central

**Red privada = el tráfico entre tus servicios nunca toca internet público.**

**Analogía:** una oficina con pasillos internos. Para ir de contabilidad a sistemas caminas por el pasillo. Salir a la calle y volver a entrar funciona, pero es más lento, más caro y menos seguro.

Para que **A hable con B en privado** deben cumplirse cinco cosas. Recuérdalas como **RPDSI**:

| Letra | Qué | Pregunta de control |
|---|---|---|
| **R** | **Ruta** | ¿Existe camino de red entre A y B? (misma VNet, peering, VPN, rutas) |
| **P** | **Permiso de red** | ¿NSG / firewall / política lo permiten en ese puerto? |
| **D** | **DNS** | ¿El nombre de B resuelve a su **IP privada** desde donde está A? |
| **S** | **Servicio** | ¿B tiene acceso privado habilitado, el Private Endpoint aprobado y está escuchando? |
| **I** | **Identidad** | ¿A tiene permiso (rol, token, clave) para usar B? |

> El 80 % de los problemas "raros" son **D** (DNS). Siguen **P** (reglas) e **I** (permisos disfrazados de problema de red).

---

## 2. La escalera de diagnóstico

Siempre en este orden. No saltes pasos.

```
0. ¿Qué cambió?  (despliegues, reglas, certificados, políticas, rotación de secretos)
        ↓
1. DNS        ¿el nombre resuelve? ¿a una IP privada?
        ↓
2. RUTA       ¿hay camino? (rutas efectivas, peering, siguiente salto)
        ↓
3. FIREWALL   ¿NSG / Azure Firewall / política permite el puerto?
        ↓
4. PUERTO     ¿alguien escucha? (conexión TCP)
        ↓
5. TLS        ¿el certificado es válido y de confianza para ese nombre?
        ↓
6. IDENTIDAD  ¿el token / rol / clave tiene permiso? (401 / 403)
        ↓
7. APLICACIÓN ¿qué dicen los logs? (404 / 500)
```

### Cómo leer el síntoma

| Lo que ves | Dónde está el problema | Significa |
|---|---|---|
| `Name or service not known`, `UnknownHostException` | **DNS** | El nombre no resuelve |
| Resuelve a **IP pública** cuando esperabas privada | **DNS / Private Endpoint** | Zona privada sin enlace o sin registro |
| **Timeout** (se queda esperando) | **Ruta o firewall** | Los paquetes se descartan en silencio |
| **Connection refused** | **Servicio / puerto** | Llegaste al destino, pero nadie escucha |
| Error de handshake / certificado | **TLS** | Certificado vencido, nombre que no coincide, CA no confiable |
| **401 / 403** | **Identidad** | La red está bien; falta permiso o token |
| **404 / 5xx** | **Aplicación** | La red está bien; falla la app o la ruta de API |

> **Un 403 no es un problema de red.** Si te responde algo, la red ya funcionó. (Excepción: un servicio con firewall que devuelve 403 al negar por red; ahí revisa el firewall del servicio.)

### Herramienta incluida
[`ejemplos/java/ConnCheck.java`](ejemplos/java/ConnCheck.java) prueba DNS y TCP en un solo paso e indica en qué escalón falla:

```bash
java ConnCheck.java mistorage.blob.core.windows.net 443
java ConnCheck.java sql-modalima.database.windows.net 1433 5000
```

---

## 3. La política de comunicación privada

### 3.1 Matriz de ejemplo ("quién habla con quién")

| Origen → Destino | Puerto | Cómo queda privado en Azure |
|---|---|---|
| Internet → Application Gateway (WAF) | 443 | IP pública **solo** aquí |
| App Gateway → APIM | 443 | APIM en modo Internal (VNet) |
| APIM → servicios en AKS | 443 / 80 | Balanceador **interno** de AKS |
| AKS → Container Registry | 443 | Private Endpoint + `privatelink.azurecr.io` |
| AKS → Key Vault | 443 | Private Endpoint + identidad de carga de trabajo |
| App / Function → Azure SQL | 1433 | Private Endpoint |
| App / Function → PostgreSQL | 5432 | Private Endpoint o acceso por VNet |
| App / Function → Blob Storage | 443 | Private Endpoint |
| App → Service Bus | 443 / 5671 | Private Endpoint |
| App → Event Hubs (Kafka) | 9093 / 443 | Private Endpoint |
| On-premises ↔ Azure | varios | VPN o ExpressRoute |
| Admin → máquinas | 22 / 3389 | Bastion, nunca IP pública |

### 3.2 Política recomendada (plantilla)

| ID | Regla |
|---|---|
| NET-01 | **Negar por defecto** entre subnets; permitir solo lo necesario. |
| NET-02 | Solo el punto de entrada (App Gateway / Front Door) tiene IP pública. |
| NET-03 | Servicios PaaS (SQL, Storage, Key Vault, Service Bus) con **Private Endpoint** y acceso público **deshabilitado**. |
| NET-04 | Cada Private Endpoint con su **zona DNS privada enlazada** a todas las VNets que lo usan. |
| NET-05 | Aplicaciones con **identidades administradas**, no claves en configuración. |
| NET-06 | Salida a internet **solo** por NAT Gateway o firewall, con lista de destinos permitidos. |
| NET-07 | Subnets dedicadas para AKS, APIM, App Gateway y Private Endpoints. |
| NET-08 | **VNet flow logs** activos hacia un workspace central. |
| NET-09 | Rangos IP registrados y **sin solapamiento** con on-premises. |
| NET-10 | Administración por Bastion; sin puertos 22/3389 abiertos a internet. |
| NET-11 | Cambios de red solo por **IaC** y revisión de código. |
| NET-12 | Las reglas anteriores se **imponen** con Azure Policy (ver `09-gobierno/azure-policy`). |

Políticas integradas útiles (busca el nombre exacto en *Azure Policy → Definitions*): "Network interfaces should not have public IPs", "Storage accounts should disable public network access", "Azure Key Vaults should use private link".

---

## 4. Network Watcher: tus herramientas de diagnóstico

**Network Watcher** es el conjunto de herramientas de diagnóstico de red de Azure. Se habilita por región (suele activarse solo al crear una VNet).

| Herramienta | Qué responde | Comando |
|---|---|---|
| **Connection troubleshoot** | ¿Puede A llegar a B:puerto? Muestra el salto donde falla | `az network watcher test-connectivity` |
| **IP flow verify** | ¿Qué regla de NSG permite o niega este flujo? | `az network watcher test-ip-flow` |
| **Next hop** | ¿Cuál es el siguiente salto para este destino? | `az network watcher show-next-hop` |
| **Effective routes** | Rutas que de verdad aplican a una NIC | `az network nic show-effective-route-table` |
| **Effective security rules** | Reglas de NSG que de verdad aplican | `az network nic list-effective-nsg` |
| **Packet capture** | Captura de paquetes en una VM | `az network watcher packet-capture create` |
| **VNet flow logs** | Registro de flujos aceptados/negados | Portal / Terraform |
| **Topology** | Mapa de la red | Portal |

Ejemplos: [`ejemplos/cli/diagnostico.sh`](ejemplos/cli/diagnostico.sh).

> Los NSG flow logs están en retiro y los reemplazan los **VNet flow logs**; verifica las fechas vigentes.

---

## 5. Checklist de 10 minutos

1. **¿Qué cambió?** *Activity Log*, último despliegue, cambios de red o política.
2. **DNS:** `nslookup` desde el **mismo lugar** donde corre la app (pod, VM, función). ¿IP privada?
3. **Ruta:** rutas efectivas y siguiente salto de la NIC de origen.
4. **Firewall:** *IP flow verify* y NSG efectivo.
5. **Puerto:** `nc -zv host puerto` o `ConnCheck.java`.
6. **TLS:** `curl -v` u `openssl s_client -connect host:443 -servername host`.
7. **Identidad:** ¿401/403? Revisa roles y token.
8. **Servicio destino:** ¿acceso público deshabilitado y Private Endpoint **aprobado**?
9. **Capacidad:** IP libres en la subnet, puertos SNAT, cuotas.
10. **Logs de la app** (última parada).

---

## 6. Seguridad

### IAM de este tema
| Quién | Qué necesita | Rol mínimo |
|---|---|---|
| Quien diagnostica | Ver sin cambiar | Reader + **Network Watcher Contributor** (para ejecutar pruebas) |
| Quien crea Private Endpoints | Permiso en la subnet y aprobación en el destino | Network Contributor + permiso sobre el recurso |
| Identidad del clúster AKS | Crear balanceadores en la subnet | Network Contributor sobre la subnet |
| Kubelet (nodos) | Descargar imágenes | **AcrPull** sobre el registro |
| App que lee secretos | Obtener secretos | Key Vault Secrets User |
| App que lee blobs | Leer datos | Storage Blob Data Reader |

---

## 7. Qué hacer y qué NO hacer

**Qué hacer**
- Seguir la escalera: DNS → ruta → firewall → puerto → TLS → identidad → aplicación.
- Probar **desde el mismo lugar** donde corre la aplicación.
- Dejar un **pod/VM de diagnóstico** con herramientas listas (`nicolaka/netshoot`).
- Registrar qué cambió con cada despliegue.
- Mantener un diagrama de rangos IP y zonas DNS.
- Usar IaC para que las reglas sean revisables.

**Qué NO hacer**
- Probar desde tu laptop y concluir que "la red está bien".
- Abrir el firewall "para ver si funciona" y olvidar cerrarlo.
- Desactivar la validación de certificados para "arreglar" TLS.
- Confundir 401/403 con problemas de red.
- Dejar `public network access` activo "por si acaso".
- Cambiar varias cosas a la vez: no sabrás qué lo arregló.

---

## 8. Límites, costos y versiones

- Network Watcher tiene costo bajo por algunas funciones (flow logs, captura, connection monitor); revisa precios.
- Los flow logs pueden generar mucho volumen: define retención.
- Comandos y nombres de herramientas evolucionan; confirma con `az network watcher --help`.
