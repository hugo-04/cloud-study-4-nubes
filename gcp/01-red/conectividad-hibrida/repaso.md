# Google Cloud · Red · Conectividad · Repaso

## Preguntas
1. ¿Qué significa que el peering no es transitivo?
2. ¿Qué rutas se intercambian siempre en un peering?
3. ¿Cuándo prefieres Shared VPC?
4. ¿Por qué HA VPN y no la clásica?
5. ¿Qué hace Cloud Router?
6. ¿Qué cambia el modo de enrutamiento global?
7. ¿Qué diferencia hay entre Dedicated y Partner Interconnect?
8. ¿El peering abre puertos de firewall?
9. ¿Dónde guardas el secreto de la VPN?
10. ¿Qué opción expone un servicio sin unir redes?

## Respuestas
1. Si A↔B y B↔C, A no llega a C.
2. Las de subred.
3. Dentro de una misma organización.
4. Por redundancia y SLA con dos túneles y BGP.
5. Intercambia rutas por BGP y gestiona NAT.
6. Que las rutas aprendidas sirvan en todas las regiones.
7. Dedicated es un enlace físico propio; Partner, vía un proveedor.
8. No.
9. En Secret Manager.
10. Private Service Connect.

## Ejercicios
1. Diseña la conexión de la oficina de ModaLima con HA VPN y BGP.
2. Decide entre peering y Shared VPC para analítica.
3. Escribe la verificación de solapes antes de un peering.
