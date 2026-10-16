# Azure · Ingress en AKS · Troubleshooting

Escalera de diagnóstico (de afuera hacia adentro):

1. **DNS:** ¿el nombre resuelve a la IP esperada? `nslookup api.modalima.example`
2. **Entrada:** ¿la IP del controlador existe y responde? `kubectl get svc -A | grep LoadBalancer`
3. **Regla:** ¿el Ingress/HTTPRoute fue aceptado? `kubectl describe ingress|httproute`
4. **Backend:** ¿el Service tiene endpoints? `kubectl get endpoints <svc>`
5. **Pod:** ¿está *Ready* y responde en el puerto? `kubectl port-forward` + `curl`

| Síntoma | Causa probable | Cómo confirmarlo | Arreglo |
|---|---|---|---|
| 404 de NGINX ("default backend") | Host o ruta no coincide con ninguna regla | `kubectl describe ingress`; `curl -H "Host: api.modalima.example"` | Corregir `host`/`path`/`pathType` |
| 503 Service Temporarily Unavailable | El Service no tiene endpoints | `kubectl get endpoints svc-pedidos` vacío | Etiquetas del Service ≠ etiquetas del Pod; pods no *Ready* |
| 502 Bad Gateway | Backend responde mal o reinicia | Logs del controlador y del pod | Puerto incorrecto (`targetPort`), app caída, sondas |
| 504 Gateway Timeout | La app tarda más que el proxy espera | Latencia en logs | Subir `proxy-read-timeout` solo para la ruta; optimizar |
| 413 Request Entity Too Large | Cuerpo mayor que el límite del proxy | Respuesta con ese código | Subir límite del Ingress **y** de la app, o usar SAS |
| La IP externa queda `<pending>` | Cuota de IPs, subred sin espacio, permisos | `kubectl describe svc` → eventos | Liberar IP; dar *Network Contributor* a la identidad del clúster |
| Certificado inválido / `CN` incorrecto | Secret TLS no creado o de otro dominio | `curl -v`; `kubectl describe certificate` | Revisar cert-manager (`kubectl describe challenge`) |
| cert-manager no emite (HTTP-01) | El desafío no llega al controlador | `kubectl get challenge -A` | Que el Ingress de desafío sea público; o usar DNS-01 |
| Redirección infinita (ERR_TOO_MANY_REDIRECTS) | El proxy termina TLS y la app vuelve a redirigir a HTTPS | Cabecera `Location` en bucle | `forward-headers-strategy` en la app; quitar la redirección doble |
| Enlaces `http://` en las respuestas | La app ignora `X-Forwarded-Proto` | Respuesta `Location` | `server.forward-headers-strategy=framework` |
| Todas las peticiones tienen la misma IP | `externalTrafficPolicy: Cluster` (SNAT) | `X-Forwarded-For` ausente o IP de nodo | `externalTrafficPolicy: Local`, sonda del balanceador correcta |
| Sonda del Load Balancer falla con NGINX | Ruta de sonda incorrecta | Estado del backend en el balanceador | Anotación `azure-load-balancer-health-probe-request-path: /healthz` |
| Conexión SSE/WebSocket se cae a los ~4 min | Inactividad del balanceador | Corte periódico exacto | *Heartbeat* < 4 min; ajustar `tcp-idle-timeout` |
| Algunas peticiones fallan al desplegar | El pod sale antes de que el controlador lo retire | Errores solo durante despliegues | `preStop: sleep`, readiness, graceful shutdown |
| Ingress no tiene `ADDRESS` | Controlador no instalado o IngressClass equivocada | `kubectl get ingressclass` | Instalar/usar `ingressClassName` correcto |
| Gateway `Programmed=False` | Recurso AGC no asociado o permisos | `kubectl describe gateway` | Revisar asociación, subred delegada e identidad del ALB Controller |
| `HTTPRoute` sin `Accepted` | `parentRefs` o `namespace` no permitido | Condiciones del HTTPRoute | `allowedRoutes` en el Gateway; `ReferenceGrant` entre namespaces |
| Tráfico privado no llega al ingress interno | NSG/DNS/subred | `kubectl get svc` IP privada; probar desde un pod | Abrir NSG; zona DNS privada; ver [diagnóstico](../../01-red/diagnostico-conectividad/README.md) |

## Comandos que siempre ayudan
```bash
kubectl get ingress,svc,endpoints -n modalima
kubectl describe ingress api-pedidos -n modalima
kubectl get events -n modalima --sort-by=.lastTimestamp | tail -20
kubectl logs -n app-routing-system deploy/nginx --tail=100        # add-on de routing
kubectl get gateway,httproute -A                                  # Gateway API
kubectl get certificate,certificaterequest,order,challenge -A     # cert-manager
kubectl run curl --rm -it --image=curlimages/curl -- sh           # probar desde dentro
```

## Orden recomendado
1. Prueba **dentro** del clúster (`curl http://svc-pedidos.modalima/health`). Si falla aquí, el problema es app/Service.
2. Prueba la **IP del controlador** con `--resolve`. Si falla, es regla/controlador.
3. Prueba el **dominio**. Si falla, es DNS/WAF/TLS.
