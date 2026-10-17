# Oracle OCI · Red · VCN y subredes · Repaso

## Preguntas
1. ¿Qué es una subred regional y por qué se prefiere?
2. ¿Cuántas direcciones reserva OCI por subred?
3. ¿Qué diferencia hay entre NAT Gateway y Internet Gateway?
4. ¿Para qué sirve el Service Gateway?
5. ¿Qué pasa si dos VCN tienen CIDR solapados?
6. ¿Quién resuelve el DNS dentro de la VCN por defecto?
7. ¿Qué subredes deben ser públicas en una tienda típica?
8. ¿Por qué dimensionar la subred de OKE por pods?
9. ¿Qué regla de ruta usa una subred privada para salir?
10. ¿Por qué separar el compartimento de red del de aplicaciones?

## Respuestas
1. Abarca todos los AD de la región; evita atar recursos a un AD concreto.
2. Tres: la de red, la del gateway y la de difusión.
3. El IGW permite entrada y salida; el NAT solo salida iniciada desde dentro.
4. Alcanzar servicios de Oracle (como Object Storage) sin pasar por Internet.
5. No se pueden conectar por peering o DRG.
6. El resolutor de la VCN, a través de las opciones DHCP.
7. Solo la del balanceador (y un bastión si hace falta).
8. Con red de pods nativa cada pod consume una IP.
9. `0.0.0.0/0` hacia el NAT Gateway.
10. Para que quien define la red no sea quien la usa y para aplicar permisos distintos.

## Ejercicios
1. Calcula las IP utilizables de `/24`, `/27` y `/28`.
2. Diseña el CIDR de 3 VCN (prod, dev, red central) sin solapamientos.
3. Escribe las rutas de la subred privada de la app.
