"""Supabase Backup Agent — exports all projects' schemas and data to an Obsidian vault."""

import argparse
import json
import logging
import os
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

import requests

from agents.framework import Agent

# Supabase Management API base
MGMT_API = "https://api.supabase.com/v1"

# Tables above this row count use incremental (PK-based) backup
INCREMENTAL_THRESHOLD = 10_000

# Rows fetched per page during full export
CHUNK_SIZE = 50_000

# Schemas to back up
TARGET_SCHEMAS = ["public"]


class SupabaseBackupAgent(Agent):
    """Back up all Supabase projects to JSON files in an Obsidian vault."""

    def get_name(self) -> str:
        return "Supabase Backup"

    def validate_config(self):
        if not self.config.get("backup_vault_path"):
            raise ValueError("backup_vault_path not set in config.json")

    # ── API helpers ──────────────────────────────────────────────

    def _token(self) -> str:
        env_var = self.config.get("supabase_access_token_env", "SUPABASE_ACCESS_TOKEN")
        token = os.environ.get(env_var)
        if not token:
            raise RuntimeError(
                f"Supabase access token not found in ${env_var}. "
                "Generate one at https://supabase.com/dashboard/account/tokens"
            )
        return token

    def _headers(self) -> dict:
        return {
            "Authorization": f"Bearer {self._token()}",
            "Content-Type": "application/json",
        }

    def _api_get(self, path: str) -> dict | list:
        url = f"{MGMT_API}{path}"
        resp = requests.get(url, headers=self._headers(), timeout=30)
        resp.raise_for_status()
        return resp.json()

    def _execute_sql(self, project_id: str, query: str) -> list[dict]:
        """Execute SQL via the Management API and return rows."""
        url = f"{MGMT_API}/projects/{project_id}/database/query"
        resp = requests.post(
            url,
            headers=self._headers(),
            json={"query": query},
            timeout=120,
        )
        resp.raise_for_status()
        result = resp.json()
        # The API returns a list of row objects directly
        if isinstance(result, list):
            return result
        # Some responses wrap in a result key (string or list)
        if isinstance(result, dict):
            inner = result.get("result", result)
            if isinstance(inner, str):
                import re
                # Extract JSON array from wrapped response
                match = re.search(r'\[.*\]', inner, re.DOTALL)
                if match:
                    return json.loads(match.group())
                return []
            if isinstance(inner, list):
                return inner
        return []

    # ── Project / table discovery ────────────────────────────────

    def _list_projects(self, filter_projects: list[str] | None = None) -> list[dict]:
        projects = self._api_get("/projects")
        active = [p for p in projects if p.get("status") == "ACTIVE_HEALTHY"]
        if filter_projects:
            names_lower = [n.lower() for n in filter_projects]
            active = [p for p in active if p["name"].lower() in names_lower or p["id"] in filter_projects]
        return active

    def _list_tables(self, project_id: str) -> list[dict]:
        """Return list of {table_name, schema, row_estimate} for public tables."""
        query = """
        SELECT
            schemaname AS schema,
            relname AS table_name,
            n_live_tup AS row_estimate
        FROM pg_stat_user_tables
        WHERE schemaname = ANY(ARRAY['public'])
        ORDER BY relname;
        """
        return self._execute_sql(project_id, query)

    def _get_schema(self, project_id: str) -> list[dict]:
        """Get full column-level schema for all public tables."""
        query = """
        SELECT
            c.table_schema,
            c.table_name,
            c.column_name,
            c.data_type,
            c.udt_name,
            c.is_nullable,
            c.column_default,
            c.character_maximum_length,
            c.ordinal_position
        FROM information_schema.columns c
        WHERE c.table_schema = 'public'
        ORDER BY c.table_name, c.ordinal_position;
        """
        return self._execute_sql(project_id, query)

    def _get_constraints(self, project_id: str) -> list[dict]:
        """Get primary keys, foreign keys, and unique constraints."""
        query = """
        SELECT
            tc.table_name,
            tc.constraint_name,
            tc.constraint_type,
            kcu.column_name,
            ccu.table_name AS foreign_table_name,
            ccu.column_name AS foreign_column_name
        FROM information_schema.table_constraints tc
        JOIN information_schema.key_column_usage kcu
            ON tc.constraint_name = kcu.constraint_name
            AND tc.table_schema = kcu.table_schema
        LEFT JOIN information_schema.constraint_column_usage ccu
            ON tc.constraint_name = ccu.constraint_name
            AND tc.table_schema = ccu.table_schema
        WHERE tc.table_schema = 'public'
        ORDER BY tc.table_name, tc.constraint_type;
        """
        return self._execute_sql(project_id, query)

    def _get_primary_key_column(self, project_id: str, table_name: str) -> str | None:
        """Find the primary key column for a table (first PK column)."""
        query = f"""
        SELECT kcu.column_name
        FROM information_schema.table_constraints tc
        JOIN information_schema.key_column_usage kcu
            ON tc.constraint_name = kcu.constraint_name
            AND tc.table_schema = kcu.table_schema
        WHERE tc.table_schema = 'public'
            AND tc.table_name = '{table_name}'
            AND tc.constraint_type = 'PRIMARY KEY'
        ORDER BY kcu.ordinal_position
        LIMIT 1;
        """
        rows = self._execute_sql(project_id, query)
        return rows[0]["column_name"] if rows else None

    # ── Data export ──────────────────────────────────────────────

    def _export_table_full(self, project_id: str, table_name: str, pk_col: str | None) -> list[dict]:
        """Full export with cursor-based pagination if PK is available."""
        if not pk_col:
            # No PK — single query, hope it fits
            self.logger.info("    No PK found, doing single SELECT *")
            return self._execute_sql(project_id, f'SELECT * FROM "public"."{table_name}"')

        all_rows = []
        last_id = None
        page = 0

        while True:
            if last_id is None:
                query = f'SELECT * FROM "public"."{table_name}" ORDER BY "{pk_col}" LIMIT {CHUNK_SIZE}'
            else:
                query = (
                    f'SELECT * FROM "public"."{table_name}" '
                    f"WHERE \"{pk_col}\" > '{last_id}' "
                    f'ORDER BY "{pk_col}" LIMIT {CHUNK_SIZE}'
                )

            rows = self._execute_sql(project_id, query)
            if not rows:
                break

            all_rows.extend(rows)
            last_id = rows[-1][pk_col]
            page += 1
            self.logger.info("    Page %d: fetched %d rows (total: %d)", page, len(rows), len(all_rows))

            if len(rows) < CHUNK_SIZE:
                break

        return all_rows

    def _export_table_incremental(
        self, project_id: str, table_name: str, pk_col: str, last_max_pk: str
    ) -> list[dict]:
        """Incremental export: only rows with PK > last known max."""
        all_rows = []
        last_id = last_max_pk

        while True:
            query = (
                f'SELECT * FROM "public"."{table_name}" '
                f"WHERE \"{pk_col}\" > '{last_id}' "
                f'ORDER BY "{pk_col}" LIMIT {CHUNK_SIZE}'
            )
            rows = self._execute_sql(project_id, query)
            if not rows:
                break

            all_rows.extend(rows)
            last_id = rows[-1][pk_col]

            if len(rows) < CHUNK_SIZE:
                break

        return all_rows

    # ── File I/O ─────────────────────────────────────────────────

    def _vault_path(self) -> Path:
        return Path(self.config["backup_vault_path"])

    def _project_dir(self, project_name: str) -> Path:
        safe_name = project_name.replace(" ", "-").replace("/", "-")
        d = self._vault_path() / safe_name
        d.mkdir(parents=True, exist_ok=True)
        return d

    def _write_json(self, path: Path, data):
        with open(path, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2, default=str, ensure_ascii=False)

    def _read_json(self, path: Path) -> dict | list | None:
        if not path.exists():
            return None
        with open(path, encoding="utf-8") as f:
            return json.load(f)

    def _load_backup_log(self) -> dict:
        log_path = self._vault_path() / "_backup_log.json"
        data = self._read_json(log_path)
        return data if isinstance(data, dict) else {}

    def _save_backup_log(self, log: dict):
        log_path = self._vault_path() / "_backup_log.json"
        self._write_json(log_path, log)

    # ── Main backup logic ────────────────────────────────────────

    def _backup_project(self, project: dict, backup_log: dict, dry_run: bool = False) -> dict:
        """Back up a single project. Returns a status dict for the log."""
        project_id = project["id"]
        project_name = project["name"]
        project_dir = self._project_dir(project_name)
        project_log = backup_log.get("projects", {}).get(project_name, {})

        self.logger.info("Backing up project: %s (%s)", project_name, project_id)

        status = {
            "project_id": project_id,
            "tables_backed_up": 0,
            "tables_skipped": 0,
            "errors": [],
            "table_details": {},
        }

        # 1. Export schema
        try:
            columns = self._get_schema(project_id)
            constraints = self._get_constraints(project_id)
            schema_doc = {
                "project_name": project_name,
                "project_id": project_id,
                "exported_at": datetime.now(timezone.utc).isoformat(),
                "columns": columns,
                "constraints": constraints,
            }
            if not dry_run:
                self._write_json(project_dir / "_schema.json", schema_doc)
            self.logger.info("  Schema exported (%d columns, %d constraints)", len(columns), len(constraints))
        except Exception as e:
            msg = f"Schema export failed: {e}"
            self.logger.error("  %s", msg)
            status["errors"].append(msg)

        # 2. List and export tables
        try:
            tables = self._list_tables(project_id)
        except Exception as e:
            msg = f"Failed to list tables: {e}"
            self.logger.error("  %s", msg)
            status["errors"].append(msg)
            return status

        if not tables:
            self.logger.info("  No tables found")
            return status

        for tbl in tables:
            table_name = tbl["table_name"]
            row_estimate = int(tbl.get("row_estimate", 0))
            table_log = project_log.get("table_details", {}).get(table_name, {})

            self.logger.info("  Table: %s (~%d rows)", table_name, row_estimate)

            try:
                pk_col = self._get_primary_key_column(project_id, table_name)

                is_incremental = (
                    row_estimate >= INCREMENTAL_THRESHOLD
                    and pk_col
                    and table_log.get("last_max_pk") is not None
                )

                if is_incremental:
                    last_max_pk = table_log["last_max_pk"]
                    self.logger.info("    Incremental from PK > %s", last_max_pk)
                    new_rows = self._export_table_incremental(project_id, table_name, pk_col, last_max_pk)

                    if new_rows:
                        # Merge with existing file
                        table_file = project_dir / f"{table_name}.json"
                        existing = self._read_json(table_file)
                        existing_data = existing.get("data", []) if isinstance(existing, dict) else []

                        merged_data = existing_data + new_rows
                        new_max_pk = str(new_rows[-1][pk_col])

                        table_doc = {
                            "table_name": table_name,
                            "project_name": project_name,
                            "exported_at": datetime.now(timezone.utc).isoformat(),
                            "backup_mode": "incremental",
                            "row_count": len(merged_data),
                            "data": merged_data,
                        }
                        if not dry_run:
                            self._write_json(table_file, table_doc)

                        status["table_details"][table_name] = {
                            "rows": len(merged_data),
                            "new_rows": len(new_rows),
                            "mode": "incremental",
                            "last_max_pk": new_max_pk,
                        }
                        self.logger.info("    +%d new rows (total: %d)", len(new_rows), len(merged_data))
                    else:
                        # No new rows — keep existing log entry
                        status["table_details"][table_name] = {
                            "rows": table_log.get("rows", 0),
                            "new_rows": 0,
                            "mode": "incremental_no_change",
                            "last_max_pk": table_log["last_max_pk"],
                        }
                        self.logger.info("    No new rows")

                else:
                    # Full export
                    self.logger.info("    Full export (pk=%s)", pk_col or "none")
                    rows = self._export_table_full(project_id, table_name, pk_col)

                    table_doc = {
                        "table_name": table_name,
                        "project_name": project_name,
                        "exported_at": datetime.now(timezone.utc).isoformat(),
                        "backup_mode": "full",
                        "row_count": len(rows),
                        "data": rows,
                    }
                    if not dry_run:
                        self._write_json(project_dir / f"{table_name}.json", table_doc)

                    last_pk = str(rows[-1][pk_col]) if rows and pk_col else None
                    status["table_details"][table_name] = {
                        "rows": len(rows),
                        "new_rows": len(rows),
                        "mode": "full",
                        "last_max_pk": last_pk,
                    }
                    self.logger.info("    Exported %d rows", len(rows))

                status["tables_backed_up"] += 1

            except Exception as e:
                msg = f"Table {table_name}: {e}"
                self.logger.error("    ERROR: %s", e)
                status["errors"].append(msg)
                status["tables_skipped"] += 1
                # Preserve previous log entry on error so we don't lose incremental state
                if table_log:
                    status["table_details"][table_name] = table_log

        return status

    def run(self, projects: list[str] | None = None, dry_run: bool = False, **kwargs):
        """Run the backup across all (or filtered) projects."""
        started_at = datetime.now(timezone.utc)
        self.logger.info("Supabase Backup started at %s", started_at.isoformat())

        if dry_run:
            self.logger.info("DRY RUN — no files will be written")

        # Ensure vault dir exists
        self._vault_path().mkdir(parents=True, exist_ok=True)

        backup_log = self._load_backup_log()
        all_projects = self._list_projects(projects)
        self.logger.info("Found %d projects to back up", len(all_projects))

        new_log = {
            "last_backup_at": started_at.isoformat(),
            "projects": {},
            "summary": {
                "total_projects": len(all_projects),
                "total_tables": 0,
                "total_errors": 0,
            },
        }

        for proj in all_projects:
            project_name = proj["name"]
            try:
                status = self._backup_project(proj, backup_log, dry_run=dry_run)
                new_log["projects"][project_name] = status
                new_log["summary"]["total_tables"] += status["tables_backed_up"]
                new_log["summary"]["total_errors"] += len(status["errors"])
            except Exception as e:
                self.logger.error("Project %s failed entirely: %s", project_name, e)
                new_log["projects"][project_name] = {
                    "project_id": proj["id"],
                    "tables_backed_up": 0,
                    "errors": [str(e)],
                    "table_details": {},
                }
                new_log["summary"]["total_errors"] += 1

        finished_at = datetime.now(timezone.utc)
        duration = (finished_at - started_at).total_seconds()
        new_log["finished_at"] = finished_at.isoformat()
        new_log["duration_seconds"] = round(duration, 1)

        if not dry_run:
            self._save_backup_log(new_log)

        self.logger.info(
            "Backup complete in %.1fs — %d projects, %d tables, %d errors",
            duration,
            new_log["summary"]["total_projects"],
            new_log["summary"]["total_tables"],
            new_log["summary"]["total_errors"],
        )

        # Print summary to stdout for the GUI
        print(json.dumps(new_log, indent=2, default=str))


def main():
    parser = argparse.ArgumentParser(description="Back up Supabase projects to Obsidian vault")
    parser.add_argument("--config", type=str, default=None, help="Path to config.json")
    parser.add_argument("--projects", nargs="*", default=None, help="Filter to specific project names or IDs")
    parser.add_argument("--dry-run", action="store_true", help="Preview without writing files")
    args = parser.parse_args()

    agent = SupabaseBackupAgent(config_path=args.config)
    agent.run(projects=args.projects, dry_run=args.dry_run)


if __name__ == "__main__":
    main()
