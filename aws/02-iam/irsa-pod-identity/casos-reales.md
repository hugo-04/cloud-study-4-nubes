# AWS · IRSA y Pod Identity · Casos reales

Historias de ModaLima y Café Andino (ficticias).

## 1. Todos los pods con el rol del nodo
**Qué pasó:** un pod de pruebas comprometido leyó el IMDS y obtuvo el rol del nodo, que tenía acceso a todos los buckets. **Solución:** IMDSv2 obligatorio con salto 1, rol del nodo mínimo y un rol por ServiceAccount. **Lección:** el rol del nodo no es de la aplicación.

## 2. IRSA sin la condición `sub`
**Qué pasó:** la confianza del rol de facturas solo comprobaba el proveedor OIDC; otro equipo creó un ServiceAccount cualquiera y asumió el rol. **Solución:** condición `sub` con `system:serviceaccount:facturas:facturador`. **Lección:** en IRSA, `sub` es la puerta.

## 3. Un rol, siete clústeres
**Qué pasó:** con IRSA, la confianza del rol listaba siete emisores OIDC y alcanzó el límite de tamaño. **Solución:** migrar a Pod Identity: una confianza (`pods.eks.amazonaws.com`) y siete asociaciones. **Lección:** Pod Identity escala mejor entre clústeres.

## 4. «El pod no obtiene credenciales»
**Qué pasó:** tras migrar a Pod Identity, un servicio con SDK antiguo siguió usando el rol del nodo. **Solución:** actualizar el SDK; verificar con `GetCallerIdentity` al arrancar. **Lección:** comprueba qué identidad usa tu pod, no lo supongas.

## 5. Fargate y Pod Identity
**Qué pasó:** se asoció un rol con Pod Identity a pods en Fargate y no funcionó. **Solución:** usar IRSA en Fargate. **Lección:** revisa las compatibilidades antes de estandarizar.

## 6. Atribución con etiquetas de sesión
**Qué pasó:** CloudTrail mostraba el mismo rol para 30 pods. **Solución:** las etiquetas de sesión de Pod Identity (namespace, ServiceAccount, pod) permitieron atribuir acciones y condiciones ABAC por namespace. **Lección:** más contexto en cada llamada.

| Problema | Solución |
|---|---|
| Rol del nodo expuesto | IMDSv2, salto 1, rol mínimo |
| Confianza sin `sub` | Condición `sub` y `aud` |
| Límite de confianza | Pod Identity |
| SDK antiguo | Actualizar y verificar |
| Fargate | IRSA |
| Auditoría débil | Etiquetas de sesión |
