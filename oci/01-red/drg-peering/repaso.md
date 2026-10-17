# Oracle OCI · Red · DRG, peering e híbrido · Repaso

## Preguntas
1. ¿Qué es una DRG y qué se adjunta a ella?
2. ¿Qué tres condiciones deben cumplirse para que un paquete cruce?
3. ¿Para qué sirve la distribución de rutas?
4. ¿Qué es hub-and-spoke?
5. ¿Qué diferencia hay entre LPG y RPC?
6. ¿Por qué un solo túnel IPSec es un riesgo?
7. ¿Qué pasa con CIDR solapados?
8. ¿La DRG filtra tráfico?
9. ¿Qué políticas necesitas para peering entre tenancies?
10. ¿Cuándo FastConnect en vez de VPN?

## Respuestas
1. Un router virtual regional; se adjuntan VCN, IPSec, circuitos virtuales y RPC.
2. Ruta en la subred origen hacia la DRG, ruta en la DRG hacia el destino, y reglas de seguridad que lo permitan.
3. Define qué rutas se aprenden automáticamente entre adjuntos.
4. Red central con servicios compartidos y redes de aplicación conectadas a ella.
5. LPG: misma región, directo; RPC: entre DRG de distintas regiones.
6. Una caída lo deja sin conectividad.
7. No se pueden conectar.
8. No; la seguridad sigue en listas/NSG y firewalls.
9. `endorse` y `admit` en los dos tenancies.
10. Ancho de banda estable, baja latencia o volúmenes grandes.

## Ejercicios
1. Diseña el hub-and-spoke para 3 spokes y una oficina.
2. Escribe las rutas de la subred app en un spoke.
3. Usa el verificador de [Java](uso-en-java.md) para comprobar 4 CIDR.
