# AWS · Red · VPC y subredes · Repaso

## Preguntas
1. ¿Qué hace pública a una subred?
   - *Una ruta `0.0.0.0/0` al Internet Gateway (más IP pública y SG que lo permitan).*
2. ¿Cuántas IP reserva AWS por subred?
   - *Cinco.*
3. ¿En cuántas AZ vive una subred?
   - *En una sola.*
4. ¿Por qué un NAT por AZ?
   - *Un NAT vive en una AZ; si esa AZ cae, las demás perderían salida.*
5. ¿Qué diferencia hay entre IGW y NAT Gateway?
   - *El IGW es bidireccional; el NAT solo permite salir.*
6. ¿Por qué los pods de EKS agotan subredes?
   - *Cada pod usa una IP de la VPC.*
7. ¿Cómo evitas pagar NAT por tráfico a S3?
   - *Con un endpoint de puerta de enlace de S3.*
8. ¿Para qué sirven los Flow Logs?
   - *Para ver tráfico aceptado/rechazado entre origen y destino.*
9. ¿Qué atributos de DNS necesitan los endpoints de interfaz?
   - *`enableDnsSupport` y `enableDnsHostnames`.*
10. ¿Se puede cambiar el CIDR primario de una VPC?
    - *No; solo añadir bloques secundarios.*

## Ejercicios
1. Diseña el plan de CIDR de dev, qa y prod en dos regiones sin solapes.
2. Calcula cuántas IP utilizables tiene una `/22`.
3. Escribe las rutas de una subred privada y de una de datos.
4. Crea la VPC con Terraform, destrúyela y recréala.

## Autoevaluación
- [ ] Explico por qué una subred es pública o privada.
- [ ] Sé dimensionar subredes para contenedores.
- [ ] Sé qué costos tiene el NAT.
- [ ] Sé activar y leer Flow Logs.
