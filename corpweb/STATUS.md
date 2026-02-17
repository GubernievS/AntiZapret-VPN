# Статус разработки CorpWeb

Последнее обновление: 2026-02-17

## ✅ Выполнено

### Инфраструктура
- [x] Создана структура проекта `corpweb/` в репозитории
- [x] Настроен Docker Compose (PostgreSQL, Backend, Frontend, Nginx)
- [x] Созданы конфигурационные файлы (.env.example, docker-compose.yml)
- [x] Создан README.md с инструкциями
- [x] **Nginx конфигурация** (reverse proxy, SPA fallback, gzip, security headers)
- [x] **Backend entrypoint.sh** (автоматический запуск миграций перед стартом)

### Backend (FastAPI) — ПОЛНОСТЬЮ ГОТОВ
- [x] Базовая структура приложения
- [x] Dockerfile для backend + entrypoint.sh
- [x] requirements.txt с зависимостями
- [x] app/config.py - управление настройками через .env
- [x] app/main.py - FastAPI приложение с lifespan, SessionMiddleware, CORS
- [x] app/db/base.py - SQLAlchemy 2.0 DeclarativeBase
- [x] app/db/models.py - SQLAlchemy модели (User, VPNConfig, ConnectionLog, SystemSettings)
- [x] app/db/session.py - сессия базы данных
- [x] app/db/init_db.py - скрипт инициализации БД (admin/admin, system settings)
- [x] **Alembic миграции** (начальная миграция + triggers)
- [x] **Настраиваемый лимит конфигов** (SystemSettings.max_configs_per_user, default: 2)

#### Аутентификация
- [x] app/core/security.py - JWT токены (access/refresh) + bcrypt hashing
- [x] app/core/oauth.py - Google OAuth2 интеграция (authlib)
- [x] app/api/deps.py - middleware: get_current_user, require_admin
- [x] **POST /api/v1/auth/login** - вход по логину/паролю
- [x] **POST /api/v1/auth/refresh** - обновление access token
- [x] **POST /api/v1/auth/logout** - выход (очистка cookie)
- [x] **GET /api/v1/auth/me** - текущий пользователь + лимиты
- [x] **POST /api/v1/auth/change-password** - смена пароля
- [x] **GET /api/v1/auth/google** - редирект на Google OAuth
- [x] **GET /api/v1/auth/google/callback** - callback с авто-регистрацией

#### VPN Конфигурации
- [x] app/services/vpn_manager.py - интерфейс с client.sh (add/delete/list)
- [x] Защита от command injection (whitelist символов)
- [x] Генерация имён конфигов (username-1, username-2)
- [x] **GET /api/v1/configs** - список конфигов (user: свои, admin: все)
- [x] **POST /api/v1/configs** - создание конфига (с проверкой лимита)
- [x] **GET /api/v1/configs/{id}** - детали конфига
- [x] **GET /api/v1/configs/{id}/download** - скачивание .conf файла
- [x] **DELETE /api/v1/configs/{id}** - удаление конфига (сервер + БД)

#### Администрирование
- [x] **GET /api/v1/admin/users** - список пользователей
- [x] **POST /api/v1/admin/users** - создание пользователя (логин/пароль)
- [x] **PUT /api/v1/admin/users/{id}** - обновление пользователя
- [x] **PATCH /api/v1/admin/users/{id}/block** - блокировка/разблокировка
- [x] **DELETE /api/v1/admin/users/{id}** - удаление пользователя
- [x] **GET /api/v1/admin/settings** - текущие настройки
- [x] **PATCH /api/v1/admin/settings** - изменение max_configs_per_user
- [x] **GET /api/v1/admin/dashboard** - статистика для админа

#### Pydantic Schemas
- [x] schemas/auth.py - LoginRequest, TokenResponse, ChangePasswordRequest
- [x] schemas/user.py - UserCreate, UserUpdate, UserResponse, MeResponse
- [x] schemas/config.py - ConfigCreate, ConfigResponse, ConfigListResponse
- [x] schemas/settings.py - SystemSettingsResponse, SystemSettingsUpdate

#### CRUD Operations
- [x] crud/user.py - полный CRUD пользователей + аутентификация
- [x] crud/config.py - полный CRUD VPN конфигов

### Frontend (React + TypeScript)
- [x] Базовая структура React приложения
- [x] Настроен Vite + TypeScript
- [x] Настроен TailwindCSS
- [x] **Поддержка брендирования (логотип)**
- [x] LoginPage с дизайном
- [x] Google OAuth кнопка (UI готов)

### Документация
- [x] README.md - основная инструкция
- [x] BRANDING.md - документация по брендированию
- [x] ADMIN_SETTINGS.md - документация по настройке лимитов

### Скрипты установки
- [x] install.sh - главный скрипт с выбором метода
- [x] install-docker.sh - Docker Compose установка
- [ ] install-native.sh - прямая установка (заглушка)

## 🚧 В разработке

### Frontend
- [ ] API client (axios instance с interceptors, JWT auto-refresh)
- [ ] AuthContext (управление состоянием пользователя)
- [ ] ProtectedRoute (проверка авторизации)
- [ ] Dashboard страница (список конфигов)
- [ ] Создание/удаление конфигов (модальные окна)
- [ ] Скачивание .conf файлов
- [ ] Мониторинг страница
- [ ] Admin панель (пользователи, настройки, статистика)

### Backend
- [ ] Мониторинг сервис (парсинг wg show, OpenVPN logs)
- [ ] GET /api/v1/monitoring/* endpoints

### Deployment
- [ ] Полная реализация install-native.sh
- [ ] Тестирование Docker Compose сборки

## 📋 План на следующие этапы

### ✅ Этап 1: База данных и миграции (завершен)
### ✅ Этап 2: Backend - Аутентификация (завершен)
### ✅ Этап 3: Backend - VPN конфиги (завершен)
### ✅ Этап 4: Backend - Администрирование (завершен)

### Этап 5: Frontend - Авторизация (следующий)
1. Axios client с JWT interceptors
2. AuthContext (Zustand store)
3. ProtectedRoute
4. Интеграция LoginPage с API
5. Обработка Google OAuth callback

### Этап 6: Frontend - Dashboard и конфиги
1. Layout (Header, Sidebar)
2. Dashboard страница
3. Создание/удаление конфигов
4. Скачивание .conf файлов

### Этап 7: Frontend - Admin панель
1. Таблица пользователей
2. Создание/блокировка пользователей
3. Настройки системы
4. Статистика (dashboard)

### Этап 8: Мониторинг
1. Backend: парсинг wg show + OpenVPN logs
2. Frontend: таблица подключений

## 🎨 Особенности реализации

### Настраиваемый лимит конфигураций
- **Таблица:** `system_settings` (singleton с id=1)
- **Поле:** `max_configs_per_user` (по умолчанию: 2)
- **Триггер:** PostgreSQL автоматически проверяет лимит
- **API:** PATCH /api/v1/admin/settings

### Брендирование
- **Расположение:** `frontend/public/branding/`
- **Файлы:** `logo.svg` (200x60px), `favicon.svg` (32x32px)
- **Fallback:** Автоматическая иконка щита при ошибке

### Безопасность
- JWT access token (1 час) + refresh token (30 дней, HttpOnly cookie)
- Bcrypt password hashing
- RBAC: user/admin roles
- Command injection защита в VPNManager
- Path traversal защита при скачивании конфигов
- Rate limiting (slowapi)
- CORS настройка

## 🐛 Известные ограничения

- Прямая установка (install-native.sh) пока не реализована
- Frontend пока не подключен к backend API
- Нет мониторинга подключений
- Нет тестов

## 📊 Прогресс

**Общий прогресс:** ~65%

- Инфраструктура: 100%
- Backend API: **95%** (все endpoints кроме мониторинга)
- Frontend: 25% (только LoginPage UI)
- Deployment: 50% (Docker готов, native нет)
- Документация: 80%

## 🚀 Быстрый старт

```bash
cd corpweb

# Скопировать .env.example в .env
cp .env.example .env

# Отредактировать .env (добавить Google OAuth credentials)
nano .env

# Запустить Docker Compose
./install-docker.sh

# Или вручную
docker-compose up -d --build

# Проверить статус
docker-compose ps

# Swagger UI: http://localhost:8000/api/docs
# Frontend: http://localhost
# Логин: admin / admin
```

---

Для вопросов и предложений создавайте Issues в репозитории.
