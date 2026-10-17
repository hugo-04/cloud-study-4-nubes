#!/usr/bin/env bash
# Rutina diaria con módulos y entornos. Léelo como guía; cambia las rutas a las tuyas.
set -euo pipefail

# ---- Calidad local (lo mismo que corre el pipeline) -----------------------------------
terraform fmt -recursive -check          # formato
terraform -chdir=modulos/app-base init -backend=false
terraform -chdir=modulos/app-base validate
terraform -chdir=modulos/app-base test   # pruebas con proveedor simulado (tests/*.tftest.hcl)
tflint --recursive                       # lint (con el plugin de Azure en .tflint.hcl)
trivy config .                           # seguridad de la configuración (o checkov -d .)

# ---- Un entorno: init con su backend y su plan ------------------------------------------
cd envs/prod
terraform init -backend-config=backend.prod.hcl
terraform plan -var-file=prod.tfvars -out=tfplan
terraform show -no-color tfplan | head -80

# ---- Versiones: fijar y actualizar con intención -------------------------------------------
terraform init -upgrade                  # sube proveedores y módulos dentro de sus restricciones
terraform providers lock -platform=linux_amd64 -platform=darwin_arm64 -platform=windows_amd64   # .terraform.lock.hcl para todo el equipo
terraform providers                      # qué módulo pide qué proveedor y versión

# ---- Publicar una versión de un módulo (repositorio de módulos con etiquetas) ---------------
# git tag -a v1.3.0 -m "app-base: añade 'lectores'" && git push origin v1.3.0
# En el consumidor: source = "git::https://github.com/modalima/tf-modulos.git//app-base?ref=v1.3.0"

# ---- Explorar y depurar -----------------------------------------------------------------
terraform console -var-file=prod.tfvars  # evalúa expresiones: for_each, locals, funciones
terraform graph | dot -Tsvg > grafo.svg  # dependencias (necesita graphviz)
terraform state list                     # direcciones que ya existen en el estado
terraform plan -refresh-only             # solo comparar estado y realidad

# ---- Traer lo que ya existe ------------------------------------------------------------
# 1) Escribe el bloque import { to = ... id = ... } y genera el código inicial:
terraform plan -generate-config-out=generado.tf     # revisa y limpia el resultado antes de usarlo
# 2) O exporta un grupo de recursos entero con aztfexport (herramienta aparte):
# aztfexport resource-group rg-heredado-prod

# ---- Forzar un reemplazo y limitar el alcance (con cuidado) ----------------------------------
terraform apply -replace='module.app["pedidos"].azurerm_storage_account.this'
# -target solo para emergencias: deja el estado a medias respecto al código.
