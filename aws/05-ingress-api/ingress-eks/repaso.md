# AWS · Ingress en EKS · Repaso

## Preguntas
1. ¿Qué crea el AWS Load Balancer Controller?
   - *ALB para Ingress y NLB para Service LoadBalancer, y registra los pods.*
2. ¿Ventaja del modo `ip`?
   - *Tráfico directo al pod, sin pasar por NodePort.*
3. ¿Para qué sirve `group.name`?
   - *Compartir un ALB entre varios Ingress.*
4. ¿Qué es el readiness gate?
   - *Condición que mantiene al pod no-Ready hasta que el ALB lo ve sano.*
5. ¿Por qué etiquetar las subredes?
   - *El controlador las descubre por etiquetas.*
6. ¿Cómo obtiene permisos el controlador?
   - *Con Pod Identity (o IRSA) y la política oficial.*
7. ¿Qué es un TargetGroupBinding?
   - *Enlace de un Service a un target group existente.*
8. ¿Cómo evitas 502 al desplegar?
   - *preStop, gracia de terminación, deregistration delay y readiness gate.*
9. ¿Por qué crear un Ingress es una decisión de seguridad?
   - *Puede publicar un servicio a Internet.*
10. ¿Qué papel tiene external-dns?
    - *Crear los registros DNS a partir del Ingress.*

## Ejercicios
1. Escribe un Ingress agrupado con dos hosts y HTTPS.
2. Calcula preStop, gracia y deregistration delay coherentes.
3. Plantea una política de admisión que exija `scheme: internal`.
4. Describe la migración de un ALB del controlador a Terraform con TargetGroupBinding.

## Autoevaluación
- [ ] Sé instalar y dar permisos al controlador.
- [ ] Sé agrupar Ingress y proteger la publicación.
- [ ] Sé coordinar el apagado de los pods con el ALB.
- [ ] Sé diagnosticar un Ingress sin dirección.
