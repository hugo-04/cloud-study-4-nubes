# Reglas permanentes del repositorio (léelas antes de tocar nada)

Repo de estudio de Hugo (ingeniero de software, español informal): 4 nubes **independientes** + módulos **transversales**. Fuente de consulta "de inicio a fin por servicio".

- **Aislamiento:** los archivos de una nube **nunca** mencionan otra nube. Transversales: sin nube.
- **Idioma/estilo:** español claro, prosa humana, tablas y listas cortas, supuestos explícitos, «verifica» en datos volátiles (precios, límites, versiones).
- **Subir siempre:** commit + push a `main` al terminar cada capítulo/módulo, sin preguntar. Termina los commits con:
  `Co-Authored-By: Claude <noreply@anthropic.com>`
- **Ahorro de tokens:** documentos compactos, validación ligera, no reinvestigar lo ya hecho.
- Empresas ficticias de ejemplo: **ModaLima** y **Café Andino**.
- Versiones objetivo: Java 21, Spring Boot 4.1.x, Quarkus 3.40.x, OCI SDK 3.97.2, Google libraries-bom 26.90.0, OpenTofu, provider `oracle/oci ~> 7.0`.

Estado, pendientes y cómo trabajar: **`HANDOFF.md`**.
