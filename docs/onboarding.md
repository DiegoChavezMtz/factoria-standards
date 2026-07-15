# Onboarding — Factoría

Para cualquier persona que se integra a un proyecto gobernado por
factoria-standards: empleados, subcontratistas, o tú-en-6-meses que ya
olvidó cómo funciona esto.

## Lo mínimo indispensable (día 1)

1. **Lee AGENTS.md** del repo en el que vas a trabajar. Son ~150 líneas.
   Es la ley. Los agentes de IA la reciben automáticamente; tú tienes que
   leerla una vez.
2. **Lee `docs/flujo-de-trabajo.md`** (5 minutos). Ahí está el ciclo
   completo: issue → branch → PR → CI → review → merge.
3. **No necesitas leer los ADRs hoy.** Están ahí para cuando preguntes
   "¿y por qué esta regla?" — cada regla dura de AGENTS.md referencia el
   suyo.

## Configura tu agente (día 1)

Trabajamos con múltiples herramientas de IA. Usa la que prefieras — las
reglas y el CI son los mismos para todas.

- **Claude Code**: no configures nada; el CLAUDE.md del repo ya importa
  AGENTS.md.
- **Codex**: no configures nada; lee AGENTS.md nativamente.
- **Gemini CLI**: no configures nada; el `.gemini/settings.json` del repo
  ya apunta a AGENTS.md.
- **Otra herramienta**: verifica que lea AGENTS.md al iniciar sesión. Si
  no lo soporta, pásaselo como primer mensaje en cada sesión — y avisa,
  para evaluar si la agregamos al estándar.

## Tu primer issue

1. Toma una Actividad del tablero que esté etiquetada como lista (no
   tomes nada marcado TOO BIG).
2. Lee el issue completo — especialmente la sección **"Explicitly OUT of
   scope"**. Es la que más previene retrabajo.
3. Branch con la convención `type/numero-descripcion` y a trabajar.
4. El PR template te guía en el resto. Los checkboxes no son adorno:
   revisor humano y CI asumen que lo que marcaste es cierto.

## Las 5 reglas que más se rompen al principio

1. **"Nada más le agrego esto rapidito"** — no. Fuera de alcance = issue
   nuevo. El scope creep es la causa #1 de PRs rechazados.
2. **Componente llamando directo a la base de datos** — el ESLint te lo va
   a marcar. La ruta es siempre componente → service → data.
3. **Editar una migración ya mergeada** porque "solo era un typo" — el CI
   lo rechaza. Migración nueva, siempre.
4. **Hardcodear un valor de catálogo** (`if (status === 'active')` contra
   un string mágico) — los valores fijos viven en tablas `cat_*` y se
   referencian por FK.
5. **Resolver un test que falla con `.skip()`** — el quality-gate lo
   detecta. Un test que estorba se arregla o se discute, no se apaga.

## Si el agente que usas hace algo raro

Los agentes a veces "reinterpretan" reglas para completar su tarea. Señales
de alerta que debes revisar antes de abrir el PR:

- Tocó archivos que el issue no mencionaba, en especial `/migrations` o
  cualquier cosa de auth.
- "Simplificó" borrando validaciones o debilitando tests.
- Metió una dependencia nueva sin que el issue la pidiera.

El PR es tuyo aunque lo haya escrito un agente. Tú lo firmas, tú
respondes por él.

## A quién preguntar

- Dudas de una regla o su porqué → el ADR referenciado; si no basta, al
  tech lead.
- La regla parece incorrecta para tu caso → sección "Notes for reviewer"
  del PR, o PR contra factoria-standards si es sistémico.
- Fallas del CI que no entiendes → el log del gate te dice tabla/archivo
  exacto; los mensajes están escritos para eso.