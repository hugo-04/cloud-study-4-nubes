# AWS · Peering y Transit Gateway · Repaso

## Preguntas
1. ¿Qué significa que el peering no sea transitivo?
   - *A↔B y B↔C no dan A↔C.*
2. ¿Cuántos peerings requiere una malla completa de 6 VPC?
   - *15 (n·(n−1)/2).*
3. ¿Qué dos acciones requiere activar un peering?
   - *Aceptarlo y poner rutas en ambas VPC.*
4. ¿Qué es una asociación en un TGW?
   - *La tabla de rutas que usa un adjunto para enrutar su tráfico.*
5. ¿Y una propagación?
   - *Publicar las rutas de un adjunto en una tabla.*
6. ¿Cómo evitas que prod alcance dev en un TGW?
   - *Tablas separadas y asociaciones/propagaciones distintas.*
7. ¿Cuándo es mejor un peering que un TGW?
   - *Pocas VPC o pares con muchísimo tráfico, por costo.*
8. ¿Qué haces con CIDR solapados?
   - *PrivateLink o renumerar.*
9. ¿Para qué sirve el modo aparato?
   - *Mantener la misma AZ de ida y vuelta con firewalls en línea.*
10. ¿Cómo compartes un TGW con otras cuentas?
    - *Con AWS RAM.*

## Ejercicios
1. Dibuja un TGW con tablas `prod`, `dev` y `compartida` y las propagaciones necesarias.
2. Calcula el costo mensual de 5 adjuntos y 20 TB (precios vigentes) frente a 2 peerings.
3. Escribe las rutas de las tablas de dos VPC con peering.
4. Lista los pasos para sumar la VPC número 7.

## Autoevaluación
- [ ] Sé elegir entre peering, TGW y PrivateLink.
- [ ] Sé segmentar con tablas del TGW.
- [ ] Sé qué rutas faltan cuando «está conectado y no pasa nada».
