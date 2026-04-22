-- Eggplant 🍆 - Initial schema
-- Users, Products, Likes

CREATE TABLE IF NOT EXISTS users (
  id            TEXT PRIMARY KEY,
  nickname      TEXT NOT NULL,
  device_uuid   TEXT NOT NULL UNIQUE,
  region        TEXT,
  manner_score  INTEGER NOT NULL DEFAULT 36,
  created_at    TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at    TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_users_device_uuid ON users(device_uuid);

CREATE TABLE IF NOT EXISTS products (
  id           TEXT PRIMARY KEY,
  seller_id    TEXT NOT NULL,
  title        TEXT NOT NULL,
  description  TEXT NOT NULL,
  price        INTEGER NOT NULL DEFAULT 0,
  category     TEXT NOT NULL,
  region       TEXT NOT NULL,
  images       TEXT DEFAULT '',          -- comma-separated /uploads/<key> paths
  status       TEXT NOT NULL DEFAULT 'sale',  -- sale | reserved | sold
  view_count   INTEGER NOT NULL DEFAULT 0,
  like_count   INTEGER NOT NULL DEFAULT 0,
  chat_count   INTEGER NOT NULL DEFAULT 0,
  created_at   TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at   TEXT NOT NULL DEFAULT (datetime('now')),
  FOREIGN KEY (seller_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_products_seller_id   ON products(seller_id);
CREATE INDEX IF NOT EXISTS idx_products_category    ON products(category);
CREATE INDEX IF NOT EXISTS idx_products_region      ON products(region);
CREATE INDEX IF NOT EXISTS idx_products_created_at  ON products(created_at);
CREATE INDEX IF NOT EXISTS idx_products_status      ON products(status);

CREATE TABLE IF NOT EXISTS product_likes (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id     TEXT NOT NULL,
  product_id  TEXT NOT NULL,
  created_at  TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE(user_id, product_id),
  FOREIGN KEY (user_id)    REFERENCES users(id)    ON DELETE CASCADE,
  FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_product_likes_user    ON product_likes(user_id);
CREATE INDEX IF NOT EXISTS idx_product_likes_product ON product_likes(product_id);
