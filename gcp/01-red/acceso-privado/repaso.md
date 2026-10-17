# Google Cloud · Red · Acceso privado · Repaso

## Preguntas
1. ¿Qué habilita PGA?
2. ¿Para qué es `restricted.googleapis.com`?
3. ¿Qué es un endpoint PSC?
4. ¿Por qué PSC necesita DNS privado?
5. ¿Qué es PSA?
6. ¿Qué servicios usan PSA?
7. ¿El acceso privado otorga permisos?
8. ¿Cómo resuelve la oficina los nombres privados?
9. ¿Qué publica un productor PSC?
10. ¿Cuándo usar NAT en vez de esto?

## Respuestas
1. Que subredes sin IP externa lleguen a APIs de Google.
2. Para acceder solo a APIs compatibles con VPC Service Controls.
3. Una IP de tu subred que conduce a un servicio.
4. Para que los clientes usen esa IP en lugar de la pública.
5. Un peering administrado para servicios con IP privada.
6. Cloud SQL, Memorystore y otros administrados.
7. No.
8. Con reenvío condicional hacia una política DNS entrante.
9. Un service attachment.
10. Para salir a Internet hacia terceros.

## Ejercicios
1. Diseña el acceso privado de un GKE privado de ModaLima.
2. Escribe la zona privada para un endpoint PSC.
3. Planifica el rango PSA para 10 instancias de Cloud SQL.
