# Google Cloud · Red · Conectividad · Troubleshooting

## Lista ordenada
1. **¿Estado del peering `ACTIVE`?** Ambos lados deben crearlo.
2. **¿Solapes?** Rangos repetidos impiden el intercambio.
3. **¿Rutas?** Rutas efectivas de la VM y rutas aprendidas en Cloud Router.
4. **¿BGP establecido?** `gcloud compute routers get-status`.
5. **¿Túneles `ESTABLISHED`?** IKE, secretos y direcciones del otro extremo.
6. **¿Firewall en ambos lados?**
7. **¿Modo de enrutamiento?**

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| Peering `INACTIVE` | Falta el otro lado | Créalo en la otra VPC |
| Error al crear peering | Rangos solapados | Replanifica |
| BGP caído | ASN/IP de enlace erróneos | Revisa interfaces y pares |
| Túnel en `NEGOTIATION_FAILURE` | Secreto o cifrado | Alinea configuración |
| Solo una región conecta | Modo regional | `GLOBAL` |
