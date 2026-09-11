# ALDC canónico: perfil nativo BC29 / AL18

Adaptación optativa para **GitHub Copilot Chat en VS Code**. Mantiene los diez
agentes, los documentos, las aprobaciones y el Conductor completo. No incorpora
la orquestación de ALDC Graph. No es una release ni una certificación de BC29.

## Base y distribución

Revisión del 11 de septiembre de 2026. Base inicial inspeccionada:
`de21a8a1e6704f6dca273b1637475367b28aa58b` (`main`, PR #96), posterior a
`4f3371f69c3013edb508540673f60e5e8a0b64b6` del handoff. Antes de entregar,
`main` avanzó a `c8cb3c078f10a993194c0807329faecadfc60466` (PR #89,
correcciones independientes de vocabulario Claude y su espejo). Se incorporó
esa base sin alterar sus cambios; la propuesta parte de `c8cb3c0`.
Referencia consultada: [NATIVE29-001, PR #81](https://github.com/javiarmesto/ALDC-Research-Lab/pull/81),
todavía abierta al revisarla, en `7d06c607677188477994b4b1c0db50bc0b75ed7b`.
Se reutilizan decisiones de herramientas, no sus agentes, Doctor ni contratos de ejecución.

| Fuente | Copia o consumidor | Tratamiento |
| --- | --- | --- |
| `agents/`, `prompts/`, `instructions/`, `skills/` | `packages/foundation/` | Editar raíz; ejecutar `sync-foundation.js`. Nunca editar el espejo a mano. |
| Agentes y prompts de raíz | Instalador npm/local | BC28 copia original; BC29 proyecta permisos y contratos al instalar. |
| `claude-plugin/` | `.claude/` | Fuente independiente; sin cambios ni traslado de nombres VS Code. |
| `agents/` y `skills/` | Plugin Copilot de raíz | Conserva su superficie actual; el nuevo perfil se selecciona con el instalador. |
| `docs/agents/`, `docs/prompts/` | Documentación histórica | No son la fuente de instalación; la matriz de este documento describe el perfil nuevo. |

`scripts/native-profile.js` transforma la fuente canónica, sin guardar otra copia
completa de los agentes. La proyección falla si aparece un agente sin asignación
de permisos o cambia la sección del Developer que necesita adaptación.
Las skills existentes incorporan conocimiento condicionado a la versión; su
espejo `foundation` se regenera. No se ha cambiado la distribución Claude.

Los workflows versionados publican documentación con push a `main` y releases con
tags `v*.*.*` o ejecución manual. Crear esta rama no activa esos destinos. La PR
sí activa validaciones. El linter existente usa `--fix`; se añade una condición
para que no haga commit/push en PRs **draft**. El trabajo queda revisable sin
reescrituras automáticas masivas. Al convertirla a lista para revisión volverá
a aplicarse su comportamiento previo. No se han inspeccionado webhooks externos
de administración ni se garantiza el comportamiento de servicios no versionados.

## Selección e instalación

Trabaja sobre una copia de prueba del proyecto. No ejecutes el instalador desde
la raíz del repositorio canónico: su destino es el directorio de trabajo actual.
Obtén esta rama en un checkout independiente y anota su commit:

```powershell
git clone --branch feat/canonical-bc29-al18 https://github.com/javiarmesto/ALDC-AL-Development-Collection.git ALDC-native29
git -C ALDC-native29 rev-parse HEAD
$aldcInstaller = (Resolve-Path .\ALDC-native29\scripts\install.js).Path
# Cambia a TU copia de prueba antes de instalar:
Set-Location C:\src\MiProyecto-Prueba
node $aldcInstaller install --profile bc29-native --yes
```

Si ya contiene una instalación BC28, revisa y conserva tus personalizaciones;
para sustituir los archivos administrados usa:

```powershell
node $aldcInstaller install --profile bc29-native --force --yes
```

La selección no modifica `app.json`, runtime, GUID, dependencias, entorno ni
fuentes AL. El instalador mantiene sus operaciones habituales sobre el toolkit
y `aldc.yaml`; `--force` reemplaza archivos administrados, incluidas instrucciones
personalizadas. La memoria de proyecto existente se conserva. No hay publicación.
El marcador `<target-dir>/aldc-profile.json` registra solo la selección, nunca
capacidad verificada. Actualizar sin `--profile` conserva la selección registrada.

Para volver a la superficie BC28:

```powershell
node $aldcInstaller install --profile bc28 --force --yes
```

Esto revierte contratos de herramientas, no cambios del proyecto que hayas hecho
durante la prueba. Las instalaciones nuevas sin `--profile` siguen usando BC28.
Se admite `--target-dir`; en VS Code debes configurar el descubrimiento de agentes
y skills si eliges una ubicación diferente de `.github`.

Recarga VS Code y comprueba qué definición de cada agente ha cargado. Evita tener
simultáneamente el plugin canónico y la instalación local con los mismos nombres.
Instalar el plugin Marketplace actual **no selecciona BC29**. Copilot CLI, Claude
Code y Codex requieren adaptación/validación propia; no uses este perfil allí.
No se exige BC Atlas ni el puente comunitario de símbolos/LSP. Las operaciones
no cubiertas por lo nativo se anotan como limitación; no se presupone equivalencia.
BCQuality sigue siendo opcional mediante el proveedor/plugin que tengas disponible.

Para revisar los agentes generados sin instalar en ningún proyecto:

```powershell
node .\ALDC-native29\scripts\native-profile.js C:\temp\ALDC-native29-review
```

El destino debe ser nuevo y externo al checkout. Esta exportación contiene
agentes/prompts y su contrato; la instalación completa se realiza con el instalador.

## Inventario por agente y flujo

La especificación corresponde a **`al-spec.create`**, no a un agente adicional.
Todos los contratos proyectados indican cuándo leer y aplicar
[el contrato nativo](framework/native-al-tools.md).

| Agente o función | Cambio y motivo | Flujo conservado |
| --- | --- | --- |
| Architect | Búsqueda/diagnósticos nativos para viabilidad y dependencias; consume grafo si aporta. | Diseña arquitectura; no convierte declaraciones de implementación en un bloqueo general. |
| `al-spec.create` | Búsqueda/diagnósticos, propuesta de dependencias; dudas de librerías quedan en Open Questions. | Escribe `.spec.md` desde arquitectura; no modifica manifiestos ni implementa. |
| Planning Subagent | Búsqueda/diagnósticos para lagunas concretas. | Devuelve hallazgos al Conductor reutilizando decisiones aprobadas. |
| Developer | Corrige `al_getdiagnostics`, habilita `al_build`; conserva descarga y depuración. | Implementación táctica, compilación, tests y grafo opcional por terminal. |
| Implementation Subagent | Búsqueda, diagnóstico, descarga y compilación nativa. | RED → GREEN → REFACTOR; ejecuta consultas acotadas del grafo cuando sirven. |
| Review Subagent | Búsqueda/diagnósticos; retira depuración de su perfil nativo de revisión. | Contrasta fuentes, compilación y tests reales; devuelve el veredicto existente. |
| Dredd | Búsqueda/diagnósticos; examina evidencia bruta con su propio criterio. | Auditoría independiente, sin sustituir aprobaciones ni ejecutar grafo. |
| Triage | Búsqueda/diagnósticos/descarga y depuración autorizada. | Diagnostica; entrega la corrección al Developer. |
| Presales | Solo búsqueda nativa para cuestiones de viabilidad pertinentes. | Estimación y propuesta; sin compilar ni ejecutar grafo. |
| Agent Builder | Búsqueda/diagnósticos para SDK y objetos relevantes. | Mantiene diseño/creación; delega ejecución técnica correspondiente. |
| Conductor | Añade alcance y referencias; sin herramientas nativas de ejecución. | Conserva íntegro su cuerpo, coordinación, agentes, modelos y aprobaciones. |

También se proyectan los prompts: se eliminan permisos obsoletos, se limita la
compilación a `al-build`, se mantiene descarga en `al-initialize` y no se añade
publicación. Un permiso amplio de editor no cambia las responsabilidades del rol.

## Guion local en Copilot Chat

Registra cada paso en los documentos existentes de la prueba, con referencia a
la traza. No basta que el agente afirme que tiene una herramienta o una skill.

1. **Entorno de prueba.** Abre App/Test, registra versiones de VS Code, Copilot,
   AL Language/ALTool, BC y paquetes. Confirma target/entorno antes de conectar.
   Lee el contrato nativo; conserva la traza de lectura y el esquema instalado.
2. **Búsqueda local, Architect.** «Localiza el objeto Customer con búsqueda nativa,
   identifica su procedencia y explica qué parte está verificada. No implementes».
   Debe ejecutar `al_symbolsearch`, con los parámetros reales del esquema.
3. **Entorno, si procede.** Elige un objeto de una app instalada que todavía no sea
   dependencia. Comprueba soporte de `filters.source = "environment"`; busca y
   conserva identidad del propietario. Architect/spec propone la dependencia.
   Developer aplica solo el cambio autorizado, descarga y repite búsqueda local.
   Si no hay soporte/conexión/objeto adecuado, registra «no ejecutado» y el motivo.
4. **Especificación.** Ejecuta `al-spec.create` con librerías de tests cuya versión
   difiera de la app. Debe evaluar semántica de dependencia, escribir lo conocido
   y anotar la incertidumbre; no exigir igualdad numérica ni inventar compatibilidad.
5. **Compilación, Developer.** «Compila App y Test con las herramientas nativas,
   conservando el resultado de cada proyecto. No publiques». Usa `scope: current`
   por proyecto o `all` solo si todos están autorizados. Conserva salidas y `.app`.
6. **Tests.** Ejecuta el runner habitual únicamente cuando esté autorizado y
   disponible. Separa escritos, compilados y ejecutados; conserva passed/failed/skipped.
   No declares tests superados por ausencia de errores en Problems.
7. **Grafo opcional, Developer/Implementer.** Comprueba versión/help como indica el
   contrato. Elige una entrada pública hacia una implementación interna o un cruce
   de aplicación. Extrae solo las fuentes pertinentes, ejecuta la consulta y
   conserva comando, versión, corpus, resultado y limitaciones. Exporta solo si
   interesa navegar el resultado y el formato está disponible.
8. **Review y Dredd.** Entrega referencias a evidencia bruta. Deben distinguir
   resultados de compilación, tests y alcance estático; Dredd mantiene su revisión
   independiente. Una ruta no prueba ejecución, fuga ni vulnerabilidad.
9. **Conductor.** Recorre planificación, implementación y revisión con los gates
   actuales. Comprueba que pasa referencias, no ejecuta herramientas por los otros
   roles y no exige Doctor ni un grafo para terminar un requisito que no lo necesita.

Para una novedad de lenguaje concreta, sigue solo su sección en las skills de
migración, rendimiento, testing, traducción o depuración. No añadas las seis por defecto.

## Estado de validación

| Estado | Evidencia |
| --- | --- |
| Verificado localmente | Instalación real en directorios temporales BC28/BC29, cambio/retorno de perfil, destino alternativo, preservación de memoria y `app.json`, permisos y referencias; 177 comprobaciones automatizadas. |
| Verificado estáticamente | Diez agentes; Conductor original completo en la proyección; modelos y handoffs conservados; nombres nativos contrastados con catálogo; sin nuevos permisos de publicación. |
| Verificado en fuentes | Catálogo LM desde AL17 y anuncios BC29; no equivalen a ejecución en el equipo del usuario. |
| Declarado, pendiente de confirmar | Esquemas instalados, opciones exactas del grafo y algunas declaraciones AL18. `publicResourceFolders`/recursos públicos NavApp no se localizaron en las páginas oficiales consultadas. |
| Pendiente local | Lectura real de referencias por Copilot, búsqueda en entorno, compilación App/Test BC29, runner y consultas/exportaciones reales de `al graph`; Windows y versión mínima de Node. |

Comandos reproducibles desde este checkout (Node 20+ para validación de desarrollo):

```bash
npm ci
npm run validate
node scripts/check-conformance.js
node scripts/sync-foundation.js --check
node scripts/sync-claude-workspace.js --check
git diff --check
```

`npm run validate` incluye las pruebas nuevas. Las pruebas de instalación usan
directorios temporales y el modo offline de npm; no ejecutan AL ni conectan a BC.
El validador de colección conserva 77 avisos preexistentes y 0 errores; la prueba
de esta adaptación no declara esos avisos como capacidades verificadas.
