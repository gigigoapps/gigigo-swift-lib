---
name: validate-ci-tests
description: Validar cambios en el repo del proyecto GIGLibrary compilando y ejecutando los tests locales con el comando fijo definido en este skill. Usar cuando se pida validar cambios o ejecutar tests locales de la gigigo swift lib.
---

# Validate Tests

## Objetivo

Ejecutar localmente el comando de tests definido en este skill para validar cambios.

## Flujo de validacion

1. Ejecutar localmente el comando de tests definido en este skill, sin modificar flags ni destinos.
2. Confirmar que `xcodebuild` completa el build y los tests sin errores.

## Comando fijo para este repo

En este repo, el comando de tests es:

```bash
xcodebuild -scheme GIGLibrary -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest' test
```
