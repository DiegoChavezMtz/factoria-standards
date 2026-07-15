# Flujo de trabajo — Factoría

Este documento describe cómo fluye el trabajo desde una idea hasta código
en producción, bajo el modelo de fábrica con agentes de IA. Es para
humanos: el detalle técnico exigible vive en AGENTS.md; el porqué de cada
regla vive en los ADRs (`docs/decisiones/`).

## El principio en una línea

**Los humanos deciden qué se construye y aprueban lo irreversible; los
agentes construyen; el CI hace cumplir las reglas sin importar quién
generó el código.**

## Las tres unidades de trabajo

| Unidad | Qué es | Quién la crea | Dónde vive |
|---|---|---|---|
| **Hito** | Meta de negocio de un proyecto (ej. "Onboarding completo") | Humano (planeación) | GitHub Projects / milestone |
| **Épica** | Feature descompuesta en Actividades | Humano + agente planeador | Issue con template `epica` |
| **Actividad** | Unidad ejecutable por UN agente en UNA sesión | Agente planeador, revisada por humano | Issue con template `actividad` |

La regla de tamaño de la Actividad no es negociable: si no cabe en una
sesión de agente, se descompone. El dropdown "TOO BIG" del template existe
exactamente para eso.

## El ciclo completo

### 1. Planeación (humano + agente planeador)
- Se toma un Hito y se descompone en Épicas, y cada Épica en Actividades.
- El agente planeador (típicamente Claude) redacta el lote de issues
  usando los templates.
- **Gate humano #1:** un humano revisa y ajusta el lote de issues ANTES de
  publicarlo. El issue es el prompt del ejecutor — issue mal escrito,
  código malo, con cualquier modelo.

### 2. Ejecución (agente ejecutor, el que sea)
- El agente (Codex, Claude Code, Gemini — da igual) toma UNA Actividad.
- Crea un branch: `type/numero-descripcion-corta`
  (ej. `feat/42-role-selection-step`).
- Trabaja dentro del alcance declarado en el issue. Si descubre trabajo
  fuera de alcance: NO lo hace — lo reporta como issue nuevo.
- Si una regla es ambigua para su caso, o la tarea parece requerir violar
  una frontera de capas: se detiene y lo señala en el PR ("Notes for
  reviewer"), en vez de improvisar.
- Antes de abrir el PR: corre lint y tests localmente y arregla lo que
  haya roto.

### 3. Validación (CI, automática, sin excepciones)
- El PR referencia su issue (`closes #N`) — sin issue no hay trabajo.
- Corren los gates:
  - **quality-gate**: lint, typecheck, tests, detección de tests
    saltados/debilitados.
  - **db-gate** (si hay cambios de schema): higiene de migraciones,
    aplicación desde cero en Postgres efímero, RLS, índices en FKs,
    naming de catálogos.
- CI rojo = no se mergea. No hay "lo arreglo después". No hay excepciones.

### 4. Revisión humana (solo donde importa)
- **Gate humano #2:** CODEOWNERS asigna revisión obligatoria únicamente
  para rutas críticas: migraciones, auth, políticas RLS, workflows de CI,
  dependencias nuevas, y la constitución misma.
- Todo lo demás fluye con revisión ligera. La velocidad viene de revisar
  poco; la seguridad, de revisar lo correcto.

### 5. Merge y cierre
- Merge a main cierra el issue automáticamente (`closes #N`).
- La Épica padre se actualiza sola (checkbox del task list).
- El tablero de GitHub Projects refleja el avance sin trabajo manual.

## Los dos gates humanos, resumidos

| Gate | Cuándo | Qué protege |
|---|---|---|
| #1 — Revisión del lote de issues | Antes de publicar la planeación | La calidad del input: el issue es el prompt |
| #2 — CODEOWNERS en rutas críticas | Antes del merge | Lo irreversible: schema, auth, el enforcement mismo |

Todo lo que no pasa por un gate humano pasa por el CI. Nada pasa por
ningún lado sin pasar por algo.

## Qué hacer cuando algo no encaja

- **¿La Actividad resultó más grande de lo estimado?** Se cierra el PR con
  lo que sí cabe del alcance original, y el resto se descompone en issues
  nuevos.
- **¿Dos branches crearon la misma numeración de migración?** El
  check-migrations.sh lo va a atrapar; se renumera la del branch que
  mergea segundo.
- **¿Una regla de AGENTS.md estorba de forma consistente?** No se ignora
  ni se rodea: se abre un PR contra factoria-standards proponiendo el
  cambio, con su ADR si aplica. Las reglas cambian por la puerta, no por
  la ventana.