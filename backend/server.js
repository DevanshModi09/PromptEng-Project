const express = require("express");
const Database = require("better-sqlite3");
const cors = require("cors");
const path = require("path");

const app = express();
const DB_PATH = process.env.DB_PATH || path.join(__dirname, "campuscrew.db");
const db = new Database(DB_PATH);

app.use(cors());
app.use(express.json());

// ── Schema ────────────────────────────────────────────────────────────────────
db.exec(`
  CREATE TABLE IF NOT EXISTS services (
    id      INTEGER PRIMARY KEY AUTOINCREMENT,
    key     TEXT UNIQUE,
    title   TEXT NOT NULL,
    cat     TEXT NOT NULL,
    name    TEXT NOT NULL,
    type    TEXT NOT NULL,
    amt     INTEGER DEFAULT 0,
    desc    TEXT,
    rating  REAL,
    reviews INTEGER DEFAULT 0,
    created_at INTEGER DEFAULT (strftime('%s','now'))
  );
`);

// Seed default services if table is empty
const count = db.prepare("SELECT COUNT(*) as n FROM services").get();
if (count.n === 0) {
  const insert = db.prepare(`
    INSERT OR IGNORE INTO services (key,title,cat,name,type,amt,desc,rating,reviews)
    VALUES (@key,@title,@cat,@name,@type,@amt,@desc,@rating,@reviews)
  `);
  const seed = [
    {key:"v0",title:"Event Photography",cat:"Photography",name:"Kabir (B.Des, 3rd yr)",type:"Negotiable",amt:300,desc:"Fests, club events and portraits. Edited photos delivered in 2 days.",rating:4.8,reviews:23},
    {key:"v1",title:"Poster & Logo Design",cat:"Design",name:"Ananya (B.Des, 2nd yr)",type:"Starting from",amt:100,desc:"Event posters, club logos and social media creatives.",rating:4.6,reviews:17},
    {key:"v2",title:"Reels & Video Editing",cat:"Video Editing",name:"Yash (BBA, 2nd yr)",type:"Negotiable",amt:200,desc:"Instagram reels, project demo videos and aftermovies.",rating:4.7,reviews:12},
    {key:"v3",title:"DSA Tutoring",cat:"Tutoring",name:"Meera (CSE, 4th yr)",type:"Skill swap",amt:0,desc:"Arrays to DP – weekend sessions. Teach me design in return!",rating:4.9,reviews:31},
    {key:"v4",title:"Resume Review",cat:"Resume Review",name:"Rohan (CSE, 4th yr)",type:"Free",amt:0,desc:"ATS-friendly resume feedback before placement season.",rating:4.5,reviews:40},
    {key:"v5",title:"Portfolio Website",cat:"Web Development",name:"Isha (IT, 3rd yr)",type:"Starting from",amt:400,desc:"Personal portfolio site with your projects and resume.",rating:4.6,reviews:9},
    {key:"v6",title:"Report Proofreading",cat:"Content Writing",name:"Sana (BBA, 3rd yr)",type:"Negotiable",amt:100,desc:"Grammar and formatting check for project reports.",rating:4.4,reviews:14},
  ];
  seed.forEach(s => insert.run(s));
  console.log("Seeded default services.");
}

// ── Serve frontend ────────────────────────────────────────────────────────────
app.get("/", (req, res) => {
  // Works both when run from repo root (Docker) and from backend/ dir (Render native)
  const htmlPath = path.join(__dirname, "..", "campuscrew_demo.html");
  const fallback = path.join(__dirname, "campuscrew_demo.html");
  const fs = require("fs");
  res.sendFile(fs.existsSync(htmlPath) ? htmlPath : fallback);
});

// ── Routes ────────────────────────────────────────────────────────────────────

// GET all services
app.get("/api/services", (req, res) => {
  const rows = db.prepare("SELECT * FROM services ORDER BY created_at DESC").all();
  res.json(rows);
});

// POST new service
app.post("/api/services", (req, res) => {
  const { title, cat, name, type, amt, desc } = req.body;
  if (!title || !name) return res.status(400).json({ error: "title and name required" });
  const key = "v" + Date.now();
  db.prepare(`
    INSERT INTO services (key,title,cat,name,type,amt,desc)
    VALUES (?,?,?,?,?,?,?)
  `).run(key, title, cat, name, type, amt || 0, desc || "");
  const row = db.prepare("SELECT * FROM services WHERE key=?").get(key);
  res.json(row);
});

// DELETE a service
app.delete("/api/services/:key", (req, res) => {
  db.prepare("DELETE FROM services WHERE key=?").run(req.params.key);
  res.json({ ok: true });
});

// Health check
app.get("/api/health", (_, res) => res.json({ ok: true }));

const PORT = process.env.PORT || 3001;
app.listen(PORT, () => console.log(`CampusCrew running on port ${PORT}`));
