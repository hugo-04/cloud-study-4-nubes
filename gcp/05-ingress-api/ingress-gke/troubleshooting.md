# Google Cloud · Ingress y API · Entrada a GKE · Troubleshooting

## Lista ordenada
1. **¿Gateway `Programmed`?** `kubectl describe gateway`: condiciones y eventos.
2. **¿HTTPRoute `Accepted` y `ResolvedRefs`?** Namespace permitido, Service existente, puerto correcto.
3. **¿Backends sanos?** `gcloud compute backend-services get-health` del backend creado.
4. **¿Firewall para chequeos?** Rangos de Google hacia los pods/nodos.
5. **¿Certificado?** Estado en Certificate Manager.
6. **¿Políticas?** `GCPBackendPolicy`/`HealthCheckPolicy` apuntando al Service correcto.

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| Gateway sin dirección | Clase o IP inválida | Eventos del Gateway |
| Ruta `NotAllowedByListeners` | Namespace no permitido | `allowedRoutes` |
| 502 | Pods no sanos | HealthCheckPolicy y firewall |
| 404 | Host o ruta | Revisa la HTTPRoute |
| Certificado pendiente | DNS | Apunta el dominio |
