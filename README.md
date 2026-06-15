# Polla Norte Verde 2026

Aplicación de predicciones del Mundial FIFA 2026 para el club Deportivo Norte Verde.

## Stack

- **Frontend**: HTML + JavaScript vanilla (sin framework), desplegado en Netlify
- **Backend**: Supabase (PostgreSQL + Auth + Edge Functions + Realtime)
- **Control de versiones**: GitHub

## Variables de entorno

El frontend usa dos variables que deben configurarse en Netlify:

```
SUPABASE_URL=https://tu-proyecto.supabase.co
SUPABASE_ANON_KEY=tu-anon-key-aqui
```

## Estructura del proyecto

```
polla-norte-verde-2026/
├── index.html                  ← Frontend completo (único archivo)
├── supabase/
│   └── migrations/
│       ├── 001_schema.sql      ← Tablas, tipos, vistas
│       ├── 002_rls.sql         ← Row Level Security
│       ├── 003_functions.sql   ← Funciones RPC (lógica de negocio)
│       └── 004_seed_data.sql   ← Datos iniciales del torneo
└── scripts/
    └── generate_seed.py        ← Script que genera seed_data.sql desde el xlsx
```

## Setup de Supabase

1. Crear proyecto en [supabase.com](https://supabase.com)
2. Ir a **SQL Editor** y ejecutar los archivos de migración en orden:
   - `001_schema.sql`
   - `002_rls.sql`
   - `003_functions.sql`
   - `004_seed_data.sql`
3. Copiar la **URL** y la **anon key** del proyecto (Settings → API)

## Deploy en Netlify

1. Conectar este repositorio de GitHub en Netlify
2. Configurar variables de entorno (SUPABASE_URL y SUPABASE_ANON_KEY)
3. El deploy es automático en cada push a `main`

## Admin

El usuario `vdonoso@reity.cl` (Vicente) tiene permisos de admin.
Las acciones de admin se hacen desde el botón 🛠️ dentro de la app.

## Credenciales de prueba

Cada usuario elige su PIN de 4 dígitos la primera vez que entra.
