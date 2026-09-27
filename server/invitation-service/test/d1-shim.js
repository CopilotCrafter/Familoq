// Minimal Cloudflare D1 stand-in backed by node:sqlite, so the Worker can be
// tested with plain `node --test` (no Cloudflare account needed).
import { DatabaseSync } from "node:sqlite";
import { readFileSync } from "node:fs";

class Statement {
  constructor(db, sql, args = []) {
    this.db = db;
    this.sql = sql;
    this.args = args;
  }
  bind(...args) {
    return new Statement(this.db, this.sql, args);
  }
  async first() {
    return this.db.prepare(this.sql).get(...this.args) ?? null;
  }
  async all() {
    return { results: this.db.prepare(this.sql).all(...this.args) };
  }
  async run() {
    const r = this.db.prepare(this.sql).run(...this.args);
    return { meta: { changes: Number(r.changes) } };
  }
}

export function createD1() {
  const db = new DatabaseSync(":memory:");
  const schema = readFileSync(new URL("../migrations/0001_init.sql", import.meta.url), "utf8");
  db.exec(schema);
  return {
    raw: db,
    prepare: (sql) => new Statement(db, sql)
  };
}
