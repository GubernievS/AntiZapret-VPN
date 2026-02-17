# Настройки администратора - Управление лимитами конфигураций

## Обзор

В CorpWeb реализована гибкая система управления ограничениями на количество конфигураций для пользователей. Администратор может динамически изменять максимальное количество конфигов, которые может создать каждый пользователь, без необходимости изменения кода или перезапуска приложения.

## Архитектура

### База данных

Настройки хранятся в таблице `system_settings`:

```sql
CREATE TABLE system_settings (
    id INTEGER PRIMARY KEY DEFAULT 1,              -- Всегда 1 (singleton)
    max_configs_per_user INTEGER NOT NULL DEFAULT 2,  -- Максимум конфигов на пользователя
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_by VARCHAR(50)                         -- Имя админа, внесшего изменение
);
```

**Важно:** Эта таблица является singleton - в ней всегда только одна строка с `id = 1`.

### Триггер проверки

При каждой попытке создания конфига автоматически срабатывает PostgreSQL триггер:

```sql
CREATE OR REPLACE FUNCTION check_user_config_limit()
RETURNS TRIGGER AS $$
DECLARE
    max_configs INTEGER;
    current_count INTEGER;
BEGIN
    -- Получаем текущий лимит из system_settings
    SELECT max_configs_per_user INTO max_configs
    FROM system_settings
    WHERE id = 1;

    -- Считаем активные конфиги пользователя
    SELECT COUNT(*) INTO current_count
    FROM vpn_configs
    WHERE user_id = NEW.user_id AND is_active = TRUE;

    -- Проверяем превышение лимита
    IF current_count >= max_configs THEN
        RAISE EXCEPTION 'User cannot have more than % active configs', max_configs;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
```

Этот триггер:
1. Читает текущий лимит из `system_settings`
2. Подсчитывает активные конфиги пользователя
3. Блокирует создание, если лимит достигнут
4. **Автоматически использует актуальное значение** без перезапуска

## API Endpoints (планируется)

### Получение текущих настроек

```http
GET /api/v1/admin/settings
Authorization: Bearer <admin_token>
```

**Ответ:**
```json
{
  "id": 1,
  "max_configs_per_user": 2,
  "updated_at": "2026-02-16T18:30:00Z",
  "updated_by": "admin"
}
```

### Изменение лимита конфигураций

```http
PATCH /api/v1/admin/settings
Authorization: Bearer <admin_token>
Content-Type: application/json

{
  "max_configs_per_user": 5
}
```

**Ответ:**
```json
{
  "id": 1,
  "max_configs_per_user": 5,
  "updated_at": "2026-02-16T19:00:00Z",
  "updated_by": "admin"
}
```

**Ограничения:**
- Минимум: 1 конфиг
- Максимум: 10 конфигов (настраивается)
- Только администраторы могут изменять

## Пользовательский интерфейс (планируется)

### Админ-панель

В разделе "Настройки системы" администратор увидит:

```
┌──────────────────────────────────────────────┐
│ Системные настройки                          │
├──────────────────────────────────────────────┤
│                                              │
│ Максимум конфигов на пользователя:          │
│  ┌───────┐                                   │
│  │   2   │  [Изменить]                       │
│  └───────┘                                   │
│                                              │
│ Рекомендуемые значения:                      │
│  • 2 - стандартно (телефон + ноутбук)        │
│  • 3-5 - для power users                     │
│  • 10 - максимум (корпоративные устройства)  │
│                                              │
│ ⚠️ Изменение применяется мгновенно для       │
│    всех новых конфигов. Существующие         │
│    конфиги пользователей не удаляются.       │
│                                              │
│ Последнее изменение: admin                   │
│ Дата: 16.02.2026 18:30                       │
└──────────────────────────────────────────────┘
```

## Примеры использования

### Сценарий 1: Увеличение лимита для корпорации

Компания хочет разрешить сотрудникам иметь конфиги для всех их устройств (телефон, ноутбук, планшет, домашний ПК).

**Действия:**
1. Администратор открывает "Настройки системы"
2. Изменяет значение с 2 на 4
3. Нажимает "Сохранить"
4. Пользователи теперь могут создать до 4 конфигов

### Сценарий 2: Временное ограничение

Нагрузка на VPN сервер высокая, нужно временно ограничить количество устройств.

**Действия:**
1. Администратор снижает лимит с 3 до 2
2. Пользователи с 3 конфигами **сохраняют** их (не удаляются)
3. Но не могут создать новые до удаления одного
4. Позже администратор возвращает лимит обратно

### Сценарий 3: Проверка текущего лимита через SQL

```sql
-- Получить текущий лимит
SELECT max_configs_per_user FROM system_settings WHERE id = 1;

-- Изменить лимит вручную (если нет доступа к админ-панели)
UPDATE system_settings
SET max_configs_per_user = 5,
    updated_at = CURRENT_TIMESTAMP,
    updated_by = 'admin'
WHERE id = 1;
```

## Логика проверки в коде (планируется)

### Backend сервис

```python
# app/services/config_service.py
from app.db.models import SystemSettings

async def check_config_limit(db: Session, user_id: UUID) -> bool:
    """
    Проверяет, может ли пользователь создать еще один конфиг

    Returns:
        True - может создать
        False - лимит достигнут
    """
    # Получаем текущий лимит
    settings = db.query(SystemSettings).filter(SystemSettings.id == 1).first()
    max_configs = settings.max_configs_per_user if settings else 2

    # Считаем активные конфиги
    current_count = db.query(VPNConfig).filter(
        VPNConfig.user_id == user_id,
        VPNConfig.is_active == True
    ).count()

    return current_count < max_configs
```

### API endpoint

```python
# app/api/v1/configs.py
@router.post("/configs")
async def create_config(
    config_data: ConfigCreate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    # Проверка лимита
    if not await check_config_limit(db, current_user.id):
        settings = db.query(SystemSettings).filter(SystemSettings.id == 1).first()
        max_limit = settings.max_configs_per_user if settings else 2
        raise HTTPException(
            status_code=400,
            detail=f"Maximum {max_limit} configs per user. Delete existing config first."
        )

    # Создание конфига...
```

## Преимущества подхода

### 1. Гибкость
- Изменение без перезапуска сервера
- Моментальное применение для новых конфигов
- Существующие конфиги пользователей не затрагиваются

### 2. Безопасность
- Триггер БД гарантирует соблюдение лимита
- Невозможно обойти проверку на уровне приложения
- Атомарная проверка без race conditions

### 3. Масштабируемость
- Легко добавить новые настройки в `system_settings`
- Можно добавить лимиты по ролям (VIP пользователи)
- Возможность истории изменений (audit log)

### 4. Удобство
- Администратор не работает с кодом
- Понятный UI для изменения
- Немедленный эффект

## Будущие расширения

### Лимиты по ролям

```sql
ALTER TABLE users ADD COLUMN config_limit_override INTEGER;

-- Если у пользователя есть override - использовать его, иначе глобальный
```

### История изменений

```sql
CREATE TABLE settings_history (
    id SERIAL PRIMARY KEY,
    setting_name VARCHAR(50),
    old_value VARCHAR(100),
    new_value VARCHAR(100),
    changed_by VARCHAR(50),
    changed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

### Уведомления пользователей

При изменении лимита администратором:
- Email уведомление: "Теперь вы можете создать до X конфигов"
- Уведомление в UI при следующем входе

## Миграция данных

При обновлении с предыдущих версий (если были):

```python
# Скрипт миграции
def migrate_to_system_settings(db: Session):
    # Проверяем, существует ли запись
    settings = db.query(SystemSettings).filter(SystemSettings.id == 1).first()

    if not settings:
        # Создаем с дефолтными значениями
        settings = SystemSettings(
            id=1,
            max_configs_per_user=2,
            updated_at=datetime.utcnow()
        )
        db.add(settings)
        db.commit()
        print("✅ SystemSettings initialized with default values")
```

## Troubleshooting

### Проблема: Пользователь не может создать конфиг

**Проверка 1:** Проверьте текущий лимит
```sql
SELECT * FROM system_settings WHERE id = 1;
```

**Проверка 2:** Посчитайте конфиги пользователя
```sql
SELECT COUNT(*) FROM vpn_configs
WHERE user_id = '<user_uuid>' AND is_active = TRUE;
```

**Решение:** Если count >= max_configs, пользователь должен удалить один конфиг

### Проблема: Триггер не срабатывает

**Проверка:** Убедитесь, что триггер существует
```sql
SELECT * FROM pg_trigger WHERE tgname = 'enforce_config_limit';
```

**Решение:** Пересоздайте триггер из миграции

## Заключение

Система настраиваемых лимитов конфигураций предоставляет администратору гибкий инструмент управления ресурсами VPN сервера. Она балансирует между удобством пользователей (возможность подключения нескольких устройств) и контролем нагрузки на инфраструктуру.

---

**Вопросы?** Создайте issue в репозитории или обратитесь к разработчику.
