# AWS · Ingress en EKS · Casos reales

Historias de ModaLima y Café Andino (ficticias).

## 1. Veinte Ingress, veinte ALB
**Qué pasó:** cada equipo creaba su Ingress y el controlador creaba un ALB por cada uno. **Solución:** `alb.ingress.kubernetes.io/group.name: tienda` en todos; un solo ALB con reglas por host/ruta. **Lección:** agrupa o pagas veinte balanceadores.

## 2. Errores 502 en cada despliegue
**Qué pasó:** al reemplazar pods, el ALB seguía enviando tráfico a pods que ya recibían SIGTERM. **Solución:** `preStop: sleep 15`, `terminationGracePeriodSeconds: 60`, `deregistration_delay` de 30 s y **readiness gate**. **Lección:** el balanceador necesita tiempo para enterarse.

## 3. El Ingress que nunca obtuvo dirección
**Qué pasó:** `kubectl get ingress` no mostraba `ADDRESS`. Las subredes no tenían la etiqueta `kubernetes.io/role/elb`. **Solución:** etiquetar subredes públicas e internas. **Lección:** el controlador descubre por etiquetas.

## 4. El controlador sin permisos
**Qué pasó:** los eventos decían `AccessDenied` al crear el ALB. La política del rol era una versión vieja que no cubría un permiso nuevo. **Solución:** política oficial de la versión instalada y Pod Identity. **Lección:** política y versión del controlador van juntas.

## 5. Un servicio interno expuesto a Internet
**Qué pasó:** alguien copió un Ingress de ejemplo con `scheme: internet-facing`. **Solución:** política de admisión que exige `internal` salvo en el *namespace* de borde, y revisión en el pipeline. **Lección:** crear un Ingress es publicar.

## 6. Mover el balanceador a Terraform sin cortar nada
**Qué pasó:** se quiso gestionar el ALB con Terraform (WAF, reglas) conservando los pods. **Solución:** `TargetGroupBinding` hacia el target group creado por Terraform. **Lección:** el controlador puede registrar pods en un balanceador que no creó.

| Problema | Solución |
|---|---|
| Muchos ALB | `group.name` |
| 502 al desplegar | preStop + gracia + readiness gate |
| Sin dirección | Etiquetas de subred |
| AccessDenied | Política oficial + Pod Identity |
| Exposición accidental | Admisión que exige `internal` |
| ALB en Terraform | TargetGroupBinding |
