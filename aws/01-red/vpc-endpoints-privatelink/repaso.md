# AWS · VPC Endpoints, PrivateLink y Route 53 · Repaso

## Preguntas
1. ¿Qué servicios usan endpoints de puerta de enlace?
   - *S3 y DynamoDB.*
2. ¿Cuánto cuesta el gateway?
   - *Nada.*
3. ¿Qué crea un endpoint de interfaz en tu subred?
   - *Una ENI con IP privada, una por AZ.*
4. ¿Qué hace el DNS privado?
   - *Hace que el nombre público del servicio resuelva a la IP privada del endpoint.*
5. ¿Por qué Fargate sin NAT necesita el endpoint de S3 para ECR?
   - *Las capas de las imágenes se descargan desde S3.*
6. ¿Qué limita una política de endpoint?
   - *Qué acciones y recursos pasan por él; no concede permisos por sí sola.*
7. ¿Cuándo PrivateLink en vez de peering?
   - *Para exponer un solo servicio, con CIDR solapados o entre muchas cuentas.*
8. ¿Qué condición fuerza que un bucket se use solo desde tu endpoint?
   - *`aws:SourceVpce` (o `aws:SourceVpc`).*
9. ¿Qué es un endpoint de Resolver saliente?
   - *Reenvía consultas DNS de AWS a la red local.*
10. ¿Cuándo el NAT sale más barato que un endpoint de interfaz?
    - *Con muy poco tráfico a un servicio poco usado.*

## Ejercicios
1. Lista los endpoints que necesita un Fargate en subredes sin NAT que lee secretos, escribe logs y consume SQS.
2. Escribe una política de bucket que solo acepte tráfico por tu endpoint.
3. Calcula el costo mensual de 8 endpoints en 3 AZ (con precios vigentes) y compáralo con el NAT.
4. Diseña la zona privada `modalima.internal` y su asociación a tres VPC.

## Autoevaluación
- [ ] Distingo gateway e interfaz.
- [ ] Sé verificar que el DNS resuelve a IP privada.
- [ ] Sé cuándo usar PrivateLink.
- [ ] Sé recortar con políticas de endpoint.
