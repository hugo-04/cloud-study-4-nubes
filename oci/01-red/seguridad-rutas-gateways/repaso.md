# Oracle OCI · Red · Listas de seguridad, NSG, rutas y gateways · Repaso

## Preguntas
1. ¿Cuál es la diferencia entre lista de seguridad y NSG?
2. ¿Existen reglas de denegación?
3. ¿Qué pasa si una VNIC está cubierta por una lista y un NSG?
4. ¿Qué significa «con estado»?
5. ¿Para qué se usa un NSG como origen de una regla?
6. ¿Cómo se elige entre dos rutas que coinciden?
7. ¿Por qué no abrir 22 a `0.0.0.0/0`?
8. ¿Qué ICMP conviene permitir y por qué?
9. ¿Cuántos NSG puede tener una VNIC (orientativo)?
10. ¿Qué reglas usarías para una app de tres capas?

## Respuestas
1. La lista aplica a toda la subred; el NSG a VNIC concretas y puede referenciar otros NSG.
2. No; todo lo no permitido se deniega.
3. Se permite si cualquiera de las dos lo permite.
4. La respuesta de una conexión permitida se admite sin regla adicional.
5. Para permitir tráfico «desde cualquiera de ese rol» sin conocer IP.
6. Gana el prefijo más largo.
7. Expone el acceso administrativo a ataques; usa Bastion.
8. ICMP tipo 3 código 4 (fragmentación necesaria) para el descubrimiento de MTU.
9. Hasta 5 (verifica).
10. NSG-lb (443 desde Internet), NSG-app (8080 desde NSG-lb), NSG-datos (5432 desde NSG-app).

## Ejercicios
1. Escribe las reglas de NSG para lb → app → datos.
2. Encuentra en una lista de reglas dada las que sean peligrosas.
3. Diseña la tabla de rutas de la subred app con NAT, Service Gateway y on-premises.
