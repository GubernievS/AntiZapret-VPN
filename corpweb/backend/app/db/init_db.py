"""
Database initialization script
Creates default admin user and system settings on first run
"""
import uuid
from datetime import datetime
from sqlalchemy.orm import Session
from app.db.base import Base
from app.db.models import User, SystemSettings
from app.core.security import get_password_hash
from app.db.session import engine, get_db


def init_db() -> None:
    """
    Initialize database with default data:
    - Create admin user (admin/admin) if not exists
    - Create default system settings if not exists
    """
    print("🔧 Initializing database...")

    # Create all tables (if not exist)
    Base.metadata.create_all(bind=engine)

    # Get database session
    db = next(get_db())

    try:
        # Check if admin user exists
        admin_user = db.query(User).filter(User.username == "admin").first()

        if not admin_user:
            print("👤 Creating default admin user...")
            admin_user = User(
                id=uuid.uuid4(),
                email="admin@localhost",
                username="admin",
                password_hash=get_password_hash("admin"),
                role="admin",
                auth_provider="local",
                is_active=True,
                created_at=datetime.utcnow(),
                updated_at=datetime.utcnow()
            )
            db.add(admin_user)
            db.commit()
            print("✅ Admin user created: admin / admin")
            print("⚠️  IMPORTANT: Change the admin password after first login!")
        else:
            print("✅ Admin user already exists")

        # Check if system settings exist
        settings = db.query(SystemSettings).filter(SystemSettings.id == 1).first()

        if not settings:
            print("⚙️  Creating default system settings...")
            settings = SystemSettings(
                id=1,
                max_configs_per_user=2,
                updated_at=datetime.utcnow()
            )
            db.add(settings)
            db.commit()
            print("✅ System settings created (max_configs_per_user: 2)")
        else:
            print(f"✅ System settings already exist (max_configs_per_user: {settings.max_configs_per_user})")

        print("✅ Database initialization completed!")

    except Exception as e:
        print(f"❌ Error during initialization: {e}")
        db.rollback()
        raise
    finally:
        db.close()


if __name__ == "__main__":
    init_db()
