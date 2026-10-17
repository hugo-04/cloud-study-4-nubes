# Oracle OCI · Compute · OKE · Troubleshooting

## Lista ordenada
1. **¿`kubectl` llega a la API?** Endpoint privado: necesitas Bastion/VPN y regla de NSG al 6443.
2. **¿Estado de nodos?** `kubectl get nodes`; `NotReady` suele ser red o kubelet.
3. **¿Pod `Pending`?** `kubectl describe pod`: recursos, IP, taints.
4. **¿`ImagePullBackOff`?** Credenciales de OCIR, nombre/etiqueta, ruta de salida.
5. **¿Servicio sin balanceador?** Anotaciones, subred del LB y permisos del servicio.
6. **¿Identidad?** ServiceAccount y política ([workload identity](../../02-iam/workload-identity-oke/README.md)).
7. **¿Versión?** Plano y pools dentro de lo soportado.

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| `kubectl` agota el tiempo | API privada sin acceso | Bastion / VPN / NSG |
| Pod `Pending` | Sin recursos o sin IP | Escala pool / amplía subred |
| `ImagePullBackOff` | Secreto de OCIR o sin NAT | Crea el secreto; revisa rutas |
| LB en `<pending>` | Faltan permisos o subred | Política del clúster y subred del LB |
| 404 al llamar OCI desde un pod | Política de workload | Revisa los 4 atributos |
