# Continuación de ALDC canónico

Entrega activa: handoff 01, revisión y cierre de la PR #97. Fecha: 2026-09-14.
El handoff 02 sigue pendiente de un encargo posterior.

## Base y revisión

- Canónico: `javiarmesto/ALDC-AL-Development-Collection`.
- Main inicial: `c8cb3c078f10a993194c0807329faecadfc60466`.
- Head inicial #97: `3a35dc5c2940d14f3113bdf02f22db1e9f86d791`.
- Se comprobó que #97 estaba abierta, draft y era la única PR abierta del
  canónico. Sin revisiones ni hilos bloqueantes. Se leyeron cuerpo y comentarios,
  los 122 archivos de la lista completa (páginas de 100 y 22), diff de fuentes,
  instalador, proyector, generadores y workflows. No hay AGENTS.md en este árbol.
- Se conserva la misma rama, sin rebase ni restauración de snapshots.
- El commit de integración, checks finales y estado de la rama se consultan en
  [PR #97](https://github.com/javiarmesto/ALDC-AL-Development-Collection/pull/97).
  La integración queda condicionada a los checks del head corregido; la rama
  solo se retira tras comprobar que ese head es ancestro de main.

## Correcciones de esta revisión

1. `scripts/native-profile.js` rechazaba frontmatter CRLF. Se reprodujo el fallo
   con el Conductor y se corrigió normalizando solo para la proyección y
   restaurando el final de línea original. Se conserva el cuerpo completo.
2. El generador CLI dejaba `TodoWrite` sin traducir cuando no llevaba backticks.
   Se corrigió en el generador y se regeneró el comando de memoria.
3. Las instrucciones instaladas y la ayuda mezclaban recuentos antiguos; se
   ajustaron al inventario, al orden arquitectura → spec para MEDIUM/HIGH y al
   carácter opcional de BCQuality. Foundation se regeneró desde la fuente.
4. Las guías separan main canónico de la rama de la extensión y explican las
   sobrescrituras reales. No se presenta vuelta de perfil como restauración.

## Comprobaciones ejecutadas y límites

Linux, Node `v24.19.0`. `npm ci --no-audit --no-fund` terminó correctamente con el
lockfile existente; el intento offline previo falló por falta de caché js-yaml.
No se modificaron dependencias ni lockfile.

| Comprobación | Resultado local |
| --- | --- |
| `npm run validate` | 0 errores de colección, 77 avisos preexistentes; 212 comprobaciones de perfil y 204 de empaquetado CLI |
| `node scripts/check-conformance.js` | 57 comprobaciones superadas |
| `node scripts/sync-foundation.js --check` | 71 archivos consistentes |
| `node scripts/sync-claude-workspace.js --check` | 40 archivos consistentes |
| `node scripts/sync-copilot-cli.js --check` | 52 archivos consistentes, sin drift |
| `git diff --check` | Correcto |

Las instalaciones se ejecutaron únicamente en fixtures temporales: BC28 por
omisión, BC29 nuevo, rechazo de mezcla sin force, actualización sin perfil,
retorno a BC28, destino alternativo e instalación desde fuentes CRLF. Se verificó
la conservación de memoria, manifest de App/Test, fuentes AL y settings de VS Code.

| Operación | Personalizaciones de toolkit/configuración |
| --- | --- |
| `install --yes` sin force, mismo perfil | Conserva archivos existentes porque los omite; no es una actualización completa |
| `install --force --yes` | Sobrescribe `aldc.yaml`, `aldc.code-workspace`, entrada Copilot e instrucciones; requiere copia/revisión previa |
| Cambio/retorno de perfil con force | Cambia contratos; conserva memoria y proyecto AL, pero no restaura personalizaciones sobrescritas |

CRLF se probó sobre Linux, no en una sesión Windows. No están disponibles Claude,
Copilot CLI ni VS Code ejecutable; el comando `code` es un wrapper que indica que
no está instalado. No se verificaron descubrimiento/carga real de roles, lectura
por el modelo, compilación App/Test ni runner BC. Architect y Conductor largos
siguen pendientes de carga completa por host; no se han recortado. Se comprobaron
permisos/referencias estáticamente, sin afirmar operación nativa observada.

No se ejecutó `test-local-install.js`: depende del checkout de la extensión y
prepara su paquete. La PR externa
[aldc-vscode-extension #1](https://github.com/javiarmesto/aldc-vscode-extension/pull/1)
seguía abierta en `adb0f26a5008d127c14c05938fb8723a244900b2` al consultar; queda
fuera de esta autorización. No hay release, tag, publicación ni despliegue BC.

Automatizaciones: el workflow de documentación está activo y un merge a main
activa su publicación habitual en GitHub Pages. El linter versionado usa fix y
puede escribir en PRs no draft, pero su estado remoto consultado fue
`disabled_manually`; no se reactivó ni modificó esa configuración. Release solo
se dispara por tag o ejecución manual. Branch main figura sin protección y no
hay rulesets; el endpoint administrativo de protección devuelve 403, sin intentar
cambiar protecciones. Los validadores aplicables se respetan igualmente.

## Delta concreto para la siguiente entrega de empaquetado

Fuente de consulta: [EXTRACTION.md](https://github.com/javiarmesto/ALDC-Research-Lab/blob/0f49d44a99f626a5e8a88d316b7041bfbc6860fb/research/canonical-reuse-001/EXTRACTION.md)
y `donors.json` en el mismo SHA. Lab se consultó, no se modificó.

Ya existe: selección BC28/BC29 en Chat, contratos terminales, plugin Claude,
CLI separado con diez agentes/diez comandos, modelos por superficie, traducción
de reglas, referencias empaquetadas y los tres generadores con checks de drift.
No hace falta copiar otros generadores ni las primitivas de Graph para repetirlo.

1. **Procedencia e inicialización:** comparar `scripts/sync.mjs`,
   `provenance.json`, `scripts/init.mjs` y `hooks/session-context.mjs` de
   `plugins/claude-code/aldc-graph/` en Lab `b2ce9d9f137fc92574261317294ca2d585beb74b`.
   Añadir solo procedencia/hash y contexto inicial útil a los mecanismos actuales.
   Contrastar `build_copilot_commands.py` con el generador CLI existente sin
   introducir uno paralelo.
2. **Instalación segura y recuperación:** adaptar lo necesario del motor y tests
   `experiments/chat-install-001/` en `0c2a14731507c24782718cc739c74676b3528f17`.
   Faltan detección de colisiones/drift del consumidor y backup/restauración cuando
   se prometan. La escritura atómica por archivo no garantiza rollback global.
3. **Codex canónico:** adaptar `plugins/codex/aldc-graph/skills/aldc-graph/`
   (`install_runtime.py`, locks y bloque gestionado) del mismo donante `b2ce9d9`.
   Regenerar roles desde canónico y excluir overlay/runtime Graph. Recuperar
   `run_python.ps1` solo si este adaptador necesita Python, sin instalarlo ni
   cambiar PATH. #97 no añade compatibilidad Codex.
4. **Prueba por host:** verificar carga completa y procedencia de roles/comandos,
   actualización con memoria/personalizaciones y ausencia de duplicados en
   proyectos aislados. Revisar después la PR externa del VSIX si se autoriza;
   regenerar sus plantillas desde el main integrado. No publicar como parte de
   estas pruebas ni certificar hosts por contar archivos.

No copiar DAG, Evidence Store, Context Envelope, fingerprints por transición,
Run Health Graph ni runtime completo. Doctor y Spec Agent siguen fuera de #97.
