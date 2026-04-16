"""
WgBlobStore — thin repository over the wg_file_state table.

All writes trigger pg_notify via DB trigger (already in the model layer).
"""
from __future__ import annotations

import hashlib
from datetime import datetime

from sqlalchemy.orm import Session

from app.db.models import WgFileState


class WgBlobStore:
    def __init__(self, db: Session):
        self._db = db

    def get(self, path: str) -> bytes | None:
        """Get file content by path. Returns None if not found."""
        row = self._db.get(WgFileState, path)
        if row is None:
            return None
        return row.content

    def put(self, path: str, content: bytes, by: str) -> None:
        """Upsert file content. Computes sha256 and size_bytes automatically."""
        sha = hashlib.sha256(content).hexdigest()
        size = len(content)
        row = self._db.get(WgFileState, path)
        if row is None:
            row = WgFileState(
                path=path,
                content=content,
                sha256=sha,
                size_bytes=size,
                updated_at=datetime.utcnow(),
                updated_by=by,
            )
            self._db.add(row)
        else:
            row.content = content
            row.sha256 = sha
            row.size_bytes = size
            row.updated_at = datetime.utcnow()
            row.updated_by = by
        self._db.commit()

    def get_all_paths(self) -> dict[str, str]:
        """Return {path: sha256} for all stored files."""
        rows = self._db.query(WgFileState).all()
        return {row.path: row.sha256 for row in rows}
