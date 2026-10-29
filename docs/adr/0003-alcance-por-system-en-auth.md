# ADR-0003 · Alcance por `system` en `auth`

- **Estado:** ✅ Aceptada · el usuario confirmó el 2026-10-08 el modelo (cuenta global, un rol por `system`), el árbol de accesos guardado y que los roles y permisos son propios de cada `system`.
- **Fecha:** 2026-10-08
- **Alcance:** cómo `auth` relaciona usuarios, roles y permisos con `system`. **No** cubre las credenciales/tokens de servicio (`aud=system`) — siguen en el [doc 09](../09-pendientes.md), D1.

## Contexto

[ADR-0001](0001-estructura-repos-servicios.md) fijó que `auth` se reutilizará en otros proyectos. Pero el modelo inicial no lo permitía: `system` era una tabla suelta, `role` y `permission` eran un catálogo global y cada usuario llevaba un único `role_id` en `app_user`. Con eso, un segundo proyecto compartiría los roles y permisos de I Found It, y una persona no podría tener un rol distinto en cada proyecto.

Respuestas del usuario que condicionan el diseño:

- Una persona **puede estar en varios `system`**.
- Un usuario tiene **un solo rol** (más roles aumentarían la complejidad).
- El **árbol de accesos se guarda** (no se deriva del prefijo del `code`).

## Decisión

1. **Cuenta global, acceso por `system`.** `person` y `app_user` siguen siendo únicos (el email es único global). El acceso a cada `system` lo da `user_system_role(user_id, system_code, role_id)`, con PK `(user_id, system_code)`: **como máximo un rol por `system`**.
2. **Roles y permisos pertenecen a un `system`** (`role.system_code`, `permission.system_code`; `code` es único por `system`, no global). La base impide asignar un rol de otro `system` mediante **FK compuestas** `(id, system_code)`.
3. **Árbol de accesos guardado:** `permission.parent_id` (autorreferencia, mismo `system`, FK compuesta) más `sort_order`. En el login se arma el árbol del `system` solicitado para el rol del usuario.
4. **Se elimina `app_user.role_id`.**
5. **`SUPER_ADMIN`, dueño de su system.** Cada system tiene su propio rol `SUPER_ADMIN` (no una bandera en `app_user`, ni un system aparte), con todos los permisos del system, presentes y futuros, y **no interviene en otros systems**. Un system nuevo se registra con un script SQL (`register-system.sql`) que crea por defecto su `SUPER_ADMIN`. Tres triggers lo mantienen: todo permiso o regla nueva se le concede solo; no se le quitan permisos ni se borra, renombra o desactiva su rol. Ningún system queda sin un `SUPER_ADMIN` activo. *(Definición propuesta por Yonko y ajustada con el usuario.)*

## Alternativas descartadas

| Alternativa | Por qué se descartó |
|---|---|
| Mantener `role_id` en `app_user` (rol global) | No permite roles distintos por proyecto; contradice la reutilización de ADR-0001. |
| Varias cuentas, una por (persona, `system`) | Duplica credenciales y datos personales; contradice "una persona en varios `system`". |
| Varios roles por usuario y `system` | Más complejidad (consulta de permisos como unión de roles, conflictos); el usuario prefirió un rol. |
| Catálogo global de roles y permisos compartido | Mezcla los permisos de proyectos distintos y obliga a coordinar nombres entre ellos. |
| Bandera `is_super_admin` en `app_user` | Es un caso especial fuera del RBAC: no figura en el catálogo, no se asigna ni se audita como un rol. |
| Rol global sin `system` | Rompe las FK compuestas `(id, system_code)` que impiden mezclar systems. |

## Consecuencias

- **A favor:** `auth` es reutilizable de verdad; la integridad (el rol pertenece al `system` del acceso) la garantiza la base, no solo el servicio; no hay datos todavía, así que el cambio no exige migración.
- **Refresh por `system`:** `refresh_token(user_id, system_code)` referencia a `user_system_role` (con `ON DELETE CASCADE`): un refresh no sirve para otro `system`, y quitar el acceso elimina sus tokens.
- **`SUPER_ADMIN`:** el invariante que se protege es "ningún system sin un `SUPER_ADMIN` activo". Es la cuenta más sensible: ver controles reforzados en el [doc 09](../09-pendientes.md), D27. Costo: tres triggers de autorización (los únicos del esquema), que conviene mantener cubiertos por pruebas; y registrar un system exige correr un script SQL.
- **Costo:** una unión más al login (`user_system_role` → `role` → `role_permission` → `permission`); `role_permission` lleva `system_code` redundante para que las FK compuestas funcionen; el login y el JWT deben indicar para qué `system` se emite el token.
- **Limitaciones:** la base no impide ciclos largos en el árbol de permisos (solo el auto-padre); lo valida el servicio. Desactivar a un usuario es global (`app_user.is_active`); no se puede suspender solo en un `system` (se agregaría `is_active` a `user_system_role` si hace falta).
- **No resuelto aquí:** credenciales de cliente/servicio para emitir JWT con `aud=system` ([doc 09](../09-pendientes.md), D1).

## Referencias

- [Doc 03 · sección A](../03-modelo-datos.md#a-auth-identidad-y-rbac) y [`auth/schema.sql`](../deliverables/db/auth/schema.sql) — modelo aplicado.
- [ADR-0001](0001-estructura-repos-servicios.md) — reutilización de `auth` en otros proyectos.
- [Requerimientos](../deliverables/requerimientos.md) — AUTH-10 (RBAC y árbol de accesos).
