// Minimal MCP server that exposes a SQL Server database to Claude Code.
// Connection info comes from environment variables set in the MCP client
// config (see `claude mcp add`), never hard-coded here.
//
// Env vars:
//   MSSQL_CONNECTION_STRING   e.g. "Server=HOST;Database=DB;User Id=USER;Password=PASS;TrustServerCertificate=True"
//   MSSQL_READONLY            "true" to block INSERT/UPDATE/DELETE/DDL (default: "false")
//   MSSQL_MAX_ROWS            cap on rows returned per query (default: 500)

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import sql from "mssql";

const CONNECTION_STRING = process.env.MSSQL_CONNECTION_STRING;
const READONLY = (process.env.MSSQL_READONLY || "false").toLowerCase() === "true";
const MAX_ROWS = Number(process.env.MSSQL_MAX_ROWS || 500);
const WRITE_PATTERN = /\b(insert|update|delete|drop|alter|truncate|create|merge|grant|revoke|exec|execute)\b/i;

if (!CONNECTION_STRING) {
  console.error("MSSQL_CONNECTION_STRING is not set");
  process.exit(1);
}

let poolPromise;
function getPool() {
  if (!poolPromise) {
    poolPromise = sql.connect(CONNECTION_STRING).catch((err) => {
      poolPromise = undefined;
      throw err;
    });
  }
  return poolPromise;
}

function textResult(obj) {
  return { content: [{ type: "text", text: typeof obj === "string" ? obj : JSON.stringify(obj, null, 2) }] };
}

const server = new McpServer({ name: "mssql", version: "1.0.0" });

server.registerTool(
  "list_tables",
  {
    title: "List tables",
    description: "List tables (schema + name) in the connected database.",
    inputSchema: {},
  },
  async () => {
    const pool = await getPool();
    const result = await pool.request().query(
      `SELECT TABLE_SCHEMA, TABLE_NAME, TABLE_TYPE
       FROM INFORMATION_SCHEMA.TABLES
       ORDER BY TABLE_SCHEMA, TABLE_NAME`
    );
    return textResult(result.recordset);
  }
);

server.registerTool(
  "describe_table",
  {
    title: "Describe table",
    description: "List columns, types, nullability and default for a table.",
    inputSchema: {
      schema: z.string().default("dbo").describe("Schema name, defaults to dbo"),
      table: z.string().describe("Table name"),
    },
  },
  async ({ schema, table }) => {
    const pool = await getPool();
    const result = await pool
      .request()
      .input("schema", sql.NVarChar, schema)
      .input("table", sql.NVarChar, table).query(`
        SELECT COLUMN_NAME, DATA_TYPE, IS_NULLABLE, CHARACTER_MAXIMUM_LENGTH, COLUMN_DEFAULT
        FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = @schema AND TABLE_NAME = @table
        ORDER BY ORDINAL_POSITION
      `);
    return textResult(result.recordset);
  }
);

server.registerTool(
  "run_sql",
  {
    title: "Run SQL",
    description:
      "Execute a T-SQL statement against the database. SELECT statements return rows " +
      `(capped at ${MAX_ROWS}). Other statements (INSERT/UPDATE/DELETE/DDL) return rows affected` +
      (READONLY ? ", but are DISABLED — this connection is read-only." : "."),
    inputSchema: {
      query: z.string().describe("The T-SQL statement to execute"),
    },
  },
  async ({ query }) => {
    if (READONLY && WRITE_PATTERN.test(query)) {
      return {
        ...textResult("Blocked: this MCP connection is configured read-only (MSSQL_READONLY=true)."),
        isError: true,
      };
    }
    const pool = await getPool();
    try {
      const result = await pool.request().query(query);
      if (result.recordset) {
        const rows = result.recordset.slice(0, MAX_ROWS);
        const truncated = result.recordset.length > MAX_ROWS;
        return textResult({ rowCount: result.recordset.length, truncated, rows });
      }
      return textResult({ rowsAffected: result.rowsAffected });
    } catch (err) {
      return { ...textResult(`SQL error: ${err.message}`), isError: true };
    }
  }
);

const transport = new StdioServerTransport();
await server.connect(transport);
