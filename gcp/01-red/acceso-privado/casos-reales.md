# Google Cloud · Red · Acceso privado · Casos reales

## 1. GKE privado sin imágenes
**Qué pasó:** los nodos de un clúster privado de ModaLima no descargaban imágenes de Artifact Registry.
**Causa:** subred sin PGA y sin NAT.
**Arreglo:** PGA en la subred de nodos.
**Lección:** privado necesita un camino a las APIs.

## 2. El endpoint que nadie usaba
**Qué pasó:** se creó un endpoint PSC para las APIs, pero el tráfico seguía por los rangos públicos de Google.
**Causa:** sin zona DNS privada para `googleapis.com`.
**Arreglo:** zona privada con `*.googleapis.com` → IP del endpoint.
**Lección:** PSC sin DNS no hace nada.

## 3. El rango PSA agotado
**Qué pasó:** Café Andino no pudo crear una segunda instancia de Cloud SQL con IP privada.
**Causa:** rango asignado `/24` demasiado pequeño.
**Arreglo:** agregar otro rango asignado y planificar `/20` o mayor.
**Lección:** PSA también entra en el plan de direcciones.

## 4. La oficina que resolvía mal
**Qué pasó:** desde la oficina por VPN, los nombres de las APIs resolvían a IPs públicas y el firewall local las bloqueaba.
**Causa:** el DNS de la oficina no reenviaba a Cloud DNS.
**Arreglo:** política de reenvío entrante en Cloud DNS y reenvío condicional en la oficina.
**Lección:** el DNS híbrido se diseña de los dos lados.

## Resumen
| # | Síntoma | Causa | Arreglo |
|---|---|---|---|
| 1 | Sin imágenes | Sin PGA | Activar PGA |
| 2 | Tráfico público | PSC sin DNS | Zona privada |
| 3 | No crea instancia | Rango PSA chico | Más rango |
| 4 | Resolución pública | DNS híbrido | Reenvío entrante |
