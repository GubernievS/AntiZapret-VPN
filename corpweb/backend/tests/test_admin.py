"""
Tests for admin API endpoints
"""
from tests.conftest import auth_header


class TestAdminUsers:
    def test_list_users_as_admin(self, client, admin_user, admin_token):
        response = client.get("/api/v1/admin/users", headers=auth_header(admin_token))
        assert response.status_code == 200
        data = response.json()
        assert "items" in data
        assert "total" in data
        assert data["total"] >= 1

    def test_list_users_as_regular_user(self, client, regular_user, user_token):
        response = client.get("/api/v1/admin/users", headers=auth_header(user_token))
        assert response.status_code == 403

    def test_create_user(self, client, admin_user, admin_token):
        response = client.post("/api/v1/admin/users",
            headers=auth_header(admin_token),
            json={
                "email": "newuser@test.com",
                "username": "newuser",
                "password": "password123"
            }
        )
        assert response.status_code == 201
        data = response.json()
        assert data["username"] == "newuser"
        assert data["role"] == "user"
        assert data["is_active"] is True

    def test_create_user_duplicate_email(self, client, admin_user, admin_token, regular_user):
        response = client.post("/api/v1/admin/users",
            headers=auth_header(admin_token),
            json={
                "email": "user@test.com",  # Already exists
                "username": "another",
                "password": "password123"
            }
        )
        assert response.status_code == 409

    def test_create_user_as_regular(self, client, regular_user, user_token):
        response = client.post("/api/v1/admin/users",
            headers=auth_header(user_token),
            json={
                "email": "new@test.com",
                "username": "new",
                "password": "password123"
            }
        )
        assert response.status_code == 403

    def test_toggle_block_user(self, client, admin_user, admin_token, regular_user):
        # Block user
        response = client.patch(
            f"/api/v1/admin/users/{regular_user.id}/block",
            headers=auth_header(admin_token)
        )
        assert response.status_code == 200
        assert response.json()["is_active"] is False

        # Unblock user
        response = client.patch(
            f"/api/v1/admin/users/{regular_user.id}/block",
            headers=auth_header(admin_token)
        )
        assert response.status_code == 200
        assert response.json()["is_active"] is True

    def test_cannot_block_admin(self, client, admin_user, admin_token):
        response = client.patch(
            f"/api/v1/admin/users/{admin_user.id}/block",
            headers=auth_header(admin_token)
        )
        assert response.status_code == 400

    def test_delete_user(self, client, admin_user, admin_token, regular_user):
        response = client.delete(
            f"/api/v1/admin/users/{regular_user.id}",
            headers=auth_header(admin_token)
        )
        assert response.status_code == 204

        # Verify user is gone
        response = client.get("/api/v1/admin/users", headers=auth_header(admin_token))
        usernames = [u["username"] for u in response.json()["items"]]
        assert "testuser" not in usernames

    def test_cannot_delete_admin(self, client, admin_user, admin_token):
        response = client.delete(
            f"/api/v1/admin/users/{admin_user.id}",
            headers=auth_header(admin_token)
        )
        assert response.status_code == 400


class TestAdminSettings:
    def test_get_settings(self, client, admin_user, admin_token, system_settings):
        response = client.get("/api/v1/admin/settings", headers=auth_header(admin_token))
        assert response.status_code == 200
        assert response.json()["max_configs_per_user"] == 2

    def test_update_settings(self, client, admin_user, admin_token, system_settings):
        response = client.patch("/api/v1/admin/settings",
            headers=auth_header(admin_token),
            json={"max_configs_per_user": 5}
        )
        assert response.status_code == 200
        assert response.json()["max_configs_per_user"] == 5

    def test_update_settings_invalid_value(self, client, admin_user, admin_token, system_settings):
        response = client.patch("/api/v1/admin/settings",
            headers=auth_header(admin_token),
            json={"max_configs_per_user": 0}
        )
        assert response.status_code == 422  # Pydantic validation error

    def test_settings_requires_admin(self, client, regular_user, user_token, system_settings):
        response = client.get("/api/v1/admin/settings", headers=auth_header(user_token))
        assert response.status_code == 403


class TestAdminDashboard:
    def test_dashboard_stats(self, client, admin_user, admin_token, system_settings):
        response = client.get("/api/v1/admin/dashboard", headers=auth_header(admin_token))
        assert response.status_code == 200
        data = response.json()
        assert "users" in data
        assert "configs" in data
        assert "connections" in data
        assert "settings" in data
        assert data["users"]["total"] >= 1

    def test_dashboard_requires_admin(self, client, regular_user, user_token):
        response = client.get("/api/v1/admin/dashboard", headers=auth_header(user_token))
        assert response.status_code == 403
