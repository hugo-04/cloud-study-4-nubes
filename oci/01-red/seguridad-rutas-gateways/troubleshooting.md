# Oracle OCI · Red · Listas de seguridad, NSG, rutas y gateways · Troubleshooting

## Lista ordenada
1. **Ruta:** ¿la tabla de rutas de la subred origen tiene la ruta al destino?
2. **Seguridad de salida:** ¿la lista o el NSG del origen permiten la salida?
3. **Seguridad de entrada:** ¿la lista o el NSG del destino permiten la entrada, con el protocolo y puerto exactos?
4. **NSG asignado:** ¿la VNIC realmente pertenece al NSG que usas como origen?
5. **Sin estado:** si la regla es sin estado, ¿existe la de retorno?
6. **Servicio:** ¿escucha en el puerto? (conexión rechazada vs *timeout*).

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| *Timeout* al conectar | Falta una regla de seguridad o una ruta | Revisa 1–3 con registros de flujo |
| Conexión rechazada | Llega pero nadie escucha | Revisa el servicio y su puerto |
| Funciona con IP pero no con nombre | DNS | [Unidad de endpoints y DNS](../endpoints-privados-dns/README.md) |
| Falla solo con paquetes grandes | ICMP tipo 3 código 4 bloqueado (MTU) | Permite ese ICMP |
| Regla nueva sin efecto | Está en otra lista/NSG que no aplica | Verifica asociaciones |
