# Google Cloud · Compute · Compute Engine · Repaso

## Preguntas
1. ¿Qué es una plantilla de instancia?
2. ¿Qué hace un MIG?
3. ¿Qué es una VM Spot?
4. ¿Qué aporta Shielded VM?
5. ¿Qué es OS Login?
6. ¿Qué cuesta una VM detenida?
7. ¿Por qué un MIG regional?
8. ¿Cómo se hace SSH sin IP externa?
9. ¿Qué cuenta de servicio usar?
10. ¿Cuándo prefieres Cloud Run?

## Respuestas
1. Una configuración inmutable para crear VMs iguales.
2. Mantiene el número de VMs, autoescala, autocura y actualiza.
3. Una VM barata que Google puede interrumpir.
4. Arranque seguro, vTPM y monitoreo de integridad.
5. SSH con identidades de IAM.
6. Discos e IPs reservadas.
7. Reparte entre zonas para tolerar la caída de una.
8. Con IAP.
9. Una propia con roles mínimos.
10. Para contenedores HTTP sin estado.

## Ejercicios
1. Diseña la plantilla del ERP de ModaLima.
2. Calcula el ahorro de Spot para 200 horas de lotes al mes.
3. Escribe la política de actualización del MIG.
