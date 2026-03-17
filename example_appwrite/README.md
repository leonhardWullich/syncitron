# syncitron Todo Example — Appwrite Backend

A simple Todo app that demonstrates **syncitron** offline-first sync with
[Appwrite](https://appwrite.io/) as the remote backend.

This example mirrors the Supabase example (`../example/`) with identical UI
and sync behaviour — only the backend integration differs.

## Prerequisites

- Flutter SDK ≥ 3.3
- An Appwrite instance (self-hosted or [Appwrite Cloud](https://cloud.appwrite.io/))
- An Appwrite project with a database

## Appwrite Setup

### 1. Create a Database

In your Appwrite Console, create a new database (e.g. `syncitron_example`).
Note the **Database ID**.

### 2. Create the `todos` Collection

Create a collection named `todos` in your database with these attributes:

| Attribute   | Type      | Required | Default |
|-------------|-----------|----------|---------|
| `user_id`   | String    | Yes      | —       |
| `title`     | String    | Yes      | —       |
| `is_done`   | Integer   | Yes      | `0`     |
| `updated_at`| String    | Yes      | —       |
| `deleted_at`| String    | No       | `null`  |

> **Note:** Use **Integer** (not Boolean) for `is_done` — SQLite stores
> booleans as 0/1 and syncitron pushes the raw values. The document `$id`
> serves as the primary key; do **not** add an `id` attribute.

### 3. Create Indexes

Add the following index for cursor-based sync:

- **Key:** `cursor_idx`
- **Type:** Key
- **Attributes:** `updated_at` (ASC), `$id` (ASC)

### 4. Set up Permissions

Configure collection-level permissions to allow authenticated users:
- **Create**: `role:member`
- **Read**: `role:member`
- **Update**: `role:member`
- **Delete**: `role:member`

For row-level security, add document-level permissions in your Appwrite
Functions or set the `$permissions` field when creating documents.

### 5. Enable Authentication

In the Appwrite Console → Auth → Settings:
- Enable **Email/Password** sign-up

### 6. Configure the App

Edit `lib/main.dart` and replace the placeholder values:

```dart
const _appwriteEndpoint = 'https://cloud.appwrite.io/v1';  // or your self-hosted URL
const _appwriteProjectId = 'YOUR_PROJECT_ID';
const _appwriteDatabaseId = 'YOUR_DATABASE_ID';
```

## Running

Since this project lives in iCloud Drive, use the build wrapper:

```bash
chmod +x flutter_icloud_build.sh
./flutter_icloud_build.sh run -d macos
# or
./flutter_icloud_build.sh run -d iPhone
```

The script syncs the project to `/tmp`, runs `flutter run`, and syncs
generated files back.

## Architecture

```
lib/
├── main.dart              # App init: Appwrite client → SQLite → syncitron
├── data/
│   ├── todo.dart          # Domain model with sync metadata
│   └── todo_repository.dart  # Local SQLite CRUD
├── sync/
│   └── sync_service.dart  # Background sync orchestration
└── ui/
    ├── login_screen.dart  # Appwrite email/password auth
    └── todo_list_screen.dart  # CRUD + pull-to-refresh + metrics
```

### Sync Flow

1. **Local write** → `TodoRepository` inserts with `is_synced = 0`
2. **Push** → `SyncEngine` detects dirty rows, calls `AppwriteAdapter.upsert()`
3. **Pull** → Engine fetches remote changes via `AppwriteAdapter.pull()`
4. **Real-time** → `AppwriteRealtimeProvider` pushes live changes via WebSocket
5. **Conflict resolution** → `lastWriteWins` based on `updated_at` timestamps

### Key Differences from the Supabase Example

| Aspect          | Supabase Example              | Appwrite Example                   |
|-----------------|-------------------------------|------------------------------------|
| Auth            | `supabase_flutter`            | `appwrite` SDK (`Account`)         |
| Remote Adapter  | `SupabaseAdapter`             | `AppwriteAdapter`                  |
| Realtime        | Postgres Changes (WebSocket)  | Appwrite Realtime (WebSocket)      |
| Batch Upsert    | Native bulk upsert            | Parallel individual upserts        |
| Database        | PostgreSQL (server)           | MariaDB (server, managed by Appwrite) |
| Schema          | SQL migration                 | Console / API attribute creation   |

## Testing Scenarios

1. **Basic CRUD** — Create, toggle, delete todos
2. **Offline mode** — Disable WiFi, make changes, reconnect → auto-sync
3. **Real-time** — Open on two devices, changes appear instantly
4. **Pull-to-refresh** — Swipe down to manually trigger sync
5. **Session expiry** — Let token expire, observe auth error banner

## License

This example is part of syncitron and is currently available free of charge
under the MIT License. See [../LICENSE](../LICENSE).

Roadmap note: as syncitron grows, future releases may also be offered under a
dual-license model.
